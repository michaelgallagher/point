import AppKit
import EditorKit
import SwiftUI

/// The Format menu. Each item sends its command to the editor that has focus.
struct FormatCommands: Commands {
    /// The front window, which Add Property applies to.
    @FocusedObject private var model: VaultModel?

    var body: some Commands {
        CommandMenu("Format") {
            item("Bold", #selector(MarkdownTextView.toggleBold(_:)), "b")
            item("Italic", #selector(MarkdownTextView.toggleItalic(_:)), "i")
            item("Highlight", #selector(MarkdownTextView.toggleHighlight(_:)), "u")
            item("Strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift])
            Divider()
            item("Body Text", #selector(MarkdownTextView.makeBodyText(_:)), "0")
            item("Heading 1", #selector(MarkdownTextView.makeHeading1(_:)), "1")
            item("Heading 2", #selector(MarkdownTextView.makeHeading2(_:)), "2")
            item("Heading 3", #selector(MarkdownTextView.makeHeading3(_:)), "3")
            item("Heading 4", #selector(MarkdownTextView.makeHeading4(_:)), "4")
            item("Heading 5", #selector(MarkdownTextView.makeHeading5(_:)), "5")
            item("Heading 6", #selector(MarkdownTextView.makeHeading6(_:)), "6")
            Divider()
            item("Bulleted List", #selector(MarkdownTextView.toggleBulletList(_:)), "l")
            item("Checklist", #selector(MarkdownTextView.toggleChecklist(_:)), "l", [.command, .shift])
            // ⌘← and ⌘→ stay as the system's start and end of line.
            item("Indent", #selector(MarkdownTextView.indentLines(_:)), .rightArrow, [.command, .option])
            item("Outdent", #selector(MarkdownTextView.outdentLines(_:)), .leftArrow, [.command, .option])
            item("Move Line Up", #selector(MarkdownTextView.moveLinesUp(_:)), .upArrow, [.command, .option])
            item("Move Line Down", #selector(MarkdownTextView.moveLinesDown(_:)), .downArrow, [.command, .option])
            Divider()
            item("Add Link…", #selector(MarkdownTextView.addLink(_:)), "k")
            Button("Add Property…") { NotificationCenter.default.post(name: .imprintAddProperty, object: model) }
                .disabled(model?.selectedNote == nil)
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: KeyEquivalent, _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: modifiers)
    }
}
