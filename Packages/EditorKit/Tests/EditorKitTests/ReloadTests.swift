import AppKit
import Testing
@testable import EditorKit

@MainActor
struct ReloadTests {
    @Test func keepsTheCursorWhenTextChangesBeforeIt() {
        let view = EditorTestSupport.makeEditor("one\ntwo\nthree", height: 300)
        view.setSelectionDirectly(NSRange(location: 9, length: 2)) // "hr" in "three"
        view.reload("one\nINSERTED\ntwo\nthree")
        #expect(view.string == "one\nINSERTED\ntwo\nthree")
        #expect((view.string as NSString).substring(with: view.selectedRange()) == "hr")
    }

    @Test func keepsTheCursorWhenTextChangesAfterIt() {
        let view = EditorTestSupport.makeEditor("one\ntwo", height: 300)
        view.setSelectionDirectly(NSRange(location: 2, length: 0))
        view.reload("one\ntwo\nthree")
        #expect(view.selectedRange().location == 2)
    }

    @Test func reloadingIsNotUndoable() {
        let view = EditorTestSupport.makeEditor("a", height: 300)
        view.reload("b")
        #expect(view.undoManager?.canUndo == false)
        #expect(view.tokens.isEmpty)
    }

    @Test func restylesWhatChanged() {
        let view = EditorTestSupport.makeEditor("plain", height: 300)
        view.reload("**bold**")
        #expect(view.tokens.first?.kind == .strong)
        #expect(view.isHidden(0))
    }
}

@MainActor
struct FrontmatterEditorTests {
    @Test func frontmatterIsHiddenAndSkipped() {
        let view = EditorTestSupport.makeEditor("---\ntags: [a]\n---\nBody", height: 300)
        #expect((0..<16).filter { (view.string as NSString).character(at: $0) != 10 }.allSatisfy(view.isHidden))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(view.selectedRange().location == 18) // Lands on the body.
    }

    @Test func openingANoteStartsAfterItsFrontmatter() {
        let view = EditorTestSupport.makeEditor("---\ntags: [a]\n---\n# Title", height: 300)
        #expect(view.selectedRange().location == 20) // After the hidden "# ".
    }

    @Test func outsideEditsKeepTheSelectionAndUndo() {
        let view = EditorTestSupport.makeEditor("---\na: 1\n---\nBody text", height: 300)
        view.setSelectionDirectly(NSRange(location: 18, length: 4)) // "text"
        view.applyEdit(replacing: NSRange(location: 4, length: 5), with: "a: 22\nb: 3\n")
        #expect(view.string == "---\na: 22\nb: 3\n---\nBody text")
        #expect((view.string as NSString).substring(with: view.selectedRange()) == "text")
        view.undoManager?.undo()
        #expect(view.string == "---\na: 1\n---\nBody text")
    }
}

@MainActor
struct ShowMarkdownTests {
    @Test func revealsEveryMarkerAndHidesThemAgain() {
        let view = EditorTestSupport.makeEditor("---\na: 1\n---\n# **Bold** [[Link]]", height: 300)
        view.showsMarkdown = true
        #expect((0..<(view.string as NSString).length).allSatisfy { !view.isHidden($0) })
        view.showsMarkdown = false
        #expect(view.isHidden(0) && view.isHidden(14))
        #expect(view.string == "---\na: 1\n---\n# **Bold** [[Link]]")
    }
}
