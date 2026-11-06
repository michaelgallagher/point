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
    /// Whether a note meeting any condition is listed, rather than only one meeting all.
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
    static func folderName(_ value: String) -> String {
        var name = value
        if name.hasPrefix("[["), name.hasSuffix("]]") { name = String(name.dropFirst(2).dropLast(2)) }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    /// What it asks the index.
    public var query: NoteQuery {
        var filters: [NoteQuery.Filter] = []
        if !folders.isEmpty {
            let each = folders.map { NoteQuery.Filter.folder($0) }
            filters.append(each.count == 1 ? each[0] : .any(each))
        }
        if !tags.isEmpty {
            let each = tags.map { NoteQuery.Filter.tag($0) }
            filters.append(each.count == 1 ? each[0] : .any(each))
        }
        let conditions = conditions.map(\.filter)
        if !conditions.isEmpty {
            filters.append(matchesAny ? .any(conditions) : .all(conditions))
        }
        return NoteQuery(filters, sort: sort.isEmpty ? [NoteQuery.Sort(.modified, descending: true)] : sort)
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
/// - `read is empty`, `read is set`, `read is not set`
/// - `rating > 3`, `published before 2020`, `date edited in last 7 days`
/// - `links to [[Service design]]`, `has words service design`
public struct ListCondition: Equatable, Sendable, Hashable {
    public enum Operator: String, CaseIterable, Sendable {
        case `is`, isNot, contains, isEmpty, isSet, isNotSet, less, greater, before, after, inLastDays, inNextDays, linksTo, hasWords

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
        let tail = op == .inLastDays || op == .inNextDays ? "\(value) days" : value
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
        let order: [Operator] = [.isNotSet, .isNot, .isEmpty, .isSet, .is, .contains, .before, .after, .inLastDays, .inNextDays, .less, .greater]
        var best: (range: Range<String.Index>, op: Operator)?
        for op in order {
            let needle = " " + op.words + (op.takesValue ? " " : "")
            var searchRange = lowered.startIndex..<lowered.endIndex
            while let found = lowered.range(of: needle, range: searchRange) {
                // An operator without a value ends the line.
                if op.takesValue || found.upperBound == lowered.endIndex {
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
        if op == .inLastDays || op == .inNextDays {
            value = value.lowercased().replacingOccurrences(of: "days", with: "").replacingOccurrences(of: "day", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard Int(value) != nil else { return nil }
        }
        self.init(subject, op, value)
    }

    /// What it asks the index.
    public var filter: NoteQuery.Filter {
        let condition: NoteQuery.Condition = switch op {
        case .is: .equals(value)
        case .isNot: .equals(value)
        case .contains: .contains(value)
        case .isEmpty: .empty
        case .isSet: .exists
        case .isNotSet: .missing
        case .less, .before: .less(value)
        case .greater, .after: .greater(value)
        case .inLastDays: .withinLastDays(Int(value) ?? 0)
        case .inNextDays: .withinNextDays(Int(value) ?? 0)
        case .linksTo, .hasWords: .exists
        }
        if op == .linksTo { return .linksTo(LinkName.normalised(value)) }
        if op == .hasWords { return .text(value) }
        let filter: NoteQuery.Filter
        if let field = ListDefinition.field(named: subject), field != .folder || [.is, .isNot, .contains].contains(op) {
            filter = field == .folder ? .folder(value, includingSubfolders: op == .contains) : .field(field, condition)
        } else {
            filter = .property(subject, condition)
        }
        return op == .isNot ? .not(filter) : filter
    }
}
