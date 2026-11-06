import Foundation
import VaultKit

/// A list: a note whose properties say which notes it lists, in what order, showing what. It's
/// kept as ordinary properties, readable in Obsidian and anywhere else:
///
/// ```yaml
/// list-from: Sources
/// list-tags: [reading]
/// list-where:
///   - format is Book
///   - read is empty
/// list-sort: published descending
/// list-show: [author, published]
/// ```
///
/// A note is a list if it has `list-from`, `list-tags` or `list-where`. Each condition is a
/// short line in words (`ListCondition`), built with menus in Point and readable as written.
public struct ListDefinition: Equatable, Sendable {
    /// Folders the notes are in (or in folders inside them). Any, if empty.
    public var folders: [String] = []
    /// Tags the notes have (any of them, or tags nested under them). Any, if empty.
    public var tags: [String] = []
    public var conditions: [ListCondition] = []
    /// Whether a note meeting any condition (or in any of the folders, or with any of the
    /// tags) is listed, rather than only one meeting all.
    public var matchesAny = false
    /// Newest edited first, unless set.
    public var sort: [NoteQuery.Sort] = []
    /// The columns shown after the title: properties, or `date created`, `date edited`, `folder`.
    public var columns: [String] = []

    public init(folders: [String] = [], tags: [String] = [], conditions: [ListCondition] = [], matchesAny: Bool = false,
                sort: [NoteQuery.Sort] = [], columns: [String] = []) {
        self.folders = folders
        self.tags = tags
        self.conditions = conditions
        self.matchesAny = matchesAny
        self.sort = sort
        self.columns = columns
    }

    public enum Key {
        public static let from = "list-from", tags = "list-tags", conditions = "list-where", match = "list-match"
        public static let sort = "list-sort", columns = "list-show"
        public static let all = [from, tags, conditions, match, sort, columns]
    }

    /// Whether a property is one of a list's own.
    public static func isListKey(_ key: String) -> Bool { Key.all.contains(key.lowercased()) }

    /// The list a note's properties describe, if they describe one.
    public init?(frontmatter: Frontmatter?) {
        guard let frontmatter else { return nil }
        func values(_ key: String) -> [String]? {
            frontmatter.properties.first { $0.key.lowercased() == key }?.values
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let from = values(Key.from), tags = values(Key.tags), conditions = values(Key.conditions)
        guard from != nil || tags != nil || conditions != nil else { return nil }
        folders = (from ?? []).map(Self.folderName)
        self.tags = (tags ?? []).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
        self.conditions = (conditions ?? []).compactMap(ListCondition.init(parsing:))
        matchesAny = values(Key.match)?.first?.lowercased() == "any"
        sort = (values(Key.sort) ?? []).compactMap(Self.sort(parsing:))
        columns = values(Key.columns) ?? []
    }

    /// `[[Sources]]` or `/Sources/` as a folder's path, `Sources`.
    public static func folderName(_ value: String) -> String {
        var name = value
        if name.hasPrefix("[["), name.hasSuffix("]]") { name = String(name.dropFirst(2).dropLast(2)) }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    /// What it asks the index.
    public var query: NoteQuery {
        let sort = sort.isEmpty ? [NoteQuery.Sort(.modified, descending: true)] : sort
        let folderFilters = folders.map { NoteQuery.Filter.folder($0) }
        let tagFilters = tags.map { NoteQuery.Filter.tag($0) }
        let conditions = conditions.map(\.filter)
        // Any: a note meeting any of them, a folder or tag as much as a condition.
        if matchesAny {
            let each = folderFilters + tagFilters + conditions
            return NoteQuery(each.isEmpty ? [] : [each.count == 1 ? each[0] : .any(each)], sort: sort)
        }
        // All: every condition, in any one of the folders, with any one of the tags.
        var filters: [NoteQuery.Filter] = []
        if !folderFilters.isEmpty { filters.append(folderFilters.count == 1 ? folderFilters[0] : .any(folderFilters)) }
        if !tagFilters.isEmpty { filters.append(tagFilters.count == 1 ? tagFilters[0] : .any(tagFilters)) }
        filters += conditions
        return NoteQuery(filters, sort: sort)
    }

    /// Its properties, in order, as they're written: each key with its values and whether it's
    /// a list. Unset ones are left out.
    public var properties: [(key: String, values: [String], isList: Bool)] {
        var properties: [(String, [String], Bool)] = []
        if !folders.isEmpty { properties.append((Key.from, folders, folders.count > 1)) }
        if !tags.isEmpty { properties.append((Key.tags, tags, true)) }
        if !conditions.isEmpty { properties.append((Key.conditions, conditions.map(\.written), true)) }
        if matchesAny { properties.append((Key.match, ["any"], false)) }
        if !sort.isEmpty { properties.append((Key.sort, sort.map(Self.written), sort.count > 1)) }
        if !columns.isEmpty { properties.append((Key.columns, columns, true)) }
        return properties
    }

    // MARK: Sorting, in words

    /// Note facts, named as they're written in a list: `date edited`, `date created`, `title`,
    /// `folder`. Anything else is a property.
    public static func field(named name: String) -> NoteQuery.Field? {
        switch name.lowercased() {
        case "title": .title
        case "folder": .folder
        case "date created", "created date": .created
        case "date edited", "edited date", "date modified": .modified
        default: nil
        }
    }

    public static func name(of field: NoteQuery.Field) -> String {
        switch field {
        case .title: "title"
        case .folder: "folder"
        case .created: "date created"
        case .modified: "date edited"
        }
    }

    /// `published descending`, `title`, `date edited descending`.
    static func sort(parsing text: String) -> NoteQuery.Sort? {
        var words = text.trimmingCharacters(in: .whitespaces)
        var descending = false
        for suffix in [" descending", " desc"] where words.lowercased().hasSuffix(suffix) {
            words = String(words.dropLast(suffix.count))
            descending = true
        }
        for suffix in [" ascending", " asc"] where words.lowercased().hasSuffix(suffix) {
            words = String(words.dropLast(suffix.count))
        }
        words = words.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return nil }
        let key: NoteQuery.Sort.Key = field(named: words).map { .field($0) } ?? .property(words)
        return NoteQuery.Sort(key, descending: descending)
    }

    static func written(_ sort: NoteQuery.Sort) -> String {
        let name = switch sort.key {
        case .field(let field): Self.name(of: field)
        case .property(let property): property
        }
        return sort.descending ? name + " descending" : name
    }
}

/// One condition of a list, as a short line in words:
///
/// - `format is Book`, `format is not Book`, `title contains design`
/// - `read is set` (has a value), `read is not set` (has none: not written, or blank),
///   `read is empty` (written, but blank)
/// - `rating > 3`, `published before 2020`, `date edited in last 7 days`, `read in last 3 months`
/// - `read between 2024-03-01 and 2025-06-30`, `read is this year`
/// - `folder is not Archive`, `tag is not draft`
/// - `links to [[Service design]]`, `has words service design`
public struct ListCondition: Equatable, Sendable, Hashable {
    public enum Operator: String, CaseIterable, Sendable {
        case `is`, isNot, contains, isEmpty, isSet, isNotSet, less, greater, before, after, between, thisPeriod, inLastDays, inNextDays, linksTo, hasWords

