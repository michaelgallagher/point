import AppKit
import Testing
@testable import EditorKit

/// List items highlighted by a character at their start (`- ! text`), as the List Callouts
/// plugin for Obsidian does.
@MainActor
struct ListHighlightTests {
    private func editor(_ text: String) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.listHighlights = [("!", .systemRed), ("?", .systemOrange)]
        return view
    }

    @Test func theCharacterIsHiddenAndTheItemColoured() {
        let view = editor("- ! Important\n- plain\n- !not one")
        #expect(view.isHidden(2) && view.isHidden(3)) // "! "
        #expect(!view.isHidden(4))
        #expect(view.textStorage?.attribute(.pointListHighlight, at: 4, effectiveRange: nil) as? NSColor == .systemRed)
        #expect(view.textStorage?.attribute(.pointListHighlight, at: 16, effectiveRange: nil) == nil)
        // Without a space after it, it's just text.
        #expect(!view.isHidden(24))
    }

    @Test func choosingAColourWritesItsCharacter() throws {
        let view = editor("- one\n- ? two")
        let first = try #require(view.tokens.first { $0.range.location == 0 })
        view.setListHighlight("!", item: first.range, marker: first.syntax[0])
        #expect(view.string == "- ! one\n- ? two")
        let second = try #require(view.tokens.first { $0.range.location == 8 })
        view.setListHighlight("!", item: second.range, marker: second.syntax[0])
        #expect(view.string == "- ! one\n- ! two")
        let again = try #require(view.tokens.first { $0.range.location == 8 })
        view.setListHighlight(nil, item: again.range, marker: again.syntax[0])
        #expect(view.string == "- ! one\n- two")
    }

    @Test func coloursHavePlainNames() {
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 1, green: 23 / 255, blue: 68 / 255, alpha: 1)) == "Red")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 0, green: 200 / 255, blue: 83 / 255, alpha: 1)) == "Green")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 158 / 255, green: 158 / 255, blue: 158 / 255, alpha: 1)) == "Grey")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 163 / 255, green: 123 / 255, blue: 123 / 255, alpha: 1)) == "Brown")
    }
}
