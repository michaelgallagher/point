import Foundation

/// Dates in frontmatter, as Obsidian writes them: `2026-10-18`, or with a time,
/// `2026-10-18T09:30` (or with a space instead of `T`, and optional seconds).
public enum PropertyDate {
    /// Property names that hold a date even before one is set.
    public static let names: Set<String> = ["date", "created", "modified", "updated", "due", "start", "end", "day", "when", "published"]

    public struct Value: Equatable, Sendable {
        public var date: Date
        public var hasTime: Bool
        /// `T` or a space, between the date and the time.
        public var separator: Character
        public var hasSeconds: Bool

        public init(date: Date, hasTime: Bool, separator: Character = "T", hasSeconds: Bool = false) {
            self.date = date
            self.hasTime = hasTime
            self.separator = separator
            self.hasSeconds = hasSeconds
        }
    }

    public static func parse(_ text: String, calendar: Calendar = .current) -> Value? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(whereSeparator: { $0 == "T" || $0 == " " }).map(String.init)
        guard (1...2).contains(parts.count) else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        guard day.count == 3, parts[0].count == 10 else { return nil }
        var components = DateComponents(year: day[0], month: day[1], day: day[2])
        var value = Value(date: Date(), hasTime: false, separator: "T", hasSeconds: false)
        if parts.count == 2 {
            let time = parts[1].split(separator: ":").compactMap { Int($0) }
            guard (2...3).contains(time.count) else { return nil }
            (components.hour, components.minute) = (time[0], time[1])
            components.second = time.count == 3 ? time[2] : 0
            value.hasTime = true
            value.hasSeconds = time.count == 3
            value.separator = text.contains("T") ? "T" : " "
        }
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        value.date = date
        return value
    }

    /// Writes a date in the same style as the value it replaces.
    public static func format(_ date: Date, like style: Value?, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var text = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        if let style, style.hasTime {
            text += String(style.separator) + String(format: "%02d:%02d", c.hour!, c.minute!)
            if style.hasSeconds { text += String(format: ":%02d", c.second!) }
        }
        return text
    }
}
