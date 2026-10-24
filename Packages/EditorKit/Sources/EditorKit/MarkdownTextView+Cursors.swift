#if canImport(AppKit)
import AppKit

/// Several cursors at once, as in code editors. The text view's own selection is the main
/// cursor; the others are kept here. Typing, deleting and moving are done at each cursor in
/// turn, last first (so an edit never shifts a cursor not yet done), with the editor's usual
/// handling each time: lists continue, hidden markers are stepped over, and the whole lot
/// undoes in one go.
///
/// ⌥-click adds a cursor (⌥-click on a link still just places the cursor in it), ⌃⇧↑ and ⌃⇧↓
/// add one on the line above or below, ⌘D adds the next match of the selection. Escape, or
/// a plain click, goes back to one.
extension MarkdownTextView {
    /// Whether there's more than one cursor.
    public var hasMultipleCursors: Bool { !extraSelections.isEmpty }

    /// Every cursor and selection, in order through the text, without overlaps.
    public var allSelections: [NSRange] { Self.merged([selectedRange()] + extraSelections) }

    /// Sorts ranges and merges any that overlap or touch.
    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last), range.length > 0 || last.length > 0 || range.location == last.location {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Back to the main cursor alone.
    public func collapseCursors() {
        guard hasMultipleCursors else { return }
        extraSelections = []
        needsDisplay = true
    }

    /// Sets the cursors: the main one, and the others.
    func setCursors(main: NSRange, others: [NSRange]) {
        isApplyingToCursors = true
        setSelectedRange(main)
        isApplyingToCursors = false
        extraSelections = Self.merged(others.filter { NSIntersectionRange($0, selectedRange()).length == 0 && $0 != selectedRange() })
        needsDisplay = true
    }

    /// Does `body` at each cursor, last first, then puts the cursors where each ended up.
    func performAtEachCursor(_ body: () -> Void) {
        guard let storage = textStorage else { return }
        let main = selectedRange()
        // Last first: an edit at one cursor then never moves one still to do.
        let ranges = allSelections.sorted { $0.location > $1.location }
        let mainIndex = ranges.firstIndex { NSLocationInRange(main.location, $0) || $0 == main } ?? 0
        isApplyingToCursors = true
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        var results: [NSRange] = []
        for range in ranges {
            let before = storage.length
            setSelectedRange(range)
            body()
            // The cursors already done are all further on: they move with the change.
            let delta = storage.length - before
            if delta != 0 { results = results.map { NSRange(location: max(0, $0.location + delta), length: $0.length) } }
            results.append(selectedRange())
        }
        undoManager?.endUndoGrouping()
        isApplyingToCursors = false
        let newMain = results[mainIndex]
        var others = results
        others.remove(at: mainIndex)
        setCursors(main: newMain, others: others)
        scrollRangeToVisible(newMain)
    }

    /// Commands done at each cursor; any other command goes back to one cursor first.
    static let perCursorCommands: Set<Selector> = [
        #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)), #selector(insertTab(_:)), #selector(insertBacktab(_:)),
        #selector(deleteBackward(_:)), #selector(deleteForward(_:)), #selector(deleteWordBackward(_:)), #selector(deleteWordForward(_:)),
        #selector(deleteToBeginningOfLine(_:)), #selector(deleteToEndOfLine(_:)),
        #selector(moveLeft(_:)), #selector(moveRight(_:)), #selector(moveUp(_:)), #selector(moveDown(_:)),
        #selector(moveWordLeft(_:)), #selector(moveWordRight(_:)),
        #selector(moveToBeginningOfLine(_:)), #selector(moveToEndOfLine(_:)),
        #selector(moveToLeftEndOfLine(_:)), #selector(moveToRightEndOfLine(_:)),
        #selector(moveLeftAndModifySelection(_:)), #selector(moveRightAndModifySelection(_:)),
        #selector(moveWordLeftAndModifySelection(_:)), #selector(moveWordRightAndModifySelection(_:)),
        #selector(moveToLeftEndOfLineAndModifySelection(_:)), #selector(moveToRightEndOfLineAndModifySelection(_:)),
    ]

    public override func doCommand(by selector: Selector) {
        guard hasMultipleCursors, !isApplyingToCursors else { return super.doCommand(by: selector) }
        if selector == #selector(cancelOperation(_:)) { return collapseCursors() }
        if Self.perCursorCommands.contains(selector) {
            performAtEachCursor { super.doCommand(by: selector) }
        } else {
            collapseCursors()
            super.doCommand(by: selector)
        }
    }

    // MARK: Adding cursors

    /// ⌥-click: a cursor where clicked, besides the ones already there. False if the click
    /// wasn't for this (no ⌥, or on a link, where ⌥-click places the cursor in it).
    func addCursor(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.option, .shift, .command, .control])
        guard modifiers == [.option], event.clickCount == 1 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(exactlyAt: point), link(at: index) != nil { return false }
        let index = characterIndexForInsertion(at: point)
        guard index != NSNotFound else { return false }
        addCursor(at: index)
        return true
    }

    /// Adds a cursor, which becomes the main one.
    public func addCursor(at index: Int) {
        let location = snappedLocation(min(max(index, 0), (string as NSString).length), forward: true)
        let current = allSelections
        guard !current.contains(where: { NSLocationInRange(location, $0) || $0.location == location }) else { return }
        setCursors(main: NSRange(location: location, length: 0), others: current)
    }

    /// ⌃⇧↑: a cursor on the line above the highest one.
    @objc public func addCursorAbove(_ sender: Any?) { addCursorOnNextLine(down: false) }
    /// ⌃⇧↓: a cursor on the line below the lowest one.
    @objc public func addCursorBelow(_ sender: Any?) { addCursorOnNextLine(down: true) }

    private func addCursorOnNextLine(down: Bool) {
        let current = allSelections
        guard let edge = down ? current.last : current.first else { return }
        isApplyingToCursors = true
        setSelectedRange(NSRange(location: down ? NSMaxRange(edge) : edge.location, length: 0))
        if down { moveDown(nil) } else { moveUp(nil) }
        let location = selectedRange().location
        isApplyingToCursors = false
        guard !current.contains(where: { NSLocationInRange(location, $0) || $0.location == location }) else {
            return setCursors(main: current[down ? current.count - 1 : 0], others: Array(current.dropLast(down ? 1 : 0).dropFirst(down ? 0 : 1)))
        }
        setCursors(main: NSRange(location: location, length: 0), others: current)
        scrollRangeToVisible(selectedRange())
    }

    /// ⌘D: with nothing selected, selects the word at the cursor; otherwise adds a selection
    /// of the next place the selected text appears (wrapping round to the top).
    @objc public func addNextMatch(_ sender: Any?) {
        let main = selectedRange()
        let text = string as NSString
        if main.length == 0, !hasMultipleCursors {
            let word = wordRange(at: main.location)
            if word.length > 0 { setSelectedRange(word) }
            return
        }
        let needle = text.substring(with: main)
        guard !needle.isEmpty else { return }
        let current = allSelections
        let after = NSMaxRange(current.last ?? main)
        var found = text.range(of: needle, options: [], range: NSRange(location: after, length: text.length - after))
        if found.location == NSNotFound {
            found = text.range(of: needle, options: [], range: NSRange(location: 0, length: text.length))
        }
        guard found.location != NSNotFound, !current.contains(found) else { return NSSound.beep() }
        setCursors(main: found, others: current)
        scrollRangeToVisible(found)
    }

    // MARK: Drawing the other cursors

    /// The other cursors' selections, behind the text.
    func drawExtraSelections(in rect: NSRect) {
        guard hasMultipleCursors, let layoutManager, let container = textContainer else { return }
        let color = window?.firstResponder === self ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor
        color.setFill()
        let origin = textContainerOrigin
        for range in extraSelections where range.length > 0 {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { box, _ in
                NSRect(x: box.minX + origin.x, y: box.minY + origin.y, width: box.width, height: box.height).fill()
            }
        }
    }

    /// The other cursors' insertion points, over the text.
    func drawExtraInsertionPoints(in rect: NSRect) {
        guard hasMultipleCursors, window?.firstResponder === self, let window else { return }
        insertionPointColor.setFill()
        for range in extraSelections where range.length == 0 {
            let screen = firstRect(forCharacterRange: range, actualRange: nil)
            guard screen != .zero else { continue }
            let local = convert(window.convertFromScreen(screen), from: nil)
            // The text's height, not the line's: without the extra line spacing above and
            // below, so cursors on lines next to each other stay apart.
            let spacing = local.height * (1 - 1 / max(styler.theme.lineHeightMultiple, 1)) / 2
            NSRect(x: local.minX.rounded(.down), y: local.minY + spacing, width: 2, height: local.height - spacing * 2).fill()
        }
    }
}
#endif
