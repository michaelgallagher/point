import IndexKit
import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var isAddingProperty = false

    /// One column (folders, tags and notes together) or two (folders and tags beside notes).
    @ViewBuilder private var splitView: some View {
        if model.browsingStyle == .twoColumns {
            // Tree and notes side by side inside one sidebar, so hiding, swiping and resizing
            // work exactly as in the single column. (SwiftUI's three-column split view on the
            // Mac won't hide both side columns from code.)
            NavigationSplitView(columnVisibility: $columns) {
                VStack(spacing: 0) {
                    SidebarTopBar()
                    HSplitView {
                        PlaceTreeColumn()
                            .frame(minWidth: 150, idealWidth: 200, maxWidth: 320)
                        NoteList(includesPlaces: false)
                            .frame(minWidth: 200, idealWidth: 260)
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(min: 360, ideal: 470, max: 760)
            } detail: {
                detail
            }
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                VStack(spacing: 0) {
                    SidebarTopBar()
                    NoteList()
                }
                .ignoresSafeArea(.container, edges: .top)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
            } detail: {
                detail
            }
        }
    }

    /// The notes: one pane, or two side by side, each with its own tabs.
    private var detail: some View {
        Group {
            if model.isSplit {
                SideBySide {
                    PaneView(paneID: model.panes[0].id)
                } side: {
                    PaneView(paneID: model.panes[1].id)
                }
            } else {
                PaneView(paneID: model.panes[0].id)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func updateColumns() {
        let visible = model.showsNoteList && !model.isFocused
        withAnimation(.easeOut(duration: 0.15)) { columns = visible ? .all : .detailOnly }
    }

    /// In the sidebar's part of the toolbar, beside the button that hides it.
    /// The note being worked on (in the active pane), else the vault's name.
    private var windowTitle: String {
        model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Imprint"
    }

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                Group {
                    splitView
                }
                .navigationTitle(windowTitle)
                // A toolbar with nothing but the system's sidebar button, so the window's top
                // row has the standard height (window buttons centred in it) and the sidebar
                // button sits where macOS puts it: at the sidebar's edge, or past the window
                // buttons while it's hidden. The sidebar and each side of a split draw their
                // own bars in that row.
                .toolbar {
                    if #available(macOS 26, *) {
                        // Without its glass backing, or it shows as a sliver.
                        ToolbarItem(placement: .automatic) { ToolbarSpacerView() }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .automatic) { ToolbarSpacerView() }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.isFocused {
                        // The one control kept in focus mode: bring the note list back.
                        Button { model.isFocused = false } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 14))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Show Note List")
                        .padding(.leading, 76)
                        .padding(.top, 2)
                    }
                }
                .onChange(of: model.searchFocusRequest) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { columns = .all } // Search needs the list.
                }
                .onChange(of: model.isFocused) { _ in updateColumns() }
                // The window keeps its size: the notes take the list's space, and their
                // text column (which has a maximum width) slides over to recentre.
                .onChange(of: model.showsNoteList) { _ in updateColumns() }

                .onChange(of: columns) { visibility in
                    // Showing the sidebar (with the system's button) leaves focus mode.
                    if model.isFocused, visibility != .detailOnly { model.isFocused = false }
                    // The toolbar's sidebar button changes the columns directly; keep ⌘S in step.
                    if !model.isFocused { model.showsNoteList = visibility != .detailOnly }
                }
            }
        }
        // Minimal is meant to sit beside other windows, so it can be narrow.
        // With the sidebar hidden, a window is one compact note that can sit beside others.
        .frame(minWidth: model.showsNoteList && !model.isFocused ? 600 : 420, minHeight: 400)
        .onAppear {
            model.startSwipeTracking()
            // Open the way the last window was left: with or without the sidebar.
            columns = model.showsNoteList ? .all : .detailOnly
        }
        .overlay(alignment: .top) {
            if model.isPaletteShown {
                ZStack(alignment: .top) {
                    // Clicking outside the palette closes it.
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture { model.isPaletteShown = false }
                    CommandPalette()
                        .padding(.top, 80)
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $model.renaming) { note in
            RenameSheet(note: note)
        }
        .sheet(item: $model.creatingFolder) { request in
            NewFolderSheet(parent: request.parent)
        }
        .sheet(isPresented: $model.isChoosingTemplate) {
            TemplatePicker()
        }
        .sheet(isPresented: $model.isShowingShortcuts) {
            ShortcutsSheet()
        }
        .sheet(item: $model.moving) { note in
            MoveSheet(note: note)
        }
        .sheet(item: $model.tagging) { note in
            AddTagSheet(note: note)
        }
        .sheet(isPresented: $isAddingProperty) {
            AddPropertySheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imprintAddProperty)) { notification in
            // Only the window that asked.
            guard notification.object as AnyObject? === model, model.selectedNote != nil else { return }
            isAddingProperty = true
        }
    }
}

