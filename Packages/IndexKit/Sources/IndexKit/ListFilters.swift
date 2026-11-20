import Foundation
import VaultKit

/// What a list can be filtered by: where a note is, its tags, facts about it, or one of the
/// vault's properties.
public enum ListFilterSubject: Hashable, Sendable {
    case folder, tag, linksTo, hasWords
    case field(NoteQuery.Field)
    case property(String)

    public var name: String {
        switch self {
        case .folder: "Folder"
        case .tag: "Tag"
        case .linksTo: "Links to"
        case .hasWords: "Has words"
        case .field(let field): ListDefinition.name(of: field).prefix(1).uppercased() + ListDefinition.name(of: field).dropFirst()
        case .property(let name): name
        }
    }
}

/// What kind of thing a property holds, so a filter on it compares and asks for values in
/// the way that suits it: dates on a calendar, choices from their menu, and so on.
public enum ListValueKind: Equatable, Sendable {
    case text, list, number, date, checkbox, tag, person, note, folder
    case choice([String])
    case rating(Int)

    public var symbol: String {
        switch self {
        case .text: PropertyType.text.symbol
        case .list: PropertyType.list.symbol
        case .number: PropertyType.number.symbol
        case .date: PropertyType.date.symbol
        case .checkbox: PropertyType.checkbox.symbol
        case .tag: PropertyType.tags.symbol
        case .person: PointTypes.Kind.person.symbol
        case .note: PointTypes.Kind.note.symbol
        case .folder: "folder"
        case .choice: PointTypes.Kind.choice.symbol
        case .rating: PointTypes.Kind.rating.symbol
        }
    }

    public var name: String {
        switch self {
        case .text: "Text"
        case .list: "List"
        case .number: "Number"
        case .date: "Date"
        case .checkbox: "Checkbox"
        case .tag: "Tags"
        case .person: "Person"
        case .note: "Link to note"
        case .folder: "Folder"
        case .choice: "Choice"
        case .rating: "Rating"
        }
    }

    public var isNumeric: Bool {
        if case .rating = self { return true }
        return self == .number
    }

    /// Whether it holds several values, which a filter looks among.
    public var isMany: Bool { [.list, .tag, .person].contains(self) }

    /// The comparisons that make sense for it, most useful first.
    public var operators: [ListCondition.Operator] {
        switch self {
        case .text, .note: [.is, .isNot, .contains, .isSet, .isNotSet]
        case .list, .person: [.is, .isNot, .contains, .isSet, .isNotSet]
        case .tag, .folder: [.is, .isNot]
        case .choice: [.is, .isNot, .isSet, .isNotSet]
        case .number, .rating: [.is, .isNot, .greater, .less, .isSet, .isNotSet]
        case .date: [.is, .before, .after, .between, .thisPeriod, .inLastDays, .inNextDays, .isSet, .isNotSet]
        case .checkbox: [.is, .isNot]
        }
    }

    /// How a comparison reads for it.
    public func label(_ op: ListCondition.Operator) -> String {
        switch op {
        case .is:
            switch self {
            case .checkbox: "is ticked"
            case .date: "is on"
            case .folder: "is in"
            default: isMany && self != .tag ? "includes" : "is"
            }
        case .isNot:
            switch self {
            case .checkbox: "isn't ticked"
            case .folder: "isn't in"
            default: isMany && self != .tag ? "doesn't include" : "isn't"
            }
        case .contains: "contains"
        case .isSet: "has a value"
        case .isNotSet, .isEmpty: "has no value"
        case .less: "is less than"
        case .greater: "is more than"
        case .before: "is before"
        case .after: "is after"
        case .between: "is between"
        case .thisPeriod: "is this"
        case .inLastDays: "is in the last"
        case .inNextDays: "is in the next"
        case .linksTo: "links to"
        case .hasWords: "has the words"
        }
    }
}

