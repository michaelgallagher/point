import Foundation

public enum PlainText {
    /// The first line of text after any frontmatter, with Markdown markers removed:
    /// `# My **idea**` gives `My idea`. Nil if the note has no text.
    public static func firstLine(of markdown: String) -> String? {
        let text = markdown as NSString
        let tokens = MarkdownParser.parse(markdown)
        var location = tokens.first { $0.kind == .frontmatter }.map { NSMaxRange($0.range) } ?? 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let hidden = tokens.flatMap(\.syntax).filter { NSIntersectionRange($0, line).length > 0 }
            let visible = String(decoding: (line.location..<NSMaxRange(line))
                .filter { index in !hidden.contains { NSLocationInRange(index, $0) } }
                .map { text.character(at: $0) }, as: UTF16.self)
            let trimmed = visible.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            location = NSMaxRange(line)
        }
        return nil
    }
}
