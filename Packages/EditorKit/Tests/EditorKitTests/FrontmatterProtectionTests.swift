import AppKit
import Testing
@testable import EditorKit

/// The frontmatter, hidden and edited as properties, can't be selected or deleted as text.
@MainActor
struct FrontmatterProtectionTests {
    private let note = "---\ntags: [work]\nstatus: draft\n---\nFirst line\nSecond line"

    @Test func selectAllThenDeleteKeepsTheProperties() {
        let view = EditorTestSupport.makeEditor(note, height: 400)
        view.selectAll(nil)
        view.deleteBackward(nil)
        #expect(view.string == "---\ntags: [work]\nstatus: draft\n---\n")
    }

    @Test func aSelectionStopsAtTheBody() {
        let view = EditorTestSupport.makeEditor(note, height: 400)
        let body = (note as NSString).range(of: "First").location
        view.setSelectedRange(NSRange(location: 2, length: body + 3))
        #expect(view.selectedRange() == NSRange(location: body, length: 5))
    }

    @Test func backspaceAtTheBodysStartLeavesTheFrontmatter() {
        let view = EditorTestSupport.makeEditor(note, height: 400)
        let body = (note as NSString).range(of: "First").location
        view.setSelectedRange(NSRange(location: body, length: 0))
        view.deleteBackward(nil)
        #expect(view.string == note)
    }

    @Test func showingMarkdownSelectsEverything() {
        let view = EditorTestSupport.makeEditor(note, height: 400)
        view.showsMarkdown = true
        view.selectAll(nil)
        #expect(view.selectedRange() == NSRange(location: 0, length: (note as NSString).length))
    }
}
