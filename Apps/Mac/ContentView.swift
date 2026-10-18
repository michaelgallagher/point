import IndexKit
import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var isAddingProperty = false
    /// The sidebar's width (note list, or tree and notes together), which hiding removes.
    @State private var sidebarWidth: CGFloat = 0
    /// How much the window narrowed when the list last hid, to widen it back by.
    @State private var narrowedBy: CGFloat = 0

    /// One column (folders, tags and notes together) or two (folders and tags beside notes).
    @ViewBuilder private var splitView: some View {
        if model.browsingStyle == .twoColumns {
            // Tree and notes side by side inside one sidebar, so hiding, swiping and resizing
            // work exactly as in the single column. (SwiftUI's three-column split view on the
            // Mac won't hide both side columns from code.)
            NavigationSplitView(columnVisibility: $columns) {
                HSplitView {
                    PlaceTreeColumn()
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 320)
                    NoteList(includesPlaces: false)
                        .frame(minWidth: 200, idealWidth: 260)
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 470, max: 760)
                .background(widthReader { sidebarWidth = $0 })
            } detail: {
                detail
            }
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                NoteList()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                    .background(widthReader { sidebarWidth = $0 })
            } detail: {
                detail
            }
        }
    }

    private var detail: some View {
        Group {
            if let note = model.selectedNote {
                NoteEditor(note: note, model: model)
                    .id(note.id)
            } else {
                Text("No Note Selected")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func widthReader(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { update(geometry.size.width) }
                .onChange(of: geometry.size.width) { width in if width > 0 { update(width) } }
        }
    }

    private func updateColumns() {
        let visible = model.showsNoteList && !model.isFocused
        withAnimation(.easeOut(duration: 0.15)) { columns = visible ? .all : .detailOnly }
    }

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                splitView
                .navigationTitle(model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Imprint")
                .toolbar(model.isFocused ? .hidden : .visible, for: .windowToolbar)
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
                .onChange(of: model.showsNoteList) { showing in
                    guard !model.isFocused else { return updateColumns() }
                    // The text keeps its width: the window narrows or widens instead.
                    if showing {
                        // Widen first, by what was taken away, then bring the list back into
                        // the space. (In a narrow window the list would cover the note instead.)
                        NoteListWindowResizing.resize(by: narrowedBy)
                        narrowedBy = 0
                        updateColumns()
                    } else {
                        // Narrow by exactly the sidebar's width as it slides away.
                        narrowedBy = sidebarWidth
                        updateColumns()
                        NoteListWindowResizing.resize(by: -sidebarWidth)
                    }
                }

                .onChange(of: columns) { visibility in
                    // The toolbar's sidebar button changes the columns directly; keep ⌘S in step.
                    if !model.isFocused { model.showsNoteList = visibility != .detailOnly }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { model.startSwipeTracking() }
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
        .sheet(isPresented: $model.isChoosingTemplate) {
            TemplatePicker()
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
        .onReceive(NotificationCenter.default.publisher(for: .imprintAddProperty)) { _ in
            if model.selectedNote != nil { isAddingProperty = true }
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