        /// How it's written.
        public var words: String {
            switch self {
            case .is: "is"
            case .isNot: "is not"
            case .contains: "contains"
            case .isEmpty: "is empty"
            case .isSet: "is set"
            case .isNotSet: "is not set"
            case .less: "<"
            case .greater: ">"
            case .before: "before"
            case .after: "after"
            case .between: "between"
            case .thisPeriod: "is this"
            case .inLastDays: "in last"
            case .inNextDays: "in next"
            case .linksTo: "links to"
            case .hasWords: "has words"
            }
        }

        /// Whether it takes a value after it.
        public var takesValue: Bool { ![.isEmpty, .isSet, .isNotSet].contains(self) }
        /// Whether it's about the note, with no property before it.
        public var isAboutNote: Bool { self == .linksTo || self == .hasWords }
    }

    /// The units `in last` and `in next` count in: `in last 3 months`.
    public enum Unit: String, CaseIterable, Sendable {
        case days, weeks, months, years
        var component: Calendar.Component {
            switch self { case .days: .day; case .weeks: .weekOfYear; case .months: .month; case .years: .year }
        }
    }
    /// What `is this` can be: `is this year`.
    public enum Period: String, CaseIterable, Sendable {
        case week, month, year
        var component: Calendar.Component {
            switch self { case .week: .weekOfYear; case .month: .month; case .year: .year }
        }
    }

    /// For `in last` and `in next`: how many, of what (`3 months`). A number alone is days.
    public var amount: (count: Int, unit: Unit)? {
        let words = value.lowercased().split(separator: " ").map(String.init)
        guard let first = words.first, let count = Int(first) else { return nil }
        guard words.count > 1 else { return (count, .days) }
        let unit = Unit.allCases.first { $0.rawValue == words[1] || $0.rawValue.dropLast() == words[1] }
        return unit.map { (count, $0) }
    }

