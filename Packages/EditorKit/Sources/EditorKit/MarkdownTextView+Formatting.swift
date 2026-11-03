#if canImport(AppKit)
import AppKit
import MarkdownKit
import SwiftUI

/// Formatting commands. Each one edits the Markdown text directly, as one undoable change.
/// The app's menus send these selectors to the first responder.
extension MarkdownTextView {
    // MARK: Inline styles

    @objc public func toggleBold(_ sender: Any?) { toggleInline("**", kind: .strong) }
    @objc public func toggleItalic(_ sender: Any?) { toggleInline("*", kind: .emphasis) }
    @objc public func toggleHighlight(_ sender: Any?) { toggleInline("==", kind: .highlight) }
    @objc public func toggleStrikethrough(_ sender: Any?) { toggleInline("~~", kind: .strikethrough) }

    /// Turns a style on or off, by `MarkdownEditing`'s rules, which the iPhone shares.
    func toggleInline(_ marker: String, kind: MarkdownToken.Kind) {
        let editing = MarkdownEditing(text: string, tokens: tokens, selection: selectedRange(), held: heldMarkers)
        if let edit = editing.toggleInline(marker, kind: kind) { apply(edit) }
    }

    /// Makes an edit, as one undoable change, and holds the styles it leaves held.
    func apply(_ edit: MarkdownEdit) {
        if edit.changesText {
            replace(edit.range, with: edit.replacement, select: edit.selection)
        } else {
            setSelectionDirectly(edit.selection)
        }
        heldMarkers = edit.held
    }

    /// Text typed at `target`, where the styles need it to go elsewhere (`MarkdownEditing.typing`).
    /// Whether it did.
    func typeForStyles(_ text: String, at target: NSRange) -> Bool {
        guard !hasMarkedText(), target == selectedRange(), heldMarkers != nil || text.allSatisfy(\.isWhitespace),
              let edit = MarkdownEditing(text: string, tokens: tokens, selection: target, held: heldMarkers).typing(text) else { return false }
        apply(edit)
        return true
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

    @objc public func toggleCode(_ sender: Any?) { toggleInline("`", kind: .code) }

    /// Quotes the lines the selection touches (`> ` before each), or unquotes them if they're
    /// all quoted already.
    @objc public func toggleBlockQuote(_ sender: Any?) {
        let lines = selectedLineRanges()
        guard let first = lines.first, let last = lines.last else { return }
        let text = string as NSString
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let contents = lines.map { text.substring(with: $0) }
        let allQuoted = contents.allSatisfy { $0.hasPrefix(">") }
        let rebuilt = contents.map { line -> String in
            guard allQuoted else { return "> " + line }
            return String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1))
        }.joined(separator: "\n")
        let newLength = (rebuilt as NSString).length
        let selection = selectedRange()
        let select: NSRange
        if lines.count == 1 {
            // The cursor keeps its place in the text, past the marker added or taken away.
            let shift = newLength - whole.length
            let cursor = min(max(selection.location + shift, first.location), first.location + newLength)
            select = NSRange(location: cursor, length: min(selection.length, first.location + newLength - cursor))
        } else {
            select = NSRange(location: first.location, length: newLength)
        }
        replace(whole, with: rebuilt, select: select)
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

    @objc public func moveLinesUp(_ sender: Any?) { movingLines { moveLines(down: false) } }
    @objc public func moveLinesDown(_ sender: Any?) { movingLines { moveLines(down: true) } }

