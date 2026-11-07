import Foundation
import VaultKit

/// What came before a note: the earlier notes of its type with any of the same people, such as
/// the earlier meetings with whoever's in this one. Point shows it as a line under a note's
/// properties ("4 earlier meetings · last on 21 October"), opening to the list.
public struct Recall: Equatable, Sendable {
    /// The note's type ("Meeting").
    public var type: String
    /// The people in it, by name: `[[Sam Lee]]` is "Sam Lee".
    public var people: [String]
    /// Its day, `yyyy-MM-dd`: its `date:`, else the day its file name starts with.
    public var day: String
    /// The properties people are in.
    public var personPropertyNames: [String]
    /// The earlier notes, newest first.
    public var query: NoteQuery

    /// What came before the note named `name` with this frontmatter, or nil if it has no type,
    /// no people or no day. People are in `personProperties` (those of Point's person kind, or
    /// `people`); its type is in `typeProperty` (the kinds' property, `type`).
    public init?(frontmatter: Frontmatter?, name: String, typeProperty: String = "type", personProperties: [String] = ["people"]) {
        guard let frontmatter else { return nil }
        func values(_ key: String) -> [String] {
            frontmatter.properties.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }.flatMap(\.values)
        }
        guard let type = values(typeProperty).first?.trimmingCharacters(in: .whitespaces), !type.isEmpty else { return nil }
        var seen = Set<String>()
        let people = personProperties.flatMap(values).compactMap(Self.personName).filter { seen.insert($0.lowercased()).inserted }
        guard !people.isEmpty, let day = values("date").lazy.compactMap(Self.day).first ?? Self.day(name) else { return nil }
        self.type = type
        self.people = people
        self.day = day
        personPropertyNames = personProperties
        let shared: [NoteQuery.Filter] = personProperties.flatMap { key in people.map { .property(key, .equals($0)) } }
        query = NoteQuery([
            .property(typeProperty, .equals(type)),
            .any(shared),
            .property("date", .less(day)),
        ], sort: [NoteQuery.Sort(.property("date"), descending: true)])
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

    /// The line under the properties: "4 earlier meetings · last on 21 October", or
    /// "1 earlier meeting · on 21 October".
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
