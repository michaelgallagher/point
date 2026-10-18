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
