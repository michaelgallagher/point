#if canImport(AppKit)
import AppKit
import CoreImage
import MarkdownKit

/// The note editor: plain Markdown text, displayed as rich text with the markers hidden.
///
/// The text storage always holds exactly the Markdown that is on disk. Styling only
/// changes attributes, so `string` can be saved as-is without any conversion.
public final class MarkdownTextView: NSTextView, @preconcurrency NSTextStorageDelegate {
    /// The parsed structure of the current text, kept up to date on every edit.
    public private(set) var tokens: [MarkdownToken] = [] {
        didSet { blockTokens = Dictionary(tokens.filter(\.isBlock).map { ($0.range.location, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    /// The block (heading, list item and so on) starting at each place, for quick lookups.
    private(set) var blockTokens: [Int: MarkdownToken] = [:]
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

    /// Folded headings and list items, by where their lines start (see +Folding).
    var folds: Set<Int> = []
    /// What each fold hid when last applied, to tell whether an edit reaches into it.
    var appliedFoldRanges: [Int: NSRange] = [:]
    /// The foldable line under the pointer, whose arrow shows.
    var hoveredFoldLine: Int?

    /// The cursors (and selections) besides the main one (see +Cursors).
    var extraSelections: [NSRange] = []
    /// Set while the cursors themselves move the selection, so it doesn't count as the
    /// selection changing some other way (which goes back to one cursor).
    var isApplyingToCursors = false

    /// How big the text is, relative to the chosen size (⌘+ / ⌘−).
    public var textScale: CGFloat {
        get { styler.theme.scale }
        set {
            let scale = min(max(newValue, 0.6), 2.5)
            guard scale != styler.theme.scale else { return }
            styler.theme.scale = scale
            themeChanged()
        }
    }

    /// The body's size and line height, and each heading's size and style (from Settings).
    public var typography: Typography {
        get { styler.theme.typography }
        set {
            guard newValue != styler.theme.typography else { return }
            styler.theme.typography = newValue
            themeChanged()
        }
    }

    private func themeChanged() {
        pointLayoutManager?.theme = styler.theme
        typingAttributes = styler.baseAttributes
        restyleAll()
    }

    /// Whether a wikilink's target is a note that exists; links to notes that don't exist yet
    /// are fainter. Set by the app, which knows the vault.
    public var wikiLinkExists: ((String) -> Bool)? {
        didSet {
            styler.wikiLinkExists = wikiLinkExists
            restyleAll()
        }
    }

    /// Restyles the whole note, for example when notes are added or removed, which can
    /// change which links lead anywhere.
    public func restyleAll() {
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        styler.style(storage, range: NSRange(location: 0, length: storage.length), tokens: tokens)
        applyFolds()
        storage.endEditing()
    }

    /// Shows the raw Markdown instead of formatted text, for fixing anything odd.
    public var showsMarkdown: Bool {
        get { styler.showsMarkdown }
        set {
            guard newValue != styler.showsMarkdown, let storage = textStorage else { return }
            styler.showsMarkdown = newValue
            storage.beginEditing()
            styler.style(storage, range: NSRange(location: 0, length: storage.length), tokens: tokens)
            applyFolds()
            storage.endEditing()
            setSelectionDirectly(selectedRange())
        }
    }
    /// The text view doesn't own a custom text system, so it is kept alive here.
    private var ownedStorage: NSTextStorage?
    private var isAdjustingSelection = false

    var pointLayoutManager: PointLayoutManager? { layoutManager as? PointLayoutManager }

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
        let layoutManager = PointLayoutManager()
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
        folds = []
        appliedFoldRanges = [:]
        storage.setAttributedString(NSAttributedString(string: markdown, attributes: styler.baseAttributes))
        undoManager?.removeAllActions()
        // Start at the first visible text, never inside hidden frontmatter or markers.
        setSelectionDirectly(NSRange(location: snappedLocation(0, forward: true), length: 0))
        scrollToBeginningOfDocument(nil)
        completeLayoutGradually()
    }

    /// Which load the gradual layout belongs to, so a newer note's text stops an older run.
    private var layoutRun = 0
    /// Whether the gradual layout is still going, so the rest of the note is a guess.
    private var isCompletingLayout = false
    private var scrollObserver: NSObjectProtocol?

    /// Lays out the rest of the note, a piece at a time, after it opens. Only what's on
    /// screen is laid out at first (so long notes open instantly), which leaves the note's
    /// full height a guess, and a fast scroll could stop at the guessed end.
    private func completeLayoutGradually() {
        layoutRun += 1
        let run = layoutRun
        isCompletingLayout = true
        func step(from start: Int) {
            DispatchQueue.main.async { [weak self] in
                guard let self, run == self.layoutRun else { return }
                guard let layoutManager, let storage = textStorage, start < storage.length else {
                    isCompletingLayout = false
                    return
                }
                let end = min(start + 20_000, storage.length)
                layoutManager.ensureLayout(forCharacterRange: NSRange(location: start, length: end - start))
                step(from: end)
            }
        }
        step(from: 0)
    }

    /// While the rest of a note is still being laid out, scrolling lays out everything up to
    /// what's showing (and a little past it), so the note's height is right where it is
    /// scrolled to, instead of a guess that jumps when the layout catches up.
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layOutThroughVisibleText() }
        }
    }

    private func layOutThroughVisibleText() {
        guard isCompletingLayout, let layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let bottom = NSPoint(x: container.lineFragmentPadding + 1, y: visibleRect.maxY - origin.y)
        let index = layoutManager.characterIndexForPoint(bottom, in: container)
        let end = min(index + 2_000, storage.length)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: end))
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

