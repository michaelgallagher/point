import Foundation
import MarkdownKit
import Testing
@testable import EditorKit

@MainActor
struct SlashMenuTests {
    /// The query at the `|` in `marked`.
    func query(_ marked: String) -> SlashQuery? {
        let (text, selection) = MarkdownEditingTests.parse(marked)
        return SlashMenu.query(in: text, tokens: MarkdownParser.parse(text), at: selection.location)
    }

    @Test func opensAtALinesStartOrAfterASpace() {
        #expect(query("/|")?.typed == "")
        #expect(query("/li|")?.typed == "li")
        #expect(query("some text /h2|")?.typed == "h2")
        #expect(query("- /ta|")?.typed == "ta")
        #expect(query("/callout w|")?.typed == "callout w")
        #expect(query("/li|")?.range == NSRange(location: 0, length: 3))
    }

    @Test func neverInAWordLinkCodeOrProperties() {
        #expect(query("and/or|") == nil)
        #expect(query("1/2|") == nil)
        #expect(query("see https://example.com/pa|") == nil)
        #expect(query("`a /co|`") == nil)
        #expect(query("```\n/co|\n```") == nil)
        #expect(query("---\ntitle: /a|\n---\n") == nil)
        #expect(query("[[a /b|]]") == nil)
        #expect(query("| a | b |\n| - | - |\n| /c| | d |") == nil)
        #expect(query("/ li|") == nil)
        #expect(query("plain|") == nil)
        #expect(query("/" + String(repeating: "a", count: 40) + "|") == nil)
    }

    @Test func narrows() {
        let names = { (typed: String) in SlashMenu.matching(SlashCommand.all, typed: typed).map(\.name) }
        #expect(names("").count == SlashCommand.all.count)
        #expect(names("").first == "List")
        #expect(names("li").first == "List")
        #expect(names("h2").first == "Heading 2")
        #expect(names("rule") == ["Divider"])
        #expect(names("date").first == "Today's date")
        #expect(names("tod").contains("Today's note"))
        #expect(names("num") == ["Numbered list"])
        #expect(names("zzz").isEmpty)
        // A command's choices, after its name and a space.
        #expect(names("callout w") == ["Warning"])
        #expect(names("code block sw") == ["Swift"])
        #expect(names("callout ").count == SlashCommand.all.first { $0.id == .callout }!.choices.count)
    }

    func written(_ marked: String, _ id: SlashCommand.ID, choice: String? = nil) -> String {
        let (text, selection) = MarkdownEditingTests.parse(marked)
        var command = SlashCommand.all.first { $0.id == id }!
        if let choice { command = command.choosing(choice) }
        guard let edit = MarkdownEditing(text: text, selection: selection).slashEdit(command) else { return "none" }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        return result.replacingCharacters(in: edit.selection, with: "|")
    }

    @Test func writesBlocksOnLinesOfTheirOwn() {
        #expect(written("|", .divider) == "---\n|")
        #expect(written("text\n|", .divider) == "text\n\n---\n|")
        #expect(written("|\nafter", .divider) == "---\n|\nafter")
        #expect(written("some |text", .divider) == "some text\n\n---\n|")
        #expect(written("|", .codeBlock) == "```|\n\n```")
        #expect(written("|", .codeBlock, choice: "swift") == "```swift\n|\n```")
        #expect(written("|", .codeBlock, choice: "none") == "```\n|\n```")
        #expect(written("|", .callout, choice: "warning") == "> [!warning] |")
        #expect(written("|", .table).hasPrefix("| | | Column 2 |"))
        #expect(written("a |", .linkToNote) == "a [[|]]")
        #expect(written("a |", .embedNote) == "a ![[|]]")
        #expect(written("|", .heading2) == "## |")
        #expect(written("|", .list) == "none")
    }

    @Test func returnAfterTheLanguageGoesInside() {
        let text = "```swift\n\n```"
        let edit = MarkdownEditing(text: text, selection: NSRange(location: 8, length: 0)).newline()
        #expect(edit == MarkdownEdit(range: NSRange(location: 8, length: 0), replacement: "", selection: NSRange(location: 9, length: 0)))
    }
}

/// The slash menu in the Mac's editor: a command chosen takes the `/` and what was typed after
/// it, and one undo gives them back.
@MainActor
struct MacSlashMenuTests {
    @Test func oneUndoGivesBackTheSlash() {
        let textView = EditorTestSupport.makeEditor("Some text\n\n")
        let window = textView.window // The undo manager is the window's.
        textView.slashCommands = SlashCommand.all
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        // Typed in key presses of their own, as the event loop would group them.
        let undo = textView.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        textView.insertText("/div", replacementRange: textView.selectedRange())
        undo.endUndoGrouping()
        textView.runSlashCommand(SlashCommand.all.first { $0.id == .divider }!)
        #expect(textView.string == "Some text\n\n---\n")
        textView.undoManager?.undo()
        #expect(textView.string == "Some text\n\n/div", "\(textView.string.debugDescription)")
        _ = window
    }

    @Test func aCommandWithChoicesOffersThemFirst() {
        let textView = EditorTestSupport.makeEditor("")
        let window = textView.window
        textView.slashCommands = SlashCommand.all
        textView.insertText("/call", replacementRange: textView.selectedRange())
        textView.runSlashCommand(SlashCommand.all.first { $0.id == .callout }!)
        #expect(textView.string == "/callout ")
        let warning = SlashMenu.matching(SlashCommand.all, typed: "callout w")[0]
        textView.runSlashCommand(warning)
        #expect(textView.string == "> [!warning] ")
        _ = window
    }
}
