import Foundation
import MarkdownKit

/// One change to a note's text: what's replaced, with what, and where the selection ends up.
public struct MarkdownEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

/// The formatting commands as plain edits to a note's text, for the iPhone's editor: what the
/// Mac's `MarkdownTextView` does in place, without a text view. `MarkdownEditingTests` holds
/// each command to the Mac's result. Each returns nil when it has nothing to do.
public struct MarkdownEditing {
    let text: NSString
    let tokens: [MarkdownToken]
    let selection: NSRange

    public init(text: String, selection: NSRange) {
        self.text = text as NSString
        self.selection = selection
        tokens = MarkdownParser.parse(text)
    }

    // MARK: Inline styles

    public func toggleBold() -> MarkdownEdit? { toggleInline("**", kind: .strong) }
    public func toggleItalic() -> MarkdownEdit? { toggleInline("*", kind: .emphasis) }
    public func toggleHighlight() -> MarkdownEdit? { toggleInline("==", kind: .highlight) }
    public func toggleStrikethrough() -> MarkdownEdit? { toggleInline("~~", kind: .strikethrough) }
    public func toggleCode() -> MarkdownEdit? { toggleInline("`", kind: .code) }

    /// Removes the style if the selection is already inside it; otherwise wraps the
    /// selection (or the word at the cursor) in `marker`.
    func toggleInline(_ marker: String, kind: MarkdownToken.Kind) -> MarkdownEdit? {
        var selection = selection

        // Already styled: remove the innermost matching span around the selection.
        if let token = tokens.filter({ $0.kind == kind && NSLocationInRange(selection.location, NSRange(location: $0.range.location, length: $0.range.length + 1)) && NSMaxRange(selection) <= NSMaxRange($0.range) })
            .min(by: { $0.range.length < $1.range.length }),
           let open = token.syntax.first, let close = token.syntax.last {
            let inner = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
            let location = min(max(selection.location - open.length, token.range.location), token.range.location + inner.length)
            let length = min(selection.length, token.range.location + inner.length - location)
            return MarkdownEdit(range: token.range, replacement: text.substring(with: inner), selection: NSRange(location: location, length: length))
        }

        if selection.length == 0 {
            let word = wordRange(at: selection.location)
            if word.length > 0 {
                selection = word
            } else {
                // Nothing to wrap: insert an empty pair and type inside it.
                return MarkdownEdit(range: selection, replacement: marker + marker, selection: NSRange(location: selection.location + (marker as NSString).length, length: 0))
            }
        }

        // Spaces just inside the markers would stop the style from applying, so leave them out.
        selection = trimmingWhitespace(selection)
        guard selection.length > 0 else { return nil }
        let length = (marker as NSString).length
        return MarkdownEdit(range: selection, replacement: marker + text.substring(with: selection) + marker,
                            selection: NSRange(location: selection.location + length, length: selection.length))
    }

