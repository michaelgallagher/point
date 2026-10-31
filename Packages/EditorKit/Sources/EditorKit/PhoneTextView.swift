#if os(iOS)
import MarkdownKit
import UIKit

/// The note editor on the iPhone: a `UITextView` on TextKit 1, sharing the Mac's styler and
/// layout manager, so notes look the same and the Markdown stays hidden. It restyles as you
/// type, takes the Mac's formatting commands as edits (`MarkdownEditing`), and keeps its rules
/// around hidden Markdown (`HiddenMarkers`), but doesn't yet have its folding.
public final class PhoneTextView: UITextView {
    public private(set) var tokens: [MarkdownToken] = []
    private var styler = MarkdownStyler()
    let pointLayoutManager: PointLayoutManager
    /// Decides which taps are for `PhoneTextView+Links`.
    var tapFilter: NSObject?

    /// How long the last edit took to parse and restyle, in milliseconds, and the slowest so
    /// far: what typing costs on this phone.
    public private(set) var lastEditMilliseconds: Double = 0
    public private(set) var slowestEditMilliseconds: Double = 0
    /// Of the last edit's time, how much was parsing the note (the rest is restyling).
    public private(set) var lastParseMilliseconds: Double = 0
    /// Called after each edit, with the text as it is now.
    public var onTextChange: ((String) -> Void)?
    /// Called as the cursor moves into or out of a `[[link` or `#tag` being typed.
    public var onCompletionChange: ((MarkdownEditing.Completion?) -> Void)?
    private var completion: MarkdownEditing.Completion?
    /// Called when a link is tapped.
    public var onOpenLink: ((LinkTarget) -> Void)?
    /// A view above the text (the note's title), scrolling with it, as wide as the text.
    public var header: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let header { addSubview(header) }
            setNeedsLayout()
        }
    }
    private static let headerTop: CGFloat = 12
    private static let headerGap: CGFloat = 8

    /// What's been edited and not yet restyled.
    var pendingRestyle: NSRange?
    var restyleScheduled = false
    /// Set while restyling, whose attribute changes aren't edits.
    var isRestyling = false
    /// Where the cursor last settled, to tell which way it's moving.
    private var cursor = 0
    /// Set while the selection is put somewhere the cursor can't rest, on the way to an edit.
    private var isAdjustingSelection = false
    /// Which load the gradual layout belongs to, so a newer load stops an older run.
    private var layoutRun = 0

    public init() {
        // TextKit 1, built by hand so the layout manager can hide markers, as on the Mac.
        let storage = NSTextStorage()
        let layoutManager = PointLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        pointLayoutManager = layoutManager
        super.init(frame: .zero, textContainer: container)
        storage.delegate = self
        delegate = self
        addTapRecognizer()
        styler.theme.typography.bodySize = 17 // The iPhone's own body size.
        styler.theme.typography.headings[0].size = 22.0 / 17 // Below the note's title, at 24.
        styler.theme.keepsTagsInsideMargin = true
        applyTextSize()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: PhoneTextView, _: UITraitCollection) in
            view.textSizeChanged()
        }
        backgroundColor = .systemBackground
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 40, right: 16)
        textContainer.lineFragmentPadding = 0
        // Markdown is plain text: substitutions would corrupt it (`---` must not become a dash).
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        autocorrectionType = .default
        spellCheckingType = .yes
        dataDetectorTypes = []
        isFindInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// Sizes the text to the phone's text size setting, and the room for list markers with it.
    private func applyTextSize() {
        let scale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17) / 17
        let standard = EditorTheme()
        styler.theme.scale = scale
        styler.theme.indentPerLevel = standard.indentPerLevel * scale
        styler.theme.markerWidth = standard.markerWidth * scale
        styler.theme.bulletWidth = standard.bulletWidth * scale
        pointLayoutManager.theme = styler.theme
        typingAttributes = styler.baseAttributes
    }

    /// The phone's text size changed, with a note open.
    private func textSizeChanged() {
        applyTextSize()
        restyle(NSRange(location: 0, length: textStorage.length))
        setNeedsLayout()
    }

    /// Places the header at the top, and starts the text below it.
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let header else { return }
        let width = bounds.width - textContainerInset.left - textContainerInset.right
        let height = header.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        header.frame = CGRect(x: textContainerInset.left, y: Self.headerTop, width: width, height: height)
        let top = Self.headerTop + height + Self.headerGap
        if textContainerInset.top != top { textContainerInset.top = top }
    }

    /// Replaces the whole text, as when opening a note. Returns how long it took, in
    /// milliseconds, to parse, style and lay out what's on screen.
    @discardableResult
    public func load(_ markdown: String) -> Double {
        let start = CACurrentMediaTime()
        textStorage.setAttributedString(NSAttributedString(string: markdown, attributes: styler.baseAttributes))
        // Styled now, all of it, not just after.
        tokens = []
        pendingRestyle = nil
        restyle(NSRange(location: 0, length: textStorage.length))
        undoManager?.removeAllActions()
        moveToBodyStart()
        layoutIfNeeded()
        // What's on screen, laid out now.
        pointLayoutManager.ensureLayout(forBoundingRect: CGRect(origin: .zero, size: bounds.size), in: textContainer)
        let milliseconds = (CACurrentMediaTime() - start) * 1000
        completeLayoutGradually()
        return milliseconds
    }

    /// Lays out the rest of the note, a piece at a time, after it opens, as the Mac does: only
    /// what's on screen is laid out at first, which leaves everything further down a guess.
    private func completeLayoutGradually() {
        layoutRun += 1
        let run = layoutRun
        func step(from start: Int) {
            DispatchQueue.main.async { [weak self] in
                guard let self, run == layoutRun, start < textStorage.length else { return }
                let end = min(start + 20_000, textStorage.length)
                pointLayoutManager.ensureLayout(forCharacterRange: NSRange(location: start, length: end - start))
                step(from: end)
            }
        }
        step(from: 0)
    }

    /// Lays out everything up to `location`, so that its place on the page is real, not a guess.
    private func layOut(through location: Int) {
        pointLayoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(location, textStorage.length)))
    }

    /// Puts the cursor anywhere in the note, however far down.
    public func placeCursor(at location: Int) {
        let location = min(location, textStorage.length)
        layOut(through: location)
        selectedRange = NSRange(location: location, length: 0)
    }

    /// Going to something further down (Find, say) goes to where it really is.
    public override func scrollRangeToVisible(_ range: NSRange) {
        layOut(through: NSMaxRange(range))
        super.scrollRangeToVisible(range)
    }

    /// Where the note's body starts: after its frontmatter, which is hidden and edited as
    /// properties, so nothing above this can be selected, typed in or deleted.
    public var bodyStart: Int {
        guard let token = tokens.first, token.kind == .frontmatter, token.range.length > 0 else { return 0 }
        let text = textStorage.string as NSString
        let last = min(NSMaxRange(token.range) - 1, text.length - 1)
        guard last >= 0 else { return 0 }
        return NSMaxRange(text.lineRange(for: NSRange(location: last, length: 0)))
    }

    /// Puts the cursor at the start of the note's body, after any markers there.
    public func moveToBodyStart() {
        cursor = bodyStart
        selectedRange = NSRange(location: bodyStart, length: 0)
        settleCursor()
    }

    private var hiddenMarkers: HiddenMarkers {
        HiddenMarkers(storage: textStorage, tokens: tokens, bodyStart: bodyStart)
    }

    /// Keeps the cursor out of hidden markers. Not before an edit is restyled, when what's hidden
    /// isn't known: restyling settles it, judged from where it was before the edit.
    func settleCursor() {
        guard pendingRestyle == nil, markedTextRange == nil, !isAdjustingSelection else { return }
        // Undo selects the markers it brings back, which the next key would then replace.
        guard selectedRange.length == 0 || hiddenMarkers.isHidden(selectedRange) else { return }
        cursor = hiddenMarkers.snapped(NSMaxRange(selectedRange), from: cursor)
        if selectedRange != NSRange(location: cursor, length: 0) { selectedRange = NSRange(location: cursor, length: 0) }
    }

    private func setSelectionDirectly(_ range: NSRange) {
        isAdjustingSelection = true
        selectedRange = range
        isAdjustingSelection = false
    }

    /// Delete, by the Mac's rules: at the start of a heading, list item or quote it removes the
    /// formatting; otherwise it takes visible text, never a hidden marker.
    public override func deleteBackward() {
        guard markedTextRange == nil else { return super.deleteBackward() }
        restylePending()
        guard selectedRange.length == 0 else {
            setSelectionDirectly(hiddenMarkers.wholeTokens(in: selectedRange))
            return super.deleteBackward()
        }
        switch hiddenMarkers.delete(at: selectedRange.location) {
        case .nothing:
            break
        case .removeMarkers(let run):
            apply(MarkdownEdit(range: run, replacement: "", selection: NSRange(location: run.location, length: 0)))
        case .delete(let location):
            setSelectionDirectly(NSRange(location: location, length: 0))
            super.deleteBackward()
        }
    }

    /// Typing over a selection takes its hidden markers too.
    public override func insertText(_ text: String) {
        if selectedRange.length > 0, markedTextRange == nil { setSelectionDirectly(hiddenMarkers.wholeTokens(in: selectedRange)) }
        super.insertText(text)
    }

    public override func cut(_ sender: Any?) {
        setSelectionDirectly(hiddenMarkers.wholeTokens(in: selectedRange))
        super.cut(sender)
    }

    /// Runs a formatting command on the selection.
    public func format(_ command: (MarkdownEditing) -> MarkdownEdit?) {
        if let edit = command(MarkdownEditing(text: textStorage.string, selection: selectedRange)) { apply(edit) }
    }

    /// Makes an edit through the text system, so it can be undone, and sets the selection.
    public func apply(_ edit: MarkdownEdit) {
        guard let start = position(from: beginningOfDocument, offset: edit.range.location),
              let end = position(from: start, offset: edit.range.length),
              let range = textRange(from: start, to: end) else { return }
        replace(range, withText: edit.replacement)
        selectedRange = edit.selection
    }

    /// Replaces text in the frontmatter, keeping the cursor on the same text in the body. This
    /// goes straight to the text, not through the text system as `apply` does: with a field in
    /// the properties sheet focused, the text system punctuates what's inserted to suit that
    /// field, and `---` came out as a dash.
    public func applyAboveBody(_ range: NSRange, with replacement: String) {
        let old = (textStorage.string as NSString).substring(with: range)
        let length = (replacement as NSString).length
        undoManager?.registerUndo(withTarget: self) {
            $0.applyAboveBody(NSRange(location: range.location, length: length), with: old)
        }
        var selection = selectedRange
        if selection.location >= NSMaxRange(range) { selection.location += length - range.length }
        textStorage.replaceCharacters(in: range, with: replacement)
        // Restyled now, so the frontmatter's end is known before the cursor goes back.
        isAdjustingSelection = true
        restylePending()
        isAdjustingSelection = false
        cursor = selection.location
        selectedRange = selection
    }
}

