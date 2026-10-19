import AppKit
import IndexKit
import SwiftUI
import VaultKit

/// ⌘E: one place to open notes, search tags and run commands, all from the keyboard.
/// ⇧⌘E: the same palette, browsing folders and tags like a column of Finder.
struct CommandPalette: View {
    @EnvironmentObject private var model: VaultModel
    @State private var query = ""
    @State private var items: [PaletteItem] = []
    @State private var highlighted = 0
    @State private var tags: [(tag: String, count: Int)] = []
    @State private var searchTask: Task<Void, Never>?
    /// Where the explorer is.
    @State private var level = ExplorerLevel.place(.allNotes)

    private var isExploring: Bool { model.paletteMode == .explorer }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isExploring ? "folder" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                PaletteField(text: $query, placeholder: placeholder,
                             onMove: move, onSubmit: run, onCancel: close,
                             onLeft: isExploring ? { goUp() } : nil, onRight: isExploring ? { enter() } : nil)
            }
            .font(.title3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if isExploring {
                Divider()
                explorerHeader
            }

            if !items.isEmpty {
                Divider()
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                PaletteRow(item: item, isHighlighted: offset == highlighted)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        highlighted = offset
                                        run()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(CGFloat(items.count) * 34 + 12, 360)) // Fits short lists.
                    .onChange(of: highlighted) { offset in
                        if items.indices.contains(offset) { scroller.scrollTo(items[offset].id) }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .task {
            level = model.explorerLevel
            tags = (try? await model.index?.allTags()) ?? []
            refresh()
        }
        .onChange(of: query) { _ in refresh() }
        .onChange(of: model.paletteMode) { _ in
            query = ""
            refresh()
        }
    }

    private var placeholder: String {
        isExploring ? "Filter \(levelTitle)" : "Search notes, #tags or >commands"
    }

    // MARK: Explorer

    /// Where the explorer is, and how to move.
    private var explorerHeader: some View {
        HStack(spacing: 4) {
            Text(levelPath)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text("← back   → open")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// What's in the explorer's level: folders or tags first, then notes, filtered by
    /// what's typed.
    private func explorerItems() -> [PaletteItem] {
        var places: [PaletteItem] = []
        var notes: [Note] = []
        switch level {
        case .tags:
            places = model.sortedTagEntries.filter { $0.depth == 0 }.map { .place(.tag($0.tag), $0.count) }
        case .place(let place):
            places = model.subplaces(of: place).map { .place($0, model.noteCount(of: $0)) }
            let topTags = model.sortedTagEntries.filter { $0.depth == 0 }.count
            if place == .allNotes, topTags > 0 { places.append(.tags(topTags)) }
            notes = model.notes(in: place).sorted(by: model.sort)
        }
        let noteItems = notes.map { PaletteItem.note($0.id, $0.title, nil) }
        let filter = query.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return places + noteItems }
        return Self.rank(places, by: filter, name: \.name) + Self.rank(noteItems, by: filter, name: \.name)
    }

    /// Opens the highlighted folder or tag.
    private func enter() {
        guard items.indices.contains(highlighted) else { return }
        switch items[highlighted] {
        case .place(let place, _): show(.place(place))
        case .tags: show(.tags)
        default: NSSound.beep()
        }
    }

    /// Back up a level, highlighting where we came from.
    private func goUp() {
        let from = level
        switch level {
        case .tags: show(.place(.allNotes))
        case .place(.allNotes): return NSSound.beep()
        case .place(.tag(let tag)) where !tag.contains("/"): show(.tags)
        case .place(let place): show(.place(place.parent))
        }
        let cameFrom: String
        switch from {
        case .tags: cameFrom = "tags"
        case .place(let place): cameFrom = "place:" + place.key
        }
        highlighted = items.firstIndex { $0.id == cameFrom } ?? 0
    }

    private func show(_ level: ExplorerLevel) {
        self.level = level
        model.explorerLevel = level
        query = ""
        items = explorerItems()
        highlighted = 0
    }

    /// "Projects" or "#work".
    private var levelTitle: String {
        switch level {
        case .tags: "Tags"
        case .place(.allNotes): model.root?.lastPathComponent ?? "Vault"
        case .place(let place): place.shortName
        }
    }

    /// "MG notes › Projects › Imprint" or "Tags › #work › imprint".
    private var levelPath: String {
        let vault = model.root?.lastPathComponent ?? "Vault"
        switch level {
        case .tags: return vault + " › Tags"
        case .place(.allNotes): return vault
        case .place(.folder(let path)): return ([vault] + path.split(separator: "/").map(String.init)).joined(separator: " › ")
        case .place(.tag(let tag)):
            let parts = tag.split(separator: "/").map(String.init)
            return ([vault, "Tags", "#" + parts[0]] + parts.dropFirst()).joined(separator: " › ")
        }
    }

    // MARK: Results

    private func refresh() {
        searchTask?.cancel()
        let query = query
        if isExploring {
            items = explorerItems()
            highlighted = 0
            return
        }
        let commands = PaletteCommand.all(for: model)
        searchTask = Task {
            var notes: [PaletteItem] = []
            var tagItems: [PaletteItem] = []
            var commandItems: [PaletteItem] = []
            let trimmed = query.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(">") {
                commandItems = Self.rank(commands, by: String(trimmed.dropFirst()), name: \.name).map(PaletteItem.command)
            } else if trimmed.hasPrefix("#") {
                let tagQuery = String(trimmed.dropFirst())
                tagItems = tags.filter { tagQuery.isEmpty || $0.tag.lowercased().contains(tagQuery.lowercased()) || Fuzzy.score(query: tagQuery, name: $0.tag) != nil }
                    .prefix(30).map { PaletteItem.tag($0.tag, $0.count) }
            } else if trimmed.isEmpty {
                notes = model.notes.sorted(by: .modified).prefix(6).map { PaletteItem.note($0.id, $0.title, nil) }
                commandItems = commands.filter(\.isSuggested).map(PaletteItem.command)
            } else {
                let results = (try? await model.index?.search(trimmed, limit: 8)) ?? []
                notes = results.map { PaletteItem.note($0.id, $0.title, $0.snippet) }
                tagItems = tags.filter { Fuzzy.score(query: trimmed, name: $0.tag) != nil }.prefix(3).map { PaletteItem.tag($0.tag, $0.count) }
                commandItems = Self.rank(commands, by: trimmed, name: \.name).prefix(3).map(PaletteItem.command)
            }
            guard !Task.isCancelled else { return }
            items = notes + tagItems + commandItems
            highlighted = 0
        }
    }

    static func rank<T>(_ things: [T], by query: String, name: KeyPath<T, String>) -> [T] {
        things.compactMap { thing in Fuzzy.score(query: query, name: thing[keyPath: name]).map { (thing, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    // MARK: Keyboard

    private func move(_ step: Int) {
        guard !items.isEmpty else { return }
        highlighted = (highlighted + step + items.count) % items.count
    }

    private func run() {
        guard items.indices.contains(highlighted) else { return }
        let item = items[highlighted]
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        switch item {
        case .place, .tags: return enter()
        default: break
        }
        close()
        switch item {
        case .note(let id, _, _):
            if inNewTab { model.newTab(noteID: id) } else { model.selection = id }
        case .tag(let tag, _): model.search(tag: tag)
        case .command(let command): command.action()
        case .place, .tags: break
        }
    }

    private func close() {
        model.isPaletteShown = false
    }
}

/// A level of the palette's explorer: the vault or a folder or tag, or the list of tags.
enum ExplorerLevel: Hashable {
    case place(SidebarPlace)
    case tags
}

enum PaletteItem: Identifiable {
    case note(Note.ID, String, String?)
    case tag(String, Int)
    case command(PaletteCommand)
    /// A folder or tag to open in the explorer, with its note count.
    case place(SidebarPlace, Int)
    /// The explorer's way into the tags, with how many top-level tags there are.
    case tags(Int)

    var id: String {
        switch self {
        case .note(let id, _, _): "note:\(id)"
        case .tag(let tag, _): "tag:\(tag)"
        case .command(let command): "command:\(command.name)"
        case .place(let place, _): "place:" + place.key
        case .tags: "tags"
        }
    }

    /// What filtering matches against.
    var name: String {
        switch self {
        case .note(_, let title, _): title
        case .tag(let tag, _): tag
        case .command(let command): command.name
        case .place(let place, _): place.shortName
        case .tags: "Tags"
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(isHighlighted ? .white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if case .note(_, _, let snippet?) = item {
                    Text(snippet.filter { $0 != SearchResult.matchStart && $0 != SearchResult.matchEnd }.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                }
            }
            Spacer()
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? Color.accentColor : .clear))
    }

    private var icon: String {
        switch item {
        case .note: "doc.text"
        case .tag: "number"
        case .command: "command"
        case .place(let place, _): place.isTag ? "number" : "folder"
        case .tags: "tag"
        }
    }

    private var title: String {
        switch item {
        case .note(_, let title, _): title
        case .tag(let tag, _): "#\(tag)"
        case .command(let command): command.name
        case .place(let place, _): place.shortName
        case .tags: "Tags"
        }
    }

    private var detail: String? {
        switch item {
        case .note: nil
        case .tag(_, let count): "\(count) \(count == 1 ? "note" : "notes")"
        case .command(let command): command.shortcut
        case .place(_, let count): "\(count)  ›"
        case .tags(let count): "\(count)  ›"
        }
    }
}

/// Something the palette can do.
struct PaletteCommand {
    let name: String
    let shortcut: String?
    /// Shown when the palette opens, before anything is typed.
    var isSuggested = false
    let action: () -> Void

    @MainActor static func all(for model: VaultModel) -> [PaletteCommand] {
        var commands = [
            PaletteCommand(name: "New Note", shortcut: "⌘N", isSuggested: true) { model.createNote() },
            PaletteCommand(name: "Today's Note", shortcut: "⌘T", isSuggested: true) { model.openTodaysNote() },
            PaletteCommand(name: "Search Notes", shortcut: "⌘F") { model.focusSearch() },
            PaletteCommand(name: "Explorer", shortcut: "⇧⌘E", isSuggested: true) { model.togglePalette(.explorer) },
            PaletteCommand(name: model.showsNoteList ? "Hide Note List" : "Show Note List", shortcut: "⌘S") { model.showsNoteList.toggle() },
            PaletteCommand(name: "Bigger Text", shortcut: "⌘=") { model.makeTextBigger() },
            PaletteCommand(name: "Smaller Text", shortcut: "⌘−") { model.makeTextSmaller() },
            PaletteCommand(name: model.isFocused ? "Leave Focus" : "Focus", shortcut: "⇧⌘\\") { model.isFocused.toggle() },
            PaletteCommand(name: model.showsMarkdown ? "Hide Markdown" : "Show Markdown", shortcut: "⇧⌘M") { model.showsMarkdown.toggle() },
            PaletteCommand(name: model.showsDateInList ? "Hide Dates in List" : "Show Dates in List", shortcut: nil) { model.showsDateInList.toggle() },
            PaletteCommand(name: model.showsTagsInList ? "Hide Tags in List" : "Show Tags in List", shortcut: nil) { model.showsTagsInList.toggle() },
            PaletteCommand(name: "Sort by Date Edited", shortcut: nil) { model.sort = .modified },
            PaletteCommand(name: "Sort by Date Created", shortcut: nil) { model.sort = .created },
            PaletteCommand(name: "Sort by Title", shortcut: nil) { model.sort = .title },
            PaletteCommand(name: "Back", shortcut: "⌘[") { model.goBack() },
            PaletteCommand(name: "Forward", shortcut: "⌘]") { model.goForward() },
            PaletteCommand(name: "Open Vault…", shortcut: "⌘O") { model.chooseVault() },
            PaletteCommand(name: "All Notes", shortcut: nil) { model.browse(.allNotes) },
            PaletteCommand(name: "Enclosing Folder", shortcut: "⌘↑") { model.goUp() },
        ]
        commands += [
            PaletteCommand(name: "New Tab", shortcut: "⌘T") { model.newTab() },
            PaletteCommand(name: "Close Tab", shortcut: "⌘W") { model.closeTab() },
            PaletteCommand(name: model.isSplit ? "Merge Split into Tabs" : "Split", shortcut: "⇧⌘S") { model.toggleSplit() },
            PaletteCommand(name: model.isSplit ? "Move Tab to Other Side" : "Move Tab to New Split", shortcut: nil) { model.moveTabToOtherSide() },
        ]
        if let note = model.selectedNote {
            commands += [
                PaletteCommand(name: "Insert Template…", shortcut: "⌥⌘T") { model.isChoosingTemplate = true },
                PaletteCommand(name: "Add Property…", shortcut: nil) { NotificationCenter.default.post(name: .imprintAddProperty, object: model) },
                PaletteCommand(name: "Rename Note…", shortcut: nil) { model.renaming = note },
                PaletteCommand(name: "Move to Folder…", shortcut: nil) { model.moving = note },
                PaletteCommand(name: "Add Tag…", shortcut: nil) { model.tagging = note },
                PaletteCommand(name: "Show in Finder", shortcut: "⌥⌘R") { model.showInFinder(note) },
                PaletteCommand(name: "Move Note to Trash", shortcut: nil) { model.moveToTrash(note) },
                PaletteCommand(name: "Find in Note", shortcut: "⌥⌘F") { FindInNote.show() },
            ]
        }
        return commands
    }
}

/// The palette's text field. AppKit, so arrow keys, Return and Escape can drive the list
/// (SwiftUI on macOS 13 can't intercept them in a text field).
private struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// ← at the start of the text, and → at its end (or ⌫ with nothing typed): for the
    /// explorer to go up a level or into one.
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField
        init(parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            // ⌘Return reaches a text field as "noop:"; it opens the note in a new tab.
            case NSSelectorFromString("noop:") where NSApp.currentEvent?.keyCode == 36: parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            case #selector(NSResponder.moveLeft(_:)) where parent.onLeft != nil && textView.selectedRange() == NSRange(location: 0, length: 0):
                parent.onLeft?()
            case #selector(NSResponder.deleteBackward(_:)) where parent.onLeft != nil && textView.string.isEmpty:
                parent.onLeft?()
            case #selector(NSResponder.moveRight(_:)) where parent.onRight != nil && textView.selectedRange() == NSRange(location: (textView.string as NSString).length, length: 0):
                parent.onRight?()
            default: return false
            }
            return true
        }
    }
}
