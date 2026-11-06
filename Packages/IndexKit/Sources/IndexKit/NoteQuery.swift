import Foundation
import VaultKit

/// A question about the vault's notes: which notes, in what order. The one way search, lists,
/// sidebar places and the properties view describe what they want from the index, so each is
/// answered by the same SQL (fast at 10,000 notes) and behaves the same.
public struct NoteQuery: Codable, Sendable, Equatable, Hashable {
    /// Notes must match every one.
    public var filters: [Filter]
    /// The first sort decides, then the next breaks ties. Title last, always, so the order is
    /// stable.
    public var sort: [Sort]
    public var limit: Int?

    public init(_ filters: [Filter] = [], sort: [Sort] = [Sort(.modified, descending: true)], limit: Int? = nil) {
        self.filters = filters
        self.sort = sort
        self.limit = limit
    }

    /// A fact about a note itself, not one of its properties.
    public enum Field: String, Codable, Sendable, Hashable, CaseIterable {
        case title
        /// The note's folder, relative to the vault (`Projects/Point`), empty at the top level.
        case folder
        case created
        case modified
    }

    public indirect enum Filter: Codable, Sendable, Equatable, Hashable {
        /// Tagged with this tag or one nested under it (`work` matches `work/point`).
        case tag(String)
        /// In this folder, or in one inside it if `includingSubfolders`.
        case folder(String, includingSubfolders: Bool = true)
        /// A property, by name (any case), meeting a condition.
        case property(String, Condition)
        /// A fact about the note meeting a condition (`.contains` for the title, dates for
        /// created and modified).
        case field(Field, Condition)
        /// Links to the note with this name, in its text or its properties.
        case linksTo(String)
        /// Words in the title, text or properties, as search finds them (whole words and
        /// prefixes, any order).
        case text(String)
        case all([Filter])
        case any([Filter])
        case not(Filter)
    }

    public enum Condition: Codable, Sendable, Equatable, Hashable {
        /// Has the property, with or without a value.
        case exists
        /// Doesn't have the property at all.
        case missing
        /// Has the property but no value in it.
        case empty
        /// A value equal to this (ignoring case). For a value that's a link, the linked name
        /// matches too, so `people is Sam Lee` finds `people: ["[[Sam Lee]]"]`.
        case equals(String)
        /// A value containing this (ignoring case).
        case contains(String)
        /// A number or date value compared with this one: a number (`3`), a date
        /// (`2026-11-06`) or a date and time.
        case less(String)
        case lessOrEqual(String)
        case greater(String)
        case greaterOrEqual(String)
        /// A date in the last so many days, today included.
        case withinLastDays(Int)
        /// A date in the next so many days, today included.
        case withinNextDays(Int)
    }

    public struct Sort: Codable, Sendable, Equatable, Hashable {
        public enum Key: Codable, Sendable, Equatable, Hashable {
            case field(Field)
            /// By a property's value: by number or date where it has one, else by text.
            /// Notes without it come last.
            case property(String)
        }
        public var key: Key
        public var descending: Bool

        public init(_ key: Key, descending: Bool = false) {
            self.key = key
            self.descending = descending
        }

        public init(_ field: Field, descending: Bool = false) {
            self.init(.field(field), descending: descending)
        }
    }
}

// MARK: SQL

extension NoteQuery {
    /// The statement finding the query's notes (their IDs, in order), and its bindings.
    func sql(now: Date = Date(), calendar: Calendar = .current) -> (String, [Any?]) {
        var bindings: [Any?] = []
        let conditions = filters.map { $0.sql(&bindings, now: now, calendar: calendar) }
        var sql = "SELECT n.id FROM notes n"
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        var order = sort.map { $0.sql(&bindings) }
        order.append("n.title COLLATE NOCASE, n.id")
        sql += " ORDER BY " + order.joined(separator: ", ")
        if let limit { sql += " LIMIT \(max(0, limit))" }
        return (sql, bindings)
    }

    /// A value as the index stores it for comparing: a date's time since 1970, or a number.
    static func comparable(_ value: String) -> (column: String, value: Double)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let date = PropertyValueKinds.date(trimmed) { return ("date", date) }
        if let number = PropertyValueKinds.number(trimmed) { return ("number", number) }
        return nil
    }
}

