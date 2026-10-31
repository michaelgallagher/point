import AppKit
import Testing
@testable import EditorKit

/// Keeping the line at the top in place: as the text rewraps to a new width, and when a
/// note is shown again where it was left.
@MainActor
struct ScrollAnchorTests {
    /// A note of long paragraphs, which rewrap to more or fewer lines at another width.
    private static let text = (1...150).map { "Paragraph \($0): " + String(repeating: "the quick brown fox jumps over the lazy dog ", count: 6) }
        .joined(separator: "\n\n")

    private func scrolled(_ view: MarkdownTextView, to y: CGFloat) {
        let clip = view.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: y))
        view.enclosingScrollView!.reflectScrolledClipView(clip)
    }

    @Test func noAnchorAtTheTop() {
        let view = EditorTestSupport.makeEditor(Self.text, height: 400)
        view.sizeToFit()
        #expect(view.scrollAnchor == nil)
    }

    @Test func theTopLineStaysAsTheWidthChanges() throws {
        let view = EditorTestSupport.makeEditor(Self.text, height: 400)
        view.sizeToFit()
        scrolled(view, to: 6000)
        let before = try #require(view.scrollAnchor)
        for width: CGFloat in [480, 900, 620] {
            view.setFrameSize(NSSize(width: width, height: view.frame.height))
            let after = try #require(view.scrollAnchor)
            // The same line at the top: its first character, or one near it on that line.
            let line = (Self.text as NSString).lineRange(for: NSRange(location: before.index, length: 0))
            #expect(NSLocationInRange(after.index, line), "at \(width) points wide")
        }
    }

    @Test func scrollsBackToAnAnchor() throws {
        let view = EditorTestSupport.makeEditor(Self.text, height: 400)
        view.sizeToFit()
        scrolled(view, to: 9000)
        let anchor = try #require(view.scrollAnchor)
        scrolled(view, to: 0)
        view.scroll(to: anchor)
        let back = try #require(view.scrollAnchor)
        #expect(abs(view.enclosingScrollView!.contentView.bounds.minY - 9000) < 1)
        #expect(back.index == anchor.index)
    }

    @Test func anAnchorPastTheEndGoesToTheEnd() {
        let view = EditorTestSupport.makeEditor("Short note.", height: 400)
        view.scroll(to: MarkdownTextView.ScrollAnchor(index: 5000, offset: 0))
        #expect(view.selectedRange().location <= 11)
    }
}