    // MARK: Fold arrows

    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawExtraSelections(in: rect)
        drawFoldArrows(in: rect)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawExtraInsertionPoints(in: dirtyRect)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.userInfo?["folds"] != nil }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                           owner: self, userInfo: ["folds": true]))
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredFoldLine(at: convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHoveredFoldLine(at: nil)
    }

    // MARK: Header

    /// A view above the text that scrolls with it, such as the note's title and properties.
    /// Its owner reports its height through `headerHeight`.
    public var headerView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let headerView {
                headerClip.addSubview(headerView)
                if headerClip.superview == nil { addSubview(headerClip) }
            }
            layoutHeader()
        }
    }

    /// Holds the header and shows only `headerHeight` of it, so while the header's contents
    /// open or close, what's revealed grows or shrinks with the text moving below it.
    private let headerClip: NSView = {
        let view = FlippedView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }()

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
        headerClip.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(headerHeight, 1))
        // Always taller than its contents can be: a SwiftUI view in a frame shorter than itself
        // is re-centred for a moment when its contents grow, which flashes. The clip shows
        // only `headerHeight` of it.
        headerView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(headerHeight, headerViewMinimumHeight, 1, 2000))
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
        // Folds move with the text; one the edit reached into opens, and everything restyles.
        if updateFolds(edited: editedRange, delta: delta, hiddenBefore: appliedFoldRanges) {
            styler.style(textStorage, range: NSRange(location: 0, length: textStorage.length), tokens: tokens)
        }
        defer { applyFolds() }

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
        // Moved some other way (a click, undo, find): back to one cursor.
        if !isApplyingToCursors, hasMultipleCursors { collapseCursors() }
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
        return storage.attribute(.pointHidden, at: index, effectiveRange: nil) != nil
    }

    /// The hidden run containing the character at `index`, limited to its line.
    func hiddenRun(at index: Int) -> NSRange? {
        guard let storage = textStorage, isHidden(index) else { return nil }
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var run = NSRange()
        _ = storage.attribute(.pointHidden, at: index, longestEffectiveRange: &run, in: line)
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
        guard start < text.length, storage.attribute(.pointCollapsed, at: start, effectiveRange: nil) != nil else { return nil }
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
        // Typed with several cursors: at each of them.
        if hasMultipleCursors, !isApplyingToCursors, replacementRange.location == NSNotFound, !hasMarkedText() {
            performAtEachCursor { self.insertText(string, replacementRange: replacementRange) }
            return
        }
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

/// A view whose origin is at its top left, like the text view's: what it clips is cut from the bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The editor's scroll view. Where the window's top bars cover its top (its top content
/// inset, from the window), it blurs the text scrolling beneath them under a light wash of
/// the page's colour, with a one-pixel hairline at the edge, like the system's scroll edge
/// effect; both show only once the text has scrolled under the bars. The blur is a Core
/// Image filter on what's behind a view inside the scroll view, above the text. (The
/// system's own effect needs a title bar that isn't transparent, which takes the top bars'
/// clicks and drops; a blur from outside the scroll view doesn't pick up the text; and a
/// within-window material either hides the text or, faded, shows it unblurred.)
final class MarkdownScrollView: NSScrollView {
    private let edgeBlur: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        view.layer?.masksToBounds = true // Otherwise the filter reaches the whole page.
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(8, forKey: kCIInputRadiusKey)
            view.backgroundFilters = [blur]
        }
        view.alphaValue = 0
        return view
    }()
    private let edgeLine: NSView = {
        let line = NSView()
        line.wantsLayer = true
        line.alphaValue = 0
        return line
    }()

    private var isScrolledUnder = false

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
        // One device pixel, as the system draws its hairlines.
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        edgeLine.frame = NSRect(x: 0, y: isFlipped ? height - pixel : top, width: bounds.width, height: pixel)
        updateEdge(animated: false)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEdge(animated: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEdge(animated: false)
    }

    /// Shows the blur and the line once the text has scrolled under the bars (the clip view's
    /// origin is past where the inset starts it), and hides them at the top.
    private func updateEdge(animated: Bool) {
        guard edgeBlur.superview != nil else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // The page's colour over the blur, so the bar's controls stay readable.
            edgeBlur.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.45).cgColor
            edgeLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
        let scrolled = contentView.bounds.minY > -contentInsets.top + 0.5
        guard scrolled != isScrolledUnder || !animated else { return }
        isScrolledUnder = scrolled
        let blur: CGFloat = scrolled ? 1 : 0, line: CGFloat = scrolled ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                edgeBlur.animator().alphaValue = blur
                edgeLine.animator().alphaValue = line
            }
        } else {
            edgeBlur.alphaValue = blur
            edgeLine.alphaValue = line
        }
    }
}
