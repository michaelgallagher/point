import SwiftUI

/// ⌘/: every keyboard shortcut, grouped, on one page.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// A group of shortcuts: its name and (keys, what they do).
    private static let groups: [(String, [(String, String)])] = [
        ("Notes", [
            ("⌘N", "New note"),
            ("⇧⌘T", "Today's note"),
            ("⌥⌘T", "Insert template"),
            ("⇧⌘N", "New folder"),
            ("⌥⌘R", "Show in Finder"),
        ]),
        ("Finding", [
            ("⌘F", "Search (type a new name and press Return to make that note)"),
            ("⌘E", "Explorer"),
            ("⇧⌘F", "Search in the sidebar's list"),
            ("⌥⌘F", "Find in note"),
            ("⌘[  ⌘]", "Back, forward"),
            ("⌘↑", "Enclosing folder"),
        ]),
        ("Tabs and sides", [
            ("⌘T", "New tab"),
            ("⌃⌘T", "New tab on the other side"),
            ("⌘W", "Close tab"),
            ("⇧⌘[  ⇧⌘]", "Previous, next tab"),
            ("⌃Tab", "Switch to a tab (in the palette)"),
            ("⇧⌘O", "Show this side's tab list"),
            ("⇧⌘S", "Split, or merge both sides into tabs"),
            ("⌥⌘N", "New window"),
            ("⌘-click a link", "Open it in a new tab"),
            ("⌥⌘-click a link", "Open it on the other side"),
        ]),
        ("Window", [
            ("⌘S", "Show or hide the sidebar"),
            ("⇧⌘\\", "Focus"),
            ("⇧⌘M", "Show Markdown"),
            ("⌘=  ⌘−", "Bigger, smaller text"),
            ("⌘R", "Reload notes"),
            ("⌘/", "This list"),
        ]),
        ("Formatting", [
            ("⌘B  ⌘I  ⌘U", "Bold, italic, highlight"),
            ("⇧⌘X", "Strikethrough"),
            ("⌥⌘C", "Inline code"),
            ("⌘'", "Block quote"),
            ("⌘0 … ⌘6", "Body text, headings 1 to 6"),
            ("⌘L", "Bulleted list"),
            ("⇧⌘L", "Checklist"),
            ("⌘K", "Add link"),
        ]),
        ("Editing", [
            ("⌥⌘→  ⌥⌘←", "Indent, outdent"),
            ("⌥⌘↑  ⌥⌘↓", "Move line up, down"),
            ("⌥⌘[  ⌥⌘]", "Fold, unfold the list item or heading"),
            ("⌘X", "With nothing selected: cut the line"),
            ("⌥-click", "Add a cursor"),
            ("⌃⇧↑  ⌃⇧↓", "Add a cursor above, below"),
            ("⌘D", "Select the word, then add the next match"),
            ("Esc", "Back to one cursor"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard Shortcuts")
                .font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 36) {
                column(Self.groups.prefix(3))
                column(Self.groups.dropFirst(3))
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 760)
    }

    private func column(_ groups: ArraySlice<(String, [(String, String)])>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.0) { name, shortcuts in
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.headline)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                        ForEach(shortcuts, id: \.0) { keys, action in
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
