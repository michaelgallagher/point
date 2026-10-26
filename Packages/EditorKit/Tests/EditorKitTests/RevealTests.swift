import AppKit
import Testing
@testable import EditorKit

/// Opening a note at a place in it (a link or mention found there).
@MainActor
struct RevealTests {
    @Test func selectsAndScrollsToTheRange() {
        let lines = (1...200).map { "Line \($0) of a long note." }
        let text = lines.joined(separator: "\n") + "\nThe mention is here."
        let view = EditorTestSupport.makeEditor(text, height: 400)
        view.enclosingScrollView?.frame.size.height = 400
        let range = (text as NSString).range(of: "mention")
        view.reveal(range)
        #expect(view.selectedRange() == range)
        // Scrolled down to it: the visible part of the note includes the range.
        let visible = view.visibleRect
        let glyphs = view.layoutManager!.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = view.layoutManager!.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        rect.origin.y += view.textContainerOrigin.y
        #expect(visible.intersects(rect))
    }

    @Test func ignoresARangePastTheEnd() {
        let view = EditorTestSupport.makeEditor("Short note.", height: 400)
        view.reveal(NSRange(location: 50, length: 4))
        #expect(view.selectedRange().location <= 11)
    }

    @Test func leavesRoomBelowTheText() {
        // A note longer than the window: its view grows with its text.
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n")
        let view = EditorTestSupport.makeEditor(text, height: 400)
        view.sizeToFit()
        let before = view.frame.height
        view.extraBottomSpace = 64
        #expect(view.frame.height >= before + 63)
    }
}