    /// Moves the line with the cursor (or every line the selection touches) up or down past
    /// its neighbour, keeping the selection on it, as one undoable edit. A folded line and the
    /// lines it hides count as one line: they move past, or with, it whole and stay folded.
    func moveLines(down: Bool) {
        let text = string as NSString
        let selection = selectedRange()
        // A selection that ends at the very start of a line doesn't take that line along.
        var end = NSMaxRange(selection)
        if selection.length > 0, end > 0, text.character(at: end - 1) == 10 { end -= 1 }
        var block = text.lineRange(for: NSRange(location: selection.location, length: max(0, end - selection.location)))
        block = NSUnionRange(foldedUnit(around: block.location), foldedUnit(around: max(block.location, NSMaxRange(block) - 1)))
        let offset = selection.location - block.location

        /// A line's text and its line break ("" for the last line of the note).
        func split(_ line: String) -> (String, String) {
            if line.hasSuffix("\r\n") { return (String(line.dropLast(2)), "\r\n") }
            if line.hasSuffix("\n") || line.hasSuffix("\r") { return (String(line.dropLast()), String(line.suffix(1))) }
            return (line, "")
        }

        /// Puts back the folds in the lines moved, which the edit opened, where they now are.
        func refold(in union: NSRange, block: NSRange, to blockStart: Int, other: NSRange, to otherStart: Int) -> () -> Void {
            let moved = folds.filter { NSLocationInRange($0, union) }
            return { [self] in
                guard !moved.isEmpty, let storage = textStorage else { return }
                folds.subtract(moved)
                for line in moved {
                    folds.insert(NSLocationInRange(line, block) ? blockStart + line - block.location : otherStart + line - other.location)
                }
                storage.beginEditing()
                applyFolds()
                storage.endEditing()
                needsDisplay = true
            }
        }

        if down {
            guard NSMaxRange(block) < text.length else { return NSSound.beep() }
            let below = foldedUnit(around: NSMaxRange(block))
            let (blockText, blockBreak) = split(text.substring(with: block))
            let (belowText, belowBreak) = split(text.substring(with: below))
            // The last line has no break of its own; the moved lines end up last and give it theirs.
            let newBelow = belowText + blockBreak
            let replacement = newBelow + blockText + belowBreak
            let union = NSRange(location: block.location, length: NSMaxRange(below) - block.location)
            let start = block.location + (newBelow as NSString).length
            let length = min(selection.length, union.location + (replacement as NSString).length - start - offset)
            let refolding = refold(in: union, block: block, to: start, other: below, to: block.location)
            if replace(union, with: replacement, select: NSRange(location: start + offset, length: max(0, length))) { refolding() }
        } else {
            guard block.location > 0 else { return NSSound.beep() }
            let above = foldedUnit(around: block.location - 1)
            let (blockText, blockBreak) = split(text.substring(with: block))
            let (aboveText, aboveBreak) = split(text.substring(with: above))
            let replacement = blockText + aboveBreak + aboveText + blockBreak
            let union = NSRange(location: above.location, length: NSMaxRange(block) - above.location)
            let refolding = refold(in: union, block: block, to: above.location,
                                   other: above, to: above.location + (blockText + aboveBreak as NSString).length)
            if replace(union, with: replacement, select: NSRange(location: above.location + offset, length: selection.length)) { refolding() }
        }
    }

    /// The line holding `index`, or if it's folded or folded away, the outermost folded line
    /// around it and everything that fold hides.
    func foldedUnit(around index: Int) -> NSRange {
        let text = string as NSString
        var unit = text.lineRange(for: NSRange(location: min(index, text.length), length: 0))
        for line in folds {
            guard let hidden = foldRange(under: line) else { continue }
            let whole = NSRange(location: line, length: NSMaxRange(hidden) - line)
            if NSLocationInRange(unit.location, whole) { unit = NSUnionRange(unit, whole) }
        }
        return unit
    }

