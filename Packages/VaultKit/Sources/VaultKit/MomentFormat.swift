import Foundation

/// Formats dates with moment.js format strings, as Obsidian does for daily notes and
/// templates (`YYYY-MM-DD`, `dddd D MMMM`, `[Week] w`).
///
/// Tokens are matched the way moment matches them, longest first, so unusual formats give
/// the same result as in Obsidian. Text in `[square brackets]` is copied literally.
public struct MomentFormat: Sendable {
    public let format: String
    public var locale = Locale(identifier: "en_US_POSIX")
    public var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    public init(_ format: String) {
        self.format = format
    }

    /// Moment's tokens that Imprint supports, longest first within each letter.
    private static let tokens = [
        "YYYYYY", "YYYYY", "YYYY", "YY", "Y",
        "MMMM", "MMM", "MM", "Mo", "M",
        "DDDD", "DDD", "DD", "Do", "D",
        "dddd", "ddd", "dd", "do", "d",
        "HH", "H", "hh", "h", "kk", "k", "mm", "m", "ss", "s",
        "A", "a", "Q", "WW", "W", "ww", "w", "GGGG", "gggg", "E", "e", "X", "x",
    ]

    public func string(from date: Date) -> String {
        var result = ""
        var rest = Substring(format)
        while let first = rest.first {
            if first == "[", let close = rest.firstIndex(of: "]") {
                result += rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                continue
            }
            if first == "\\", rest.count > 1 {
                result.append(rest[rest.index(after: rest.startIndex)])
                rest = rest.dropFirst(2)
                continue
            }
            if let token = Self.tokens.first(where: { rest.hasPrefix($0) }) {
                result += value(of: token, for: date)
                rest = rest.dropFirst(token.count)
            } else {
                result.append(first)
                rest = rest.dropFirst()
            }
        }
        return result
    }

    private func value(of token: String, for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday, .weekOfYear, .yearForWeekOfYear], from: date)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let isoComponents = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let year = c.year!, month = c.month!, day = c.day!, hour = c.hour!, minute = c.minute!, second = c.second!
        let weekday = c.weekday! - 1 // Sunday = 0, as in moment.
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(abs(value))
            return (value < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        func symbol(_ symbols: [String], _ index: Int) -> String { symbols[index] }
        let formatter = DateFormatter()
        formatter.locale = locale
        switch token {
        case "YYYYYY": return (year < 0 ? "-" : "+") + pad(abs(year), 6)
        case "YYYYY": return pad(year, 5)
        case "YYYY": return pad(year, 4)
        case "YY": return pad(year % 100, 2)
        case "Y": return year <= 9999 ? pad(year, 4) : "+\(year)"
        case "MMMM": return symbol(formatter.monthSymbols, month - 1)
        case "MMM": return symbol(formatter.shortMonthSymbols, month - 1)
        case "MM": return pad(month, 2)
        case "Mo": return ordinal(month)
        case "M": return String(month)
        case "DDDD", "DDD":
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            return token == "DDDD" ? pad(dayOfYear, 3) : String(dayOfYear)
        case "DD": return pad(day, 2)
        case "Do": return ordinal(day)
        case "D": return String(day)
        case "dddd": return symbol(formatter.weekdaySymbols, weekday)
        case "ddd": return symbol(formatter.shortWeekdaySymbols, weekday)
        case "dd": return String(symbol(formatter.shortWeekdaySymbols, weekday).prefix(2))
        case "do": return ordinal(weekday)
        case "d", "e": return String(weekday)
        case "E": return String(weekday == 0 ? 7 : weekday)
        case "HH": return pad(hour, 2)
        case "H": return String(hour)
        case "hh": return pad(hour % 12 == 0 ? 12 : hour % 12, 2)
        case "h": return String(hour % 12 == 0 ? 12 : hour % 12)
        case "kk": return pad(hour == 0 ? 24 : hour, 2)
        case "k": return String(hour == 0 ? 24 : hour)
        case "mm": return pad(minute, 2)
        case "m": return String(minute)
        case "ss": return pad(second, 2)
        case "s": return String(second)
        case "A": return hour < 12 ? "AM" : "PM"
        case "a": return hour < 12 ? "am" : "pm"
        case "Q": return String((month - 1) / 3 + 1)
        case "WW": return pad(isoComponents.weekOfYear!, 2)
        case "W": return String(isoComponents.weekOfYear!)
        case "ww": return pad(c.weekOfYear!, 2)
        case "w": return String(c.weekOfYear!)
        case "GGGG": return pad(isoComponents.yearForWeekOfYear!, 4)
        case "gggg": return pad(c.yearForWeekOfYear!, 4)
        case "X": return String(Int(date.timeIntervalSince1970))
        case "x": return String(Int(date.timeIntervalSince1970 * 1000))
        default: return token
        }
    }

    private func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}
