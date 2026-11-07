import Foundation
import VaultKit

/// What came before a note, by what it's about. Point shows it as a line under a note's
/// properties, opening to the list.
/// - **By people,** for a note with a type, people and a day: the earlier notes of its type with
///   any of the same people, newest first, such as the earlier meetings with whoever's in this
///   one ("4 earlier meetings · last on 21 October").
/// - **By topics,** for a note with topics and no people: every other note with any of the same
///   topics, of whatever type, such as the posts, sources and meetings on what a post is about
///   ("23 notes on Org design and Service design").
public struct Recall: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        case people
        case topics
    }
    public var basis: Basis
    /// The note's type ("Meeting"), if it has one.
    public var type: String?
    /// The people or topics in it, by name: `[[Sam Lee]]` is "Sam Lee".
    public var names: [String]
    /// Its day, `yyyy-MM-dd`, by people: its `date:`, else the day its file name starts with.
    public var day: String?
    /// The properties the people or topics are in.
    public var propertyNames: [String]
    /// The notes, newest first. By topics, the note itself is among them.
    public var query: NoteQuery

    /// What came before the note named `name` with this frontmatter, or nil if it has neither
    /// a type, people and a day, nor topics. People are in `personProperties` (those of Point's
    /// person kind, or `people`), topics in `topicProperties`; its type is in `typeProperty`
    /// (the kinds' property, `type`).
    public init?(frontmatter: Frontmatter?, name: String, typeProperty: String = "type",
                 personProperties: [String] = ["people"], topicProperties: [String] = ["topics"]) {
        guard let frontmatter else { return nil }
        func values(_ key: String) -> [String] {
            frontmatter.properties.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }.flatMap(\.values)
        }
        func names(in keys: [String]) -> [String] {
            var seen = Set<String>()
            return keys.flatMap(values).compactMap(Self.personName).filter { seen.insert($0.lowercased()).inserted }
        }
        let type = values(typeProperty).first?.trimmingCharacters(in: .whitespaces)
        self.type = type?.isEmpty == false ? type : nil
        let people = names(in: personProperties)
        let byDate = [NoteQuery.Sort(.property("date"), descending: true), NoteQuery.Sort(.modified, descending: true)]
        if !people.isEmpty {
            guard let type = self.type, let day = values("date").lazy.compactMap(Self.day).first ?? Self.day(name) else { return nil }
            basis = .people
            self.names = people
            self.day = day
            propertyNames = personProperties
            query = NoteQuery([
                .property(typeProperty, .equals(type)),
                .any(personProperties.flatMap { key in people.map { .property(key, .equals($0)) } }),
                .property("date", .less(day)),
            ], sort: byDate)
        } else {
            let topics = names(in: topicProperties)
            guard !topics.isEmpty else { return nil }
            basis = .topics
            self.names = topics
            day = nil
            propertyNames = topicProperties
            query = NoteQuery([.any(topicProperties.flatMap { key in topics.map { .property(key, .equals($0)) } })], sort: byDate)
        }
    }

    /// A person's name from a value: the note a link goes to, else the text.
    public static func personName(_ value: String) -> String? {
        var name = value.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[["), name.hasSuffix("]]"), name.count > 4 {
            name = String(name.dropFirst(2).dropLast(2).split(separator: "|", maxSplits: 1).first ?? "")
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The `yyyy-MM-dd` a value or file name starts with, if it's a real day.
    public static func day(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.count >= 10 else { return nil }
        let start = String(text.prefix(10))
        guard start.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              dayFormatter.date(from: start) != nil else { return nil }
        if text.count > 10, let next = text.dropFirst(10).first, next.isNumber { return nil }
        return start
    }

    /// A `yyyy-MM-dd` day as a date (its start, in the current time zone).
    public static func dayDate(_ day: String) -> Date? { dayFormatter.date(from: day) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    /// A day as it's shown: "21 October", or "21 October 2025" outside this year.
    public static func shown(day: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(sameYear ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year())
    }

    /// The line under the properties: by people, "4 earlier meetings · last on 21 October";
    /// by topics, "23 notes on Org design and Service design" (with more than two topics, "on
    /// these 3 topics").
    public func summary(count: Int, lastDay: String?, now: Date = Date()) -> String {
        switch basis {
        case .people:
            return Self.summary(count: count, type: type ?? "note", lastDay: lastDay, now: now)
        case .topics:
            let on = names.count <= 2 ? ListFormatter.localizedString(byJoining: names) : "these \(names.count) topics"
            return "\(count.formatted()) \(count == 1 ? "note" : "notes") on \(on)"
        }
    }

    /// Who or what the list is of: "With Sam Lee and Ann Cole", "On Org design".
    public var heading: String {
        (basis == .people ? "With " : "On ") + ListFormatter.localizedString(byJoining: names)
    }

    /// "1 earlier meeting · on 21 October", "4 earlier meetings · last on 21 October".
    public static func summary(count: Int, type: String, lastDay: String?, now: Date = Date()) -> String {
        let noun = type.lowercased()
        var text = "\(count.formatted()) earlier \(count == 1 ? noun : plural(noun))"
        if let lastDay { text += (count == 1 ? " · on " : " · last on ") + shown(day: lastDay, now: now) }
        return text
    }

    private static func plural(_ noun: String) -> String {
        if noun.hasSuffix("s") || noun.hasSuffix("x") || noun.hasSuffix("ch") || noun.hasSuffix("sh") { return noun + "es" }
        if noun.hasSuffix("y"), let before = noun.dropLast().last, !"aeiou".contains(before) { return noun.dropLast() + "ies" }
        return noun + "s"
    }
}

/// What a recall list shows of each note, read from the index for the first `shown`: its day,
/// its type, who or what it shares with the note, and its first line (read by the app).
public struct RecallDetails: Sendable {
    /// How many are listed; more are rarely wanted.
    public static let shown = 100
    public var days: [String: String] = [:]
    public var types: [String: String] = [:]
    public var shared: [String: [String]] = [:]
    public var lines: [String: String] = [:]

    public init() {}

    /// The properties to read for a recall's list.
    public static func keys(for recall: Recall, typeProperty: String) -> [String] {
        ["date", typeProperty] + recall.propertyNames
    }

    /// Takes in what the index gave (by note, then by property in lowercase). A note without a
    /// `date:` has the day its file name starts with, from `name`.
    public mutating func take(_ values: [String: [String: [String]]], for ids: [String], recall: Recall,
                              typeProperty: String, name: (String) -> String?) {
        let wanted = Set(recall.names.map { $0.lowercased() })
        for id in ids {
            let row = values[id] ?? [:]
            days[id] = row["date"]?.lazy.compactMap(Recall.day).first ?? name(id).flatMap(Recall.day)
            types[id] = row[typeProperty.lowercased()]?.first?.trimmingCharacters(in: .whitespaces)
            shared[id] = recall.propertyNames.flatMap { row[$0.lowercased()] ?? [] }
                .compactMap(Recall.personName).filter { wanted.contains($0.lowercased()) }
        }
    }

    /// The day and what's shared: "21 October · Sam Lee".
    public func detail(_ id: String, now: Date = Date()) -> String? {
        let parts = [days[id].map { Recall.shown(day: $0, now: now) },
                     shared[id].flatMap { $0.isEmpty ? nil : ListFormatter.localizedString(byJoining: $0) }]
        let detail = parts.compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    /// The first `shown` notes in groups: by people, one group without a title; by topics, one
    /// for each type, the note's own first, then the biggest, untyped notes last ("Other").
    /// Each keeps the order it was given (newest first).
    public func groups(of ids: [String], recall: Recall) -> [(title: String, ids: [String])] {
        let shown = Array(ids.prefix(Self.shown))
        guard recall.basis == .topics else { return [("", shown)] }
        var order: [String] = []
        var members: [String: [String]] = [:]
        for id in shown {
            let type = types[id].flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
            if members[type] == nil { order.append(type) }
            members[type, default: []].append(id)
        }
        let own = recall.type?.lowercased()
        order.sort { a, b in
            let ranks = [a, b].map { $0.lowercased() == own ? 0 : $0 == "Other" ? 2 : 1 }
            if ranks[0] != ranks[1] { return ranks[0] < ranks[1] }
            return members[a]!.count != members[b]!.count ? members[a]!.count > members[b]!.count : a < b
        }
        return order.map { ($0, members[$0]!) }
    }
}