    @objc public func indentLines(_ sender: Any?) { movingLines { changeIndent(by: 1) } }
    @objc public func outdentLines(_ sender: Any?) { movingLines { changeIndent(by: -1) } }

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
        if moveInTable(.next) { return }
        if selectedLineRanges().contains(where: { parts(ofLineAt: $0).listMarker != nil }) {
            changeIndent(by: 1)
        } else {
            super.insertTab(sender)
        }
    }

    public override func insertBacktab(_ sender: Any?) {
        if moveInTable(.previous) { return }
        if selectedLineRanges().contains(where: { parts(ofLineAt: $0).listMarker != nil }) {
            changeIndent(by: -1)
        } else {
            super.insertBacktab(sender)
        }
    }

    // MARK: Return continues lists and quotes

    public override func insertNewline(_ sender: Any?) {
        if moveInTable(.down) { return }
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

    /// Asks for a URL, in a sheet, and links the selection to it.
    @objc public func addLink(_ sender: Any?) {
        let selection = selectedRange()
        guard let window else { return }
        var address = ""
        if let clip = NSPasteboard.general.string(forType: .string), Self.isURL(clip) {
            address = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let hosting = NSHostingController(rootView: AddLinkSheet(address: address) { _ in })
        let sheet = NSWindow(contentViewController: hosting)
        hosting.rootView = AddLinkSheet(address: address) { [weak self, weak window, weak sheet] url in
            if let sheet { window?.endSheet(sheet) }
            guard let self, let url else { return }
            self.window?.makeFirstResponder(self)
            self.link(selection, to: url)
        }
        window.beginSheet(sheet)
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
        // Into a table's cell, as one line (see `insertText`).
        if renderedTable(at: selection.location) != nil {
            insertText(clip, replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
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
        if tableControlsMouseDown(event) { return }
        if clickBelowTable(at: point) { return }
        if showHighlightMenu(at: point, for: event) { return }
        if toggleCheckbox(at: point) { return }
        if addCursor(for: event) { return } // ⌥-click adds a cursor (but not on a link).
        if openLink(for: event) { return } // ⌥-click places the cursor in a link instead.
        super.mouseDown(with: event)
    }

    /// Ticks or unticks the checkbox at a point in the view, if there is one there.
    func toggleCheckbox(at point: NSPoint) -> Bool {
        guard let layoutManager = pointLayoutManager, let container = textContainer, let storage = textStorage else { return false }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let index = layoutManager.characterIndexForPoint(local, in: container)
        let lineStart = lineStart(of: min(index, max(storage.length - 1, 0)))
        guard let token = tokens.first(where: { $0.range.location == lineStart }),
              case .listItem(.task(let done), _) = token.kind,
              let decoration = storage.attribute(.pointListMarker, at: lineStart, effectiveRange: nil) as? ListMarkerDecoration,
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

// MARK: Highlighting list items

extension MarkdownTextView {
    /// ⌘-clicking a bullet or a checkbox offers the highlight colours: choosing one writes its
    /// character at the start of the item (`- ! text`, `- [ ] ! text`), as the List Callouts
    /// plugin for Obsidian reads them. (A plain click ticks a checkbox, so the menu can't be
    /// on that, and bullets do the same, to match.)
    func showHighlightMenu(at point: NSPoint, for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.option),
              let (item, marker) = listItemMarked(at: point), let menu = highlightMenu(item: item, marker: marker) else { return false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        return true
    }

    /// The bulleted or task list item whose bullet or checkbox is at a point in the view, and
    /// its marker's range in the text.
    func listItemMarked(at point: NSPoint) -> (item: NSRange, marker: NSRange)? {
        guard !styler.listHighlights.isEmpty, let layoutManager = pointLayoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let index = layoutManager.characterIndexForPoint(NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: container)
        let lineStart = lineStart(of: min(index, storage.length - 1))
        guard let token = tokens.first(where: { $0.range.location == lineStart }), let marker = token.syntax.first,
              let target = markerTarget(onLineAt: lineStart), target.contains(point) else { return nil }
        return (token.range, marker)
    }

    /// Where a bulleted or task item's bullet or checkbox is, in the view, with a little room
    /// around it (a bullet is a small target). Numbered items have none: they aren't highlighted.
    func markerTarget(onLineAt lineStart: Int) -> NSRect? {
        guard let layoutManager = pointLayoutManager, let container = textContainer, let storage = textStorage,
              let token = blockTokens[lineStart], case .listItem(let kind, _) = token.kind,
              let decoration = storage.attribute(.pointListMarker, at: lineStart, effectiveRange: nil) as? ListMarkerDecoration else { return nil }
        if case .ordered = kind { return nil }
        let line = layoutManager.lineRect(containing: lineStart, storage: storage)
        let font = layoutManager.textFont(near: lineStart, storage: storage)
        let visible = layoutManager.firstVisibleCharacter(onLineOf: lineStart, storage: storage)
        let baseline = line.minY + (visible.map { layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: $0)).y } ?? font.ascender)
        let x = container.lineFragmentPadding + layoutManager.theme.indentPerLevel * CGFloat(decoration.level)
        let room: CGFloat = kind == .bullet ? -6 : -5
        let target = layoutManager.markerRect(kind, x: x, baseline: baseline, font: font).insetBy(dx: room, dy: room)
        return target.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// The highlight colours for a list item, its own ticked, and No Highlight if it has one.
    func highlightMenu(item: NSRange, marker: NSRange) -> NSMenu? {
        guard !listHighlights.isEmpty else { return nil }
        let current = styler.listHighlight(after: marker, in: item, text: string as NSString)
        let menu = NSMenu()
        for highlight in listHighlights {
            let entry = NSMenuItem(title: Self.colourName(highlight.color), action: #selector(chooseHighlight(_:)), keyEquivalent: "")
            entry.target = self
            entry.image = Self.swatch(highlight.color)
            entry.representedObject = HighlightChoice(item: item, marker: marker, character: highlight.character)
            if let current, (string as NSString).character(at: current.0.location) == highlight.character.utf16.first {
                entry.state = .on
            }
            menu.addItem(entry)
        }
        if current != nil {
            menu.addItem(.separator())
            let none = NSMenuItem(title: "No Highlight", action: #selector(chooseHighlight(_:)), keyEquivalent: "")
            none.target = self
            none.representedObject = HighlightChoice(item: item, marker: marker, character: nil)
            menu.addItem(none)
        }
        return menu
    }

    /// The Format menu's highlight commands: highlights the list items the selection touches
    /// (or the cursor's) in a colour, named as `colourName` names them ("Orange"), or removes
    /// their highlight. Beeps if the cursor isn't in a list, or no highlight has that colour.
    @objc public func highlightListItems(_ sender: Any?) {
        guard let request = sender as? ListHighlightRequest else { return }
        let character: Character?
        if let colour = request.colour {
            guard let highlight = listHighlights.first(where: { Self.colourName($0.color) == colour }) else { return NSSound.beep() }
            character = highlight.character
        } else {
            character = nil
        }
        let selection = selectedRange()
        let lines = (string as NSString).lineRange(for: selection)
        let items = tokens.filter { token in
            guard case .listItem = token.kind, token.syntax.first != nil else { return false }
            return NSLocationInRange(token.range.location, lines) || NSLocationInRange(lines.location, token.range)
        }
        guard !items.isEmpty else { return NSSound.beep() }
        // One edit across the items' lines (one undo), each item's highlight character written
        // or removed in it, from the last so the earlier positions hold. The selection grows and
        // shrinks with the changes inside it, so it still covers the same items next time.
        let text = string as NSString
        let affected = NSUnionRange(items[0].range, items[items.count - 1].range)
        let edited = NSMutableString(string: text.substring(with: affected))
        var start = selection.location, end = NSMaxRange(selection)
        for item in items.reversed() {
            let marker = item.syntax[0]
            let existing = styler.listHighlight(after: marker, in: item.range, text: text)?.0
                ?? NSRange(location: NSMaxRange(marker), length: 0)
            let replacement = character.map { "\($0) " } ?? ""
            edited.replaceCharacters(in: NSRange(location: existing.location - affected.location, length: existing.length), with: replacement)
            let delta = (replacement as NSString).length - existing.length
            if existing.location < start { start += delta }
            if existing.location <= end { end += delta }
        }
        guard edited as String != text.substring(with: affected) else { return }
        replace(affected, with: edited as String, select: NSRange(location: start, length: max(end - start, 0)))
        undoManager?.setActionName(character == nil ? "Remove Highlight" : "Highlight")
    }

    @objc private func chooseHighlight(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? HighlightChoice else { return }
        setListHighlight(choice.character, item: choice.item, marker: choice.marker)
    }

    /// Writes a highlight character at the start of a list item, replacing any there (nil
    /// removes it).
    func setListHighlight(_ character: Character?, item: NSRange, marker: NSRange) {
        guard NSMaxRange(item) <= (string as NSString).length else { return }
        let text = string as NSString
        let existing = styler.listHighlight(after: marker, in: item, text: text)?.0
            ?? NSRange(location: NSMaxRange(marker), length: 0)
        let replacement = character.map { "\($0) " } ?? ""
        let previous = selectedRange()
        // The cursor stays where it was in the item's text.
        let shift = (replacement as NSString).length - existing.length
        let select = previous.location >= NSMaxRange(existing) ? NSRange(location: previous.location + shift, length: previous.length) : previous
        replace(existing, with: replacement, select: select)
    }

    /// Which highlight `highlightListItems(_:)` applies: a colour's name, or nil for none.
    public final class ListHighlightRequest: NSObject {
        public let colour: String?
        public init(colour: String?) { self.colour = colour }
    }

    private final class HighlightChoice: NSObject {
        let item: NSRange, marker: NSRange
        let character: Character?
        init(item: NSRange, marker: NSRange, character: Character?) {
            self.item = item
            self.marker = marker
            self.character = character
        }
    }

    /// A plain name for a highlight's colour, from its hue.
    static func colourName(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "Colour" }
        if rgb.saturationComponent < 0.2 { return rgb.brightnessComponent > 0.9 ? "White" : "Grey" }
        let hue = rgb.hueComponent * 360
        if rgb.saturationComponent < 0.45, rgb.brightnessComponent < 0.75 { return "Brown" }
        switch hue {
        case ..<15, 345...: return "Red"
        case ..<40: return "Orange"
        case ..<70: return "Yellow"
        case ..<165: return "Green"
        case ..<200: return "Teal"
        case ..<250: return "Blue"
        case ..<290: return "Purple"
        default: return "Pink"
        }
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

extension NSLayoutManager {
    /// The character nearest a point in the text container.
    func characterIndexForPoint(_ point: NSPoint, in container: NSTextContainer) -> Int {
        let glyph = glyphIndex(for: point, in: container)
        return characterIndexForGlyph(at: glyph)
    }
}
/// The address for Add Link (⌘K), laid out as a Mac sheet: the buttons at the bottom right.
private struct AddLinkSheet: View {
    @State var address: String
    /// The address to link to, or nil when cancelled.
    let finish: (String?) -> Void

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Link")
                .font(.headline)
            TextField("Address", text: $address, prompt: Text("https://"))
                .onSubmit { if !trimmed.isEmpty { finish(trimmed) } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add Link") { finish(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
#endif
