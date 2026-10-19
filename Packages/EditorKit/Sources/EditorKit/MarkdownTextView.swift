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
    /// Called when a link is clicked.
    public var onOpenLink: ((LinkTarget) -> Void)?
    /// Called when a link is ⌘-clicked, to open it in a new tab.
    public var onOpenLinkInNewTab: ((LinkTarget) -> Void)?
    /// Called when a link is ⌥⌘-clicked, to open it beside this note.
    public var onOpenLinkToSide: ((LinkTarget) -> Void)?
    /// Called when the view takes the keyboard (clicked into, or tabbed to).
    public var onFocus: (() -> Void)?

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
    /// Note titles to suggest while a `[[wikilink]]` is typed, best first.
    public var completeNoteTitle: ((String) -> [String])?

    var styler = MarkdownStyler()

    /// How big the text is, relative to the normal 15pt (⌘+ / ⌘−).
    public var textScale: CGFloat {
        get { styler.theme.bodySize / 15 }
        set {
            let size = (15 * min(max(newValue, 0.6), 2.5)).rounded()
            guard size != styler.theme.bodySize, let storage = textStorage else { return }
            styler.theme.bodySize = size
            imprintLayoutManager?.theme = styler.theme
            typingAttributes = styler.baseAttributes
            storage.beginEditing()
            styler.style(storage, range: NSRange(location: 0, length: storage.length), tokens: tokens)
            storage.endEditing()
        }
    }

    /// Shows the raw Markdown instead of formatted text, for fixing anything odd.
    public var showsMarkdown: Bool {
        get { styler.showsMarkdown }
        set {
            guard newValue != styler.showsMarkdown, let storage = textStorage else { return }
            styler.showsMarkdown = newValue
            storage.beginEditing()
            styler.style(storage, range: NSRange(location: 0, length: storage.length), tokens: tokens)
            storage.endEditing()
            setSelectionDirectly(selectedRange())
        }
    }
    /// The text view doesn't own a custom text system, so it is kept alive here.
    private var ownedStorage: NSTextStorage?
    private var isAdjustingSelection = false

    var imprintLayoutManager: ImprintLayoutManager? { layoutManager as? ImprintLayoutManager }

    /// An editor inside a scroll view, ready to put in a window.
    public static func makeScrollable() -> (NSScrollView, MarkdownTextView) {
        let textView = MarkdownTextView(markdown: ())
        let scrollView = MarkdownScrollView()
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
        // Start at the first visible text, never inside hidden frontmatter or markers.
        setSelectionDirectly(NSRange(location: snappedLocation(0, forward: true), length: 0))
        scrollToBeginningOfDocument(nil)
    }

    /// Swaps in a newer version of the text (for example, edited in Obsidian), replacing only
    /// what differs so the cursor and scroll position stay where they were. Clears undo,
    /// whose positions refer to the old text.
    public func reload(_ markdown: String) {
        guard let storage = textStorage, markdown != string else { return }
        let old = string as NSString, new = markdown as NSString
        var prefix = 0
        while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let changed = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        let delta = (replacement as NSString).length - changed.length

        func map(_ index: Int) -> Int {
            if index <= changed.location { return index }
            if index >= NSMaxRange(changed) { return index + delta }
            return changed.location + (replacement as NSString).length
        }
        let selection = selectedRange()
        storage.replaceCharacters(in: changed, with: replacement)
        let start = map(selection.location), end = map(NSMaxRange(selection))
        setSelectionDirectly(NSRange(location: start, length: end - start))
        undoManager?.removeAllActions()
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
        layoutHeader()
    }

    // MARK: Header

    /// A view above the text that scrolls with it, such as the note's title and properties.
    /// Its owner reports its height through `headerHeight`.
    public var headerView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let headerView { addSubview(headerView) }
            layoutHeader()
        }
    }

    /// The header's height. The text starts below it.
    public var headerHeight: CGFloat = 0 {
        didSet {
            guard headerHeight != oldValue else { return }
            layoutHeader()
            sizeToFit()
            needsDisplay = true
            updateInsertionPointStateAndRestartTimer(true)
        }
    }

    /// A height the header view keeps even while `headerHeight` is smaller, so its contents
    /// aren't squeezed while the text below animates to a new place.
    public var headerViewMinimumHeight: CGFloat = 0 {
        didSet { layoutHeader() }
    }

    /// The text's origin, moved down below the header.
    public override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y + headerHeight)
    }

    /// Makes room for the header when the view grows or shrinks to fit its text.
    public override func setConstrainedFrameSize(_ desiredSize: NSSize) {
        super.setConstrainedFrameSize(NSSize(width: desiredSize.width, height: desiredSize.height + headerHeight))
    }

    private func layoutHeader() {
        headerView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(headerHeight, headerViewMinimumHeight, 1))
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

    /// The line holding `index`, as a range without its line break, if it is collapsed: a
    /// code fence or frontmatter line, which the cursor never stops on. (An empty list item is
    /// also all hidden, but it is a real line to type on, so it isn't collapsed.)
    func collapsedLine(containing index: Int) -> NSRange? {
        guard let storage = textStorage, index >= 0, index <= storage.length else { return nil }
        let text = string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        guard start < text.length, storage.attribute(.imprintCollapsed, at: start, effectiveRange: nil) != nil else { return nil }
        return NSRange(location: start, length: contentsEnd - start)
    }

    func snappedLocation(_ location: Int, forward: Bool) -> Int {
        let text = string as NSString
        // Collapsed lines (code fences, frontmatter) are skipped entirely, however many.
        guard var line = collapsedLine(containing: location) else {
            return snappedToMarkers(location, forward: forward)
        }
        var forward = forward
        while true {
            if !forward, line.location == 0 { forward = true } // Nothing visible above: go down.
            let next = forward ? min(NSMaxRange(text.lineRange(for: line)), text.length) : line.location - 1
            guard let following = collapsedLine(containing: next), following != line else {
                return snappedToMarkers(next, forward: forward)
            }
            line = following
        }
    }

    /// Keeps the cursor out of hidden markers on an ordinary line.
    private func snappedToMarkers(_ location: Int, forward: Bool) -> Int {
        // The hidden run the location is at the start of, inside, or at the end of.
        guard let run = hiddenRun(at: location) ?? hiddenRun(at: location - 1) else { return location }

        // Markers that start a line (`- `, `# `, `> `): the cursor belongs after them. Left
        // from there goes straight to the previous line rather than to an invisible stop.
        if run.location == lineStart(of: run.location) {
            let previous = selectedRange().location
            if !forward, previous == NSMaxRange(run), location < previous, run.location > 0 {
                return run.location - 1
            }
            return NSMaxRange(run)
        }

        // Inline markers (`**`, `[[`): never stop inside them, so every press visibly moves.
        if forward, isHidden(location) { return NSMaxRange(run) }
        if !forward, isHidden(location - 1) { return run.location }
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
            if run.location == lineStart(of: run.location), collapsedLine(containing: run.location) == nil {
                // Backspace at the start of a heading, list item or quote removes its formatting.
                replace(run, with: "")
                return
            }
            // Otherwise delete the visible character before the markers, not a marker.
            setSelectionDirectly(NSRange(location: run.location, length: 0))
            if run.location == 0 { return }
        } else if (string as NSString).character(at: location - 1) == 10, location >= 2,
                  collapsedLine(containing: location - 2) != nil {
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
            if collapsedLine(containing: run.location) != nil { return }
            setSelectionDirectly(NSRange(location: NSMaxRange(run), length: 0))
        }
        super.deleteForward(sender)
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound, selectedRange().length > 0 {
            expandSelectionToWholeTokens()
        }
        super.insertText(string, replacementRange: replacementRange)
        suggestCompletionsIfInWikiLink()
    }

    public override func cut(_ sender: Any?) {
        if cutWholeLine() { return }
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

    /// Replaces a range as one undoable edit, keeping the selection on the same text.
    /// For edits made outside the text, such as from a properties panel.
    public func applyEdit(replacing range: NSRange, with replacement: String) {
        let delta = (replacement as NSString).length - range.length
        func map(_ index: Int) -> Int {
            if index <= range.location { return index }
            return index >= NSMaxRange(range) ? index + delta : range.location
        }
        let selection = selectedRange()
        let start = map(selection.location), end = map(NSMaxRange(selection))
        replace(range, with: replacement, select: NSRange(location: start, length: end - start))
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

/// The editor's scroll view. Where the window's top bars cover its top (its top content
/// inset, from the window), it blurs the text scrolling beneath them, with a hairline at the
/// edge, like the system's hard scroll edge effect. (The system's own effect needs a title
/// bar that isn't transparent, which takes the top bars' clicks and drops; and a blur from
/// outside the scroll view doesn't pick up the text.)
final class MarkdownScrollView: NSScrollView {
    private let edgeBlur: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }()
    private let edgeLine: NSBox = {
        let line = NSBox()
        line.boxType = .separator
        return line
    }()

    override func tile() {
        super.tile()
        let height = contentInsets.top
        guard height > 0 else {
            edgeBlur.removeFromSuperview()
            edgeLine.removeFromSuperview()
            return
        }
        if edgeBlur.superview == nil {
            addSubview(edgeBlur, positioned: .above, relativeTo: contentView)
            addSubview(edgeLine, positioned: .above, relativeTo: edgeBlur)
        }
        let top = isFlipped ? 0 : bounds.height - height
        edgeBlur.frame = NSRect(x: 0, y: top, width: bounds.width, height: height)
        edgeLine.frame = NSRect(x: 0, y: isFlipped ? height - 1 : top, width: bounds.width, height: 1)
    }
}
