import Foundation
import MarkdownKit

/// Lists written in a note, as `list` blocks, found in its text, for both editors.
enum ListBlocks {
    /// The lines between the fences of the note's `index`th closed `list` block (from 0, as
    /// `BlockEmbed.list` counts them), each with its line break.
    static func body(at index: Int, tokens: [MarkdownToken], text: NSString) -> NSRange? {
        var count = 0
        for token in tokens {
            guard case .codeBlock(let language) = token.kind, language == MarkdownStyler.listLanguage else { continue }
            defer { count += 1 }
            guard count == index else { continue }
            guard token.syntax.count == 2 else { return nil }
            let opening = text.lineRange(for: token.syntax[0]), closing = text.lineRange(for: token.syntax[1])
            return NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening))
        }
        return nil
    }

    /// The whole of the note's `index`th closed `list` block, its fences too: from the start
    /// of its opening fence's line to the end of its closing fence's, without its line break.
    static func block(at index: Int, tokens: [MarkdownToken], text: NSString) -> NSRange? {
        var count = 0
        for token in tokens {
            guard case .codeBlock(let language) = token.kind, language == MarkdownStyler.listLanguage else { continue }
            defer { count += 1 }
            guard count == index else { continue }
            guard token.syntax.count == 2 else { return nil }
            let start = text.lineRange(for: token.syntax[0]).location
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: token.syntax[1])
            return NSRange(location: start, length: contentsEnd - start)
        }
        return nil
    }

    /// Which of the note's `list` blocks (from 0) starts at `location`, nil if none does.
    static func index(ofBlockAt location: Int, tokens: [MarkdownToken]) -> Int? {
        var count = 0
        for token in tokens {
            guard case .codeBlock(let language) = token.kind, language == MarkdownStyler.listLanguage else { continue }
            if token.range.location == location { return count }
            count += 1
        }
        return nil
    }
}
