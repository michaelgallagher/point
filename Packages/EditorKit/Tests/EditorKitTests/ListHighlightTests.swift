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

    /// ⌘-clicking a bullet or a checkbox offers the colours.
    @Test func bulletsAndCheckboxesOfferTheColours() throws {
        let view = editor("- bullet\n- [ ] ? task\n1. numbered\nText")
        let bullet = try #require(view.markerTarget(onLineAt: 0))
        let item = try #require(view.listItemMarked(at: NSPoint(x: bullet.midX, y: bullet.midY)))
        #expect(item.item.location == 0)
        let checkbox = try #require(view.markerTarget(onLineAt: 9))
        let task = try #require(view.listItemMarked(at: NSPoint(x: checkbox.midX, y: checkbox.midY)))
        #expect(task.item.location == 9)
        // Numbered items and plain text have no marker to click.
        #expect(view.markerTarget(onLineAt: 22) == nil)
        #expect(view.markerTarget(onLineAt: 34) == nil)
        // Beside a marker, in the item's text, isn't on it.
        #expect(view.listItemMarked(at: NSPoint(x: checkbox.maxX + 40, y: checkbox.midY)) == nil)

        // The task's own colour is ticked, with No Highlight to take it off.
        let menu = try #require(view.highlightMenu(item: task.item, marker: task.marker))
        #expect(menu.items.map(\.title) == ["Red", "Orange", "", "No Highlight"])
        #expect(menu.items[1].state == .on)
        view.setListHighlight("!", item: task.item, marker: task.marker)
        #expect(view.string == "- bullet\n- [ ] ! task\n1. numbered\nText")
    }

    /// The Format menu's commands (⌘⇧1, ⌘⇧2…): every list item the selection touches, of any
    /// kind, by the colour's name; one undo puts them all back.
    @Test func theHighlightCommandColoursTheSelectedItems() {
        let view = EditorTestSupport.makeEditor("Intro\n- one\n- [ ] two\n1. three\nAfter", height: 300)
        view.listHighlights = [("!", NSColor(srgbRed: 1, green: 23 / 255, blue: 68 / 255, alpha: 1)),
                               ("?", NSColor(srgbRed: 1, green: 145 / 255, blue: 0, alpha: 1))]
        let text = view.string as NSString
        view.setSelectedRange(NSRange(location: 0, length: text.range(of: "three").location))
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: "Orange"))
        #expect(view.string == "Intro\n- ? one\n- [ ] ? two\n1. ? three\nAfter")
        // One edit, so one undo. (In a test, successive commands are one undo group, so
        // this undoes only the first.)
        view.undoManager?.undo()
        #expect(view.string == "Intro\n- one\n- [ ] two\n1. three\nAfter")
        view.setSelectedRange(NSRange(location: 0, length: text.range(of: "three").location))
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: "Orange"))
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: "Red"))
        #expect(view.string == "Intro\n- ! one\n- [ ] ! two\n1. ! three\nAfter")
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: nil))
        #expect(view.string == "Intro\n- one\n- [ ] two\n1. three\nAfter")
    }

    @Test func theHighlightCommandLeavesOtherLinesAlone() {
        let view = EditorTestSupport.makeEditor("Just a paragraph\n- one", height: 300)
        view.listHighlights = [("!", NSColor(srgbRed: 1, green: 23 / 255, blue: 68 / 255, alpha: 1))]
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: "Red"))
        #expect(view.string == "Just a paragraph\n- one")
        // A colour no highlight has: nothing changes.
        view.setSelectedRange(NSRange(location: 20, length: 0))
        view.highlightListItems(MarkdownTextView.ListHighlightRequest(colour: "Purple"))
        #expect(view.string == "Just a paragraph\n- one")
    }

    @Test func coloursHavePlainNames() {
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 1, green: 23 / 255, blue: 68 / 255, alpha: 1)) == "Red")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 0, green: 200 / 255, blue: 83 / 255, alpha: 1)) == "Green")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 158 / 255, green: 158 / 255, blue: 158 / 255, alpha: 1)) == "Grey")
        #expect(MarkdownTextView.colourName(NSColor(srgbRed: 163 / 255, green: 123 / 255, blue: 123 / 255, alpha: 1)) == "Brown")
    }
}
