import Foundation

/// How notes made by Point are named: the name you see is their `title:` property, and the
/// file is named from the day the note was made and the title, `2026-11-06-questions-about-my-vault.md`.
///
/// Only notes named this way take their title from `title:`. Every other note's title is its
/// file name, as before, even if it has a `title:` property (many notes clipped from the web
/// do, and their names mustn't change).
public enum NoteNames {
    /// A title as it goes in a file name: lowercase plain letters and digits joined by hyphens.
    /// Accents and other scripts become plain letters (`Café` gives `cafe`, `東京` gives
    /// `dong-jing`), emoji and punctuation go. Long titles stay long. Empty if nothing's left.
    public static func slug(_ title: String) -> String {
        // Other scripts to Latin letters, then to plain ones (é to e, ß to ss, Œ to OE).
        let latin = title.applyingTransform(.toLatin, reverse: false) ?? title
        let plain = latin.applyingTransform(StringTransform("Latin-ASCII"), reverse: false)
            ?? latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        var slug = ""
        var pendingHyphen = false
        for scalar in plain.lowercased().unicodeScalars {
            // Plain letters and digits only; anything else (spaces, punctuation, emoji) parts words.
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !slug.isEmpty { slug.append("-") }
                pendingHyphen = false
                slug.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "’" {
                continue // "Mike's" is "mikes", not "mike-s".
            } else {
                pendingHyphen = true
            }
        }
        return slug
    }

    /// The day part of a name: `2026-11-06`.
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// A new note's name (without `.md`): its day and its title, or `untitled` without one.
    public static func name(for title: String, created: Date, calendar: Calendar = .current) -> String {
        day(created, calendar: calendar) + "-" + (slug(title).isEmpty ? "untitled" : slug(title))
    }

    /// A new note's name until it has a title: the day and the time it was made
    /// (`2026-11-10-untitled-213809`), so two devices making notes the same day don't pick the
    /// same name (counting up, each picked the first free one it knew of).
    public static func untitledName(created: Date, calendar: Calendar = .current) -> String {
        let time = calendar.dateComponents([.hour, .minute, .second], from: created)
        return day(created, calendar: calendar) + "-untitled-"
            + String(format: "%02d%02d%02d", time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
    }

    /// A note named with its title, keeping the day it was made: `2026-11-06-old` retitled
    /// "New" becomes `2026-11-06-new`.
    public static func renamed(_ name: String, to title: String) -> String? {
        guard let day = day(of: name) else { return nil }
        return day + "-" + (slug(title).isEmpty ? "untitled" : slug(title))
    }

    private static let pattern = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})-[a-z0-9]+(?:-[a-z0-9]+)*$"#)

    /// Whether a file name (without `.md`) is one Point gave a note: a day, then a slug.
    public static func isDated(_ name: String) -> Bool { day(of: name) != nil }

    /// The day a Point-named note was made, from its name.
    public static func day(of name: String) -> String? {
        let ns = name as NSString
        guard let match = pattern.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// The title to show for a Point-named note whose `title:` can't be read (not downloaded
    /// yet, say): its name without the day, in words.
    public static func fallbackTitle(for name: String) -> String {
        guard let day = day(of: name) else { return name }
        // Untitled, however it's numbered (`-untitled-213809`, `-untitled-3`): the number only
        // keeps names apart.
        if name.dropFirst(day.count + 1).range(of: #"^untitled(-\d+)?$"#, options: .regularExpression) != nil { return "Untitled" }
        let words = name.dropFirst(day.count + 1).replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// A note's `title:` property, if it has one that isn't empty.
    public static func title(in text: String) -> String? {
        guard let property = Frontmatter.parse(text)?.properties.first(where: { $0.key.lowercased() == "title" }),
              let value = property.values.first?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    /// The title to show for the note named `name` at `url`: for a Point-named note, its
    /// `title:` (read from the file's start), else its name.
    public static func shownTitle(name: String, url: URL, isDownloaded: Bool = true) -> String {
        guard isDated(name) else { return name }
        guard isDownloaded, let text = readStart(of: url), let title = title(in: text) else { return fallbackTitle(for: name) }
        return title
    }

    /// The start of a file, enough for its frontmatter.
    private static func readStart(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The edit that sets a note's `title:`: the value changed where it is, or the property
    /// added first in its frontmatter, or frontmatter made for it.
    public static func edit(settingTitle title: String, in text: String) -> (NSRange, String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard let frontmatter = Frontmatter.parse(text) else {
            return (NSRange(location: 0, length: 0), "---\n" + Frontmatter.yaml(key: "title", values: [value], isList: false) + "---\n")
        }
        if let existing = frontmatter.properties.first(where: { $0.key.lowercased() == "title" }) {
            return frontmatter.edit(setting: existing.key, to: [value], isList: false)
        }
        // First, just after the opening `---`.
        let ns = text as NSString
        let opening = ns.lineRange(for: NSRange(location: frontmatter.range.location, length: 0))
        return (NSRange(location: NSMaxRange(opening), length: 0), Frontmatter.yaml(key: "title", values: [value], isList: false))
    }

    /// A note's text with its `title:` set.
    public static func settingTitle(_ title: String, in text: String) -> String {
        let (range, replacement) = edit(settingTitle: title, in: text)
        return (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}