    /// For `between`: the first and last days (`2024-03-01 and 2025-06-30`).
    public var range: (from: String, to: String)? {
        let parts = value.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    /// The property (or note fact: `title`, `folder`, `date created`, `date edited`) it's about;
    /// empty for `links to` and `has words`.
    public var subject: String
    public var op: Operator
    public var value: String

    public init(_ subject: String, _ op: Operator, _ value: String = "") {
        self.subject = subject
        self.op = op
        self.value = value
    }

    /// As written in the list's `list-where`.
    public var written: String {
        var tail = value
        if op == .inLastDays || op == .inNextDays, let amount {
            tail = "\(amount.count) " + (amount.count == 1 ? String(amount.unit.rawValue.dropLast()) : amount.unit.rawValue)
        }
        let head = op.isAboutNote ? op.words : subject + " " + op.words
        return op.takesValue ? head + " " + tail : head
    }

    /// Reads one, as written. Nil if it can't be read.
    public init?(parsing line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        let lowered = text.lowercased()
        for op in [Operator.linksTo, .hasWords] where lowered.hasPrefix(op.words + " ") {
            self.init("", op, String(text.dropFirst(op.words.count + 1)).trimmingCharacters(in: .whitespaces))
            return
        }
        // The first operator found, longest first where they start alike ("is not set" before "is").
        let order: [Operator] = [.isNotSet, .isNot, .isEmpty, .isSet, .thisPeriod, .is, .contains, .before, .after, .between,
                                 .inLastDays, .inNextDays, .less, .greater]
        var best: (range: Range<String.Index>, op: Operator)?
        for op in order {
            let needle = " " + op.words + (op.takesValue ? " " : "")
            var searchRange = lowered.startIndex..<lowered.endIndex
            while let found = lowered.range(of: needle, range: searchRange) {
                // An operator without a value ends the line.
                // `is this` only before a period (`is this year`): else it's `is`, and a value.
                let isPeriod = op != .thisPeriod || Period(rawValue: String(lowered[found.upperBound...]).trimmingCharacters(in: .whitespaces)) != nil
                if isPeriod, op.takesValue || found.upperBound == lowered.endIndex {
                    if best == nil || found.lowerBound < best!.range.lowerBound { best = (found, op) }
                    break
                }
                searchRange = found.upperBound..<lowered.endIndex
            }
        }
        guard let (range, op) = best else { return nil }
        let subject = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        var value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !subject.isEmpty, !op.takesValue || !value.isEmpty else { return nil }
        self.init(subject, op, value)
        switch op {
        case .inLastDays, .inNextDays:
            guard let amount else { return nil }
            self.value = amount.unit == .days ? String(amount.count) : "\(amount.count) \(amount.unit.rawValue)"
        case .between:
            guard self.range != nil else { return nil }
        case .thisPeriod:
            guard Period(rawValue: value.lowercased()) != nil else { return nil }
            self.value = value.lowercased()
        default: break
        }
    }

    /// What it asks the index, as of today (`is this year`, `in last 3 months`).
    public var filter: NoteQuery.Filter { filter(now: Date()) }

    public func filter(now: Date, calendar: Calendar = .current) -> NoteQuery.Filter {
        func on(_ condition: NoteQuery.Condition) -> NoteQuery.Filter {
            ListDefinition.field(named: subject).map { .field($0, condition) } ?? .property(subject, condition)
        }
        func day(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        switch op {
        case .between:
            guard let range else { return on(.exists) }
            return .all([on(.greaterOrEqual(range.from)), on(.lessOrEqual(range.to))])
        case .thisPeriod:
            guard let period = Period(rawValue: value), let interval = calendar.dateInterval(of: period.component, for: now) else { return on(.exists) }
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return .all([on(.greaterOrEqual(day(interval.start))), on(.lessOrEqual(day(last)))])
        case .inLastDays, .inNextDays:
            // Counted in days back (or on) from today, whatever the unit.
            guard let amount else { return on(.exists) }
            let today = calendar.startOfDay(for: now)
            let other = calendar.date(byAdding: amount.unit.component, value: op == .inLastDays ? -amount.count : amount.count, to: today) ?? today
            let days = max(1, abs(calendar.dateComponents([.day], from: today, to: other).day ?? amount.count))
            return on(op == .inLastDays ? .withinLastDays(days) : .withinNextDays(days))
        default: break
        }
        let condition: NoteQuery.Condition = switch op {
        case .is: .equals(value)
        case .isNot: .equals(value)
        case .contains: .contains(value)
        case .isEmpty: .empty
        case .isSet: .exists
        case .isNotSet: .missing
        case .less, .before: .less(value)
        case .greater, .after: .greater(value)
        case .inLastDays, .inNextDays, .between, .thisPeriod, .linksTo, .hasWords: .exists
        }
        if op == .linksTo { return .linksTo(LinkName.normalised(value)) }
        if op == .hasWords { return .text(value) }
        // A tag, with the tags nested under it, as `list-tags` takes them.
        if ["tag", "tags"].contains(subject.lowercased()), op == .is || op == .isNot {
            let tag = NoteQuery.Filter.tag(value.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
            return op == .isNot ? .not(tag) : tag
        }
        let filter: NoteQuery.Filter
        if let field = ListDefinition.field(named: subject), field != .folder || [.is, .isNot, .contains].contains(op) {
            filter = field == .folder ? .folder(ListDefinition.folderName(value)) : .field(field, condition)
        } else if op == .isSet {
            // Given a value: written, and not left blank (`read:`).
            return .all([.property(subject, .exists), .not(.property(subject, .empty))])
        } else if op == .isNotSet {
            // No value: not written, or left blank.
            return .any([.property(subject, .missing), .property(subject, .empty)])
        } else {
            filter = .property(subject, condition)
        }
        return op == .isNot ? .not(filter) : filter
    }
}
