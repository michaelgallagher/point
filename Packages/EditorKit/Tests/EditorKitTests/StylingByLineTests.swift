import Foundation
import Testing
@testable import EditorKit

/// A style put on a selection across lines, or over a line's markers, goes on each line's text
/// separately, so the Markdown stays valid: a pair of markers can't span lines or take in a bullet.
struct StylingByLineTests {
    private func edited(_ text: String, selecting selected: String, _ toggle: (MarkdownEditing) -> MarkdownEdit?) -> String? {
        let range = (text as NSString).range(of: selected)
        let editing = MarkdownEditing(text: text, selection: range)
        guard let edit = toggle(editing) else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func highlightingAListAndParagraphs() {
        let text = "Intro line here.\n\n- First item\n- [ ] Second item\n  - Nested item\n\n> Quoted text\n\n## A heading\n"
        let result = edited(text, selecting: "line here.\n\n- First item\n- [ ] Second item\n  - Nested item\n\n> Quoted text\n\n## A heading") { $0.toggleHighlight() }
        #expect(result == "Intro ==line here.==\n\n- ==First item==\n- [ ] ==Second item==\n  - ==Nested item==\n\n> ==Quoted text==\n\n## ==A heading==\n")
    }

    @Test func boldingATripleClickedListItemKeepsTheBullet() {
        let text = "- One\n  - Two point five\n- Three\n"
        // A triple-click takes in the whole line, marker, indent and line break.
        #expect(edited(text, selecting: "  - Two point five\n") { $0.toggleBold() } == "- One\n  - **Two point five**\n- Three\n")
        #expect(edited(text, selecting: "- One\n") { $0.toggleItalic() } == "- *One*\n  - Two point five\n- Three\n")
        #expect(edited(text, selecting: "- One\n") { $0.toggleStrikethrough() } == "- ~~One~~\n  - Two point five\n- Three\n")
    }

    @Test func aStyleOnEveryLineComesOff() {
        let text = "- **One**\n- **Two**\n"
        #expect(edited(text, selecting: "- **One**\n- **Two**") { $0.toggleBold() } == "- One\n- Two\n")
    }

    @Test func partlyStyledLinesAreStyledWhole() {
        let text = "Some **bold** words\nMore words\n"
        #expect(edited(text, selecting: "Some **bold** words\nMore words") { $0.toggleBold() } == "**Some bold words**\n**More words**\n")
    }

    @Test func blankLinesAndCodeAreLeftAlone() {
        let text = "One\n\n```\ncode\n```\nTwo\n"
        #expect(edited(text, selecting: text.trimmingCharacters(in: .newlines)) { $0.toggleItalic() } == "*One*\n\n```\ncode\n```\n*Two*\n")
    }

    @Test func withinOneLineItsAsBefore() {
        #expect(edited("Some words here", selecting: "words") { $0.toggleBold() } == "Some **words** here")
        #expect(edited("- An item", selecting: "item") { $0.toggleHighlight() } == "- An ==item==")
    }
}
