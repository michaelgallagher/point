import Foundation
import MarkdownKit

/// One change to a note's text: what's replaced, with what, and where the selection ends up.
public struct MarkdownEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
    /// The styles held at the cursor afterwards, for what's typed next.
    public var held: HeldMarkers? = nil

    /// Whether the text changes, rather than only the cursor or the held styles.
    public var changesText: Bool { range.length > 0 || !replacement.isEmpty }
}

/// Inline style markers held at the cursor for what's typed next, so a style can be turned on
/// before its text is typed without an empty pair of markers ever being seen.
public struct HeldMarkers: Equatable, Sendable {
    public let location: Int
    /// The outermost first.
    public let markers: [String]

    public init(location: Int, markers: [String]) {
        self.location = location
        self.markers = markers
    }

    /// The markers held once `marker` is toggled at `location`: added, or let go if it was
    /// held there already. Nil when none are left.
    static func toggling(_ held: HeldMarkers?, _ marker: String, at location: Int) -> HeldMarkers? {
        var markers = held?.location == location ? held!.markers : []
        if let index = markers.firstIndex(of: marker) { markers.remove(at: index) } else { markers.append(marker) }
        return markers.isEmpty ? nil : HeldMarkers(location: location, markers: markers)
    }
}

/// The formatting commands as plain edits to a note's text: the Mac's `MarkdownTextView` and
/// the iPhone's editor both make them. Each returns nil when it has nothing to do.
public struct MarkdownEditing {
    let text: NSString
    let tokens: [MarkdownToken]
    let selection: NSRange
    let held: HeldMarkers?

    public init(text: String, selection: NSRange, held: HeldMarkers? = nil) {
        self.init(text: text, tokens: MarkdownParser.parse(text), selection: selection, held: held)
    }

    /// With the text's tokens already parsed.
    public init(text: String, tokens: [MarkdownToken], selection: NSRange, held: HeldMarkers? = nil) {
        self.text = text as NSString
        self.tokens = tokens
        self.selection = selection
        self.held = held
    }

    // MARK: Inline styles

    public func toggleBold() -> MarkdownEdit? { toggleInline("**", kind: .strong) }
    public func toggleItalic() -> MarkdownEdit? { toggleInline("*", kind: .emphasis) }
    public func toggleHighlight() -> MarkdownEdit? { toggleInline("==", kind: .highlight) }
    public func toggleStrikethrough() -> MarkdownEdit? { toggleInline("~~", kind: .strikethrough) }
    public func toggleCode() -> MarkdownEdit? { toggleInline("`", kind: .code) }

    private static let styleKinds: [MarkdownToken.Kind] = [.strong, .emphasis, .highlight, .strikethrough, .code]

    /// The styled spans whose text ends at `location`, the innermost first: the cursor is
    /// there while their text is being typed, before their closing markers.
    private func spans(endingAt location: Int) -> [MarkdownToken] {
        var spans: [MarkdownToken] = []
        var at = location
        while let span = tokens.first(where: { Self.styleKinds.contains($0.kind) && $0.syntax.count == 2 && $0.syntax[1].location == at }) {
            spans.append(span)
            at = NSMaxRange(span.syntax[1])
        }
        return spans
    }

    /// The styled spans that end just before `location`, closing markers and all, the
    /// outermost first.
    private func spans(endedAt location: Int) -> [MarkdownToken] {
        var spans: [MarkdownToken] = []
        var at = location
        while let span = tokens.first(where: { Self.styleKinds.contains($0.kind) && $0.syntax.count == 2 && NSMaxRange($0.range) == at }) {
            spans.append(span)
            at = span.syntax[1].location
        }
        return spans
    }

