#if os(iOS)
import MarkdownKit
import UIKit

/// The note editor on the iPhone: a `UITextView` on TextKit 1, sharing the Mac's styler and
/// layout manager, so notes look the same and the Markdown stays hidden. The first version,
/// for the spike: styling and restyling as you type, without the Mac's folding, cursor rules
/// or formatting commands yet.
public final class PhoneTextView: UITextView {
    public private(set) var tokens: [MarkdownToken] = []
    private var styler = MarkdownStyler()
    private let pointLayoutManager: PointLayoutManager

    /// How long the last edit took to parse and restyle, in milliseconds, and the slowest so
    /// far: what typing costs on this phone.
    public private(set) var lastEditMilliseconds: Double = 0
    public private(set) var slowestEditMilliseconds: Double = 0
    /// Of the last edit's time, how much was parsing the note (the rest is restyling).
    public private(set) var lastParseMilliseconds: Double = 0
    /// Called after each edit, with the text as it is now.
    public var onTextChange: ((String) -> Void)?

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
        styler.theme.typography.bodySize = 17 // The iPhone's own body size.
        layoutManager.theme = styler.theme
        typingAttributes = styler.baseAttributes
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// Replaces the whole text, as when opening a note. Returns how long it took, in
    /// milliseconds, to parse, style and lay out what's on screen.
    @discardableResult
    public func load(_ markdown: String) -> Double {
        let start = CACurrentMediaTime()
        textStorage.setAttributedString(NSAttributedString(string: markdown, attributes: styler.baseAttributes))
        undoManager?.removeAllActions()
        selectedRange = NSRange(location: 0, length: 0)
        layoutIfNeeded()
        // What's on screen, laid out now.
        pointLayoutManager.ensureLayout(forBoundingRect: CGRect(origin: .zero, size: bounds.size), in: textContainer)
        return (CACurrentMediaTime() - start) * 1000
    }

}

extension PhoneTextView: @preconcurrency NSTextStorageDelegate {
    // MARK: Restyling

    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let start = CACurrentMediaTime()
        let old = tokens
        tokens = MarkdownParser.parse(textStorage.string)
        lastParseMilliseconds = (CACurrentMediaTime() - start) * 1000
        let all = NSRange(location: 0, length: textStorage.length)
        // A change to code blocks or frontmatter can restyle everything after it, so all is
        // restyled; otherwise only what the edit touched (widened to whole tokens).
        let blocks = { (tokens: [MarkdownToken]) in tokens.filter(\.changesFollowingText).count }
        let range = blocks(old) != blocks(tokens) || old.isEmpty ? all : editedRange
        styler.style(textStorage, range: range, tokens: tokens)
        lastEditMilliseconds = (CACurrentMediaTime() - start) * 1000
        slowestEditMilliseconds = max(slowestEditMilliseconds, lastEditMilliseconds)
        let text = textStorage.string
        DispatchQueue.main.async { [weak self] in self?.onTextChange?(text) }
    }
}
#endif