/// One condition in the filters window, as its controls hold it.
public struct ListFilterRow: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var subject: ListFilterSubject
    public var op: ListCondition.Operator
    public var text = ""
    public var date = Calendar.current.startOfDay(for: Date())
    public var endDate = Calendar.current.startOfDay(for: Date())
    public var count = 7
    public var unit: ListCondition.Unit = .days
    public var period: ListCondition.Period = .year

    /// A new row about `subject`, comparing as suits its kind.
    public init(subject: ListFilterSubject, kind: ListValueKind) {
        self.subject = subject
        switch subject {
        case .linksTo: op = .linksTo
        case .hasWords: op = .hasWords
        default: op = kind.operators.first ?? .is
        }
        if kind == .checkbox { text = "true" }
    }

    /// The row for a filter the list has.
    public init(condition: ListCondition) {
        switch condition.op {
        case .linksTo: subject = .linksTo
        case .hasWords: subject = .hasWords
        default:
            let lowered = condition.subject.lowercased()
            if lowered == "folder" { subject = .folder } else if lowered == "tag" || lowered == "tags" { subject = .tag } else {
                subject = ListDefinition.field(named: condition.subject).map { .field($0) } ?? .property(condition.subject)
            }
        }
        op = condition.op == .isEmpty ? .isNotSet : condition.op
        text = condition.op == .linksTo ? ListFilterRow.unlinked(condition.value) : condition.value
        switch condition.op {
        case .is, .before, .after:
            if let parsed = PropertyDate.parse(condition.value)?.date { date = parsed }
        case .between:
            if let range = condition.range {
                date = PropertyDate.parse(range.from)?.date ?? date
                endDate = PropertyDate.parse(range.to)?.date ?? endDate
            }
        case .thisPeriod: period = ListCondition.Period(rawValue: condition.value) ?? .year
        case .inLastDays, .inNextDays:
            if let amount = condition.amount { count = amount.count; unit = amount.unit }
        default: break
        }
    }

    /// The condition it makes, if it's whole.
    public func condition(kind: ListValueKind) -> ListCondition? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        switch subject {
        case .linksTo: return typed.isEmpty ? nil : ListCondition("", .linksTo, "[[\(typed)]]")
        case .hasWords: return typed.isEmpty ? nil : ListCondition("", .hasWords, typed)
        default: break
        }
        let name: String = switch subject {
        case .folder: "folder"
        case .tag: "tag"
        case .field(let field): ListDefinition.name(of: field)
        case .property(let name): name
        default: ""
        }
        guard op.takesValue else { return ListCondition(name, op) }
        let value: String
        switch op {
        case .between:
            let (from, to) = date <= endDate ? (date, endDate) : (endDate, date)
            value = "\(Self.day(from)) and \(Self.day(to))"
        case .thisPeriod: value = period.rawValue
        case .inLastDays, .inNextDays:
            guard count > 0 else { return nil }
            value = unit == .days ? String(count) : "\(count) \(unit.rawValue)"
        default:
            if kind == .checkbox { return ListCondition(name, op, "true") }
            value = kind == .date ? Self.day(date) : typed
        }
        guard !value.isEmpty else { return nil }
        if kind.isNumeric, op == .less || op == .greater, Double(value) == nil { return nil }
        return ListCondition(name, op, value)
    }

    public static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func unlinked(_ value: String) -> String {
        guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
        return String(value.dropFirst(2).dropLast(2))
    }
}

// MARK: What a vault's properties hold

/// What the vault's properties hold, for lists' filters and columns: from Point's kinds, the
/// vault's property types, and what the index says of each property and its values. The Mac
/// and the iPhone each make one from what they have.
public struct ListVocabulary {
    public var pointTypes: PointTypes
    public var propertyTypes: PropertyTypes
    /// The index's summary of each property.
    public var summaries: [SearchIndex.PropertySummary]
    /// A property's values, most used first.
    public var values: (String) -> [String]

    public init(pointTypes: PointTypes, propertyTypes: PropertyTypes, summaries: [SearchIndex.PropertySummary],
                values: @escaping (String) -> [String]) {
        self.pointTypes = pointTypes
        self.propertyTypes = propertyTypes
        self.summaries = summaries
        self.values = values
    }

