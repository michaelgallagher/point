import AppKit
import Testing
@testable import EditorKit

@MainActor
struct LinkEditingTests {
    @Test func findsLinksAtPositions() {
        let view = EditorTestSupport.makeEditor("[[Note#Part|alias]] [web](https://a.com) [doc](My%20Note.md) #tag https://b.org", height: 300)
        #expect(view.link(at: 3) == .note("Note#Part"))
        #expect(view.link(at: 21) == .web(URL(string: "https://a.com")!))
        #expect(view.link(at: 43) == .file("My%20Note.md"))
        #expect(view.link(at: 62) == .tag("tag"))
        #expect(view.link(at: 70) == .web(URL(string: "https://b.org")!))
        #expect(view.link(at: 19) == nil) // The space between links.
    }

    @Test func knowsWhenAWikiLinkIsBeingTyped() {
        let view = EditorTestSupport.makeEditor("See [[Imp", height: 300)
        view.setSelectionDirectly(NSRange(location: 9, length: 0))
        #expect(view.wikiLinkPartialRange() == NSRange(location: 6, length: 3))
        #expect(view.rangeForUserCompletion == NSRange(location: 6, length: 3))
    }

    @Test func notAfterTheLinkIsClosedOrAliased() {
        let closed = EditorTestSupport.makeEditor("[[Done]] more", height: 300)
        closed.setSelectionDirectly(NSRange(location: 13, length: 0))
        #expect(closed.wikiLinkPartialRange() == nil)
        let aliased = EditorTestSupport.makeEditor("[[Note|ali", height: 300)
        aliased.setSelectionDirectly(NSRange(location: 10, length: 0))
        #expect(aliased.wikiLinkPartialRange() == nil)
    }

    @Test func completionFinishesTheLink() {
        let view = EditorTestSupport.makeEditor("See [[Imp", height: 300)
        view.completeNoteTitle = { _ in ["Imprint App", "Important"] }
        view.setSelectionDirectly(NSRange(location: 9, length: 0))
        var index = 0
        #expect(view.completions(forPartialWordRange: NSRange(location: 6, length: 3), indexOfSelectedItem: &index) == ["Imprint App", "Important"])
        view.insertCompletion("Imprint App", forPartialWordRange: NSRange(location: 6, length: 3), movement: NSReturnTextMovement, isFinal: true)
        #expect(view.string == "See [[Imprint App]]")
        #expect(view.tokens.contains { $0.kind == .wikiLink(target: "Imprint App") })
    }

    @Test func completionDoesntDoubleExistingBrackets() {
        let view = EditorTestSupport.makeEditor("See [[Imp]]", height: 300)
        view.completeNoteTitle = { _ in ["Imprint App"] }
        view.setSelectionDirectly(NSRange(location: 9, length: 0))
        view.insertCompletion("Imprint App", forPartialWordRange: NSRange(location: 6, length: 3), movement: NSReturnTextMovement, isFinal: true)
        #expect(view.string == "See [[Imprint App]]")
    }
}
