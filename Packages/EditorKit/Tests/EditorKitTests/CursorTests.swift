import AppKit
import Testing
@testable import EditorKit

@MainActor
struct CursorTests {
    private func editor(_ text: String, cursors: [Int]) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(text, height: 400)
        view.setSelectedRange(NSRange(location: cursors[0], length: 0))
        for cursor in cursors.dropFirst() { view.addCursor(at: cursor) }
        return view
    }

    @Test func typingGoesInAtEveryCursor() {
        let view = editor("one\ntwo\nthree", cursors: [0, 4, 8])
        #expect(view.allSelections.count == 3)
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "xone\nxtwo\nxthree")
        #expect(view.allSelections.map(\.location) == [1, 6, 11])
    }

    @Test func deletingAtEveryCursor() {
        let view = editor("ab\ncd", cursors: [2, 5])
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(view.string == "a\nc")
    }

    @Test func listsContinueAtEveryCursor() {
        let view = editor("- a\n- b", cursors: [3, 7])
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.string == "- a\n- \n- b\n- ")
    }

    @Test func nextMatchThenTypeReplacesEach() {
        let view = EditorTestSupport.makeEditor("cat dog cat", height: 400)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.addNextMatch(nil)
        #expect(view.allSelections == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        view.insertText("cow", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "cow dog cow")
    }

    @Test func addingACursorBelow() {
        let view = editor("one\ntwo", cursors: [1])
        view.addCursorBelow(nil)
        #expect(view.allSelections.map(\.location) == [1, 5])
    }

    @Test func escapeGoesBackToOneCursor() {
        let view = editor("one\ntwo", cursors: [0, 4])
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(!view.hasMultipleCursors)
    }

    @Test func oneUndoTakesBackEveryCursor() {
        let view = editor("one\ntwo", cursors: [0, 4])
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "xone\nxtwo")
        view.undoManager?.undo()
        #expect(view.string == "one\ntwo")
    }
}
