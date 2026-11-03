import AppKit
import Testing
@testable import EditorKit

/// The editor's own cursor (see +AnimatedCursor): where it goes, and when it hides.
@MainActor
struct AnimatedCursorTests {
    func editor(_ markdown: String, at location: Int) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(markdown, height: 500)
        view.window?.makeFirstResponder(view)
        view.setSelectionDirectly(NSRange(location: location, length: 0))
        return view
    }

    /// Where the system puts the insertion point, in the view.
    func systemRect(_ view: MarkdownTextView) -> NSRect {
        let screen = view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil)
        return view.convert(view.window!.convertFromScreen(screen), from: nil)
    }

    @Test func itGoesWhereTheSystemsWould() throws {
        let text = "First line\n\nA **bold** word and more"
        for location in [0, 3, 10, 12, 16, (text as NSString).length] {
            let view = editor(text, at: location)
            let rect = try #require(view.cursorRect())
            let system = systemRect(view)
            #expect(abs(rect.minX - system.minX) <= 1, "at \(location)")
            #expect(rect.minY >= system.minY && rect.maxY <= system.maxY, "at \(location)")
            #expect(rect.height > 10)
        }
    }

    @Test func itsAsTallAsTheTextItsIn() throws {
        let heading = try #require(editor("# A heading\n\nBody", at: 2).cursorRect())
        let body = try #require(editor("# A heading\n\nBody", at: 15).cursorRect())
        #expect(heading.height > body.height + 4)
        let bold = try #require(editor("Some **bold** text", at: 7).cursorRect())
        #expect(abs(bold.height - body.height) < 1)
    }

    @Test func onTheEmptyLastLineItsFullHeight() throws {
        let view = editor("Some text\n", at: 10)
        let rect = try #require(view.cursorRect())
        let above = try #require(editor("Some text\n", at: 0).cursorRect())
        #expect(rect.minY > above.maxY)
        #expect(abs(rect.height - above.height) < 1)
        #expect(abs(rect.minX - above.minX) <= 1)
    }

    @Test func inAnEmptyNoteItsAtTheStart() throws {
        let view = editor("", at: 0)
        let rect = try #require(view.cursorRect())
        #expect(rect.height > 10)
        #expect(abs(rect.minX - view.textContainerOrigin.x - view.textContainer!.lineFragmentPadding) <= 1)
    }

    @Test func itHidesWithASelectionOrOutsideTheKeyWindow() {
        let view = editor("Some text", at: 2)
        view.updateCursor(animated: false)
        // The test's window is never key, so nothing shows.
        #expect(view.cursorView.isHidden)
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.updateCursor(animated: false)
        #expect(view.cursorView.isHidden)
        #expect(view.cursorView.superview === view)
    }

    @Test func itBlinksSolidThenOffThenOn() throws {
        let view = editor("Some text", at: 2)
        view.restartCursorBlink()
        let blink = try #require(view.cursorView.layer?.animation(forKey: "blink") as? CAKeyframeAnimation)
        let values = try #require(blink.values as? [NSNumber]).map(\.doubleValue)
        let times = try #require(blink.keyTimes?.map(\.doubleValue))
        #expect(values.count == times.count)
        #expect(values.first == 1 && values.last == 1 && values.contains(0))
        #expect(times.first == 0 && times.last == 1 && times == times.sorted())
        #expect(blink.repeatCount == .infinity)
    }
}

/// The lines below a typed line break sliding into place (see +SlidingLines).
@MainActor
struct SlidingLinesTests {
    func editor(_ markdown: String, at location: Int) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(markdown, height: 500)
        view.window?.makeFirstResponder(view)
        view.setSelectionDirectly(NSRange(location: location, length: 0))
        return view
    }

    @Test func returnSlidesTheLinesBelowDownALine() throws {
        let view = editor("One\nTwo\nThree", at: 3)
        let start = try #require(view.lineSlideStart())
        view.insertNewline(nil)
        let slide = try #require(view.lineSlide(since: start))
        #expect(slide.distance > 10)
        let two = view.layoutManager!.lineFragmentRect(forGlyphAt: view.layoutManager!.glyphIndexForCharacter(at: 5), effectiveRange: nil)
        #expect(abs(slide.top - (two.minY + view.textContainerOrigin.y)) < 0.5)

        // The picture of them ends where they are, over the text.
        view.slideLines(since: start)
        let container = try #require(view.slidingLines)
        let lines = try #require(container.subviews.first)
        #expect(abs(container.frame.minY + lines.frame.minY - slide.top) < 0.5)
        #expect(container.superview === view)
        view.endLineSlide()
        #expect(view.slidingLines == nil && container.superview == nil)
    }

    @Test func deletingALineBreakSlidesThemUp() throws {
        let view = editor("One\nTwo\nThree", at: 4)
        let start = try #require(view.lineSlideStart())
        view.deleteBackward(nil)
        #expect(view.string == "OneTwo\nThree")
        #expect(try #require(view.lineSlide(since: start)).distance < -10)
    }

    @Test func nothingSlidesWithinALineOrWithNothingBelow() throws {
        let view = editor("One\nTwo", at: 2)
        let start = try #require(view.lineSlideStart())
        view.insertText("x", replacementRange: view.selectedRange())
        #expect(view.lineSlide(since: start) == nil)
        #expect(editor("One\nTwo", at: 6).lineSlideStart() == nil)
    }
}

