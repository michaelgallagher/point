import Foundation
import VaultKit

/// Your notes on a clip, above its saved text (see plan/reader-mode.md): everything between the
/// properties and the marker, a line of its own, `==---- Text ----==`. Everything after the
/// marker is the saved text.
public enum ReaderNotes {
    /// The marker, as Obsidian's Web Clipper notes already have it: it shows itself as a
    /// highlight, and can't be taken for a heading the article starts with.
    public static let marker = "==---- Text ----=="

    /// Where the note's body starts: after its frontmatter's closing line, or 0.
    static func bodyStart(of text: String) -> Int {
        let ns = text as NSString
        guard let frontmatter = Frontmatter.parse(text) else { return 0 }
        let end = NSMaxRange(frontmatter.range)
        guard end < ns.length else { return ns.length }
        // The closing `---` and its line break.
        let line = ns.lineRange(for: NSRange(location: max(end - 1, 0), length: 0))
        return max(end, NSMaxRange(line))
    }

    /// The marker's line (without its line break): the first line that's exactly the marker,
    /// spaces around it aside, after the properties. Nil if there's none.
    public static func markerLine(in text: String) -> NSRange? {
        let ns = text as NSString
        let start = bodyStart(of: text)
        var found: NSRange?
        ns.enumerateSubstrings(in: NSRange(location: start, length: ns.length - start), options: .byLines) { line, range, _, stop in
            if line?.trimmingCharacters(in: .whitespaces) == marker {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    /// Your notes, without the blank lines around them; empty if there are none, or no marker.
    public static func notes(in text: String) -> String {
        guard let marker = markerLine(in: text) else { return "" }
        let start = bodyStart(of: text)
        return (text as NSString).substring(with: NSRange(location: start, length: marker.location - start))
            .trimmingCharacters(in: .newlines)
    }

    /// `text` with your notes set to `notes`: between the properties and the marker, a blank
    /// line between them and the marker, the rest left exactly as it was. A note without the
    /// marker gets it, straight under the properties, so everything already in it counts as
    /// saved text.
    public static func settingNotes(_ notes: String, in text: String) -> String {
        let ns = text as NSString
        let start = bodyStart(of: text)
        var head = ns.substring(to: start)
        if !head.isEmpty, !head.hasSuffix("\n") { head += "\n" }
        let trimmed = notes.trimmingCharacters(in: .newlines).replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
        let block = trimmed.trimmingCharacters(in: .whitespaces).isEmpty ? "" : trimmed + "\n\n"
        if let line = markerLine(in: text) {
            return head + block + ns.substring(from: line.location)
        }
        let rest = ns.substring(from: start).replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
        return head + block + marker + (rest.isEmpty ? "\n" : "\n\n" + rest)
    }

    /// Adds `quote` to the end of your notes, as a quote (`> …`, a line each) in a paragraph of
    /// its own, and returns the text with where the cursor goes for a comment under it.
    public static func addingQuote(_ quote: String, to notes: String) -> (notes: String, cursor: Int) {
        let lines = quote.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let quoted = lines.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> " + $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (existing.isEmpty ? "" : existing + "\n\n") + quoted + "\n\n"
        return (result, (result as NSString).length)
    }
}
