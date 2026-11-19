import Foundation
import VaultKit

/// What's typed in a list's filter field, read as words and a few short terms:
/// - plain words match the title, as they always have (`service design`; quotes keep a
///   phrase together, `"org design"`);
/// - `#tag`, with the tags nested under it;
/// - `property:value`, a property containing the value (`topics:"service design"`,
///   `format:book`), only for a property the vault has; else it's plain words, so a title
///   like `Re: plans` still matches;
/// - `property>value` and `property<value`, for numbers and dates (`published>2020`);
/// - `has:property`, given a value; `in:folder`; `title:`, `folder:` and `tag:` as facts;
/// - `is:unread` and `is:read`, by each kind's `read` property (worked out by the app);
/// - `@today`, `@yesterday`, `@thisweek`, `@thismonth`, `@thisyear`, `@7d`: edited then;
/// - `-` before any of these turns it round (`-#draft`, `-has:read`).
/// A term half typed (`#`, `topics:`) is left out, so the list doesn't empty while it's typed.
public struct FilterText: Equatable, Sendable {
    /// The plain words, as typed, joined by single spaces: matched against titles.
    public var words: String
    /// What the terms ask the index.
    public var filters: [NoteQuery.Filter]
    /// `is:unread` (true) or `is:read` (false), when given.
    public var unread: Bool?

    /// Whether there's anything beyond plain words.
    public var hasTerms: Bool { !filters.isEmpty || unread != nil }
    public var isEmpty: Bool { words.isEmpty && !hasTerms }

    /// Reads it. `isProperty` says whether the vault has a property by that name (any case).
    public init(_ text: String, now: Date = Date(), calendar: Calendar = .current, isProperty: (String) -> Bool) {
        var words: [String] = []
        var filters: [NoteQuery.Filter] = []
        var unread: Bool?
        for token in Self.tokens(text) {
            var body = token
            let negated = body.hasPrefix("-") && body.count > 1
            if negated { body.removeFirst() }
            switch Self.term(body, now: now, calendar: calendar, isProperty: isProperty) {
            case .word:
                words.append(Self.unquoted(token))
            case .partial:
                break
            case .unread(let value):
                unread = negated ? !value : value
            case .filter(let filter):
                filters.append(negated ? .not(filter) : filter)
            }
        }
        self.words = words.joined(separator: " ")
        self.filters = filters
        self.unread = unread
    }

    /// Whether a title matches the plain words.
    public func matchesTitle(_ title: String) -> Bool {
        words.isEmpty || title.localizedStandardContains(words)
    }

    // MARK: Reading

    private enum Term {
        case word, partial, unread(Bool), filter(NoteQuery.Filter)
    }

    private static let periods: [String: String] = ["thisweek": "week", "thismonth": "month", "thisyear": "year"]
    private static let facts: Set<String> = ["title", "folder", "tag", "tags", "in", "has", "is"]

    private static func term(_ token: String, now: Date, calendar: Calendar, isProperty: (String) -> Bool) -> Term {
        if token == "#" || token == "@" { return .partial }
        if token.hasPrefix("#") {
            return .filter(.tag(String(token.dropFirst())))
        }
        if token.hasPrefix("@") {
            return edited(String(token.dropFirst()).lowercased(), now: now, calendar: calendar).map(Term.filter) ?? .word
        }
        // `name:value`, `name>value`, `name<value`: the first of these marks, outside quotes.
        guard let mark = token.firstIndex(where: { ":<>".contains($0) }), mark != token.startIndex,
              !token[..<mark].contains("\"") else { return .word }
        let name = String(token[..<mark]).lowercased()
        let value = unquoted(String(token[token.index(after: mark)...]))
        let known = facts.contains(name) || isProperty(name)
        guard known else { return .word }
        guard !value.isEmpty else { return .partial }
        switch token[mark] {
        case ">": return .filter(ListCondition(name, .greater, value).filter(now: now, calendar: calendar))
        case "<": return .filter(ListCondition(name, .less, value).filter(now: now, calendar: calendar))
        default: break
        }
        switch name {
        case "is":
            switch value.lowercased() {
            case "unread": return .unread(true)
            case "read": return .unread(false)
            default: return .partial
            }
        case "has": return .filter(ListCondition(value, .isSet).filter(now: now, calendar: calendar))
        case "in", "folder": return .filter(.folder(ListDefinition.folderName(value)))
        case "tag", "tags": return .filter(.tag(value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))))
        default: return .filter(ListCondition(name, .contains, value).filter(now: now, calendar: calendar))
        }
    }

    /// `@today` and the rest: notes edited then.
    private static func edited(_ word: String, now: Date, calendar: Calendar) -> NoteQuery.Filter? {
        let condition: ListCondition
        switch word {
        case "today":
            condition = ListCondition("date edited", .inLastDays, "1")
        case "yesterday":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
            let day = NoteNames.day(yesterday, calendar: calendar)
            condition = ListCondition("date edited", .between, "\(day) and \(day)")
        default:
            if let period = periods[word] {
                condition = ListCondition("date edited", .thisPeriod, period)
            } else if word.hasSuffix("d"), let days = Int(word.dropLast()), days > 0 {
                condition = ListCondition("date edited", .inLastDays, String(days))
            } else {
                return nil
            }
        }
        return condition.filter(now: now, calendar: calendar)
    }

    /// Split at spaces outside quotes.
    public static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            if character.isWhitespace, !quoted {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func unquoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "")
    }
}

