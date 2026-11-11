#if os(iOS)
import MarkdownKit
import UIKit

/// Where a tapped link points. (The Mac's is in `MarkdownTextView+Links.swift`.)
public enum LinkTarget: Equatable, Sendable {
    /// A wikilink or embed target, such as `Note#Heading`.
    case note(String)
    /// A Markdown link destination that isn't a web address, such as `Other%20Note.md`.
    case file(String)
    case web(URL)
    case tag(String)

    /// Whether a link opens without asking: web pages and email.
    public static func opensWithoutAsking(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}

/// Taps on the text that aren't for a checkbox, link or image, while it isn't being edited,
/// alongside the text view's own (which clears a selection).
private final class PlainTapFilter: NSObject, UIGestureRecognizerDelegate {
    weak var textView: PhoneTextView?

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let textView, textView.onPlainTap != nil, !textView.isEditable else { return false }
        let point = recognizer.location(in: textView)
        return textView.checkboxState(at: point) == nil && textView.link(at: point) == nil && textView.image(at: point) == nil
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Lets the tap through only for a checkbox or a link: anywhere else it's the text view's own.
private final class TapFilter: NSObject, UIGestureRecognizerDelegate {
    weak var textView: PhoneTextView?

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        let point = recognizer.location(in: textView)
        return textView.checkboxState(at: point) != nil
            || (!textView.isFirstResponder && (textView.link(at: point) != nil || textView.image(at: point) != nil))
    }

    /// Ahead of the text view's own tap, which would place the cursor and raise the keyboard.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other.view === textView && other is UITapGestureRecognizer
    }
}

/// Tapping: a checkbox ticks, always. A link opens while reading; with the keyboard up, the tap
/// places the cursor, so a link's text can be edited.
extension PhoneTextView {
    func addTapRecognizer() {
        let filter = TapFilter()
        filter.textView = self
        tapFilter = filter
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = filter
        addGestureRecognizer(tap)
        let plainFilter = PlainTapFilter()
        plainFilter.textView = self
        plainTapFilter = plainFilter
        let plain = UITapGestureRecognizer(target: self, action: #selector(plainTapped))
        plain.delegate = plainFilter
        addGestureRecognizer(plain)
    }

    @objc private func plainTapped() {
        // A selection being cleared by this tap isn't a tap on the text.
        let hadSelection = selectedRange.length > 0
        DispatchQueue.main.async { [weak self] in
            guard let self, !hadSelection else { return }
            self.onPlainTap?()
        }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if let state = checkboxState(at: point) {
            UISelectionFeedbackGenerator().selectionChanged()
            apply(MarkdownEdit(range: state.range, replacement: state.done ? " " : "x", selection: selectedRange))
        } else if let url = image(at: point) {
            onOpenImage?(url)
        } else if let target = link(at: point) {
            // An image's caption opens the image, not a note named after it.
            if case .note(let name) = target, MarkdownStyler.isImageName(name), let url = styler.imageURL?(name) {
                onOpenImage?(url)
            } else {
                onOpenLink?(target)
            }
        }
    }

    /// The character at a point in the view, only if the point is on its glyph (not in the
    /// empty space past the end of a line).
    private func characterIndex(exactlyAt point: CGPoint) -> Int? {
        guard textStorage.length > 0 else { return nil }
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let bounds = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard bounds.contains(local) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    /// The link at a point in the view, if any.
    func link(at point: CGPoint) -> LinkTarget? {
        guard let index = characterIndex(exactlyAt: point) else { return nil }
        let text = textStorage.string as NSString
        for token in tokens where NSLocationInRange(index, token.range) {
            switch token.kind {
            case .wikiLink(let target), .embed(let target):
                return .note(target)
            case .link(let destination), .image(let destination):
                if let url = URL(string: destination), let scheme = url.scheme, scheme != "file" { return .web(url) }
                return .file(destination)
            case .url:
                return URL(string: text.substring(with: token.range)).map(LinkTarget.web)
            case .tag(let tag):
                return .tag(tag)
            default:
                continue
            }
        }
        return nil
    }

    /// The checkbox at a point in the view, with room around it for a finger: the character
    /// between its brackets, and whether it's ticked.
    func checkboxState(at point: CGPoint) -> (range: NSRange, done: Bool)? {
        let manager = pointLayoutManager
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        guard textStorage.length > 0 else { return nil }
        let index = manager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        let text = textStorage.string as NSString
        let lineStart = text.lineRange(for: NSRange(location: min(index, textStorage.length - 1), length: 0)).location
        guard let token = tokens.first(where: { $0.range.location == lineStart }),
              case .listItem(.task(let done), _) = token.kind,
              let decoration = textStorage.attribute(.pointListMarker, at: lineStart, effectiveRange: nil) as? ListMarkerDecoration,
              let marker = token.syntax.first else { return nil }

        let line = manager.lineRect(containing: lineStart, storage: textStorage)
        let font = manager.textFont(near: lineStart, storage: textStorage)
        let visible = manager.firstVisibleCharacter(onLineOf: lineStart, storage: textStorage)
        let baseline = line.minY + (visible.map { manager.location(forGlyphAt: manager.glyphIndexForCharacter(at: $0)).y } ?? font.ascender)
        let x = textContainer.lineFragmentPadding + manager.theme.indentPerLevel * CGFloat(decoration.level)
        let box = manager.checkboxRect(x: x, baseline: baseline, font: font).insetBy(dx: -12, dy: -8)
        guard box.contains(local) else { return nil }

        let bracket = text.range(of: "[", options: [], range: marker)
        guard bracket.location != NSNotFound else { return nil }
        return (NSRange(location: bracket.location + 1, length: 1), done)
    }
}
#endif