private struct OpenVaultView: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Imprint")
                .font(.largeTitle.weight(.semibold))
            Text("Choose the folder that holds your notes.")
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Button("Open Vault…") { model.chooseVault() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteList: View {
    @EnvironmentObject private var model: VaultModel
    @FocusState private var searchFocused: Bool
    /// False in the two-column view, where folders and tags have their own column.
    var includesPlaces = true

    var body: some View {
        VStack(spacing: 0) {
            if includesPlaces, model.place != .allNotes, model.searchResults == nil {
                PlaceHeader()
            } else if !includesPlaces, model.searchResults == nil {
                Text(model.place == .allNotes ? (model.root?.lastPathComponent ?? "Notes") : model.place.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            SearchField(text: $model.searchText, isFocused: $searchFocused) {
                // Return opens the top result.
                if let first = model.searchResults?.first { model.selection = first.id }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            if let results = model.searchResults {
                List(results, selection: $model.selection) { result in
                    SearchResultRow(result: result)
                }
                // On the sidebar's material, not white, in both layouts.
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .overlay {
                    if results.isEmpty {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                browser
            }
        }
        .onChange(of: model.searchFocusRequest) { _ in searchFocused = true }
        .overlay {
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    /// Pins, folders (or nested tags), tags and notes for the current place.
    private var browser: some View {
        SidebarTable(model: model, includesPlaces: includesPlaces)
            .overlay {
                if model.notes(in: model.place).isEmpty, !includesPlaces || model.subplaces(of: model.place).isEmpty, model.place != .allNotes {
                    Text(model.place.isTag ? "No notes have this tag." : "This folder has no notes.")
                        .foregroundStyle(.secondary)
                }
            }
    }
}

/// The folder or tag being browsed, with a way back up.
private struct PlaceHeader: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.goUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back (⌘↑)")
            Text(model.place.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button { model.togglePin(model.place) } label: {
                Image(systemName: model.isPinned(model.place) ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.isPinned(model.place) ? "Unpin" : "Pin to the top of the sidebar")
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

/// The toolbar's one, invisible item: it's there so the window has a toolbar's height.
private struct ToolbarSpacerView: View {
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}

extension SidebarPlace {
    var isTag: Bool {
        if case .tag = self { return true }
        return false
    }

    /// "NHS", "Projects" or "#work/imprint".
    var title: String {
        switch self {
        case .allNotes: "All Notes"
        case .folder(let path): FolderTree.name(of: path)
        case .tag(let tag): "#" + tag
        }
    }

    /// The last part only: "imprint" for #work/imprint, under its parent in the tag list.
    var shortName: String {
        switch self {
        case .tag(let tag): tag.split(separator: "/").last.map(String.init) ?? tag
        default: title
        }
    }
}

/// The search field above the note list.
private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
    }
}

/// A search result: the note's name and, if its text matched, a snippet with the match marked.
private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .lineLimit(1)
            if let snippet = result.snippet {
                Text(Self.highlighted(snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    /// The snippet with matches in bold, from the index's start and end marks.
    static func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var isMatch = false
        var current = ""
        func flush() {
            var piece = AttributedString(current.replacingOccurrences(of: "\n", with: " "))
            if isMatch {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = .primary
            }
            result += piece
            current = ""
        }
        for character in snippet {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                isMatch = character == SearchResult.matchStart
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Note")
                .font(.headline)
            TextField("Name", text: $title)
                .frame(width: 320)
                .onSubmit(rename)
            Text("Links to this note in other notes will be updated.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { title = note.title }
    }

    private func rename() {
        model.rename(note, to: title)
        dismiss()
    }
}

private struct NewFolderSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let parent: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Folder")
                .font(.headline)
            TextField("Name", text: $name)
                .frame(width: 320)
                .onSubmit(create)
            Text("In " + ([model.root?.lastPathComponent ?? "Vault"] + parent.split(separator: "/").map(String.init)).joined(separator: " › "))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.createFolder(named: name, in: parent)
        dismiss()
    }
}

private struct TemplatePicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?

    var body: some View {
        let templates = model.templates
        VStack(alignment: .leading, spacing: 12) {
            Text("Insert Template")
                .font(.headline)
            if templates.isEmpty {
                Text(model.settings.templatesFolder.isEmpty
                     ? "No templates folder is set. Choose one in Obsidian's Templates settings."
                     : "There are no templates in “\(model.settings.templatesFolder)”.")
                    .foregroundStyle(.secondary)
                    .frame(width: 320, alignment: .leading)
            } else {
                List(templates, id: \.url, selection: $selection) { template in
                    Text(template.name)
                }
                .frame(width: 320, height: 220)
                .onAppear { selection = templates.first?.url }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
    }

    private func insert() {
        guard let selection else { return }
        dismiss()
        model.insertTemplate(at: selection)
    }
}


/// Chooses a folder to move a note into.
private struct MoveSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var filter = ""
    @State private var selection: String?

    /// Every folder ("" is the vault root), filtered as you type, except the note's own.
    private var folders: [String] {
        let all = [""] + model.folderTree.noteCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let current = FolderTree.folder(of: note.id)
        return all.filter { $0 != current && (filter.isEmpty || $0.localizedCaseInsensitiveContains(filter)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move “\(note.title)”")
                .font(.headline)
            TextField("Filter folders", text: $filter)
            List(folders, id: \.self, selection: $selection) { folder in
                Label(folder.isEmpty ? "Vault (top level)" : folder, systemImage: "folder")
            }
            .frame(width: 360, height: 260)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move", action: move)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .onChange(of: filter) { _ in selection = folders.first }
    }

    private func move() {
        guard let selection else { return }
        dismiss()
        model.move(noteID: note.id, toFolder: selection)
    }
}
