import SwiftUI

/// ⌘/: every keyboard shortcut, grouped, on one page.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shortcuts = ShortcutStore.shared

    /// What a row's keys are: commands, shown with their shortcuts as set in Settings (the row
    /// is left out if none has one), or keys that aren't a menu command.
    private enum Keys {
        case commands([ShortcutAction])
        case fixed(String)
    }

    /// A group of shortcuts: its name and (keys, what they do).
    private static let groups: [(String, [(Keys, String)])] = [
        ("Notes", [
            (.commands([.newNote]), "New note"),
            (.commands([.applyTemplate]), "Insert template"),
            (.commands([.newFolder]), "New folder"),
            (.commands([.showInFinder]), "Show in Finder"),
        ]),
        ("Finding", [
            (.commands([.explorer]), "Explorer: search or use commands (type a new name and press Return to make that note)"),
            (.commands([.searchVault]), "Search vault: folders and tags in two columns"),
            (.commands([.searchInList]), "Search in the sidebar's list"),
            (.commands([.findInNote]), "Find in note"),
            (.commands([.back, .forward]), "Back, forward"),
            (.commands([.enclosingFolder]), "Enclosing folder"),
        ]),
        ("Tabs and sides", [
            (.commands([.newTab]), "New tab"),
            (.commands([.newTabOnOtherSide]), "New tab on the other side"),
            (.commands([.closeTab]), "Close tab"),
            (.commands([.previousTab, .nextTab]), "Previous, next tab"),
            (.commands([.switchToTab]), "Switch to a tab (in the palette)"),
            (.commands([.tabList]), "Show this side's tab list"),
            (.commands([.split]), "Split, or merge both sides into tabs"),
            (.commands([.newWindow]), "New window"),
            (.fixed("⌘-click a link"), "Open it in a new tab"),
            (.fixed("⌥⌘-click a link"), "Open it on the other side"),
        ]),
        ("Window", [
            (.commands([.toggleNoteList]), "Show or hide the sidebar"),
            (.commands([.focus]), "Focus"),
            (.commands([.showMarkdown]), "Show Markdown"),
            (.commands([.biggerText, .smallerText]), "Bigger, smaller text"),
            (.commands([.reloadNotes]), "Reload notes"),
            (.commands([.keyboardShortcuts]), "This list"),
        ]),
        ("Formatting", [
            (.commands([.bold, .italic, .highlight]), "Bold, italic, highlight"),
            (.commands([.strikethrough]), "Strikethrough"),
            (.commands([.inlineCode]), "Inline code"),
            (.commands([.blockQuote]), "Block quote"),
            (.commands([.bodyText, .heading1, .heading6]), "Body text, headings 1 to 6"),
            (.commands([.bulletList]), "Bulleted list"),
            (.commands([.checklist]), "Checklist"),
            (.commands([.highlightOrange, .highlightRed]), "Highlight a list item orange, red (the rest under Format › Highlight List Item)"),
            (.commands([.addLink]), "Add link"),
        ]),
        ("Editing", [
            (.commands([.indent, .outdent]), "Indent, outdent"),
            (.commands([.moveLineUp, .moveLineDown]), "Move line up, down"),
            (.commands([.fold, .unfold]), "Fold, unfold the list item or heading"),
            (.fixed("⌘X"), "With nothing selected: cut the line"),
            (.fixed("⌥-click"), "Add a cursor"),
            (.commands([.addCursorAbove, .addCursorBelow]), "Add a cursor above, below"),
            (.commands([.addNextMatch]), "Select the word, then add the next match"),
            (.fixed("Esc"), "Back to one cursor"),
        ]),
    ]

    /// A row's keys as shown, or nil to leave it out.
    private func label(_ keys: Keys) -> String? {
        switch keys {
        case .fixed(let text): return text
        case .commands(let actions):
            let labels = actions.compactMap { shortcuts.label(for: $0) }
            guard !labels.isEmpty else { return nil }
            // Body text, then headings 1 to 6: "⌘0 … ⌘6".
            if actions == [.bodyText, .heading1, .heading6], labels.count == 3 { return "\(labels[0]) … \(labels[2])" }
            return labels.joined(separator: "  ")
        }
    }

    /// Settings › Shortcuts changes them.
    private let footnote = "Change any of these in Settings, under Shortcuts."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard Shortcuts")
                .font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 36) {
                column(Self.groups.prefix(3))
                column(Self.groups.dropFirst(3))
            }
            HStack {
                Text(footnote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 760)
    }

    private func column(_ groups: ArraySlice<(String, [(Keys, String)])>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.0) { name, rows in
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.headline)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                        ForEach(rows.compactMap { row in label(row.0).map { ($0, row.1) } }, id: \.1) { keys, action in
                            GridRow {
                                Text(keys)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                Text(action)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
