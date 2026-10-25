import AppKit
import IndexKit
import EditorKit
import SwiftUI
import VaultKit

/// ⌘F: one place to open notes, search tags and run commands, all from the keyboard.
/// ⌘E: the same palette as a two-column explorer of folders, tags and their notes.
/// ⌃Tab: only the open tabs, most recently shown first, to switch between them.
/// An empty tab shows the same palette as a page: the start page.
struct CommandPalette: View {
    @EnvironmentObject private var model: VaultModel
    @State private var query = ""
    @State private var items: [PaletteItem] = []
    @State private var highlighted = 0
    /// Notes open in tabs, marked in the list.
    @State private var openIDs: Set<Note.ID> = []
    @State private var tags: [(tag: String, count: Int)] = []
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var explorer = ExplorerState()
    /// Shown as a tab's start page rather than over the window.
    var isPage = false
    /// On a start page: browsing in the explorer, rather than searching.
    @State private var pageExplores = false

    private var isExploring: Bool { isPage ? pageExplores : model.paletteMode == .explorer }
    private var isSwitchingTabs: Bool { !isPage && model.paletteMode == .tabs }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isExploring ? "folder" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                PaletteField(text: $query, placeholder: placeholder, fontSize: isPage ? 22 : 18,
                             onMove: move, onSubmit: run, onCancel: cancel, onCloseItem: closeHighlightedTab,
                             onLeft: isExploring ? { explorerLeft() } : nil, onRight: isExploring ? { explorerRight() } : nil)
            }
            .font(isPage ? .title2 : .title3)
            .padding(.horizontal, 16)
            .padding(.vertical, isPage ? 12 : 18)
            // On a start page, the field is a rounded box; in the floating palette, a line
            // below it divides it from the list.
            .background {
                if isPage {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .padding(.bottom, isPage ? 10 : 0)

            if isExploring {
                if !isPage { Divider() }
                ExplorerColumns(state: explorer, open: { id in open(id, inNewTab: false) },
                                drop: { dragged, folder in model.drop(dragged, onFolder: folder) })
                    .frame(height: isPage ? nil : Self.listHeight)
                    .frame(maxHeight: isPage ? .infinity : nil)
            } else if !items.isEmpty || !isPage {
                if !isPage { Divider() }
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                // Every row is an open tab when switching tabs, so none is marked.
                                PaletteRow(item: item, isHighlighted: offset == highlighted,
                                           isOpen: !isSwitchingTabs && openIDs.contains(item.noteID ?? ""))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        highlighted = offset
                                        run()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    // The same height as the explorer, so the palette doesn't change size;
                    // as a page, it fills the tab.
                    .frame(height: isPage ? nil : Self.listHeight)
                    .frame(maxHeight: isPage ? .infinity : nil)
                    .onChange(of: highlighted) { offset in
                        if items.indices.contains(offset) { scroller.scrollTo(items[offset].id) }
                    }
                }
            }
        }
        .modifier(PaletteChrome(isPage: isPage, isWide: isExploring))
        .task {
            if !isPage, let seed = model.paletteSeed {
                query = seed
                model.paletteSeed = nil
            }
            if isExploring { explorer.load(model) }
            tags = (try? await model.index?.allTags()) ?? []
            refresh()
        }
        .onChange(of: query) { _ in refresh() }
        // Something moved (dragged in the explorer, say): list it where it is now.
        .onReceive(model.store.$folderTree.dropFirst()) { _ in
            if isExploring { explorer.reload() }
        }
        // At launch the palette (or a start page) can appear before the notes have loaded.
        .onChange(of: model.notes.count) { _ in
            if query.isEmpty, !isExploring { refresh() }
        }
        .onChange(of: model.paletteMode) { _ in
            guard !isPage else { return }
            query = ""
            if isExploring { explorer.load(model) }
            refresh()
        }
        // ⌃Tab again: the next tab down.
        .onChange(of: model.paletteCycleRequest) { _ in
            if isSwitchingTabs { move(1) }
        }
        .onChange(of: model.startPageRequest.count) { _ in
            // ⌘F or ⌘E on a start page switches the page itself.
            guard isPage else { return }
            setPageExplores(model.startPageRequest.mode == .explorer)
        }
    }

    /// The palette's list height, searching or exploring.
    static let listHeight: CGFloat = 420

    private var placeholder: String {
        if isExploring { return explorer.inNotes ? "Filter notes" : "Filter folders and tags" }
        if isSwitchingTabs { return "Switch to a tab" }
        return isPage ? "Search notes, #tags or >commands" : "Search notes, #tags or >commands"
    }

    /// Escape closes the palette; on a start page, it clears what's typed, then leaves the
    /// explorer.
    private func cancel() {
        guard isPage else { return close() }
        if !query.isEmpty { query = "" } else if pageExplores { setPageExplores(false) }
    }

    private func setPageExplores(_ explores: Bool) {
        query = ""
        pageExplores = explores
        if explores { explorer.load(model) }
        refresh()
    }

    // MARK: Explorer keys

    private func explorerRight() {
        if explorer.enterNotes() { query = "" } else { NSSound.beep() }
    }

    private func explorerLeft() {
        if explorer.leaveNotes() { query = "" } else if isPage { setPageExplores(false) } else { NSSound.beep() }
    }

    private func open(_ id: Note.ID, inNewTab: Bool) {
        if !isPage { close() }
        // A start page opens the note in its own tab, which is the active one.
        if inNewTab { model.newTab(noteID: id) } else { model.selection = id }
    }

    // MARK: Results

    /// Lists what matches what's typed. `keeping` keeps the highlight at that row (or the
    /// last one) rather than going back to the top, as after closing a tab from the list.
    private func refresh(keeping: Int? = nil) {
        searchTask?.cancel()
        let query = query
        if isExploring {
            explorer.setFilter(query)
            return
        }
        if isSwitchingTabs { return refreshTabs(keeping: keeping) }
        let commands = PaletteCommand.all(for: model)
        // Notes open in tabs come first, marked as open.
        let openNotes = model.openNoteIDs.compactMap { model.note($0) }
        let openSet = Set(openNotes.map(\.id))
        openIDs = openSet
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
                let open = openNotes.map { PaletteItem.note($0.id, $0.title, nil) }
                let recent = model.notes.sorted(by: .modified).lazy.filter { !openSet.contains($0.id) }.prefix(6)
                notes = open + recent.map { PaletteItem.note($0.id, $0.title, nil) }
                commandItems = commands.filter(\.isSuggested).map(PaletteItem.command)
            } else {
                let results = (try? await model.index?.search(trimmed, limit: 8)) ?? []
                // Open notes that match, by title or in the search, then the rest.
                let openMatches = Self.rank(openNotes, by: trimmed, name: \.title).map(\.id)
                let found = results.map { PaletteItem.note($0.id, $0.title, $0.snippet) }
                let openFirst = openMatches.compactMap { id in
                    found.first { $0.noteID == id } ?? model.note(id).map { PaletteItem.note($0.id, $0.title, nil) }
                } + found.filter { item in openSet.contains(item.noteID ?? "") && !openMatches.contains(item.noteID ?? "") }
                notes = openFirst + found.filter { !openSet.contains($0.noteID ?? "") }
                // A name no note has yet: offer to make it, first if nothing else matched (so
                // typing a new name and pressing Return makes the note).
                let title = NoteFiles.sanitizedTitle(trimmed)
                if !title.isEmpty, !model.notes.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                    notes = notes.isEmpty ? [.create(title)] : notes + [.create(title)]
                }
                tagItems = tags.filter { Fuzzy.score(query: trimmed, name: $0.tag) != nil }.prefix(3).map { PaletteItem.tag($0.tag, $0.count) }
                commandItems = Self.rank(commands, by: trimmed, name: \.name).prefix(3).map(PaletteItem.command)
            }
            guard !Task.isCancelled else { return }
            items = notes + tagItems + commandItems
            highlighted = keeping.map { max(0, min($0, items.count - 1)) } ?? 0
        }
    }

    /// The open tabs' notes, most recently shown first (both sides), filtered by what's typed.
    /// With nothing typed, the one shown before this is highlighted, so ⌃Tab and Return flip
    /// between two notes.
    private func refreshTabs(keeping: Int?) {
        let tabs = model.panes.flatMap(\.tabs)
        let order = model.recentTabs + tabs.map(\.id).filter { !model.recentTabs.contains($0) }
        var notes = order.compactMap { id in tabs.first { $0.id == id }?.noteID }.compactMap { model.note($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { notes = Self.rank(notes, by: trimmed, name: \.title) }
        openIDs = Set(notes.map(\.id))
        items = notes.map { PaletteItem.note($0.id, $0.title, nil) }
        if let keeping {
            highlighted = max(0, min(keeping, items.count - 1))
        } else {
            highlighted = trimmed.isEmpty && items.count > 1 && items.first?.noteID == model.selection ? 1 : 0
        }
    }

    /// ⌘⌫ on a note open in a tab closes that tab, and the palette stays open. Returns false
    /// for anything else, so ⌘⌫ deletes what's typed as usual.
    private func closeHighlightedTab() -> Bool {
        guard !isExploring, items.indices.contains(highlighted), let id = items[highlighted].noteID,
              openIDs.contains(id), model.openNoteIDs.contains(id) else { return false }
        let row = highlighted
        model.closeTab(of: id)
        refresh(keeping: row)
        return true
    }

    static func rank<T>(_ things: [T], by query: String, name: KeyPath<T, String>) -> [T] {
        things.compactMap { thing in Fuzzy.score(query: query, name: thing[keyPath: name]).map { (thing, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    // MARK: Keyboard

    private func move(_ step: Int) {
        if isExploring { return explorer.move(step) }
        guard !items.isEmpty else { return }
        highlighted = (highlighted + step + items.count) % items.count
    }

    private func run() {
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        if isExploring {
            if explorer.inNotes, let note = explorer.currentNote { open(note.id, inNewTab: inNewTab) } else { explorerRight() }
            return
        }
        guard items.indices.contains(highlighted) else { return }
        let item = items[highlighted]
        if !isPage { close() }
        switch item {
        case .note(let id, _, _) where isSwitchingTabs:
            model.goToTab(of: id)
        case .note(let id, _, _):
            open(id, inNewTab: inNewTab)
        case .tag(let tag, _): model.search(tag: tag)
        case .create(let title): model.createNote(titled: title)
        case .command(let command): command.action()
        }
    }

    private func close() {
        model.isPaletteShown = false
    }
}

enum PaletteItem: Identifiable {
    case note(Note.ID, String, String?)
    case tag(String, Int)
    /// A new note with this name.
    case create(String)
    case command(PaletteCommand)

    var noteID: Note.ID? {
        if case .note(let id, _, _) = self { return id }
        return nil
    }

    var id: String {
        switch self {
        case .note(let id, _, _): "note:\(id)"
        case .tag(let tag, _): "tag:\(tag)"
        case .create(let title): "create:\(title)"
        case .command(let command): "command:\(command.name)"
        }
    }

    /// What filtering matches against.
    var name: String {
        switch self {
        case .note(_, let title, _): title
        case .tag(let tag, _): tag
        case .create(let title): title
        case .command(let command): command.name
        }
    }
}

/// The palette's frame: a floating panel over the window, or as a page, a centred column
/// on the tab's own background.
private struct PaletteChrome: ViewModifier {
    let isPage: Bool
    /// The explorer's two columns need more room.
    let isWide: Bool

    func body(content: Content) -> some View {
        if isPage {
            content
                .frame(maxWidth: 600) // The same width searching and exploring.
                .padding(.top, 48)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            // As wide as it wants, within a narrow window.
            content
                .frame(maxWidth: 540) // The same width searching and exploring.
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // One shadow for the whole panel, not one per row.
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                .padding(.horizontal, 20) // Clear of a narrow window's edges.
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isHighlighted: Bool
    /// A note open in a tab.
    var isOpen = false

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
        case .create: "plus"
        case .command: "command"
        }
    }

    private var title: String {
        switch item {
        case .note(_, let title, _): title
        case .tag(let tag, _): "#\(tag)"
        case .create(let title): "New Note “\(title)”"
        case .command(let command): command.name
        }
    }

    private var detail: String? {
        switch item {
        case .note: isOpen ? "Open" : nil
        case .tag(_, let count): "\(count) \(count == 1 ? "note" : "notes")"
        case .create: nil
        case .command(let command): command.shortcut
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
            PaletteCommand(name: "Today's Note", shortcut: "⇧⌘T", isSuggested: true) { model.openTodaysNote() },
            PaletteCommand(name: "Explorer", shortcut: "⌘E", isSuggested: true) { model.togglePalette(.explorer) },
            PaletteCommand(name: "New Folder…", shortcut: "⇧⌘N") { model.newFolder() },
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
            PaletteCommand(name: "New Tab on Other Side", shortcut: "⌃⌘T") { model.newTabOnOtherSide() },
            PaletteCommand(name: "Close Tab", shortcut: "⌘W") { model.closeTab() },
            PaletteCommand(name: "Switch to Tab…", shortcut: "⌃Tab") {
                // After the palette running this has closed.
                DispatchQueue.main.async { model.togglePalette(.tabs) }
            },
            PaletteCommand(name: "Show Tab List", shortcut: "⇧⌘O") { model.toggleTabMenu() },
        ]
        commands += [
            PaletteCommand(name: model.isSplit ? "Merge Split into Tabs" : "Split", shortcut: "⇧⌘S") { model.toggleSplit() },
            PaletteCommand(name: model.isSplit ? "Move Tab to Other Side" : "Move Tab to New Split", shortcut: nil) { model.moveTabToOtherSide() },
        ]
        commands.append(PaletteCommand(name: "Search in List", shortcut: "⇧⌘F") { model.focusSearch() })
        commands.append(PaletteCommand(name: "Keyboard Shortcuts", shortcut: "⌘/") { model.isShowingShortcuts = true })
        commands.append(model.sidebarDensity == .compact
            ? PaletteCommand(name: "Use Comfortable Sidebar", shortcut: nil) { model.sidebarDensity = .comfortable }
            : PaletteCommand(name: "Use Compact Sidebar", shortcut: nil) { model.sidebarDensity = .compact })
        for (style, name) in [(VaultModel.BrowsingStyle.singleColumn, "Use One Column Sidebar"), (.twoColumns, "Use Two Column Sidebar")]
            where model.browsingStyle != style {
            commands.append(PaletteCommand(name: name, shortcut: nil) { model.browsingStyle = style })
        }
        if let note = model.selectedNote {
            commands += [
                PaletteCommand(name: "Insert Template…", shortcut: "⌥⌘T") { model.isChoosingTemplate = true },
                PaletteCommand(name: "Add Property…", shortcut: nil) { NotificationCenter.default.post(name: .pointAddProperty, object: model) },
                PaletteCommand(name: "Rename Note…", shortcut: nil) { model.renaming = note },
                PaletteCommand(name: "Move to Folder…", shortcut: nil) { model.moving = note },
                PaletteCommand(name: "Add Tag…", shortcut: nil) { model.tagging = note },
                PaletteCommand(name: "Show in Finder", shortcut: "⌥⌘R") { model.showInFinder(note) },
                PaletteCommand(name: "Move Note to Trash", shortcut: nil) { model.moveToTrash(note) },
                PaletteCommand(name: "Find in Note", shortcut: "⌥⌘F") { FindInNote.show() },
            ]
        }
        if let note = model.selectedNote {
            // Each template, straight into the note.
            for template in model.templates {
                commands.append(PaletteCommand(name: "Apply Template “\(template.name)”", shortcut: nil) { model.insertTemplate(at: template.url) })
            }
            // Formatting, done to the note's selection, as the Format menu does.
            let formats: [(String, String?, Selector)] = [
                ("Bold", "⌘B", #selector(MarkdownTextView.toggleBold(_:))),
                ("Italic", "⌘I", #selector(MarkdownTextView.toggleItalic(_:))),
                ("Highlight", "⌘U", #selector(MarkdownTextView.toggleHighlight(_:))),
                ("Strikethrough", "⇧⌘X", #selector(MarkdownTextView.toggleStrikethrough(_:))),
                ("Inline Code", "⌥⌘C", #selector(MarkdownTextView.toggleCode(_:))),
                ("Block Quote", "⌘'", #selector(MarkdownTextView.toggleBlockQuote(_:))),
                ("Body Text", "⌘0", #selector(MarkdownTextView.makeBodyText(_:))),
                ("Heading 1", "⌘1", #selector(MarkdownTextView.makeHeading1(_:))),
                ("Heading 2", "⌘2", #selector(MarkdownTextView.makeHeading2(_:))),
                ("Heading 3", "⌘3", #selector(MarkdownTextView.makeHeading3(_:))),
                ("Heading 4", "⌘4", #selector(MarkdownTextView.makeHeading4(_:))),
                ("Heading 5", "⌘5", #selector(MarkdownTextView.makeHeading5(_:))),
                ("Heading 6", "⌘6", #selector(MarkdownTextView.makeHeading6(_:))),
                ("Bulleted List", "⌘L", #selector(MarkdownTextView.toggleBulletList(_:))),
                ("Checklist", "⇧⌘L", #selector(MarkdownTextView.toggleChecklist(_:))),
                ("Indent", "⌥⌘→", #selector(MarkdownTextView.indentLines(_:))),
                ("Outdent", "⌥⌘←", #selector(MarkdownTextView.outdentLines(_:))),
                ("Move Line Up", "⌥⌘↑", #selector(MarkdownTextView.moveLinesUp(_:))),
                ("Move Line Down", "⌥⌘↓", #selector(MarkdownTextView.moveLinesDown(_:))),
                ("Fold", "⌥⌘[", #selector(MarkdownTextView.foldLine(_:))),
                ("Unfold", "⌥⌘]", #selector(MarkdownTextView.unfoldLine(_:))),
                ("Add Link…", "⌘K", #selector(MarkdownTextView.addLink(_:))),
            ]
            for (name, shortcut, action) in formats {
                commands.append(PaletteCommand(name: name, shortcut: shortcut) {
                    NotificationCenter.default.post(name: .pointEditorCommand, object: nil,
                                                    userInfo: ["noteID": note.id, "action": NSStringFromSelector(action)])
                })
            }
        }
        return commands
    }
}

/// The palette's text field. AppKit, so arrow keys, Return and Escape can drive the list
/// (SwiftUI on macOS 13 can't intercept them in a text field).
private struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 18
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// ⌘⌫: closes the highlighted tab, if it is one (returning true); otherwise the text
    /// field deletes to the start of the line as usual.
    var onCloseItem: (() -> Bool)?
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
        field.font = .systemFont(ofSize: fontSize)
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
            case #selector(NSResponder.deleteToBeginningOfLine(_:)) where NSApp.currentEvent?.modifierFlags.contains(.command) == true:
                return parent.onCloseItem?() ?? false
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