    /// What a property holds: as Point's own kinds or the vault's types say, else as its
    /// values read.
    public func kind(ofProperty name: String) -> ListValueKind {
        if let definition = pointTypes.definition(forKey: name) {
            switch definition.type {
            case .choice: return .choice(definition.choices ?? values(name))
            case .person: return .person
            case .rating: return .rating(definition.stars)
            case .note: return .note
            }
        }
        switch propertyTypes.type(forKey: name) ?? guessedType(ofProperty: name) {
        case .text:
            // A few values used again and again (a format, a status): chosen from a menu, like
            // the others, rather than typed.
            if let summary = summary(of: name), summary.distinctValues > 0, summary.distinctValues <= 30,
               summary.valueCount >= summary.distinctValues * 3 {
                return .choice(values(name))
            }
            return .text
        case .list, .aliases: return .list
        case .tags: return .tag
        case .number: return .number
        case .checkbox: return .checkbox
        case .date, .datetime: return .date
        }
    }

    /// A property's type when none is set: from how its values read across the vault.
    public func guessedType(ofProperty name: String) -> PropertyType {
        if name.lowercased() == "tags" { return .tags }
        if name.lowercased() == "aliases" { return .aliases }
        guard let summary = summary(of: name) else { return .text }
        if summary.listCount * 2 > summary.noteCount { return .list }
        if summary.valueCount > 0, summary.dateValues * 2 > summary.valueCount { return .date }
        if summary.valueCount > 0, summary.numberValues * 2 > summary.valueCount { return .number }
        let values = values(name)
        if !values.isEmpty, values.allSatisfy({ ["true", "false"].contains($0.lowercased()) }) { return .checkbox }
        return .text
    }

    public func kind(of subject: ListFilterSubject) -> ListValueKind {
        switch subject {
        case .folder: .folder
        case .tag: .tag
        case .linksTo: .note
        case .hasWords: .text
        case .field(.title): .text
        case .field(.folder): .folder
        case .field: .date
        case .property(let name): kind(ofProperty: name)
        }
    }

    private func summary(of name: String) -> SearchIndex.PropertySummary? {
        summaries.first { $0.id == name.lowercased() }
    }

    // MARK: How a list reads

    /// A condition as it reads, in the filters' words ("read has no value", "published is
    /// before 6 Nov 2026"): a token on the Mac, a line on the phone.
    public func reading(_ condition: ListCondition) -> String {
        let kind = kind(of: ListFilterRow(condition: condition).subject)
        if condition.op.isAboutNote { return condition.written }
        var value = condition.value
        switch condition.op {
        case .inLastDays, .inNextDays:
            if let amount = condition.amount {
                value = "\(amount.count) " + (amount.count == 1 ? String(amount.unit.rawValue.dropLast()) : amount.unit.rawValue)
            }
        case .between:
            if let range = condition.range { value = "\(Self.shownDate(range.from)) and \(Self.shownDate(range.to))" }
        case .is, .before, .after:
            if kind == .date { value = Self.shownDate(value) }
        default: break
        }
        if kind == .checkbox { value = "" }
        return [condition.subject, kind.label(condition.op), condition.op.takesValue ? value : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A day as the apps show it (6 Nov 2026), for a day written in a list (2026-11-06).
    public static func shownDate(_ written: String) -> String {
        PropertyDate.parse(written).map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? written
    }

    /// The list as one line: where its notes come from, its conditions joined by "and" or
    /// "or", and its order. "In Reading · format is Book · by published".
    public func summary(of list: ListDefinition) -> String {
        var parts = list.folders.map { "In " + ($0.isEmpty ? "the vault" : $0) }
        parts += list.tags.map { "Tagged #" + $0 }
        let conditions = list.conditions.map(reading)
        if !conditions.isEmpty { parts.append(conditions.joined(separator: list.matchesAny ? " or " : " and ")) }
        if parts.isEmpty { parts.append("Every note") }
        let sort = list.sort.first ?? NoteQuery.Sort(.modified, descending: true)
        let key: String = switch sort.key {
        case .field(let field): ListDefinition.name(of: field)
        case .property(let name): name
        }
        parts.append("by " + key)
        return parts.joined(separator: " · ")
    }
}
