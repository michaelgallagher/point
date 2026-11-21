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
    }

    @Test func notAfterTheLinkIsClosedOrAliased() {
        let closed = EditorTestSupport.makeEditor("[[Done]] more", height: 300)
        closed.setSelectionDirectly(NSRange(location: 13, length: 0))
        #expect(closed.wikiLinkPartialRange() == nil)
        let aliased = EditorTestSupport.makeEditor("[[Note|ali", height: 300)
        aliased.setSelectionDirectly(NSRange(location: 10, length: 0))
        #expect(aliased.wikiLinkPartialRange() == nil)
    }

    /// An editor with the cursor at the end, focused, as when typing.
    private func typing(_ text: String, titles: [String]) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.completeNoteTitle = { _ in titles }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    @Test func thePopupOffersTitlesAndReturnFinishesTheLink() {
        let view = typing("See [[Imp", titles: ["Imprint App", "Important"])
        #expect(view.popup?.model.rows.map(\.title) == ["Imprint App", "Important"])
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "See [[Imprint App]]")
        #expect(view.tokens.contains { $0.kind == .wikiLink(target: "Imprint App") })
        #expect(view.popup == nil)
    }

    @Test func downChoosesAnother() {
        let view = typing("See [[Imp", titles: ["Imprint App", "Important"])
        #expect(view.handlePopupKey(#selector(NSResponder.moveDown(_:))))
        #expect(view.handlePopupKey(#selector(NSResponder.insertTab(_:))))
        #expect(view.string == "See [[Important]]")
    }

    @Test func typingOnKeepsWhatWasTyped() {
        // Nothing's filled in while the list shows: what's typed is all there is.
        let view = typing("See [[2026-10-28", titles: ["2026-10-28 Weekly planning"])
        view.insertText(" W", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "See [[2026-10-28 W")
        #expect(view.popup != nil)
    }

    @Test func clickingASuggestionFinishesTheLink() {
        let view = typing("See [[2026-10", titles: ["2026-10-20 Budget review", "2026-10-28 Weekly planning"])
        view.popup?.model.pick(1)
        #expect(view.string == "See [[2026-10-28 Weekly planning]]")
    }

    @Test func escapeKeepsWhatWasTypedAndReturnIsANewLine() {
        let view = typing("See [[2026-10", titles: ["2026-10-28 Weekly planning"])
        #expect(view.handlePopupKey(#selector(NSResponder.cancelOperation(_:))))
        #expect(view.popup == nil)
        #expect(view.string == "See [[2026-10")
        #expect(!view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        // Typing on, it stays closed for that link.
        view.insertText("-2", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.popup == nil)
    }

    @Test func completionDoesntDoubleExistingBrackets() {
        let view = EditorTestSupport.makeEditor("See [[Imp]]", height: 300)
        view.completeNoteTitle = { _ in ["Imprint App"] }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "See [[Imprint App]]")
    }

    @Test func aTagIsFinishedWithASpace() {
        let view = EditorTestSupport.makeEditor("Filed #wo", height: 300)
        view.completeTag = { _ in ["work", "work/imprint"] }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(view.popup?.model.rows.map(\.title) == ["work", "work/imprint"])
        #expect(view.handlePopupKey(#selector(NSResponder.moveDown(_:))))
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "Filed #work/imprint ")
    }

    @Test func noTagPopupForAHashAloneOrInCode() {
        let heading = EditorTestSupport.makeEditor("#", height: 300)
        heading.completeTag = { _ in ["work"] }
        heading.window?.makeFirstResponder(heading)
        heading.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(heading.popup == nil)
        let code = EditorTestSupport.makeEditor("`#wo`", height: 300)
        code.completeTag = { _ in ["work"] }
        code.window?.makeFirstResponder(code)
        code.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(code.popup == nil)
    }
}

@MainActor
struct MentionTests {
    private func editor(_ text: String) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.completePerson = { typed in ["Sam Lee", "Samira Khan"].filter { $0.lowercased().contains(typed.lowercased()) } }
        view.setSelectionDirectly(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    @Test func knowsWhenANameIsTypedAfterAnAt() {
        #expect(editor("Met @Sa").mentionPartialRange() == NSRange(location: 5, length: 2))
        #expect(editor("@").mentionPartialRange() == NSRange(location: 1, length: 0))
        #expect(editor("(@Sa").mentionPartialRange() == NSRange(location: 2, length: 2))
    }

    @Test func notInAnEmailAddressOrCodeOrAfterASpace() {
        #expect(editor("me@exa").mentionPartialRange() == nil)
        #expect(editor("`@Sa").mentionPartialRange() == nil)
        #expect(editor("@Sam L").mentionPartialRange() == nil)
        let off = EditorTestSupport.makeEditor("Met @Sa", height: 300)
        off.setSelectionDirectly(NSRange(location: 7, length: 0))
        #expect(off.mentionPartialRange() == nil) // No people to suggest.
    }

    @Test func pickingAPersonWritesALink() {
        let view = editor("Met @sa today")
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(view.popup?.model.rows.map(\.title) == ["Sam Lee", "Samira Khan"])
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "Met [[Sam Lee]] today")
    }

    @Test func escapeKeepsTheAt() {
        let view = editor("Met @sa")
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(view.handlePopupKey(#selector(NSResponder.cancelOperation(_:))))
        #expect(view.string == "Met @sa")
    }
}
