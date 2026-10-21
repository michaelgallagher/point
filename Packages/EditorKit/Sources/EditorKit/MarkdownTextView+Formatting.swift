#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Formatting commands. Each one edits the Markdown text directly, as one undoable change.
/// The app's menus send these selectors to the first responder.
extension MarkdownTextView {
    // MARK: Inline styles

    @objc public func toggleBold(_ sender: Any?) { toggleInline("**", kind: .strong) }
    @objc public func toggleItalic(_ sender: Any?) { toggleInline("*", kind: .emphasis) }
    @objc public func toggleHighlight(_ sender: Any?) { toggleInline("==", kind: .highlight) }
    @objc public func toggleStrikethrough(_ sender: Any?) { toggleInline("~~", kind: .strikethrough) }

    /// Removes the style if the selection is already inside it; otherwise wraps the
    /// selection (or the word at the cursor) in `marker`.
    func toggleInline(_ marker: String, kind: MarkdownToken.Kind) {
        let text = string as NSString
        var selection = selectedRange()

        // Already styled: remove the innermost matching span around the selection.
        if let token = tokens.filter({ $0.kind == kind && NSLocationInRange(selection.location, NSRange(location: $0.range.location, length: $0.range.length + 1)) && NSMaxRange(selection) <= NSMaxRange($0.range) })
            .min(by: { $0.range.length < $1.range.length }),
           let open = token.syntax.first, let close = token.syntax.last {
            let inner = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
            let location = min(max(selection.location - open.length, token.range.location), token.range.location + inner.length)
            let length = min(selection.length, token.range.location + inner.length - location)
            replace(token.range, with: text.substring(with: inner), select: NSRange(location: location, length: length))
            return
        }

        if selection.length == 0 {
            let word = wordRange(at: selection.location)
            if word.length > 0 {
                selection = word
            } else {
                // Nothing to wrap: insert an empty pair and type inside it.
                replace(selection, with: marker + marker, select: NSRange(location: selection.location + (marker as NSString).length, length: 0))
                return
            }
        }

        // Spaces just inside the markers would stop the style from applying, so leave them out.
        selection = trimmingWhitespace(selection)
        guard selection.length > 0 else { return }
        let length = (marker as NSString).length
        replace(selection, with: marker + text.substring(with: selection) + marker,
                select: NSRange(location: selection.location + length, length: selection.length))
    }

