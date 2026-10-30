import AppKit
import Testing
@testable import EditorKit

/// The iPhone's formatting commands against the Mac's: from the same text and selection, each
/// must leave the same text and selection as `MarkdownTextView` does.
@MainActor
struct MarkdownEditingTests {
    /// A command, as each editor has it.
    struct Command: CustomTestStringConvertible, Sendable {
        let name: String
        let mac: @MainActor @Sendable (MarkdownTextView) -> Void
        let phone: @Sendable (MarkdownEditing) -> MarkdownEdit?
        var testDescription: String { name }
    }

    nonisolated static let commands = [
        Command(name: "bold", mac: { $0.toggleBold(nil) }, phone: { $0.toggleBold() }),
        Command(name: "italic", mac: { $0.toggleItalic(nil) }, phone: { $0.toggleItalic() }),
        Command(name: "highlight", mac: { $0.toggleHighlight(nil) }, phone: { $0.toggleHighlight() }),
        Command(name: "strikethrough", mac: { $0.toggleStrikethrough(nil) }, phone: { $0.toggleStrikethrough() }),
        Command(name: "code", mac: { $0.toggleCode(nil) }, phone: { $0.toggleCode() }),
        Command(name: "body", mac: { $0.makeBodyText(nil) }, phone: { $0.setHeading(0) }),
        Command(name: "h1", mac: { $0.makeHeading1(nil) }, phone: { $0.setHeading(1) }),
        Command(name: "h2", mac: { $0.makeHeading2(nil) }, phone: { $0.setHeading(2) }),
        Command(name: "quote", mac: { $0.toggleBlockQuote(nil) }, phone: { $0.toggleBlockQuote() }),
        Command(name: "bullets", mac: { $0.toggleBulletList(nil) }, phone: { $0.toggleBulletList() }),
        Command(name: "checklist", mac: { $0.toggleChecklist(nil) }, phone: { $0.toggleChecklist() }),
        Command(name: "indent", mac: { $0.indentLines(nil) }, phone: { $0.indent() }),
        Command(name: "outdent", mac: { $0.outdentLines(nil) }, phone: { $0.outdent() }),
        Command(name: "return", mac: { $0.insertNewline(nil) }, phone: { $0.newline() }),
    ]

    /// Notes to try each command on, with the selection as `|` (a cursor) or `|…|` (a range).
    static let cases = [
        "|",
        "plain wo|rd here",
        "plain |word| here",
        "plain| |here",
        "**bo|ld** text",
        "*it|alic* and **bold**",
        "==high|light==",
        "`co|de`",
        "# Hea|ding",
        "## Hea|ding",
        "- a bul|let",
        "* a bul|let",
        "\t- nes|ted",
        "    - nes|ted",
        "- [ ] a ta|sk",
        "- [x] do|ne",
        "1. fir|st",
        "9) nin|th",
        "- |",
        "\t- |",
        "- [ ] |",
        "1. |",
        "> quo|ted",
        "> first\n> |",
        "> [!note] A call|out\n> text",
        "|one\ntwo\nthree|",
        "- one|\n- two\n- three|",
        "- one\n- tw|o\nafter",
        "---\ntitle: x\n---\nBody te|xt",
    ]

    /// `marked` without its bars, and the selection they mark.
    static func parse(_ marked: String) -> (String, NSRange) {
        let parts = marked.components(separatedBy: "|")
        let start = (parts[0] as NSString).length
        let length = parts.count == 3 ? (parts[1] as NSString).length : 0
        return (parts.joined(), NSRange(location: start, length: length))
    }

    @Test(arguments: commands)
    func matchesTheMac(command: Command) {
        for marked in Self.cases {
            let (text, selection) = Self.parse(marked)
            let view = EditorTestSupport.makeEditor(text, height: 300)
            view.setSelectionDirectly(selection)
            command.mac(view)

            let edit = command.phone(MarkdownEditing(text: text, selection: selection))
            var phoneText = text
            var phoneSelection = selection
            if let edit {
                phoneText = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                phoneSelection = edit.selection
            } else if command.name == "return" {
                // An ordinary line break, which the text view makes itself.
                phoneText = (text as NSString).replacingCharacters(in: selection, with: "\n")
                phoneSelection = NSRange(location: selection.location + 1, length: 0)
            }
            #expect(phoneText == view.string, "\(command.name) on \(marked.debugDescription)")
            #expect(phoneSelection == view.selectedRange(), "\(command.name) on \(marked.debugDescription)")
        }
    }

    @Test func wikiLinks() {
        let empty = MarkdownEditing(text: "a ", selection: NSRange(location: 2, length: 0)).wikiLink()
        #expect(empty == MarkdownEdit(range: NSRange(location: 2, length: 0), replacement: "[[]]", selection: NSRange(location: 4, length: 0)))
        let word = MarkdownEditing(text: "a note", selection: NSRange(location: 2, length: 4)).wikiLink()
        #expect(word == MarkdownEdit(range: NSRange(location: 2, length: 4), replacement: "[[note]]", selection: NSRange(location: 10, length: 0)))
    }
}