// MARK: Terms as tokens

extension FilterText {
    /// The terms a field's typed text holds, each as written, and the plain words left.
    /// For turning what's typed into tokens: the last word, still being typed, stays text
    /// unless `finished`.
    public static func splitting(_ text: String, finished: Bool, isProperty: (String) -> Bool) -> (terms: [String], rest: String) {
        var parts = tokens(text)
        let open = !finished && !(text.last?.isWhitespace ?? true) ? parts.popLast() : nil
        var terms: [String] = []
        var words: [String] = []
        for part in parts {
            let read = FilterText(part, isProperty: isProperty)
            if read.hasTerms { terms.append(part) } else if !read.words.isEmpty { words.append(part) }
        }
        var rest = words.joined(separator: " ")
        if let open { rest += (rest.isEmpty ? "" : " ") + open }
        else if !rest.isEmpty { rest += " " }
        return (terms, rest)
    }

    /// `topics:design`, or `topics:"service design"`: a property containing a value.
    public static func term(property: String, value: String) -> String {
        let value = value.replacingOccurrences(of: "\"", with: "")
        return property.lowercased() + ":" + (value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value)
    }

    /// `#tag`.
    public static func term(tag: String) -> String { "#" + tag.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }

    /// Whether a property's name can be written in a term (no spaces or marks).
    public static func canWrite(property name: String) -> Bool {
        !name.isEmpty && !name.contains(where: { $0.isWhitespace || ":<>\"#@-".contains($0) })
    }

    /// The term turned round: `#draft` and `-#draft`.
    public static func toggled(_ term: String) -> String {
        term.hasPrefix("-") ? String(term.dropFirst()) : "-" + term
    }

    /// The edited-when terms, in order, with what they say.
    public static let editedTerms: [(term: String, label: String)] = [
        ("@today", "Today"), ("@yesterday", "Yesterday"), ("@thisweek", "This week"),
        ("@thismonth", "This month"), ("@thisyear", "This year"),
    ]

    /// How a token shows a term: `Topics: design`, `Not #draft`, `Edited this week`.
    public static func label(of term: String) -> String {
        let negated = term.hasPrefix("-") && term.count > 1
        let body = negated ? String(term.dropFirst()) : term
        func capitalised(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
        if body.hasPrefix("#") { return negated ? "Not " + body : body }
        if body.hasPrefix("@") {
            let word = String(body.dropFirst()).lowercased()
            let when = editedTerms.first { $0.term == body.lowercased() }?.label.lowercased()
                ?? (word.hasSuffix("d") && Int(word.dropLast()) != nil ? "in the last \(word.dropLast()) days" : word)
            return (negated ? "Not edited " : "Edited ") + when
        }
        guard let mark = body.firstIndex(where: { ":<>".contains($0) }) else { return term }
        let name = String(body[..<mark]).lowercased()
        let value = unquoted(String(body[body.index(after: mark)...]))
        switch (name, body[mark]) {
        case ("is", _):
            let unread = (value.lowercased() == "unread") != negated
            return unread ? "Unread" : "Read"
        case ("has", _): return (negated ? "Without " : "Has ") + value
        case ("in", _), ("folder", _): return (negated ? "Not in " : "In ") + value
        case ("tag", _), ("tags", _): return (negated ? "Not #" : "#") + value
        case (_, ">"): return capitalised(name) + (negated ? " not after " : " after ") + value
        case (_, "<"): return capitalised(name) + (negated ? " not before " : " before ") + value
        default: return capitalised(name) + ": " + (negated ? "not " : "") + value
        }
    }
}
