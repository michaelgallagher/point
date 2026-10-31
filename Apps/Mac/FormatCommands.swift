import AppKit
import EditorKit
import SwiftUI

/// The Format menu. Each item sends its command to the editor that has focus.
struct FormatCommands: Commands {
    /// The front window, which Add Property applies to.
    @FocusedObject private var model: VaultModel?
    /// Each command's shortcut, as set in Settings (or its default).
    @ObservedObject private var shortcuts = ShortcutStore.shared

    var body: some Commands {
        CommandMenu("Format") {
            item(.bold, #selector(MarkdownTextView.toggleBold(_:)))
            item(.italic, #selector(MarkdownTextView.toggleItalic(_:)))
            item(.highlight, #selector(MarkdownTextView.toggleHighlight(_:)))
            item(.strikethrough, #selector(MarkdownTextView.toggleStrikethrough(_:)))
            item(.inlineCode, #selector(MarkdownTextView.toggleCode(_:)))
            Divider()
            item(.bodyText, #selector(MarkdownTextView.makeBodyText(_:)))
            item(.heading1, #selector(MarkdownTextView.makeHeading1(_:)))
            item(.heading2, #selector(MarkdownTextView.makeHeading2(_:)))
            item(.heading3, #selector(MarkdownTextView.makeHeading3(_:)))
            item(.heading4, #selector(MarkdownTextView.makeHeading4(_:)))
            item(.heading5, #selector(MarkdownTextView.makeHeading5(_:)))
            item(.heading6, #selector(MarkdownTextView.makeHeading6(_:)))
            Divider()
            item(.bulletList, #selector(MarkdownTextView.toggleBulletList(_:)))
            item(.checklist, #selector(MarkdownTextView.toggleChecklist(_:)))
            item(.blockQuote, #selector(MarkdownTextView.toggleBlockQuote(_:)))
            item(.indent, #selector(MarkdownTextView.indentLines(_:)))
            item(.outdent, #selector(MarkdownTextView.outdentLines(_:)))
            item(.moveLineUp, #selector(MarkdownTextView.moveLinesUp(_:)))
            item(.moveLineDown, #selector(MarkdownTextView.moveLinesDown(_:)))
            item(.fold, #selector(MarkdownTextView.foldLine(_:)))
            item(.unfold, #selector(MarkdownTextView.unfoldLine(_:)))
            // The list item's colour, as the List Callouts plugin for Obsidian marks it (a
            // character at its start). The colours are the vault's own, named by their hue.
            Menu("Highlight List Item") {
                ForEach(ShortcutAction.allCases.filter { $0.menu == "Highlight List Item" }) { action in
                    if action == .removeHighlight { Divider() }
                    Button(action.title) {
                        NSApp.sendAction(#selector(MarkdownTextView.highlightListItems(_:)), to: nil,
                                         from: MarkdownTextView.ListHighlightRequest(colour: action.highlightColour))
                    }
                    .shortcut(action, in: shortcuts)
                }
            }
            Divider()
            // More cursors (⌥-click adds one too; Escape goes back to one).
            item(.addCursorAbove, #selector(MarkdownTextView.addCursorAbove(_:)))
            item(.addCursorBelow, #selector(MarkdownTextView.addCursorBelow(_:)))
            item(.addNextMatch, #selector(MarkdownTextView.addNextMatch(_:)))
            Divider()
            item(.addLink, #selector(MarkdownTextView.addLink(_:)))
            Button("Add Property…") { NotificationCenter.default.post(name: .pointAddProperty, object: model) }
                .shortcut(.addProperty, in: shortcuts)
                .disabled(model?.selectedNote == nil)
        }
    }

    private func item(_ action: ShortcutAction, _ selector: Selector) -> some View {
        Button(action.title) { NSApp.sendAction(selector, to: nil, from: nil) }
            .shortcut(action, in: shortcuts)
    }
}
