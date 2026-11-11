import Foundation
import Testing
@testable import EditorKit

struct HighlightingTests {
    /// The text after highlighting the part of `text` between `«` and `»` (which are taken out).
    func highlighted(_ marked: String, skipping: String? = nil) -> String? {
        let (text, selection) = Self.unmark(marked)
        guard let edit = MarkdownEditing(text: text, selection: selection).highlightingSelection(skipping: skipping) else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    static func unmark(_ marked: String) -> (String, NSRange) {
        let ns = marked as NSString
        let open = ns.range(of: "«").location, close = ns.range(of: "»").location
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return (text, NSRange(location: open, length: close - open - 1))
    }

    @Test func aFewWords() {
        #expect(highlighted("Some «quiet words» here.\n") == "Some ==quiet words== here.\n")
    }

    @Test func spacesAtTheEdgesAreLeftOut() {
        #expect(highlighted("Some« quiet words »here.\n") == "Some ==quiet words== here.\n")
    }

    @Test func acrossParagraphsOneEach() {
        #expect(highlighted("First «para.\n\nSecond» para.\n") == "First ==para.==\n\n==Second== para.\n")
    }

    @Test func outsideQuoteListAndHeadingMarkers() {
        #expect(highlighted("«> A quote\n> goes on\n- An item\n- [ ] A task\n## A heading»\n")
                == "> ==A quote==\n> ==goes on==\n- ==An item==\n- [ ] ==A task==\n## ==A heading==\n")
    }

    @Test func partlyBoldTakesInTheWholeSpan() {
        #expect(highlighted("Some **bo«ld** and» more.\n") == "Some ==**bold** and== more.\n")
    }

    @Test func partlyALinkTakesInTheWholeLink() {
        let markdown = "See [the](https://e.x) link.\n"
        // Selected from inside the link's text to after it.
        let ns = markdown as NSString
        let selection = NSRange(location: ns.range(of: "he](").location, length: ns.range(of: " link").location + 5 - ns.range(of: "he](").location)
        let edit = MarkdownEditing(text: markdown, selection: selection).highlightingSelection()!
        #expect(ns.replacingCharacters(in: edit.range, with: edit.replacement) == "See ==[the](https://e.x) link==.\n")
    }

    @Test func joinsHighlightsItOverlapsOrTouches() {
        #expect(highlighted("One ==two «three== four» five.\n") == "One ==two three four== five.\n")
        #expect(highlighted("One ==two==« three» four.\n") == "One ==two three== four.\n")
        #expect(highlighted("«One ==two== three»\n") == "==One two three==\n")
    }

    @Test func alreadyHighlightedChangesNothing() {
        #expect(highlighted("One ==«two»== three.\n") == nil)
    }

    @Test func codeBlocksAndTheMarkerAreLeftAlone() {
        #expect(highlighted("«Text\n\n```\ncode\n```\n\nMore»\n") == "==Text==\n\n```\ncode\n```\n\n==More==\n")
        #expect(highlighted("«Notes\n\n==---- Text ----==\n\nArticle»\n", skipping: "==---- Text ----==")
                == "==Notes==\n\n==---- Text ----==\n\n==Article==\n")
    }

    @Test func removingTakesOffEveryHighlightTouched() {
        let (text, selection) = Self.unmark("One ==t«wo== and ==thr»ee== and ==four==.\n")
        let edit = MarkdownEditing(text: text, selection: selection).removingHighlights()!
        #expect((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) == "One two and three and ==four==.\n")
        // A cursor inside one.
        let cursor = MarkdownEditing(text: "A ==b c== d\n", selection: NSRange(location: 5, length: 0)).removingHighlights()!
        #expect(("A ==b c== d\n" as NSString).replacingCharacters(in: cursor.range, with: cursor.replacement) == "A b c d\n")
    }

    @Test func quotingKeepsMarkdownWholeAndParagraphsApart() {
        let (text, selection) = Self.unmark("Some **bo«ld** and ==lit==\nnext line.\n\nNew para» here.\n")
        #expect(MarkdownEditing(text: text, selection: selection).quotableSelection() == "**bold** and lit\nnext line.\n\nNew para")
    }

    @Test func listsTheHighlights() {
        let text = "==Notes hl==\n\n==---- Text ----==\n\nAn ==important== bit and ==another one==.\n"
        let found = MarkdownEditing.highlights(in: text, skipping: "==---- Text ----==")
        #expect(found.map(\.text) == ["Notes hl", "important", "another one"])
        let start = (text as NSString).range(of: "An ").location
        #expect(MarkdownEditing.highlights(in: text, from: start).map(\.text) == ["important", "another one"])
    }

    // From the audit of a vault's clips (plan/reader-mode.md).

    @Test func anEdgeWhereTheMarkersWouldBeTextGoesToTheWordsEdge() {
        // `don==’t`, `,==` before a word: not read as highlights, so out to the word's edge.
        #expect(highlighted("I don«’t know, but» more.\n") == "I ==don’t know, but== more.\n")
        #expect(highlighted("Some groups«—some» left.\n") == "Some ==groups—some== left.\n")
        #expect(highlighted("Words«, then more» here.\n") == "==Words, then more== here.\n")
        // Within a word, between letters, it's read: left as chosen.
        #expect(highlighted("The I«DEO site» here.\n") == "The I==DEO site== here.\n")
    }

    @Test func anEmojiIsntSplit() {
        #expect(highlighted("«🛡️ Governance»\n") == "==🛡️ Governance==\n")
        #expect(highlighted("«Rules 🏳️‍⚧️»\n") == "==Rules 🏳️‍⚧️==\n")
    }

    @Test func aBareLinkAtTheEndIsLeftOut() {
        #expect(highlighted("«See this video: https://e.x/v»\n") == "==See this video:== https://e.x/v\n")
        #expect(highlighted("«https://e.x/v»\n") == nil)
        #expect(highlighted("«https://e.x/v and more»\n") == "==https://e.x/v and more==\n")
    }

    @Test func aParagraphSeparatorIsntALineBreak() {
        // U+2029 at a line's end, as some clipped pages have: Markdown reads it as text, so
        // the closing marker goes after it, where it's read.
        #expect(highlighted("- «What are we after?\u{2029}\n- Why» now\n") == "- ==What are we after?\u{2029}==\n- ==Why== now\n")
    }

    @Test func equalsSignsAtTheEdgesAreLeftOut() {
        #expect(highlighted("Perfectly OK «= where you started» from\n") == "Perfectly OK = ==where you started== from\n")
        #expect(highlighted("One\n\n«==»\n\nTwo\n") == nil)
    }

    @Test func aFootnotesLabelStaysOutside() {
        #expect(highlighted("«[^4]: A source.»\n") == "[^4]: ==A source.==\n")
    }
}
