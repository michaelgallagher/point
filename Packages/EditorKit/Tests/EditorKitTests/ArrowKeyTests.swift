import AppKit
import Testing
@testable import EditorKit

/// Real up/down arrow movement (NSTextView's moveUp/moveDown) through lines that start
/// with hidden markers.
@MainActor
struct ArrowKeyTests {
    private let text = "Plain first line\n- item one\n- item two\n# Heading\n> quoted\nlast line"

    /// The 0-based line the cursor is on.
    private func line(_ view: MarkdownTextView) -> Int {
        let before = (view.string as NSString).substring(to: view.selectedRange().location)
        return before.filter { $0 == "\n" }.count
    }

    @Test func downVisitsEveryLineInOrder() {
        let view = EditorTestSupport.makeEditor(text, height: 600)
        view.setSelectionDirectly(NSRange(location: 0, length: 0))
        var visited = [line(view)]
        for _ in 0..<5 {
            view.moveDown(nil)
            visited.append(line(view))
        }
        #expect(visited == [0, 1, 2, 3, 4, 5])
    }

    @Test func upVisitsEveryLineInOrder() {
        let view = EditorTestSupport.makeEditor(text, height: 600)
        view.setSelectionDirectly(NSRange(location: (text as NSString).length, length: 0))
        var visited = [line(view)]
        for _ in 0..<5 {
            view.moveUp(nil)
            visited.append(line(view))
        }
        #expect(visited == [5, 4, 3, 2, 1, 0])
    }

    @Test func upAndDownFromTheStartOfLines() {
        let view = EditorTestSupport.makeEditor(text, height: 600)
        view.setSelectionDirectly(NSRange(location: 0, length: 0))
        view.moveDown(nil) // Into "- item one", at the start of its text.
        view.moveDown(nil)
        view.moveUp(nil)
        #expect(line(view) == 1)
        view.moveUp(nil)
        #expect(line(view) == 0)
    }

    @Test func leftFromTheStartOfAListItemGoesToThePreviousLine() {
        let view = EditorTestSupport.makeEditor("first\n- item", height: 300)
        view.setSelectionDirectly(NSRange(location: 8, length: 0)) // Before "item".
        view.moveLeft(nil)
        #expect(view.selectedRange().location == 5) // End of "first".
    }

    @Test func theCursorNeverRestsBeforeALineStartMarker() {
        let view = EditorTestSupport.makeEditor("first\n- item", height: 300)
        view.setSelectionDirectly(NSRange(location: 2, length: 0))
        view.setSelectedRange(NSRange(location: 6, length: 0)) // Line start, before the hidden "- ".
        #expect(view.selectedRange().location == 8)
    }
}

/// Arrows through a note with every kind of formatting, checking that each press moves
/// exactly one visible line.
@MainActor
struct ArrowKeySweepTests {
    static let tour = try! String(contentsOf: Bundle.module.url(forResource: "FormattingTour", withExtension: "md")!, encoding: .utf8)

    /// The top of the visible line the cursor is drawn on.
    private func caretLineTop(_ view: MarkdownTextView) -> CGFloat {
        let layout = view.layoutManager!
        let text = view.string as NSString
        var k = view.selectedRange().location
        if k >= text.length { return layout.extraLineFragmentRect.height > 0 ? layout.extraLineFragmentRect.minY : layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil).minY }
        // A hidden marker at the cursor is drawn where the next visible character is.
        while k < text.length - 1, view.isHidden(k), text.character(at: k) != 10 { k += 1 }
        return layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: k), effectiveRange: nil).minY
    }

    /// The tops of all visible lines (collapsed fence lines excluded), in order.
    private func visibleLineTops(_ view: MarkdownTextView) -> [CGFloat] {
        let layout = view.layoutManager!
        var tops: [CGFloat] = []
        var glyph = 0
        while glyph < layout.numberOfGlyphs {
            var range = NSRange()
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            // Collapsed lines (code fences, frontmatter) are a sliver high and never visited.
            if rect.height > 8, tops.last != rect.minY { tops.append(rect.minY) }
            glyph = NSMaxRange(range)
        }
        if layout.extraLineFragmentRect.height > 0 { tops.append(layout.extraLineFragmentRect.minY) }
        return tops
    }

    @Test(arguments: [0, 3, 12, 40])
    func downThenUpVisitsEveryLine(column: Int) {
        let view = EditorTestSupport.makeEditor(Self.tour, height: 2400)
        let expected = visibleLineTops(view)
        // Start on the first visible line after the frontmatter, `column` characters in.
        let heading = (Self.tour as NSString).range(of: "Formatting tour\n").location
        view.setSelectionDirectly(NSRange(location: heading + min(column, 14), length: 0))
        let start = expected.firstIndex(of: caretLineTop(view))!

        var down = [caretLineTop(view)]
        for _ in 0..<(expected.count - start - 1) {
            view.moveDown(nil)
            down.append(caretLineTop(view))
        }
        #expect(down == Array(expected[start...]), "down from column \(column)")

        var up = [caretLineTop(view)]
        for _ in 0..<(expected.count - start - 1) {
            view.moveUp(nil)
            up.append(caretLineTop(view))
        }
        #expect(up == Array(expected[start...].reversed()), "up from column \(column)")
    }
}