    func wordRange(at location: Int) -> NSRange {
        let text = string as NSString
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
        let text = string as NSString
        var start = range.location, end = NSMaxRange(range)
        while start < end, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: start)) ?? " ") { start += 1 }
        while end > start, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: end - 1)) ?? " ") { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Line styles

    @objc public func makeBodyText(_ sender: Any?) { setHeading(0) }
    @objc public func makeHeading1(_ sender: Any?) { setHeading(1) }
    @objc public func makeHeading2(_ sender: Any?) { setHeading(2) }
    @objc public func makeHeading3(_ sender: Any?) { setHeading(3) }
    @objc public func makeHeading4(_ sender: Any?) { setHeading(4) }
    @objc public func makeHeading5(_ sender: Any?) { setHeading(5) }
    @objc public func makeHeading6(_ sender: Any?) { setHeading(6) }

    /// A line split into its leading whitespace, its block marker (`## `, `- [ ] `) and its text.
    struct LineParts {
        var indent: String
        var marker: String
        var content: String
        var listMarker: ListMarker?
        var headingLevel: Int?
    }

    func parts(ofLineAt range: NSRange) -> LineParts {
        let text = string as NSString
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
        let text = string as NSString
        let selection = selectedRange()
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

    /// Rewrites each selected line, as one undoable change, keeping the cursor on the same text.
    func rewriteSelectedLines(_ transform: (LineParts) -> LineParts) {
        let lines = selectedLineRanges()
        guard let first = lines.first, let last = lines.last else { return }
        let text = string as NSString
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let selection = selectedRange()

        var rebuilt = text.substring(with: whole)
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
        rebuilt = pieces.joined(separator: "\n")
        let newLength = (rebuilt as NSString).length
        let cursor = min(max(selection.location + cursorShift, first.location), first.location + newLength)
        let select = lines.count == 1
            ? NSRange(location: cursor, length: min(selection.length, first.location + newLength - cursor))
            : NSRange(location: first.location, length: newLength)
        replace(whole, with: rebuilt, select: select)
    }

    func setHeading(_ level: Int) {
        rewriteSelectedLines { line in
            var line = line
            let isSame = line.headingLevel == level
            line.indent = ""
            line.listMarker = nil
            line.marker = level == 0 || isSame ? "" : String(repeating: "#", count: level) + " "
            return line
        }
    }

    @objc public func toggleBulletList(_ sender: Any?) { toggleList(task: false) }
    @objc public func toggleChecklist(_ sender: Any?) { toggleList(task: true) }

    func toggleList(task: Bool) {
        let lines = selectedLineRanges().map { parts(ofLineAt: $0) }
        let allAlready = lines.allSatisfy { line in
            switch line.listMarker {
            case .task?: task
            case .bullet?: !task
            default: false
            }
        }
        rewriteSelectedLines { line in
            var line = line
            line.marker = allAlready ? "" : (task ? "- [ ] " : "- ")
            if allAlready { line.indent = "" }
            return line
        }
    }

    // MARK: Indenting

    @objc public func moveLinesUp(_ sender: Any?) { moveLines(down: false) }
    @objc public func moveLinesDown(_ sender: Any?) { moveLines(down: true) }

    /// Moves the line with the cursor (or every line the selection touches) up or down past
    /// its neighbour, keeping the selection on it, as one undoable edit.
    func moveLines(down: Bool) {
        let text = string as NSString
        let selection = selectedRange()
        // A selection that ends at the very start of a line doesn't take that line along.
        var end = NSMaxRange(selection)
        if selection.length > 0, end > 0, text.character(at: end - 1) == 10 { end -= 1 }
        let block = text.lineRange(for: NSRange(location: selection.location, length: max(0, end - selection.location)))
        let offset = selection.location - block.location

        /// A line's text and its line break ("" for the last line of the note).
        func split(_ line: String) -> (String, String) {
            if line.hasSuffix("\r\n") { return (String(line.dropLast(2)), "\r\n") }
            if line.hasSuffix("\n") || line.hasSuffix("\r") { return (String(line.dropLast()), String(line.suffix(1))) }
            return (line, "")
        }

        if down {
            guard NSMaxRange(block) < text.length else { return NSSound.beep() }
            let below = text.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let (blockText, blockBreak) = split(text.substring(with: block))
            let (belowText, belowBreak) = split(text.substring(with: below))
            // The last line has no break of its own; the moved lines end up last and give it theirs.
            let newBelow = belowText + blockBreak
            let replacement = newBelow + blockText + belowBreak
            let union = NSRange(location: block.location, length: NSMaxRange(below) - block.location)
            let start = block.location + (newBelow as NSString).length
            let length = min(selection.length, union.location + (replacement as NSString).length - start - offset)
            replace(union, with: replacement, select: NSRange(location: start + offset, length: max(0, length)))
        } else {
            guard block.location > 0 else { return NSSound.beep() }
            let above = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let (blockText, blockBreak) = split(text.substring(with: block))
            let (aboveText, aboveBreak) = split(text.substring(with: above))
            let replacement = blockText + aboveBreak + aboveText + blockBreak
            let union = NSRange(location: above.location, length: NSMaxRange(block) - above.location)
            replace(union, with: replacement, select: NSRange(location: above.location + offset, length: selection.length))
        }
    }

    @objc public func indentLines(_ sender: Any?) { changeIndent(by: 1) }
    @objc public func outdentLines(_ sender: Any?) { changeIndent(by: -1) }

    /// Indents or outdents list items by a tab, Obsidian's default. Other lines are left alone:
    /// an indented paragraph would turn into a code block.
    func changeIndent(by step: Int) {
        let lines = selectedLineRanges().map { parts(ofLineAt: $0) }
        guard lines.contains(where: { $0.listMarker != nil }) else {
            NSSound.beep()
            return
        }
        rewriteSelectedLines { line in
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

    public override func insertTab(_ sender: Any?) {
        if selectedLineRanges().contains(where: { parts(ofLineAt: $0).listMarker != nil }) {
            changeIndent(by: 1)
        } else {
            super.insertTab(sender)
        }
    }

    public override func insertBacktab(_ sender: Any?) {
        if selectedLineRanges().contains(where: { parts(ofLineAt: $0).listMarker != nil }) {
            changeIndent(by: -1)
        } else {
            super.insertBacktab(sender)
        }
    }

    // MARK: Return continues lists and quotes

    public override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0, let line = selectedLineRanges().first else {
            return super.insertNewline(sender)
        }
        let text = string as NSString
        let parts = parts(ofLineAt: line)

        if let listMarker = parts.listMarker {
            if parts.content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty item outdents it, or ends the list at the top level.
                if !parts.indent.isEmpty {
                    changeIndent(by: -1)
                } else {
                    replace(line, with: "")
                }
                return
            }
            let next: String
            switch listMarker {
            case .bullet: next = String(parts.marker.prefix(1)) + " "
            case .task: next = String(parts.marker.prefix(1)) + " [ ] "
            case .ordered(let number):
                let delimiter = parts.marker.trimmingCharacters(in: .whitespaces).last.map(String.init) ?? "."
                next = "\(number + 1)\(delimiter) "
            }
            insertText("\n" + parts.indent + next, replacementRange: selection)
            return
        }

        if let quote = tokens.first(where: { ($0.kind == .blockquote || { if case .callout = $0.kind { true } else { false } }($0)) && NSLocationInRange(line.location, $0.range) }) {
            let marker = quote.syntax.first { $0.location >= line.location && $0.location <= NSMaxRange(line) && text.character(at: $0.location) != 91 }
            let markerLength = marker.map { NSMaxRange($0) - line.location } ?? 0
            let content = text.substring(with: NSRange(location: line.location + markerLength, length: line.length - markerLength))
            if content.trimmingCharacters(in: .whitespaces).isEmpty, markerLength > 0, line.location != quote.range.location {
                replace(line, with: "") // An empty quoted line ends the quote.
                return
            }
            insertText("\n> ", replacementRange: selection)
            return
        }
        super.insertNewline(sender)
    }

    // MARK: Links

    /// Asks for a URL and links the selection to it.
    @objc public func addLink(_ sender: Any?) {
        let selection = selectedRange()
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "Enter the address to link to."
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "https://"
        if let clip = NSPasteboard.general.string(forType: .string), Self.isURL(clip) {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            self.link(selection, to: url)
        }
    }

    func link(_ range: NSRange, to url: String) {
        let text = string as NSString
        let selection = trimmingWhitespace(range)
        let label = selection.length > 0 ? text.substring(with: selection) : url
        let destination = url.contains(" ") ? "<\(url)>" : url
        let replacement = "[\(label)](\(destination))"
        replace(selection, with: replacement, select: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    static func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "obsidian"].contains(scheme) && (scheme == "mailto" || url.host != nil || scheme == "obsidian")
    }

    /// Pasting a URL over selected text links the text instead of replacing it. Pasting a
    /// list item (say, one picked up with a triple-click) into another list item drops its
    /// own marker, and the line break after it, so it doesn't arrive as "- - item".
    public override func paste(_ sender: Any?) {
        let selection = selectedRange()
        guard let clip = NSPasteboard.general.string(forType: .string) else { return super.paste(sender) }
        if selection.length > 0, Self.isURL(clip) {
            link(selection, to: clip.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        let text = string as NSString
        let before = text.substring(with: NSRange(location: lineStart(of: selection.location), length: selection.location - lineStart(of: selection.location)))
        if let merged = Self.withoutListMarker(clip, pastedAfter: before) {
            insertText(merged, replacementRange: selection)
            return
        }
        super.paste(sender)
    }

    /// A list marker at the start of a line: indent, `-`, `*`, `+` or `1.`, and a checkbox.
    private static let listMarkerPattern = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#)

    /// `clip` without the list marker on its first line (and one line break at its end), when
    /// it's going into a list item after its marker (`before` is the line up to the cursor);
    /// nil when it should paste as it is.
    static func withoutListMarker(_ clip: String, pastedAfter before: String) -> String? {
        func markerLength(_ line: String) -> Int? {
            let range = NSRange(location: 0, length: (line as NSString).length)
            return listMarkerPattern.firstMatch(in: line, range: range).map(\.range.length)
        }
        guard let target = markerLength(before), (before as NSString).length >= target,
              let marker = markerLength(clip) else { return nil }
        var result = (clip as NSString).substring(from: marker)
        if result.hasSuffix("\r\n") { result.removeLast(1) } else if result.hasSuffix("\n") { result.removeLast() }
        return result
    }

    /// ⌘X with nothing selected cuts the whole line (a list item, say), line break and all,
    /// ready to paste somewhere else. False if there's no line to cut.
    func cutWholeLine() -> Bool {
        let selection = selectedRange()
        let text = string as NSString
        guard selection.length == 0, text.length > 0 else { return false }
        let line = text.lineRange(for: NSRange(location: min(selection.location, text.length), length: 0))
        let lineText = text.substring(with: line)
        guard !lineText.isEmpty else { return false }
        var removed = line
        // The last line has no line break of its own: remove the one before it instead, so
        // no empty line is left behind.
        if !lineText.hasSuffix("\n"), line.location > 0 {
            removed = NSRange(location: line.location - 1, length: line.length + 1)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lineText.hasSuffix("\n") ? lineText : lineText + "\n", forType: .string)
        guard shouldChangeText(in: removed, replacementString: "") else { return true }
        replaceCharacters(in: removed, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: min(removed.location, (string as NSString).length), length: 0))
        return true
    }

    // MARK: Checkboxes

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let line = foldArrowLine(at: point) {
            setFolded(!folds.contains(line), line: line)
            return
        }
        if toggleCheckbox(at: point) { return }
        if openLink(for: event) { return } // ⌥-click places the cursor in a link instead.
        super.mouseDown(with: event)
    }

    /// Ticks or unticks the checkbox at a point in the view, if there is one there.
    func toggleCheckbox(at point: NSPoint) -> Bool {
        guard let layoutManager = imprintLayoutManager, let container = textContainer, let storage = textStorage else { return false }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let index = layoutManager.characterIndexForPoint(local, in: container)
        let lineStart = lineStart(of: min(index, max(storage.length - 1, 0)))
        guard let token = tokens.first(where: { $0.range.location == lineStart }),
              case .listItem(.task(let done), _) = token.kind,
              let decoration = storage.attribute(.imprintListMarker, at: lineStart, effectiveRange: nil) as? ListMarkerDecoration,
              let marker = token.syntax.first else { return false }

        let line = layoutManager.lineRect(containing: lineStart, storage: storage)
        let font = layoutManager.textFont(near: lineStart, storage: storage)
        let visible = layoutManager.firstVisibleCharacter(onLineOf: lineStart, storage: storage)
        let baseline = line.minY + (visible.map { layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: $0)).y } ?? font.ascender)
        let x = container.lineFragmentPadding + layoutManager.theme.indentPerLevel * CGFloat(decoration.level)
        let box = layoutManager.checkboxRect(x: x, baseline: baseline, font: font).insetBy(dx: -5, dy: -5)
        guard box.contains(local) else { return false }

        let text = string as NSString
        let bracket = text.range(of: "[", options: [], range: marker)
        guard bracket.location != NSNotFound else { return false }
        let state = NSRange(location: bracket.location + 1, length: 1)
        let previous = selectedRange()
        replace(state, with: done ? " " : "x", select: previous)
        return true
    }
}

extension NSLayoutManager {
    /// The character nearest a point in the text container.
    func characterIndexForPoint(_ point: NSPoint, in container: NSTextContainer) -> Int {
        let glyph = glyphIndex(for: point, in: container)
        return characterIndexForGlyph(at: glyph)
    }
}
#endif
