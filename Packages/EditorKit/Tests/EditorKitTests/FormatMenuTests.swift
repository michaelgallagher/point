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

    /// Typed in the menu's own field.
    private func type(_ text: String, in view: MarkdownTextView) {
        view.popup?.model.filter = (view.popup?.model.filter ?? "") + text
    }

    /// Return in the field.
    private func choose(in view: MarkdownTextView) {
        guard let model = view.popup?.model else { return }
        model.pick(model.highlighted)
    }

    @Test func opensWithEveryCommand() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        #expect(view.popup?.model.rows.map(\.title) == FormatCommand.all.map(\.name))
        #expect(view.popup?.model.filter == "")
    }

    @Test func returnAppliesTheHighlightedStyle() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        choose(in: view)
        #expect(view.string == "Some **words** here")
        #expect(view.popup == nil)
    }

    @Test func typingNarrowsItAndLeavesTheTextAlone() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("str", in: view)
        #expect(view.string == "Some words here")
        #expect(view.selectedRange() == NSRange(location: 5, length: 5))
        #expect(view.popup?.model.rows.first?.title == "Strikethrough")
        view.popup?.model.move(by: 0)
        choose(in: view)
        #expect(view.string == "Some ~~words~~ here")
    }

    @Test func downChoosesAnother() {
        let view = opened("A line", selecting: NSRange(location: 0, length: 6))
        type("heading", in: view)
        view.popup?.model.move(by: 1)
        choose(in: view)
        #expect(view.string == "## A line")
    }

    @Test func findsByOtherNames() {
        let view = opened("A line", selecting: NSRange(location: 0, length: 6))
        type("h2", in: view)
        #expect(view.popup?.model.rows.map(\.title) == ["Heading 2"])
        choose(in: view)
        #expect(view.string == "## A line")
    }

    @Test func whatMatchesNothingLeavesNoRows() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("boz", in: view)
        #expect(view.popup?.model.rows.isEmpty == true)
        choose(in: view)
        #expect(view.string == "Some words here")
    }

    @Test func closingLeavesTheNoteAsItWas() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        type("it", in: view)
        view.popup?.model.close()
        #expect(view.popup == nil)
        #expect(view.string == "Some words here")
        #expect(view.selectedRange() == NSRange(location: 5, length: 5))
    }

    @Test func movingTheSelectionClosesIt() {
        let view = opened("Some words here", selecting: NSRange(location: 5, length: 5))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(view.popup == nil)
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