    func wordRange(at location: Int) -> NSRange {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’"
        }
        var start = location, end = location
        while isWordCharacter(start - 1) { start -= 1 }
        while isWordCharacter(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    func trimmingWhitespace(_ range: NSRange) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        while start < end, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: start)) ?? " ") { start += 1 }
        while end > start, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: end - 1)) ?? " ") { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Lines

    /// A line split into its leading whitespace, its block marker (`## `, `- [ ] `) and its text.
    struct LineParts {
        var indent: String
        var marker: String
        var content: String
        var listMarker: ListMarker?
        var headingLevel: Int?
    }

    func parts(ofLineAt range: NSRange) -> LineParts {
        let line = text.substring(with: range)
        let token = tokens.first { $0.isBlock && $0.range.location == range.location }
        switch token?.kind {
        case .heading(let level)?:
            let marker = text.substring(with: token!.syntax[0])
            return LineParts(indent: "", marker: marker, content: String(line.dropFirst(marker.count)), headingLevel: level)
        case .listItem(let listMarker, _)?:
            let markerRange = token!.syntax[0]
            let indent = text.substring(with: NSRange(location: range.location, length: markerRange.location - range.location))
            let content = text.substring(with: NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(range) - NSMaxRange(markerRange)))
            return LineParts(indent: indent, marker: text.substring(with: markerRange), content: content, listMarker: listMarker)
        default:
            return LineParts(indent: "", marker: "", content: line)
        }
    }

    /// The lines touched by the selection, as content ranges without line breaks.
    func selectedLineRanges() -> [NSRange] {
        let paragraphs = text.paragraphRange(for: selection)
        var lines: [NSRange] = []
        var location = paragraphs.location
        repeat {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            lines.append(NSRange(location: start, length: contentsEnd - start))
            location = end
        } while location < NSMaxRange(paragraphs)
        return lines
    }

    /// Rewrites each selected line, keeping the cursor on the same text.
    func rewriteSelectedLines(_ transform: (LineParts) -> LineParts) -> MarkdownEdit? {
        let lines = selectedLineRanges()
        guard let first = lines.first, let last = lines.last else { return nil }
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)

        var cursorShift = 0
        var pieces: [String] = []
        for (index, line) in lines.enumerated() {
            let old = parts(ofLineAt: line)
            let new = transform(old)
            pieces.append(new.indent + new.marker + new.content)
            if index == 0 {
                cursorShift = (new.indent + new.marker as NSString).length - (old.indent + old.marker as NSString).length
            }
        }
        let rebuilt = pieces.joined(separator: "\n")
        let newLength = (rebuilt as NSString).length
        let cursor = min(max(selection.location + cursorShift, first.location), first.location + newLength)
        let select = lines.count == 1
            ? NSRange(location: cursor, length: min(selection.length, first.location + newLength - cursor))
            : NSRange(location: first.location, length: newLength)
        return MarkdownEdit(range: whole, replacement: rebuilt, selection: select)
    }

    /// Makes the selected lines a heading of `level`, or body text (0, or the level they are).
    public func setHeading(_ level: Int) -> MarkdownEdit? {
        rewriteSelectedLines { line in
            var line = line
            let isSame = line.headingLevel == level
            line.indent = ""
            line.listMarker = nil
            line.marker = level == 0 || isSame ? "" : String(repeating: "#", count: level) + " "
            return line
        }
    }

    /// Quotes the lines the selection touches (`> ` before each), or unquotes them if they're
    /// all quoted already.
    public func toggleBlockQuote() -> MarkdownEdit? {
        let lines = selectedLineRanges()
        guard let first = lines.first, let last = lines.last else { return nil }
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let contents = lines.map { text.substring(with: $0) }
        let allQuoted = contents.allSatisfy { $0.hasPrefix(">") }
        let rebuilt = contents.map { line -> String in
            guard allQuoted else { return "> " + line }
            return String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1))
        }.joined(separator: "\n")
        let newLength = (rebuilt as NSString).length
        let select: NSRange
        if lines.count == 1 {
            // The cursor keeps its place in the text, past the marker added or taken away.
            let shift = newLength - whole.length
            let cursor = min(max(selection.location + shift, first.location), first.location + newLength)
            select = NSRange(location: cursor, length: min(selection.length, first.location + newLength - cursor))
        } else {
            select = NSRange(location: first.location, length: newLength)
        }
        return MarkdownEdit(range: whole, replacement: rebuilt, selection: select)
    }

    public func toggleBulletList() -> MarkdownEdit? { toggleList(task: false) }
    public func toggleChecklist() -> MarkdownEdit? { toggleList(task: true) }

    func toggleList(task: Bool) -> MarkdownEdit? {
        let lines = selectedLineRanges().map { parts(ofLineAt: $0) }
        let allAlready = lines.allSatisfy { line in
            switch line.listMarker {
            case .task?: task
            case .bullet?: !task
            default: false
            }
        }
        return rewriteSelectedLines { line in
            var line = line
            line.marker = allAlready ? "" : (task ? "- [ ] " : "- ")
            if allAlready { line.indent = "" }
            return line
        }
    }

    public func indent() -> MarkdownEdit? { changeIndent(by: 1) }
    public func outdent() -> MarkdownEdit? { changeIndent(by: -1) }

    /// Indents or outdents list items by a tab, Obsidian's default. Other lines are left alone:
    /// an indented paragraph would turn into a code block.
    func changeIndent(by step: Int) -> MarkdownEdit? {
        let lines = selectedLineRanges().map { parts(ofLineAt: $0) }
        guard lines.contains(where: { $0.listMarker != nil }) else { return nil }
        return rewriteSelectedLines { line in
            guard line.listMarker != nil else { return line }
            var line = line
            if step > 0 {
                line.indent = "\t" + line.indent
            } else if line.indent.hasPrefix("\t") {
                line.indent.removeFirst()
            } else {
                line.indent = String(line.indent.dropFirst(min(4, line.indent.prefix { $0 == " " }.count)))
            }
            return line
        }
    }

    // MARK: Return continues lists and quotes

    /// What Return does in a list or a quote; nil for an ordinary line break.
    public func newline() -> MarkdownEdit? {
        guard selection.length == 0, let line = selectedLineRanges().first else { return nil }
        let parts = parts(ofLineAt: line)

        if let listMarker = parts.listMarker {
            if parts.content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty item outdents it, or ends the list at the top level.
                return parts.indent.isEmpty
                    ? MarkdownEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
                    : changeIndent(by: -1)
            }
            let next: String
            switch listMarker {
            case .bullet: next = String(parts.marker.prefix(1)) + " "
            case .task: next = String(parts.marker.prefix(1)) + " [ ] "
            case .ordered(let number):
                let delimiter = parts.marker.trimmingCharacters(in: .whitespaces).last.map(String.init) ?? "."
                next = "\(number + 1)\(delimiter) "
            }
            return inserting("\n" + parts.indent + next)
        }

        if let quote = tokens.first(where: { ($0.kind == .blockquote || { if case .callout = $0.kind { true } else { false } }($0)) && NSLocationInRange(line.location, $0.range) }) {
            let marker = quote.syntax.first { $0.location >= line.location && $0.location <= NSMaxRange(line) && text.character(at: $0.location) != 91 }
            let markerLength = marker.map { NSMaxRange($0) - line.location } ?? 0
            let content = text.substring(with: NSRange(location: line.location + markerLength, length: line.length - markerLength))
            if content.trimmingCharacters(in: .whitespaces).isEmpty, markerLength > 0, line.location != quote.range.location {
                // An empty quoted line ends the quote.
                return MarkdownEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
            }
            return inserting("\n> ")
        }
        return nil
    }

    /// Puts `string` in place of the selection, the cursor after it.
    public func inserting(_ string: String) -> MarkdownEdit {
        MarkdownEdit(range: selection, replacement: string, selection: NSRange(location: selection.location + (string as NSString).length, length: 0))
    }

    // MARK: Links

    /// Links the selection to a note: `[[selection]]`, or an empty `[[]]` to type in, the
    /// cursor inside the brackets, ready for suggestions.
    public func wikiLink() -> MarkdownEdit? {
        let inner = trimmingWhitespace(selection)
        guard inner.length > 0 else {
            return MarkdownEdit(range: selection, replacement: "[[]]", selection: NSRange(location: selection.location + 2, length: 0))
        }
        let replacement = "[[" + text.substring(with: inner) + "]]"
        return MarkdownEdit(range: inner, replacement: replacement, selection: NSRange(location: inner.location + (replacement as NSString).length, length: 0))
    }

    // MARK: Completing

    /// What's being typed at the cursor that can be completed: `partial`, after `[[` or `#`, at
    /// `range`.
    public struct Completion: Equatable, Sendable {
        public enum Kind: Sendable { case note, tag }
        public let kind: Kind
        public let partial: String
        public let range: NSRange
    }

    /// The completion at a cursor, if there is one. Static, without parsing: it's asked each
    /// time the cursor moves.
    public static func completion(in text: String, at cursor: Int) -> Completion? {
        let text = text as NSString
        guard cursor <= text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: cursor, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: cursor - line.location)) as NSString

        let open = before.range(of: "[[", options: .backwards)
        if open.location != NSNotFound {
            let partial = before.substring(from: NSMaxRange(open))
            if !partial.contains("]") {
                return Completion(kind: .note, partial: partial, range: NSRange(location: line.location + NSMaxRange(open), length: (partial as NSString).length))
            }
        }

        // A tag: `#` at the start of a word, then what a tag can hold, up to the cursor.
        var start = before.length
        while start > 0, let scalar = Unicode.Scalar(before.character(at: start - 1)),
              CharacterSet.alphanumerics.contains(scalar) || "_-/".unicodeScalars.contains(scalar) { start -= 1 }
        guard start > 0, before.character(at: start - 1) == 35 else { return nil } // #
        if start > 1, let scalar = Unicode.Scalar(before.character(at: start - 2)), !CharacterSet.whitespaces.contains(scalar) { return nil }
        let partial = before.substring(from: start)
        return Completion(kind: .tag, partial: partial, range: NSRange(location: line.location + start, length: (partial as NSString).length))
    }

    /// Finishes a completion: a note's title with the brackets closed (past any already
    /// there), or a tag followed by a space.
    public func complete(_ completion: Completion, with choice: String) -> MarkdownEdit {
        switch completion.kind {
        case .note:
            // Up to any closing brackets on the line: the cursor can be partway through a link.
            let start = completion.range.location
            let end = NSMaxRange(completion.range)
            let line = text.lineRange(for: NSRange(location: end, length: 0))
            let close = text.range(of: "]]", options: [], range: NSRange(location: end, length: NSMaxRange(line) - end))
            guard close.location != NSNotFound else {
                let replacement = choice + "]]"
                return MarkdownEdit(range: completion.range, replacement: replacement, selection: NSRange(location: start + (replacement as NSString).length, length: 0))
            }
            return MarkdownEdit(range: NSRange(location: start, length: close.location - start), replacement: choice,
                                selection: NSRange(location: start + (choice as NSString).length + 2, length: 0))
        case .tag:
            let replacement = choice + " "
            return MarkdownEdit(range: completion.range, replacement: replacement,
                                selection: NSRange(location: completion.range.location + (replacement as NSString).length, length: 0))
        }
    }
}