extension PhoneTextView: UITextViewDelegate {
    /// Keeps edits out of the frontmatter, and has Return continue lists and quotes.
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let start = bodyStart
        guard range.location >= start else { return false }
        let content = textStorage.string as NSString
        // A note that's only frontmatter, with no line break after it: typing starts a new line.
        if start > 0, start == content.length, content.character(at: start - 1) != 10, !text.isEmpty {
            apply(MarkdownEdit(range: range, replacement: "\n" + text, selection: NSRange(location: start + 1 + (text as NSString).length, length: 0)))
            return false
        }
        if text == "\n", let edit = MarkdownEditing(text: textStorage.string, selection: range).newline() {
            apply(edit)
            return false
        }
        return true
    }

    /// Never into the hidden frontmatter, where what's selected can be deleted, nor hidden markers.
    public func textViewDidChangeSelection(_ textView: UITextView) {
        let start = bodyStart
        let selection = selectedRange
        guard selection.location < start else {
            settleCursor()
            return updateCompletion()
        }
        selectedRange = NSRange(location: start, length: max(NSMaxRange(selection) - start, 0))
    }
}

extension PhoneTextView: @preconcurrency NSTextStorageDelegate {
    // MARK: Restyling

    /// Notes what an edit changed, and restyles it just after, not during the edit: restyled
    /// in the middle of it, the keyboard's autocorrection and suggestions lost track of the
    /// text, and typed words went missing.
    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isRestyling else { return }
        pendingRestyle = pendingRestyle.map { NSUnionRange($0, editedRange) } ?? editedRange
        guard !restyleScheduled else { return }
        restyleScheduled = true
        DispatchQueue.main.async { [weak self] in self?.restylePending() }
    }

    /// Restyles what was edited since last time, once the keyboard isn't in the middle of
    /// composing (marked text, as for accented letters).
    func restylePending() {
        restyleScheduled = false
        guard markedTextRange == nil else {
            restyleScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.restylePending() }
            return
        }
        guard let edited = pendingRestyle else { return }
        pendingRestyle = nil
        restyle(edited)
        settleCursor()
        let text = textStorage.string
        onTextChange?(text)
        updateCompletion()
    }

    /// Says when what can be completed at the cursor has changed.
    func updateCompletion() {
        let new = selectedRange.length == 0 ? MarkdownEditing.completion(in: textStorage.string, at: selectedRange.location) : nil
        guard new != completion else { return }
        completion = new
        onCompletionChange?(new)
    }

    /// Parses the note again and restyles `edited` (all of it, if a code block or frontmatter
    /// changed, which changes how everything after them reads).
    func restyle(_ edited: NSRange) {
        let start = CACurrentMediaTime()
        let old = tokens
        tokens = MarkdownParser.parse(textStorage.string)
        lastParseMilliseconds = (CACurrentMediaTime() - start) * 1000
        let all = NSRange(location: 0, length: textStorage.length)
        let blocks = { (tokens: [MarkdownToken]) in tokens.filter(\.changesFollowingText).count }
        let range = blocks(old) != blocks(tokens) || old.isEmpty ? all : NSIntersectionRange(edited, all)
        let selection = selectedRange
        isRestyling = true
        textStorage.beginEditing()
        styler.style(textStorage, range: range, tokens: tokens)
        textStorage.endEditing()
        isRestyling = false
        if selectedRange != selection { selectedRange = selection }
        lastEditMilliseconds = (CACurrentMediaTime() - start) * 1000
        slowestEditMilliseconds = max(slowestEditMilliseconds, lastEditMilliseconds)
    }
}
#endif
