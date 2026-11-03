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
}
