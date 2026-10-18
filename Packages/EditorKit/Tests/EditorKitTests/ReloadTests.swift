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

@MainActor
struct HeadingStyleTests {
    private func font(_ markdown: String) -> NSFont {
        let view = EditorTestSupport.makeEditor(markdown, height: 300)
        let index = (markdown as NSString).length - 1 // The heading's last letter.
        return view.textStorage!.attribute(.font, at: index, effectiveRange: nil) as! NSFont
    }

    private func traits(_ font: NSFont) -> NSFontDescriptor.SymbolicTraits { font.fontDescriptor.symbolicTraits }

    @Test func headingLevels() {
        #expect(font("# A").pointSize == 26 && traits(font("# A")).contains(.bold))
        #expect(font("## A").pointSize == 18)
        #expect(font("### A").pointSize == 15 && traits(font("### A")).contains(.bold))
        let h4 = font("#### A")
        #expect(h4.pointSize == 15 && traits(h4).contains(.italic) && !traits(h4).contains(.bold))
    }
}

@MainActor
struct LinkAndTagStyleTests {
    @Test func webLinksMakeRoomForTheirSymbol() {
        let text = "[site](https://a.com) [[Note]] https://b.org"
        let view = EditorTestSupport.makeEditor(text, height: 300)
        let storage = view.textStorage!
        let ns = text as NSString
        let siteEnd = ns.range(of: "site").location + 3
        #expect(storage.attribute(.imprintWebLink, at: siteEnd, effectiveRange: nil) != nil)
        #expect((storage.attribute(.kern, at: siteEnd, effectiveRange: nil) as? CGFloat ?? 0) > 0)
        #expect(storage.attribute(.imprintWebLink, at: ns.length - 1, effectiveRange: nil) != nil)
        // Wikilinks don't get the symbol.
        let noteEnd = ns.range(of: "Note").location + 3
        #expect(storage.attribute(.imprintWebLink, at: noteEnd, effectiveRange: nil) == nil)
    }

    @Test func tagsAreMarkedForPills() {
        let view = EditorTestSupport.makeEditor("a #tag b", height: 300)
        #expect(view.textStorage!.attribute(.imprintTag, at: 3, effectiveRange: nil) != nil)
        #expect(view.textStorage!.attribute(.imprintTag, at: 7, effectiveRange: nil) == nil)
    }
}
