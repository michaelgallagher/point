import Foundation
import VaultKit

/// Reader mode (see plan/reader-mode.md): which notes open for reading, what's said about one
/// above its text, how long it takes to read, and where the reader was in it.
public enum Reading {
    /// Whether a note opens for reading rather than writing: one of the clip kind (Media, or
    /// whatever `Clipping.kind(in:)` finds). The one place this is decided.
    public static func opensForReading(_ text: String, kinds: NoteKinds) -> Bool {
        guard let clips = Clipping.kind(in: kinds), let kind = kinds.kind(of: text) else { return false }
        return kind.name.caseInsensitiveCompare(clips.name) == .orderedSame
    }

    /// Words a minute, for the time it takes to read.
    static let wordsPerMinute = 230

    /// Minutes to read `text` (its frontmatter left out), at least one.
    public static func minutes(toRead text: String) -> Int {
        let body = Frontmatter.parse(text).map { (text as NSString).substring(from: NSMaxRange($0.range)) } ?? text
        var words = 0
        body.enumerateSubstrings(in: body.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }

    /// The line under a clip's title: who wrote it, where, when, and how long it takes to read.
    /// "Ann Lee and Bo Ng · example.com · 3 Nov 2025 · 12 min read". Links are shown as their
    /// names; anything not known is left out.
    public static func byline(of frontmatter: Frontmatter?, minutes: Int, locale: Locale = .current) -> String {
        func values(_ key: String) -> [String] {
            let property = frontmatter?.properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
            return (property?.values ?? []).map(shown).filter { !$0.isEmpty }
        }
        var parts: [String] = []
        let authors = values("author")
        if !authors.isEmpty { parts.append(ListFormatter.localizedString(byJoining: authors)) }
        if let source = values("source").first, let host = URL(string: source)?.host() {
            parts.append(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
        }
        if let published = values("published").first { parts.append(day(published, locale: locale) ?? published) }
        parts.append("\(minutes) min read")
        return parts.joined(separator: " · ")
    }

    /// A property's value as read: `[[Ann Lee]]` and `[[Ann Lee|Ann]]` as their names.
    static func shown(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
        value = String(value.dropFirst(2).dropLast(2))
        if let bar = value.firstIndex(of: "|") { return String(value[value.index(after: bar)...]) }
        return value
    }

    /// `2025-11-03` as "3 Nov 2025" (in the reader's own way); a year alone stays as it is.
    static func day(_ text: String, locale: Locale) -> String? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// Where the reader was in a note: the start of the paragraph at the top of the screen,
    /// kept as its first few words and where it was. Not a scroll offset, which a change of text
    /// size or an edit on another device would leave pointing somewhere else.
    public struct Place: Codable, Equatable, Sendable {
        /// The paragraph's first characters.
        public var anchor: String
        /// Where the paragraph started (UTF-16).
        public var location: Int

        public init(anchor: String, location: Int) {
            self.anchor = anchor
            self.location = location
        }
    }

    /// How much of a paragraph is kept to find it again.
    static let anchorLength = 60

    /// The place for `location` in `text`: the paragraph it's in.
    public static func place(at location: Int, in text: String) -> Place {
        let ns = text as NSString
        let at = min(max(location, 0), ns.length)
        let line = ns.lineRange(for: NSRange(location: min(at, max(ns.length - 1, 0)), length: 0))
        let start = ns.length == 0 ? 0 : line.location
        let length = min(anchorLength, max(0, NSMaxRange(line) - start))
        var anchor = ns.substring(with: NSRange(location: start, length: length))
        if let newline = anchor.firstIndex(of: "\n") { anchor = String(anchor[..<newline]) }
        return Place(anchor: anchor, location: start)
    }

    /// Where `place` is in `text` now: its paragraph, the occurrence nearest where it was, or
    /// failing that (the paragraph's gone), where it was, as far as the text still reaches.
    public static func location(of place: Place, in text: String) -> Int {
        let ns = text as NSString
        let fallback = min(max(place.location, 0), ns.length)
        guard !place.anchor.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
        var best: Int?
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let found = ns.range(of: place.anchor, options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            // Only at the start of a line, as a paragraph starts.
            if found.location == 0 || ns.character(at: found.location - 1) == 10 {
                if best.map({ abs($0 - place.location) > abs(found.location - place.location) }) ?? true { best = found.location }
            }
            let next = found.location + 1
            search = NSRange(location: next, length: ns.length - next)
        }
        return best ?? fallback
    }
}