extension NoteQuery.Filter {
    func sql(_ bindings: inout [Any?], now: Date, calendar: Calendar) -> String {
        switch self {
        case .tag(let tag):
            let lowered = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            bindings += [lowered, SearchIndex.likePattern(under: lowered)]
            return "n.row IN (SELECT note FROM tags WHERE lowered = ? OR lowered LIKE ? ESCAPE '\\')"
        case .folder(let folder, let includingSubfolders):
            let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            bindings.append(trimmed)
            guard includingSubfolders, !trimmed.isEmpty else { return "n.folder = ?" }
            bindings.append(SearchIndex.likePattern(under: trimmed))
            return "(n.folder = ? OR n.folder LIKE ? ESCAPE '\\')"
        case .property(let name, let condition):
            return condition.sql(property: name, &bindings, now: now, calendar: calendar)
        case .field(let field, let condition):
            return condition.sql(field: field, &bindings, now: now, calendar: calendar)
        case .linksTo(let name):
            bindings.append(LinkName.normalised(name))
            return "n.row IN (SELECT note FROM links WHERE name = ?)"
        case .text(let words):
            let terms = Fuzzy.words(words)
            guard !terms.isEmpty else { return "1" }
            bindings.append(terms.map { "\"\($0)\"*" }.joined(separator: " AND "))
            return "n.row IN (SELECT rowid FROM words WHERE words MATCH ?)"
        case .all(let filters):
            guard !filters.isEmpty else { return "1" }
            return "(" + filters.map { $0.sql(&bindings, now: now, calendar: calendar) }.joined(separator: " AND ") + ")"
        case .any(let filters):
            guard !filters.isEmpty else { return "0" }
            return "(" + filters.map { $0.sql(&bindings, now: now, calendar: calendar) }.joined(separator: " OR ") + ")"
        case .not(let filter):
            return "NOT " + filter.sql(&bindings, now: now, calendar: calendar)
        }
    }
}

extension NoteQuery.Condition {
    /// The days covered by a relative date range, as times since 1970: from the start of the
    /// first day to the start of the day after the last.
    private func days(_ count: Int, forward: Bool, now: Date, calendar: Calendar) -> (Double, Double) {
        let today = calendar.startOfDay(for: now)
        let days = max(1, count)
        let start = forward ? today : calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: forward ? days : 1, to: today) ?? today
        return (start.timeIntervalSince1970, end.timeIntervalSince1970)
    }

    /// The test on one stored value (`v`), or nil for the conditions about having the
    /// property at all.
    private func valueTest(_ bindings: inout [Any?], now: Date, calendar: Calendar) -> String? {
        func compare(_ op: String, _ value: String) -> String {
            guard let (column, number) = NoteQuery.comparable(value) else {
                bindings.append(value)
                return "v.value \(op) ? COLLATE NOCASE"
            }
            bindings.append(number)
            return "v.\(column) \(op) ?"
        }
        switch self {
        case .exists, .missing, .empty:
            return nil
        case .equals(let value):
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            bindings += [trimmed, LinkName.normalised(trimmed)]
            return "(v.value = ? COLLATE NOCASE OR v.link = ?)"
        case .contains(let value):
            bindings.append("%" + SearchIndex.escapedLike(value.trimmingCharacters(in: .whitespaces)) + "%")
            return "v.value LIKE ? ESCAPE '\\'"
        case .less(let value): return compare("<", value)
        case .lessOrEqual(let value):
            // A date without a time means the whole of that day.
            if let date = PropertyValueKinds.dayEnd(value, calendar: calendar) {
                bindings.append(date)
                return "v.date < ?"
            }
            return compare("<=", value)
        case .greater(let value):
            if let date = PropertyValueKinds.dayEnd(value, calendar: calendar) {
                bindings.append(date)
                return "v.date >= ?"
            }
            return compare(">", value)
        case .greaterOrEqual(let value): return compare(">=", value)
        case .withinLastDays(let count), .withinNextDays(let count):
            if case .withinNextDays = self {}
            let forward: Bool = { if case .withinNextDays = self { return true } else { return false } }()
            let (start, end) = days(count, forward: forward, now: now, calendar: calendar)
            bindings += [start, end]
            return "(v.date >= ? AND v.date < ?)"
        }
    }

    func sql(property name: String, _ bindings: inout [Any?], now: Date, calendar: Calendar) -> String {
        let lowered = name.lowercased()
        switch self {
        case .exists:
            bindings.append(lowered)
            return "n.row IN (SELECT note FROM property_names WHERE lowered = ?)"
        case .missing:
            bindings.append(lowered)
            return "n.row NOT IN (SELECT note FROM property_names WHERE lowered = ?)"
        case .empty:
            bindings += [lowered, lowered]
            return "(n.row IN (SELECT note FROM property_names WHERE lowered = ?) AND n.row NOT IN (SELECT note FROM property_values WHERE name = ?))"
        default:
            bindings.append(lowered)
            let test = valueTest(&bindings, now: now, calendar: calendar)!
            return "n.row IN (SELECT v.note FROM property_values v WHERE v.name = ? AND \(test))"
        }
    }

    func sql(field: NoteQuery.Field, _ bindings: inout [Any?], now: Date, calendar: Calendar) -> String {
        let column: String
        switch field {
        case .title: column = "n.title"
        case .folder: column = "n.folder"
        case .created: column = "n.created"
        case .modified: column = "n.edited"
        }
        let isDate = field == .created || field == .modified
        switch self {
        case .exists: return "1"
        case .missing: return "0"
        case .empty: return isDate ? "0" : "\(column) = ''"
        case .equals(let value):
            if isDate, let (start, end) = PropertyValueKinds.dayRange(value, calendar: calendar) {
                bindings += [start, end]
                return "(\(column) >= ? AND \(column) < ?)"
            }
            bindings.append(value)
            return "\(column) = ? COLLATE NOCASE"
        case .contains(let value):
            bindings.append("%" + SearchIndex.escapedLike(value) + "%")
            return "\(column) LIKE ? ESCAPE '\\'"
        case .withinLastDays(let count), .withinNextDays(let count):
            let forward: Bool = { if case .withinNextDays = self { return true } else { return false } }()
            let (start, end) = days(count, forward: forward, now: now, calendar: calendar)
            bindings += [start, end]
            return "(\(column) >= ? AND \(column) < ?)"
        case .less(let value), .lessOrEqual(let value), .greater(let value), .greaterOrEqual(let value):
            guard isDate, let date = PropertyValueKinds.date(value) else {
                bindings.append(value)
                let op: String = switch self { case .less: "<"; case .lessOrEqual: "<="; case .greater: ">"; default: ">=" }
                return "\(column) \(op) ? COLLATE NOCASE"
            }
            switch self {
            case .less: bindings.append(date); return "\(column) < ?"
            case .greaterOrEqual: bindings.append(date); return "\(column) >= ?"
            case .lessOrEqual:
                bindings.append(PropertyValueKinds.dayEnd(value, calendar: calendar) ?? date)
                return "\(column) < ?"
            default:
                bindings.append(PropertyValueKinds.dayEnd(value, calendar: calendar) ?? date)
                return "\(column) >= ?"
            }
        }
    }
}

