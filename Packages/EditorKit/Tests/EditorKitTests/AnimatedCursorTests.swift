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

    @Test func onAnEmptyLineItsWhereTextWouldBe() throws {
        let text = try #require(editor("One\nTwo\nThree", at: 4).cursorRect())
        let empty = try #require(editor("One\n\nThree", at: 4).cursorRect())
        #expect(abs(empty.minY - text.minY) < 0.5)
        #expect(abs(empty.height - text.height) < 0.5)
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
        view.cursorView.restartBlink()
        let blink = try #require(view.cursorView.layer?.animation(forKey: "blink") as? CAKeyframeAnimation)
        let values = try #require(blink.values as? [NSNumber]).map(\.doubleValue)
        let times = try #require(blink.keyTimes?.map(\.doubleValue))
        #expect(values.count == times.count)
        #expect(values.first == 1 && values.last == 1 && values.contains(0))
        #expect(times.first == 0 && times.last == 1 && times == times.sorted())
        #expect(blink.repeatCount == .infinity)
    }
}

/// The same cursor in other text fields (see FieldCursors).
@MainActor
struct FieldCursorsTests {
    @Test func itGoesWhereTheSystemsWouldInAField() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(string: "Some words")
        field.frame = NSRect(x: 20, y: 20, width: 200, height: 22)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(editor.isFieldEditor && !(editor is MarkdownTextView))
        for location in [0, 4, 10] {
            editor.setSelectedRange(NSRange(location: location, length: 0))
            let rect = try #require(FieldCursors.cursorRect(in: editor))
            let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let system = editor.convert(window.convertFromScreen(screen), from: nil)
            #expect(abs(rect.minX - system.minX) <= 1, "at \(location)")
            #expect(rect.minY >= system.minY - 0.5 && rect.maxY <= system.maxY + 0.5)
            #expect(rect.height > 10)
        }
        // Further along, further across.
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let start = try #require(FieldCursors.cursorRect(in: editor))
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(try #require(FieldCursors.cursorRect(in: editor)).minX > start.minX + 30)
    }
}

/// Lines an edit moves sliding into place (see +SlidingLines).
@MainActor
struct SlidingLinesTests {
    func editor(_ markdown: String, at location: Int) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(markdown, height: 500)
        view.window?.makeFirstResponder(view)
        view.setSelectionDirectly(NSRange(location: location, length: 0))
        return view
    }

    /// What moved in `edit`, top first.
    func moves(_ view: MarkdownTextView, _ edit: () -> Void) throws -> [MarkdownTextView.LineMove] {
        let start = try #require(view.lineMoveStart())
        view.isRecordingLineMoves = true
        edit()
        view.isRecordingLineMoves = false
        defer { view.lineMoveEdits = nil }
        return view.lineMoves(since: start).sorted { $0.rect.minY < $1.rect.minY }
    }

    func lineHeight(_ view: MarkdownTextView) -> CGFloat {
        view.layoutManager!.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    }

    @Test func returnAtTheEndOfALineMovesTheLinesBelowDown() throws {
        let view = editor("One\nTwo\nThree", at: 3)
        let moved = try moves(view) { view.insertNewline(nil) }
        // "Two" and "Three" each come down a line; "One" stays.
        let down = moved.filter { $0.rect.minX == 0 }
        #expect(down.count >= 2)
        for move in down { #expect(abs(move.offset.dy + lineHeight(view)) < 1 || move.offset.dy < 0) }
        #expect(!moved.contains { $0.rect.minY < view.textContainerOrigin.y + 1 })
    }

    @Test func returnInALinesTextMovesNothing() throws {
        // The rest of the line goes straight to the new one, as typed text does.
        let view = editor("Hello world\nNext", at: 6)
        #expect(try moves(view) { view.insertNewline(nil) }.isEmpty)
        // At the end of a list item, the new item comes in and the lines below slide down.
        let list = editor("- One\n- Two", at: 5)
        #expect(try !moves(list) { list.insertNewline(nil) }.isEmpty)
    }

    @Test func deletingALineBreakMovesTheJoinedTextUp() throws {
        let view = editor("One\nTwo\nThree", at: 4)
        let moved = try moves(view) { view.deleteBackward(nil) }
        #expect(view.string == "OneTwo\nThree")
        // "Two" goes up from the start of its line to after "One"; "Three" goes up a line.
        let two = try #require(moved.first)
        #expect(two.offset.dy > 10 && two.offset.dx < -10)
        let three = try #require(moved.last)
        #expect(three.offset.dy > 10 && abs(three.offset.dx) < 1)
    }

    @Test func typingWithinALineMovesNothing() throws {
        let view = editor("One\nTwo", at: 1)
        #expect(try moves(view) { view.insertText("x", replacementRange: view.selectedRange()) }.isEmpty)
    }

    @Test func typingThatWrapsMovesTheWrappedWordWithWhatWasTyped() throws {
        let words = Array(repeating: "word", count: 40).joined(separator: " ")
        let view = editor(words + "\nNext", at: 0)
        // Typing at the end of the first line's last word, until it wraps.
        let layoutManager = view.layoutManager!
        var firstLine = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLine)
        let end = layoutManager.characterRange(forGlyphRange: firstLine, actualGlyphRange: nil)
        let wordEnd = NSMaxRange(end) - 1 // Before the space the line breaks at.
        view.setSelectionDirectly(NSRange(location: wordEnd, length: 0))
        var moved: [MarkdownTextView.LineMove] = []
        for _ in 0..<12 where moved.isEmpty {
            moved = try moves(view) { view.insertText("x", replacementRange: view.selectedRange()) }
        }
        // The wrapped word, typed letter and all, comes down from the end of the first line.
        let wrapped = try #require(moved.first)
        #expect(wrapped.rect.minX == 0)
        #expect(wrapped.offset.dy < -10 && wrapped.offset.dx > 100)
    }

    @Test func indentingAListItemMovesItAcross() throws {
        let view = editor("- One\n- Two\n- Three", at: 9)
        let moved = try moves(view) { view.changeIndent(by: 1) }
        let two = try #require(moved.first)
        #expect(two.offset.dx < -5 && abs(two.offset.dy) < 1)
    }

    @Test func movingALineDownSwapsThem() throws {
        let view = editor("One\nTwo\nThree", at: 1)
        let moved = try moves(view) { view.moveLinesDown(nil) }
        #expect(view.string.hasPrefix("Two\nOne"))
        #expect(moved.contains { $0.offset.dy > 10 }) // "Two", up.
        #expect(moved.contains { $0.offset.dy < -10 }) // "One", down.
    }

    @Test func thePiecesSlideOverPatchesAndGo() throws {
        let view = editor("One\nTwo\nThree", at: 3)
        view.movingLines { view.insertNewline(nil) }
        let container = try #require(view.slidingLines)
        #expect(container.superview === view && !container.subviews.isEmpty)
        // Typing on that moves nothing leaves them sliding.
        view.movingLines { view.insertText("x", replacementRange: view.selectedRange()) }
        #expect(view.slidingLines === container)
        view.endLineSlide()
        #expect(view.slidingLines == nil && container.superview == nil)
    }
}
