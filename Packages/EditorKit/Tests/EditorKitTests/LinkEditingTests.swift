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

    /// The end of a link has two stops: inside it (typing goes on with the link), then, one
    /// press on, just after it (typing doesn't).
    @Test func theEndOfALinkHasTwoStops() {
        let text = "See [[Note]] more" // The link's text ends at 10; its `]]` ends at 12.
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.setSelectionDirectly(NSRange(location: 9, length: 0))
        var rightward: [Int] = []
        for _ in 0..<3 { view.moveRight(nil); rightward.append(view.selectedRange().location) }
        #expect(rightward == [10, 12, 13])
        var leftward: [Int] = []
        for _ in 0..<3 { view.moveLeft(nil); leftward.append(view.selectedRange().location) }
        #expect(leftward == [12, 10, 9])
    }

    @Test func typingAtTheEndOfALinkExtendsIt() {
        let inside = EditorTestSupport.makeEditor("See [[Note]] more", height: 300)
        inside.setSelectedRange(NSRange(location: 10, length: 0))
        inside.insertText("s", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(inside.string == "See [[Notes]] more")
        let after = EditorTestSupport.makeEditor("See [[Note]] more", height: 300)
        after.setSelectedRange(NSRange(location: 12, length: 0))
        after.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(after.string == "See [[Note]]x more")
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

    @Test func noSuggestionIsChosenUntilPicked() {
        let view = EditorTestSupport.makeEditor("See [[2026-10-2", height: 300)
        view.completeNoteTitle = { _ in ["2026-10-20 Budget review", "2026-10-28 Weekly planning"] }
        view.setSelectionDirectly(NSRange(location: 15, length: 0))
        var index = 0
        _ = view.completions(forPartialWordRange: NSRange(location: 6, length: 9), indexOfSelectedItem: &index)
        #expect(index == -1)
    }

    @Test func typingOnKeepsWhatWasTyped() {
        // A key typed while the list shows a title ends the completion with what was typed:
        // the title isn't kept.
        let view = EditorTestSupport.makeEditor("See [[2026-10-28", height: 300)
        view.completeNoteTitle = { _ in ["2026-10-28 Weekly planning"] }
        view.setSelectionDirectly(NSRange(location: 16, length: 0))
        let partial = NSRange(location: 6, length: 10)
        var index = 0
        _ = view.completions(forPartialWordRange: partial, indexOfSelectedItem: &index)
        view.isTypingKey = true
        view.insertCompletion("2026-10-28 Weekly planning", forPartialWordRange: partial, movement: NSOtherTextMovement, isFinal: true)
        view.isTypingKey = false
        #expect(view.string == "See [[2026-10-28")
    }

    @Test func returnWithNothingPickedLeavesTheLinkOpen() {
        let view = EditorTestSupport.makeEditor("See [[2026-10-28", height: 300)
        view.completeNoteTitle = { _ in ["2026-10-28 Weekly planning"] }
        view.setSelectionDirectly(NSRange(location: 16, length: 0))
        let partial = NSRange(location: 6, length: 10)
        var index = 0
        _ = view.completions(forPartialWordRange: partial, indexOfSelectedItem: &index)
        view.insertCompletion("2026-10-28", forPartialWordRange: partial, movement: NSReturnTextMovement, isFinal: true)
        #expect(view.string == "See [[2026-10-28")
    }

    @Test func clickingASuggestionFinishesTheLink() {
        let view = EditorTestSupport.makeEditor("See [[2026-10", height: 300)
        view.completeNoteTitle = { _ in ["2026-10-28 Weekly planning"] }
        view.setSelectionDirectly(NSRange(location: 13, length: 0))
        let partial = NSRange(location: 6, length: 7)
        var index = 0
        _ = view.completions(forPartialWordRange: partial, indexOfSelectedItem: &index)
        view.insertCompletion("2026-10-28 Weekly planning", forPartialWordRange: partial, movement: NSOtherTextMovement, isFinal: true)
        #expect(view.string == "See [[2026-10-28 Weekly planning]]")
    }

    @Test func escapeKeepsWhatWasTyped() {
        let view = EditorTestSupport.makeEditor("See [[2026-10", height: 300)
        view.completeNoteTitle = { _ in ["2026-10-28 Weekly planning"] }
        view.setSelectionDirectly(NSRange(location: 13, length: 0))
        let partial = NSRange(location: 6, length: 7)
        var index = 0
        _ = view.completions(forPartialWordRange: partial, indexOfSelectedItem: &index)
        view.insertCompletion("2026-10-28 Weekly planning", forPartialWordRange: partial, movement: NSCancelTextMovement, isFinal: true)
        #expect(view.string == "See [[2026-10")
    }

    @Test func completionDoesntDoubleExistingBrackets() {
        let view = EditorTestSupport.makeEditor("See [[Imp]]", height: 300)
        view.completeNoteTitle = { _ in ["Imprint App"] }
        view.setSelectionDirectly(NSRange(location: 9, length: 0))
        view.insertCompletion("Imprint App", forPartialWordRange: NSRange(location: 6, length: 3), movement: NSReturnTextMovement, isFinal: true)
        #expect(view.string == "See [[Imprint App]]")
    }
}