extension NoteQuery.Sort {
    func sql(_ bindings: inout [Any?]) -> String {
        let direction = descending ? "DESC" : "ASC"
        switch key {
        case .field(.title): return "n.title COLLATE NOCASE \(direction)"
        case .field(.folder): return "n.folder COLLATE NOCASE \(direction)"
        case .field(.created): return "n.created \(direction)"
        case .field(.modified): return "n.edited \(direction)"
        case .property(let name):
            // Dates, then numbers, then text; the first value of a list.
            let lowered = name.lowercased()
            bindings += [lowered, lowered, lowered]
            let pick = descending ? "MAX" : "MIN"
            return """
                (SELECT \(pick)(date) FROM property_values WHERE note = n.row AND name = ?) IS NULL, \
                (SELECT \(pick)(COALESCE(date, number)) FROM property_values WHERE note = n.row AND name = ?) \(direction), \
                (SELECT \(pick)(value COLLATE NOCASE) FROM property_values WHERE note = n.row AND name = ?) \(direction)
                """
        }
    }
}

/// How the index reads a property value's number or date.
enum PropertyValueKinds {
    /// A date (`2026-11-06`) or a date and time, as a time since 1970.
    static func date(_ value: String, calendar: Calendar = .current) -> Double? {
        PropertyDate.parse(value, calendar: calendar)?.date.timeIntervalSince1970
    }

    /// For a date without a time, the start of the day after it: "on or before 6 November"
    /// takes in the whole of the 6th.
    static func dayEnd(_ value: String, calendar: Calendar) -> Double? {
        guard let parsed = PropertyDate.parse(value, calendar: calendar), !parsed.hasTime,
              let next = calendar.date(byAdding: .day, value: 1, to: parsed.date) else { return nil }
        return next.timeIntervalSince1970
    }

    /// The whole of a day, for a date without a time.
    static func dayRange(_ value: String, calendar: Calendar) -> (Double, Double)? {
        guard let parsed = PropertyDate.parse(value, calendar: calendar), !parsed.hasTime,
              let end = dayEnd(value, calendar: calendar) else { return nil }
        return (parsed.date.timeIntervalSince1970, end)
    }

    /// A plain number (`3`, `-2.5`), not words that Swift would read as one (`nan`, `inf`).
    static func number(_ value: String) -> Double? {
        guard let first = value.first, first.isNumber || first == "-" || first == "." || first == "+",
              let number = Double(value), number.isFinite else { return nil }
        return number
    }
}

/// How a link's target is matched: lowercased, without a folder, `#heading` or `.md`.
enum LinkName {
    static func normalised(_ target: String) -> String {
        var name = target.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[["), name.hasSuffix("]]") { name = String(name.dropFirst(2).dropLast(2)) }
        name = name.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        name = name.split(separator: "#", omittingEmptySubsequences: false).first.map(String.init) ?? name
        name = (name as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        return name.lowercased()
    }

    /// The linked name, if a property value is just one wikilink (`[[Sam Lee]]`).
    static func onlyLink(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return nil }
        let inside = trimmed.dropFirst(2).dropLast(2)
        guard !inside.contains("[["), !inside.contains("]]") else { return nil }
        return normalised(trimmed)
    }
}