    /// Turns a style on or off. With a selection, wraps it in `marker` or, if it's already
    /// in that style, takes the style off. With a cursor, as typing in a word processor:
    /// - while typing the style's text, at its end, the style stops there;
    /// - just after text in the style, it carries on;
    /// - inside a word, the whole word is styled, or unstyled;
    /// - anywhere else, the style is held for what's typed next.
    func toggleInline(_ marker: String, kind: MarkdownToken.Kind) -> MarkdownEdit? {
        var selection = selection
        let cursor = NSRange(location: selection.location, length: 0)

        if selection.length == 0 {
            // At the end of the style's text: out past its closing markers, holding any styles
            // inside it for what's typed next.
            let ending = spans(endingAt: selection.location)
            if let index = ending.firstIndex(where: { $0.kind == kind }) {
                // Only inside styles that go on: out past its own closing marker, into theirs.
                if index == 0, ending.count > 1 {
                    return MarkdownEdit(range: cursor, replacement: "", selection: NSRange(location: NSMaxRange(ending[0].range), length: 0))
                }
                let after = NSMaxRange(ending.last!.range)
                let kept = ending.enumerated().filter { $0.offset != index }.reversed().map { text.substring(with: $0.element.syntax[0]) }
                return MarkdownEdit(range: cursor, replacement: "", selection: NSRange(location: after, length: 0),
                                    held: kept.isEmpty ? nil : HeldMarkers(location: after, markers: kept))
            }
            // Just after text in the style: back inside it, to carry on with it.
            if let span = spans(endedAt: selection.location).first(where: { $0.kind == kind }) {
                return MarkdownEdit(range: cursor, replacement: "", selection: NSRange(location: span.syntax[1].location, length: 0))
            }
        }

        // Already styled: remove the innermost matching span around the selection.
        if let token = tokens.filter({ $0.kind == kind && NSLocationInRange(selection.location, $0.range) && NSMaxRange(selection) <= NSMaxRange($0.range)
                                        && (selection.length > 0 || selection.location > $0.range.location) })
            .min(by: { $0.range.length < $1.range.length }),
           let open = token.syntax.first, let close = token.syntax.last {
            let inner = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
            let location = min(max(selection.location - open.length, token.range.location), token.range.location + inner.length)
            let length = min(selection.length, token.range.location + inner.length - location)
            return MarkdownEdit(range: token.range, replacement: text.substring(with: inner), selection: NSRange(location: location, length: length))
        }

        if selection.length == 0 {
            // A cursor in a link takes in the whole link, and one inside a word, the word.
            let link = tokens.wideningToLinks(selection)
            let word = wordRange(at: selection.location)
            if link.length > 0 {
                selection = link
            } else if word.location < selection.location, selection.location < NSMaxRange(word) {
                selection = word
            } else {
                return MarkdownEdit(range: cursor, replacement: "", selection: cursor,
                                    held: HeldMarkers.toggling(held, marker, at: selection.location))
            }
        }

        // Spaces just inside the markers would stop the style from applying, so leave them out.
        selection = tokens.wideningToLinks(trimmingWhitespace(selection))
        guard selection.length > 0 else { return nil }
        let length = (marker as NSString).length
        return MarkdownEdit(range: selection, replacement: marker + text.substring(with: selection) + marker,
                            selection: NSRange(location: selection.location + length, length: selection.length))
    }

