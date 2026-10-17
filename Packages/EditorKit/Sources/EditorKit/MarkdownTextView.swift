#if canImport(AppKit)
import AppKit
import MarkdownKit

/// The note editor: plain Markdown text, displayed as rich text with the markers hidden.
///
/// The text storage always holds exactly the Markdown that is on disk. Styling only
/// changes attributes, so `string` can be saved as-is without any conversion.
public final class MarkdownTextView: NSTextView, @preconcurrency NSTextStorageDelegate {
    /// The parsed structure of the current text, kept up to date on every edit.
    public private(set) var tokens: [MarkdownToken] = []
    /// Called after every change the user makes to the text.
    public var onTextChange: ((MarkdownTextView) -> Void)?

    let styler = MarkdownStyler()
    /// The text view doesn't own a custom text system, so it is kept alive here.
    private var ownedStorage: NSTextStorage?
    private var isAdjustingSelection = false

    var imprintLayoutManager: ImprintLayoutManager? { layoutManager as? ImprintLayoutManager }

    /// An editor inside a scroll view, ready to put in a window.
    public static func makeScrollable() -> (NSScrollView, MarkdownTextView) {
        let textView = MarkdownTextView(markdown: ())
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    /// Builds the TextKit 1 text system by hand so the custom layout manager can hide markers.
    convenience init(markdown: Void) {
        let storage = NSTextStorage()
        let layoutManager = ImprintLayoutManager()
        // Lay out only what is on screen, so long notes open instantly.
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        ownedStorage = storage
        storage.delegate = self
        configure()
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        // Markdown is plain text: substitutions would corrupt it (`---` must not become an em dash).
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        typingAttributes = styler.baseAttributes
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        updateInsets()
    }

    /// Replaces the whole text, for example when opening a note. Not undoable.
    public func load(_ markdown: String) {
        guard let storage = textStorage else { return }
        storage.setAttributedString(NSAttributedString(string: markdown, attributes: styler.baseAttributes))
        undoManager?.removeAllActions()
        isAdjustingSelection = true
        setSelectedRange(NSRange(location: 0, length: 0))
        isAdjustingSelection = false
        scrollToBeginningOfDocument(nil)
    }

    public override func didChangeText() {
        super.didChangeText()
        onTextChange?(self)
    }

    // MARK: Layout

    /// Keeps the text in a readable column, centred in wide windows.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let side = max(28, ((frame.width - styler.theme.maxTextWidth) / 2).rounded())
        if textContainerInset.width != side {
            textContainerInset = NSSize(width: side, height: 28)
        }
    }

    // MARK: Restyling

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let old = tokens
        tokens = MarkdownParser.parse(textStorage.string)

