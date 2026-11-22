import AppKit
import Testing
@testable import EditorKit

@MainActor
struct FormatMenuTests {
    /// An editor with `selection` selected, focused, and the formatting menu open.
    private func opened(_ text: String, selecting selection: NSRange) -> MarkdownTextView {
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(selection)
        view.showFormatMenu(nil)
        return view
    }

    private func type(_ text: String, in view: MarkdownTextView) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @Test func opensWithEveryCommand() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        #expect(view.popup?.model.rows.map(\.title) == FormatCommand.all.map(\.name))
        #expect(view.popup?.model.filter == "")
    }

    @Test func returnAppliesTheHighlightedStyle() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "Some **words** here")
        #expect(view.popup == nil)
    }

    @Test func typingNarrowsItAndLeavesTheTextAlone() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("str", in: view)
        #expect(view.string == "Some words here")
        #expect(view.selectedRange() == NSRange(location: 5, length: 5))
        #expect(view.popup?.model.rows.first?.title == "Strikethrough")
        #expect(view.popup?.model.filter == "str")
        #expect(view.handlePopupKey(#selector(NSResponder.insertTab(_:))))
        #expect(view.string == "Some ~~words~~ here")
    }

    @Test func findsByOtherNames() {
        let view = opened("A line", selecting: NSRange(location: 0, length: 6))
        type("h2", in: view)
        #expect(view.popup?.model.rows.map(\.title) == ["Heading 2"])
        #expect(view.handlePopupKey(#selector(NSResponder.insertNewline(_:))))
        #expect(view.string == "## A line")
    }

    @Test func typingWhatMatchesNothingIsIgnored() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("bo", in: view)
        type("z", in: view)
        #expect(view.popup?.model.filter == "bo")
        #expect(view.string == "Some words here")
    }

    @Test func deleteTakesBackWhatWasTypedThenCloses() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("it", in: view)
        #expect(view.handlePopupKey(#selector(NSResponder.deleteBackward(_:))))
        #expect(view.popup?.model.filter == "i")
        #expect(view.handlePopupKey(#selector(NSResponder.deleteBackward(_:))))
        #expect(view.handlePopupKey(#selector(NSResponder.deleteBackward(_:))))
        #expect(view.popup == nil)
        #expect(view.string == "Some words here")
    }

    @Test func escapeOrMovingTheSelectionClosesIt() {
        let escaped = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        #expect(escaped.handlePopupKey(#selector(NSResponder.cancelOperation(_:))))
        #expect(escaped.popup == nil)
        let moved = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        moved.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(moved.popup == nil)
    }

    @Test func showsShortcuts() {
        let view = EditorTestSupport.makeEditor("Words", height: 300)
        view.formatShortcut = { $0 == #selector(MarkdownTextView.toggleBold(_:)) ? "⌘B" : nil }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        view.showFormatMenu(nil)
        #expect(view.popup?.model.rows.first?.detail == "⌘B")
        #expect(view.popup?.model.rows.dropFirst().allSatisfy { $0.detail == nil } == true)
    }
}
