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

    /// The note's text with Markdown markers removed (`**`, `[[`, `# `, link destinations),
    /// for search and snippets. Frontmatter keeps its contents but loses its fences, or is
    /// left out entirely. Character positions are not preserved.
    public static func strippingMarkers(from markdown: String, includingFrontmatter: Bool = true) -> String {
        let text = markdown as NSString
        var hidden: [NSRange] = []
        for token in MarkdownParser.parse(markdown) {
            if token.kind == .frontmatter, !includingFrontmatter {
                hidden.append(text.lineRange(for: token.range))
            } else if token.kind == .frontmatter {
                // Keep the properties' text, drop the `---` lines.
                let first = text.lineRange(for: NSRange(location: token.range.location, length: 0))
                let last = text.lineRange(for: NSRange(location: NSMaxRange(token.range) - 1, length: 0))
                hidden += [first, last]
            } else {
                hidden += token.syntax
            }
        }
        hidden.sort { $0.location < $1.location }
        var result = ""
        var location = 0
        for range in hidden where NSMaxRange(range) > location {
            if range.location > location {
                result += text.substring(with: NSRange(location: location, length: range.location - location))
            }
            location = NSMaxRange(range)
        }
        if location < text.length { result += text.substring(from: location) }
        return result
    }
}
