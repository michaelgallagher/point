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
    /// What was typed when titles were last suggested, and the titles (see +Links).
    var offeredCompletion: (typed: String, titles: [String])?
    /// Set while a key press is handled (see +Links).
    var isTypingKey = false

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

    /// The widest the text column gets; wider views centre it (from Settings).
    public var maxTextWidth: CGFloat {
        get { styler.theme.maxTextWidth }
        set {
            guard newValue != styler.theme.maxTextWidth else { return }
            styler.theme.maxTextWidth = newValue
            pointLayoutManager?.theme = styler.theme
            updateInsets()
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

    /// Characters that highlight a list item when they start it (`- ! Important`, as the List
    /// Callouts plugin for Obsidian does), with their colours. Set by the app, from the vault.
    public var listHighlights: [(character: Character, color: NSColor)] = [] {
        didSet {
            styler.listHighlights = Dictionary(listHighlights.map { ($0.character, $0.color) }, uniquingKeysWith: { first, _ in first })
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
        layoutManager.onInvalidateLayout = { [weak self] in self?.completeLayoutGradually() }
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
    /// Whether a run is about to start, so asking again in the meantime doesn't start another.
    private var isLayoutQueued = false
    private var scrollObserver: NSObjectProtocol?

    /// Lays out the rest of the note, a piece at a time, after it opens, and again whenever
    /// its layout is thrown away (the column's width changing, the text restyled). Only
    /// what's on screen is laid out then (so long notes open instantly), which leaves the
    /// note's full height a guess, and a fast scroll could stop at the guessed end.
    private func completeLayoutGradually() {
        // Once per turn of the run loop, however many times the layout is thrown away in it
        // (each keystroke does, for its own line).
        guard !isLayoutQueued else { return }
        isLayoutQueued = true
        layoutRun += 1
        let run = layoutRun
        isCompletingLayout = true
        func step(from start: Int) {
            DispatchQueue.main.async { [weak self] in
                guard let self, run == self.layoutRun else { return }
                isLayoutQueued = false
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

    /// Keeps the text in a readable column, centred in wide windows. When the width changes
    /// (the window resized, the sidebar shown or hidden), the text rewraps: the line at the
    /// top stays at the top, instead of the note scrolling by however much the text above it
    /// grew or shrank.
    public override func setFrameSize(_ newSize: NSSize) {
        let anchor = newSize.width != frame.width && !isRestoringAnchor ? scrollAnchor : nil
        super.setFrameSize(newSize)
        updateInsets()
        layoutHeader()
        if let anchor { scroll(to: anchor) }
    }

    /// At the end of a live resize (the window dragged, or the sidebar sliding, which resizes
    /// the window), AppKit scrolls back to what it had in sight when it began, worked out from
    /// the layout then, which was partly a guess: by a line or more, or with the cursor out of
    /// sight, all the way back to it. The line at the top stays instead.
    public override func viewDidEndLiveResize() {
        let anchor = scrollAnchor
        super.viewDidEndLiveResize()
        if let anchor { scroll(to: anchor) }
    }

    /// A place in the note to scroll back to: the character on the first line showing below
    /// the top bars, and how far that line is scrolled up past them.
    public struct ScrollAnchor: Equatable, Sendable {
        public var index: Int
        public var offset: CGFloat
        public init(index: Int, offset: CGFloat) {
            self.index = index
            self.offset = offset
        }
    }

    private var isRestoringAnchor = false

    /// Where the note is scrolled to, or nil at the top (with the header, or some of it, in sight).
    public var scrollAnchor: ScrollAnchor? {
        guard let scrollView = enclosingScrollView, let layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let top = scrollView.contentView.bounds.minY + scrollView.contentInsets.top - origin.y
        guard top > 0 else { return nil }
        // Everything above laid out, so the line found is the one really there.
        layoutManager.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: container.size.width, height: top + 1), in: container)
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: container.lineFragmentPadding, y: top), in: container)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return ScrollAnchor(index: layoutManager.characterIndexForGlyph(at: glyph), offset: max(0, top - line.minY))
    }

    /// Scrolls so `anchor`'s line is back at the top, as far past it as it was.
    public func scroll(to anchor: ScrollAnchor) {
        guard let scrollView = enclosingScrollView, let layoutManager, let storage = textStorage, storage.length > 0 else { return }
        isRestoringAnchor = true
        defer { isRestoringAnchor = false }
        let index = min(max(anchor.index, 0), storage.length - 1)
        // Everything up to it laid out, so its place (and the note's height) is real, not a guess.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: index + 1))
        sizeToFit()
        let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil)
        let y = textContainerOrigin.y + line.minY + min(anchor.offset, line.height) - scrollView.contentInsets.top
        let clip = scrollView.contentView
        let bounds = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: clip.bounds.minX, y: y), size: clip.bounds.size))
        guard bounds.origin != clip.bounds.origin else { return }
        clip.scroll(to: bounds.origin)
        scrollView.reflectScrolledClipView(clip)
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
        // Only while the pointer is over the text itself. Mouse moves come to the text view
        // wherever the pointer is (it has the keyboard), and its I-beam replaced the resize
        // pointer over a divider beside it, which then could hardly be found.
        if let hit = window?.contentView?.superview?.hitTest(event.locationInWindow), hit !== self, !hit.isDescendant(of: self) {
            updateHoveredFoldLine(at: nil)
            return
        }
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

    /// Room below the text, past its margin, for something floating over the bottom of the
    /// note (the links button), so the last line can scroll clear of it.
    public var extraBottomSpace: CGFloat = 0 {
        didSet {
            guard extraBottomSpace != oldValue else { return }
            sizeToFit()
        }
    }

    /// Makes room for the header (and any space below) when the view grows or shrinks to fit
    /// its text.
    public override func setConstrainedFrameSize(_ desiredSize: NSSize) {
        super.setConstrainedFrameSize(NSSize(width: desiredSize.width, height: desiredSize.height + headerHeight + extraBottomSpace))
    }

    /// Selects a range and scrolls it into the middle of the view, with the system's brief
    /// highlight, as Find does: for opening a note at a link or mention in it.
    public func reveal(_ range: NSRange) {
        guard NSMaxRange(range) <= (string as NSString).length else { return }
        setSelectedRange(range)
        layoutManager?.ensureLayout(forCharacterRange: range)
        if let layoutManager, let textContainer {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            let visible = enclosingScrollView?.contentView.bounds.height ?? bounds.height
            scrollToVisible(rect.insetBy(dx: 0, dy: -max(0, (visible - rect.height) / 2)))
        }
        showFindIndicator(for: range)
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
        // Never into hidden frontmatter: what's selected can be deleted.
        let start = bodyStart
        let ranges = start == 0 ? ranges : ranges.map { value -> NSValue in
            let range = value.rangeValue
            guard range.length > 0, range.location < start else { return value }
            return NSValue(range: NSRange(location: start, length: max(NSMaxRange(range) - start, 0)))
        }
        // Moved some other way (a click, undo, find): back to one cursor.
        if !isApplyingToCursors, hasMultipleCursors { collapseCursors() }
        guard !isAdjustingSelection, !stillSelecting, ranges.count == 1, ranges[0].rangeValue.length == 0 else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        let location = ranges[0].rangeValue.location
        let forward = location >= selectedRange().location
        var snapped = snappedLocation(location, forward: forward)
        // A click puts the cursor inside a link's end only when it's on the link's text, not
        // anywhere to its right, which caught clicks meant for after it.
        if let close = wikiLinkEnding(at: snapped)?.syntax.last, let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type),
           isPastText(endingAt: close.location, event: event) {
            snapped = NSMaxRange(close)
        }
        super.setSelectedRanges([NSValue(range: NSRange(location: snapped, length: 0))], affinity: affinity, stillSelecting: false)
        showLinkBeingTyped()
    }

    /// Whether a mouse event is to the right of the character before `end`.
    private func isPastText(endingAt end: Int, event: NSEvent) -> Bool {
        guard event.window === window, end > 0, let layoutManager, let textContainer else { return false }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: end - 1, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        return convert(event.locationInWindow, from: nil).x > rect.maxX + textContainerOrigin.x
    }

    // MARK: Typing at the end of a wikilink

    /// The wikilink whose hidden `]]` starts at `location`, so that the cursor there is at the
    /// end of its text, inside it.
    func wikiLinkEnding(at location: Int) -> MarkdownToken? {
        guard !styler.showsMarkdown else { return nil }
        return tokens.first { token in
            guard case .wikiLink = token.kind, let close = token.syntax.last else { return false }
            return close.location == location && close.length == 2
        }
    }

    /// The link the cursor is inside the end of, shaded so it's clear that typing goes on
    /// with it (just after it, which looks the same, typing doesn't).
    private var shadedLink: NSRange?

    private func showLinkBeingTyped() {
        let selection = selectedRange()
        let link = selection.length == 0 ? wikiLinkEnding(at: selection.location) : nil
        let visible = link.flatMap { token -> NSRange? in
            guard let open = token.syntax.first, let close = token.syntax.last else { return nil }
            return NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
        }
        guard visible != shadedLink, let layoutManager else { return }
        if let shadedLink, NSMaxRange(shadedLink) <= (string as NSString).length {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: shadedLink)
        }
        if let visible {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.linkColor.withAlphaComponent(0.12), forCharacterRange: visible)
        }
        shadedLink = visible
    }

    // MARK: Protecting the properties

    /// Where the note's body starts while its frontmatter is hidden (its properties are edited
    /// in the strip above the note, not as text), else 0. Nothing above it can be selected, so
    /// Select All then Delete clears the body and leaves the properties.
    public var bodyStart: Int {
        guard !styler.showsMarkdown, let token = tokens.first, token.kind == .frontmatter, token.range.length > 0 else { return 0 }
        let text = string as NSString
        let last = min(NSMaxRange(token.range) - 1, text.length - 1)
        guard last >= 0 else { return 0 }
        return NSMaxRange(text.lineRange(for: NSRange(location: last, length: 0)))
    }

    /// The body only, while the frontmatter is hidden.
    public override func selectAll(_ sender: Any?) {
        let start = bodyStart
        guard start > 0 else { return super.selectAll(sender) }
        setSelectedRange(NSRange(location: start, length: (string as NSString).length - start))
    }

    /// Where text put in "at the cursor" as whole lines (a template's body) should go: the start
    /// of the cursor's line when only hidden markers come before the cursor on it (the cursor
    /// rests after a heading's "# "), else the cursor.
    public func insertionPointForLines(at location: Int) -> Int {
        let start = lineStart(of: location)
        return (start..<location).allSatisfy(isHidden) ? start : location
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

        // The end of a wikilink's text, just before its hidden `]]`, is a stop of its own:
        // typing there goes on with the link. One more press steps out, after the `]]`.
        if location == run.location, wikiLinkEnding(at: location) != nil { return location }
        if location == NSMaxRange(run), wikiLinkEnding(at: run.location) != nil { return location }

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
        // Not into the frontmatter's last line, which would join the body to it.
        if location == bodyStart { return }

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
#endif