        var range = editedRange
        if structureChanged(from: old, to: tokens, editedRange: editedRange, delta: delta) {
            range = NSRange(location: 0, length: textStorage.length)
        } else {
            // Multi-line blocks the edit touched may have changed shape; restyle all of them.
            let before = NSRange(location: editedRange.location, length: max(0, editedRange.length - delta))
            for token in old where token.isMultiLineBlock && NSIntersectionRange(token.range, before).length > 0 || token.isMultiLineBlock && NSLocationInRange(before.location, token.range) {
                let shifted = NSRange(location: token.range.location, length: max(0, token.range.length + delta))
                range = NSUnionRange(range, NSIntersectionRange(shifted, NSRange(location: 0, length: textStorage.length)))
            }
        }
        styler.style(textStorage, range: range, tokens: tokens)
    }

    /// Whether code blocks or frontmatter changed, which can restyle everything after them.
    private func structureChanged(from old: [MarkdownToken], to new: [MarkdownToken], editedRange: NSRange, delta: Int) -> Bool {
        func spans(_ tokens: [MarkdownToken], shiftingAfter edit: Int?) -> [NSRange] {
            tokens.filter(\.changesFollowingText).map { token in
                guard let edit, token.range.location > edit else { return token.range }
                return NSRange(location: token.range.location + delta, length: token.range.length)
            }
        }
        let before = spans(old, shiftingAfter: editedRange.location)
        let after = spans(new, shiftingAfter: nil)
        guard before.count == after.count else { return true }
        for (a, b) in zip(before, after) where a.location != b.location {
            return true
        }
        return false
    }

    // MARK: Cursor movement around hidden markers

    /// Keeps the insertion point out of hidden markers, so every arrow press visibly moves it.
    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        guard !isAdjustingSelection, !stillSelecting, ranges.count == 1, ranges[0].rangeValue.length == 0 else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        let location = ranges[0].rangeValue.location
        let forward = location >= selectedRange().location
        let snapped = snappedLocation(location, forward: forward)
        super.setSelectedRanges([NSValue(range: NSRange(location: snapped, length: 0))], affinity: affinity, stillSelecting: false)
    }

    func isHidden(_ index: Int) -> Bool {
        guard let storage = textStorage, index >= 0, index < storage.length else { return false }
        return storage.attribute(.imprintHidden, at: index, effectiveRange: nil) != nil
    }

    /// The hidden run containing the character at `index`, limited to its line.
    func hiddenRun(at index: Int) -> NSRange? {
        guard let storage = textStorage, isHidden(index) else { return nil }
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var run = NSRange()
        _ = storage.attribute(.imprintHidden, at: index, longestEffectiveRange: &run, in: line)
        return run
    }

    /// Whether `run` hides a whole line, as for a code fence.
    func hidesWholeLine(_ run: NSRange) -> Bool {
        let text = string as NSString
        var start = 0, contentsEnd = 0, end = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: run)
        return run.location == start && NSMaxRange(run) == contentsEnd
    }

    func snappedLocation(_ location: Int, forward: Bool) -> Int {
        let text = string as NSString
        if forward, let run = hiddenRun(at: location) {
            if hidesWholeLine(run) {
                return min(NSMaxRange(text.lineRange(for: run)), text.length)
            }
            return NSMaxRange(run)
        }
        if !forward, let run = hiddenRun(at: location - 1) ?? (isHidden(location) && isHidden(location - 1) ? hiddenRun(at: location) : nil) {
            if hidesWholeLine(run) {
                return max(run.location - 1, 0)
            }
            return run.location
        }
        // Moving forward onto the end of a run from inside it is fine; landing inside one is not.
        if let run = hiddenRun(at: location), run.location < location {
            return forward ? NSMaxRange(run) : run.location
        }
        return location
    }

    // MARK: Deleting around hidden markers

    public override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0 else {
            expandSelectionToWholeTokens()
            super.deleteBackward(sender)
            return
        }
        let location = selection.location
        guard location > 0 else { return super.deleteBackward(sender) }

        if let run = hiddenRun(at: location - 1) {
            if run.location == lineStart(of: run.location), !hidesWholeLine(run) {
                // Backspace at the start of a heading, list item or quote removes its formatting.
                replace(run, with: "")
                return
            }
            // Otherwise delete the visible character before the markers, not a marker.
            setSelectionDirectly(NSRange(location: run.location, length: 0))
            if run.location == 0 { return }
        } else if (string as NSString).character(at: location - 1) == 10, location >= 2,
                  let run = hiddenRun(at: location - 2), hidesWholeLine(run) {
            // Never merge a line into a hidden code fence.
            return
        }
        super.deleteBackward(sender)
    }

    public override func deleteForward(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0 else {
            expandSelectionToWholeTokens()
            super.deleteForward(sender)
            return
        }
        if let run = hiddenRun(at: selection.location) {
            if hidesWholeLine(run) { return }
            setSelectionDirectly(NSRange(location: NSMaxRange(run), length: 0))
        }
        super.deleteForward(sender)
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound, selectedRange().length > 0 {
            expandSelectionToWholeTokens()
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    public override func cut(_ sender: Any?) {
        expandSelectionToWholeTokens()
        super.cut(sender)
    }

    /// If a selection covers all the visible text of a formatted span, takes its hidden
    /// markers too, so deleting `bold` doesn't leave a stray `****` behind.
    func expandSelectionToWholeTokens() {
        var selection = selectedRange()
        guard selection.length > 0 else { return }
        for token in tokens where token.syntax.count >= 2 && !token.isBlock {
            let open = token.syntax[0], close = token.syntax[token.syntax.count - 1]
            let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
            if selection.location <= inner.location, NSMaxRange(selection) >= NSMaxRange(inner),
               NSIntersectionRange(selection, token.range).length > 0 || inner.length == 0 {
                selection = NSUnionRange(selection, token.range)
            }
        }
        setSelectionDirectly(selection)
    }

    // MARK: Helpers

    func setSelectionDirectly(_ range: NSRange) {
        isAdjustingSelection = true
        setSelectedRange(range)
        isAdjustingSelection = false
    }

    func lineStart(of index: Int) -> Int {
        (string as NSString).lineRange(for: NSRange(location: index, length: 0)).location
    }

    /// Replaces text as an undoable user edit.
    @discardableResult
    func replace(_ range: NSRange, with replacement: String, select: NSRange? = nil) -> Bool {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: replacement) else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectionDirectly(select ?? NSRange(location: range.location + (replacement as NSString).length, length: 0))
        return true
    }
}

extension MarkdownToken {
    var isBlock: Bool {
        switch kind {
        case .frontmatter, .heading, .blockquote, .callout, .listItem, .codeBlock, .thematicBreak, .table, .footnoteDefinition:
            true
        default:
            false
        }
    }

    var isMultiLineBlock: Bool {
        switch kind {
        case .frontmatter, .blockquote, .callout, .codeBlock, .table: true
        default: false
        }
    }

    /// Code blocks and frontmatter change how everything after them is read.
    var changesFollowingText: Bool {
        switch kind {
        case .frontmatter, .codeBlock: true
        default: false
        }
    }
}
#endif
