import Foundation
import MarkdownKit
import Testing
@testable import EditorKit

/// Lists and headings inside a quote or callout: read as Obsidian reads them, and edited as
/// they are outside one, the quote's `> ` kept on each line.
struct QuotedBlocksTests {
    @Test func parsesListsAndHeadingsInAQuote() {
        let text = "> Plain\n> - Bullet\n>   - Nested\n> 1. Numbered\n> - [x] Done\n> ## Heading\n"
        let kinds = MarkdownParser.parse(text).map(\.kind)
        #expect(kinds.contains(.blockquote))
        #expect(kinds.contains(.listItem(.bullet, indent: 0)))
        #expect(kinds.contains(.listItem(.bullet, indent: 2)))
        #expect(kinds.contains(.listItem(.ordered(1), indent: 0)))
        #expect(kinds.contains(.listItem(.task(done: true), indent: 0)))
        #expect(kinds.contains(.heading(level: 2)))
    }

    @Test func aCalloutsTitleIsntAListItem() {
        let tokens = MarkdownParser.parse("> [!note] - Not a bullet\n> - A bullet\n")
        let items = tokens.filter { if case .listItem = $0.kind { true } else { false } }
        #expect(items.count == 1)
    }

    private func edited(_ text: String, cursorAfter marker: String, _ make: (MarkdownEditing) -> MarkdownEdit?) -> String? {
        let found = (text as NSString).range(of: marker)
        let editing = MarkdownEditing(text: text, selection: NSRange(location: NSMaxRange(found), length: 0))
        guard let edit = make(editing) else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func returnContinuesAQuotedList() {
        #expect(edited("> - One", cursorAfter: "One") { $0.newline() } == "> - One\n> - ")
        #expect(edited("> 1. One", cursorAfter: "One") { $0.newline() } == "> 1. One\n> 2. ")
        #expect(edited("> - [ ] One", cursorAfter: "One") { $0.newline() } == "> - [ ] One\n> - [ ] ")
    }

    @Test func returnOnAnEmptyQuotedItemEndsTheListNotTheQuote() {
        #expect(edited("> - One\n> - ", cursorAfter: "> - One\n> - ") { $0.newline() } == "> - One\n> ")
    }

    @Test func listCommandsKeepTheQuote() {
        #expect(edited("> Some text", cursorAfter: "Some") { $0.toggleBulletList() } == "> - Some text")
        #expect(edited("> - Some text", cursorAfter: "Some") { $0.toggleBulletList() } == "> Some text")
        #expect(edited("> Some text", cursorAfter: "Some") { $0.setHeading(2) } == "> ## Some text")
        #expect(edited("> - One", cursorAfter: "One") { $0.indent() } == "> \t- One")
    }

    @Test func highlightingAQuotedListKeepsItsMarkers() {
        let text = "> - One\n> - Two\n"
        let editing = MarkdownEditing(text: text, selection: NSRange(location: 0, length: (text as NSString).length))
        let edit = editing.toggleHighlight()
        #expect(edit.map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) } == "> - ==One==\n> - ==Two==\n")
    }
}