    /// Text typed at the cursor, where the styles need it to go somewhere other than the
    /// cursor, or nil to type it there as usual:
    /// - where styles are held, inside their markers, so they're never seen empty;
    /// - a space at the end of a style's text, just after its closing markers, with the style
    ///   held for the next word (a style's text can't end with a space). That word then joins
    ///   the run, the markers moving to after it, so it's still one run in the Markdown.
    public func typing(_ typed: String) -> MarkdownEdit? {
        guard selection.length == 0, !typed.isEmpty, !typed.contains(where: \.isNewline) else { return nil }
        let location = selection.location
        let isSpace = typed.allSatisfy(\.isWhitespace)
        let length = (typed as NSString).length

        if let held, held.location == location {
            // Spaces before the text: the styles wait after them.
            if isSpace {
                return MarkdownEdit(range: selection, replacement: typed, selection: NSRange(location: location + length, length: 0),
                                    held: HeldMarkers(location: location + length, markers: held.markers))
            }
            // The next word after styled text and a space: into the same run, its closing
            // markers moved to after the word, so the Markdown stays one run.
            var start = location
            while start > 0, let scalar = Unicode.Scalar(text.character(at: start - 1)), scalar == " " || scalar == "\t" { start -= 1 }
            let ended = spans(endedAt: start)
            if start < location, ended.count == held.markers.count,
               ended.map({ text.substring(with: $0.syntax[0]) }) == held.markers, let inner = ended.last {
                let closing = NSRange(location: inner.syntax[1].location, length: start - inner.syntax[1].location)
                let spaces = text.substring(with: NSRange(location: start, length: location - start))
                let moved = spaces + typed
                return MarkdownEdit(range: NSRange(location: closing.location, length: location - closing.location),
                                    replacement: moved + text.substring(with: closing),
                                    selection: NSRange(location: closing.location + (moved as NSString).length, length: 0))
            }
            let open = held.markers.joined(), close = held.markers.reversed().joined()
            return MarkdownEdit(range: selection, replacement: open + typed + close,
                                selection: NSRange(location: location + (open as NSString).length + length, length: 0))
        }

        let ending = spans(endingAt: location).filter { $0.kind != .code }
        guard isSpace, !ending.isEmpty, ending.count == spans(endingAt: location).count else { return nil }
        let after = NSMaxRange(ending.last!.range)
        return MarkdownEdit(range: NSRange(location: after, length: 0), replacement: typed,
                            selection: NSRange(location: after + length, length: 0),
                            held: HeldMarkers(location: after + length, markers: ending.reversed().map { text.substring(with: $0.syntax[0]) }))
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

    /// (Half of an emoji, a lone surrogate, isn't a space.)
    func trimmingWhitespace(_ range: NSRange) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        while start < end, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: start)) ?? "x") { start += 1 }
        while end > start, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: end - 1)) ?? "x") { end -= 1 }
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
    public func toggleNumberedList() -> MarkdownEdit? {
        let lines = selectedLineRanges()
        guard let first = lines.first else { return nil }
        var above: LineParts?
        if first.location > 0 {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: first.location - 1, length: 0))
            above = parts(ofLineAt: NSRange(location: start, length: contentsEnd - start))
        }
        let all = lines.map { parts(ofLineAt: $0) }
        var numbering = ListNumbering(lines: all.map { ($0.indent, $0.listMarker) }, above: above.map { ($0.indent, $0.listMarker) })
        return rewriteSelectedLines { line in
            var line = line
            let (indent, marker) = numbering.next(indent: line.indent)
            line.marker = marker
            line.indent = indent
            return line
        }
    }

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
        return headingStartNewline()
    }

    /// Return at the start of a heading's text (just after its hidden `## `, where the cursor
    /// shows at the line's start) adds a line above, and the heading moves down whole, its
    /// marker with it, rather than leaving the marker behind on an empty heading above.
    /// Nil anywhere else, and on an empty heading.
    public func headingStartNewline() -> MarkdownEdit? {
        guard selection.length == 0, let line = selectedLineRanges().first,
              let heading = tokens.first(where: {
                  if case .heading = $0.kind { return $0.range.location == line.location }
                  return false
              }),
              let marker = heading.syntax.first, marker.location == line.location,
              selection.location >= line.location, selection.location <= NSMaxRange(marker) else { return nil }
        // Something after the marker: an empty heading breaks as an ordinary line.
        var contentsEnd = 0
        text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: line.location, length: 0))
        guard contentsEnd > NSMaxRange(marker) else { return nil }
        return MarkdownEdit(range: NSRange(location: line.location, length: 0), replacement: "\n",
                            selection: NSRange(location: selection.location + 1, length: 0))
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

/// Numbered List's markers for the lines it's turning into (or out of) a numbered list, shared
/// by both editors. Each indent level counts from 1, or on from a numbered item just above at
/// the same level; going back out to a shallower level forgets the deeper counts.
struct ListNumbering {
    /// Whether every line is a numbered item already, so the command takes the numbers off.
    let removing: Bool
    private var counts: [String: Int] = [:]

    init(lines: [(indent: String, marker: ListMarker?)], above: (indent: String, marker: ListMarker?)?) {
        removing = lines.allSatisfy { if case .ordered? = $0.marker { true } else { false } }
        if case .ordered(let number)? = above?.marker, let indent = above?.indent { counts[indent] = number + 1 }
    }

    /// The indent and marker for the next line, which has `indent` now.
    mutating func next(indent: String) -> (indent: String, marker: String) {
        guard !removing else { return ("", "") }
        counts = counts.filter { $0.key.count <= indent.count }
        let number = counts[indent] ?? 1
        counts[indent] = number + 1
        return (indent, "\(number). ")
    }
}
