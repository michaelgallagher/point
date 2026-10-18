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
    /// How much the window widened to fit a side note.
    @State private var widenedForSide: CGFloat = 0
    /// Whether the side note shows. It follows the model's side note, but only once the
    /// window has widened, so the split never squeezes the sidebar.
    @State private var showsSide = false
    /// Narrower than this, two notes side by side are too cramped, so the window widens.
    private let sideBySideWidth: CGFloat = 760

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
                .toolbar { newNoteButton }
            } detail: {
                detail
            }
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                NoteList()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                    .background(widthReader { sidebarWidth = $0 })
                    .toolbar { newNoteButton }
            } detail: {
                detail
            }
        }
    }

    private var detail: some View {
        Group {
            if showsSide, let side = model.sideNoteValue {
                // Two equal notes, each with its title above it, so neither is
                // the window's "real" note.
                SideBySide {
                    if let main = model.selectedNote {
                        NotePane(note: main, isSide: false)
                    } else {
                        mainEditor
                    }
                } side: {
                    NotePane(note: side, isSide: true)
                }
            } else {
                mainEditor
            }
        }
        .onChange(of: model.sideNote != nil) { isSplit in
            if isSplit {
                // The notes get what the sidebar (if showing) leaves.
                let listWidth = columns == .detailOnly ? 0 : sidebarWidth
                widenedForSide = max(0, listWidth + sideBySideWidth - (model.window?.frame.width ?? 0))
                NoteListWindowResizing.resize(model.window, by: widenedForSide)
                DispatchQueue.main.asyncAfter(deadline: .now() + (widenedForSide > 1 ? 0.17 : 0)) {
                    showsSide = model.sideNote != nil
                }
            } else {
                showsSide = false
                NoteListWindowResizing.resize(model.window, by: -widenedForSide)
                widenedForSide = 0
            }
        }
    }

    @ViewBuilder private var mainEditor: some View {
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

    /// In the sidebar's part of the toolbar, beside the button that hides it.
    private var newNoteButton: some ToolbarContent {
        ToolbarItem {
            Button { model.createNote() } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .help("New Note (⌘N)")
        }
    }

    /// The note's title, or with two notes open (each titled above itself), the vault's name.
    private var windowTitle: String {
        if showsSide, model.sideNote != nil { return model.root?.lastPathComponent ?? "Imprint" }
        return model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Imprint"
    }

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                splitView
                .navigationTitle(windowTitle)
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
                        NoteListWindowResizing.resize(model.window, by: narrowedBy)
                        narrowedBy = 0
                        updateColumns()
                    } else {
                        // Narrow by exactly the sidebar's width as it slides away.
                        narrowedBy = sidebarWidth
                        updateColumns()
                        NoteListWindowResizing.resize(model.window, by: -sidebarWidth)
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

/// Two views side by side with a divider to drag between them. Unlike HSplitView, it
/// takes only the width it's offered, so it never squeezes the sidebar.
private struct SideBySide<Main: View, Side: View>: View {
    @ViewBuilder let main: Main
    @ViewBuilder let side: Side
    /// How much of the width the main note gets.
    @AppStorage("sideBySideFraction") private var fraction = 0.5
    @State private var isHoveringDivider = false
    private let minimumWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let mainWidth = clamp(width * fraction, in: width)
            HStack(spacing: 0) {
                main
                    .frame(width: mainWidth)
                Divider()
                    .overlay {
                        // A wider grip than the line itself.
                        Color.clear
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("sideBySide"))
                                .onChanged { value in
                                    guard width > 0 else { return }
                                    fraction = clamp(value.location.x, in: width) / width
                                })
                    }
                side
                    .frame(maxWidth: .infinity)
            }
        }
        .coordinateSpace(name: "sideBySide")
    }

    private func clamp(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        guard width > minimumWidth * 2 else { return width / 2 }
        return min(max(x, minimumWidth), width - minimumWidth)
    }
}

/// One of two notes side by side: its title, a button to close it, and the note.
/// Closing either leaves the other as the window's only note.
private struct NotePane: View {
    @EnvironmentObject private var model: VaultModel
    let note: Note
    let isSide: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    if isSide { model.closeSideNote() } else { model.closeMainNote() }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close This Note")
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
            Divider()
            NoteEditor(note: note, model: model, isSide: isSide)
                .id((isSide ? "side:" : "") + note.id)
        }
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
