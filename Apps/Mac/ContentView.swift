import IndexKit
import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel
    @EnvironmentObject private var store: VaultStore
    @State private var isAddingProperty = false

    /// The sidebar and the notes, in the window's own split view (see `SidebarSplitController`).
    private var splitView: some View {
        let twoColumns = model.browsingStyle == .twoColumns
        return SidebarSplitView(
            controller: model.sidebarSplit,
            sidebar: AnyView(sidebar.environmentObject(model).environmentObject(store)),
            detail: AnyView(detail.environmentObject(model).environmentObject(store)),
            // Two columns start at half as wide again as one column, split 40/60 (see `sidebar`).
            widths: twoColumns ? (300, 360, 760) : (180, 240, 400),
            widthKey: twoColumns ? "sidebarWidth.twoColumns" : "sidebarWidth.singleColumn",
            showsSidebar: model.showsNoteList && !model.isFocused
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    /// One column (folders, tags and notes together) or two (folders and tags beside notes).
    @ViewBuilder private var sidebar: some View {
        Group {
            if model.browsingStyle == .twoColumns {
                // Tree and notes side by side inside one sidebar, so hiding, swiping and
                // resizing work exactly as in the single column.
                // 40/60, the notes wider, kept as the sidebar widens or narrows. (HSplitView
                // gave any extra width to the tree, so it started at half.) The columns, and
                // the divider between them, run to the window's top, under the top bar.
                // Each column has its own top bar; the notes scroll up beneath theirs.
                SideBySide(key: "treeColumnFraction", fraction: 0.4, minimumWidths: (120, 180)) {
                    PlaceTreeColumn()
                        .padding(.top, model.topBarHeight)
                        .overlay(alignment: .top) { SidebarTopBar() }
                } side: {
                    NoteList(includesPlaces: false)
                        .overlay(alignment: .top) { NoteListTopBar() }
                        // The notes in the page's colour, the tree alone in the sidebar's grey,
                        // and a line between the notes and the note (which share a colour).
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(alignment: .trailing) { HStack(spacing: 0) { Divider() } }
                }
            } else {
                VStack(spacing: 0) {
                    SidebarTopBar()
                    NoteList()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The notes: one pane, or two side by side, each with its own tabs.
    private var detail: some View {
        Group {
            // One side or two, in the same view, so the left side's note stays as it is when
            // the right side closes (and can slide to its new place).
            SideBySide(minimumWidths: model.notesSplitMinimums, showsSide: model.isSplit, sideDrawsDivider: true) {
                PaneView(paneID: model.panes[0].id)
            } side: {
                if model.isSplit {
                    SlidingSide(slideOffset: model.sideSlideOffset,
                                content: PaneView(paneID: model.panes[1].id)
                                    .environmentObject(model).environmentObject(store))
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Shows or hides the sidebar. Shown or hidden by hand (⌘S, the sidebar button, a swipe),
    /// the window widens or narrows by the sidebar's width so the notes keep theirs; in focus
    /// mode, when the window's width hid it, or where the window can't resize, the notes take
    /// the space instead.
    private func updateSidebar(resizingWindow: Bool) {
        model.sidebarSplit.setSidebar(shown: model.showsNoteList && !model.isFocused, resizingWindow: resizingWindow)
    }

    /// The note being worked on (in the active pane), else the vault's name.
    private var windowTitle: String {
        model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Point"
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
                // The window's toolbar holds only the system's sidebar button (the split view
                // controller adds it), which gives the top row its standard height and puts the
                // button where macOS does. No other toolbar items: an item, even an invisible
                // one, takes the clicks meant for the bars drawn in that row (the back and forward
                // arrows sat under one). The sidebar and each side draw their own bars there.
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
                        .help("Show note list")
                        .padding(.leading, 76)
                        .padding(.top, 2)
                    }
                }
                .onChange(of: model.searchFocusRequest) { _ in
                    if !model.showsNoteList { model.showsNoteList = true } // The filter needs the list.
                }
                .onChange(of: model.isFocused) { focused in
                    model.sidebarSplit.hidesSidebarButton = focused
                    updateSidebar(resizingWindow: false)
                }
                // Shown or hidden by hand, the window widens or narrows instead of the notes.
                .onChange(of: model.showsNoteList) { _ in
                    updateSidebar(resizingWindow: !model.lastToggleWasAutomatic && !model.isFocused)
                }
            }
        }
        // Minimal is meant to sit beside other windows, so it can be narrow.
        // With the sidebar hidden, a window is one compact note that can sit beside others.
        .modifier(WindowMinimum(model: model, slide: model.sidebarSlide))
        .onAppear {
            model.startSwipeTracking()
        }
        // After a rename or move: which notes' links were updated, for a moment.
        .overlay(alignment: .bottom) {
            if let update = store.linkUpdate {
                LinkUpdateNotice(update: update)
                    .id(update.id)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: store.linkUpdate)
        // After a change across the vault: what changed, with Undo, for a moment.
        .overlay(alignment: .bottom) {
            if let notice = store.vaultChangeNotice {
                VaultChangeNoticeView(notice: notice)
                    .id(notice.id)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: store.vaultChangeNotice)
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
        .sheet(item: $model.renamingAcrossVault) { rename in
            RenameAcrossVaultSheet(rename: rename, store: model.store, model: model)
        }
        .sheet(isPresented: $model.isShowingUnusedImages) {
            UnusedImagesSheet()
        }
        .sheet(item: $model.creatingFolder) { request in
            NewFolderSheet(parent: request.parent)
        }
        .sheet(isPresented: $model.isCreatingFromTemplate) {
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
        .onReceive(NotificationCenter.default.publisher(for: .pointAddProperty)) { notification in
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
            Text("Point")
                .font(.largeTitle.weight(.semibold))
            Text("Choose the folder that holds your notes.")
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Button("Open vault…") { model.chooseVault() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window's narrowest size: the notes' narrowest, plus the sidebar's width once it shows.
/// Not while it slides in: counted from the start, the window jumped to that width before the
/// slide began (the notes stretched to fill it), and the sidebar snapped to its full width at
/// the end. Only this watches the sliding, so nothing else redraws as it starts and stops.
private struct WindowMinimum: ViewModifier {
    @ObservedObject var model: VaultModel
    @ObservedObject var slide: SidebarSlide

    func body(content: Content) -> some View {
        content.frame(minWidth: slide.isSliding ? SidebarSplitController.minimumNotesWidth : model.minimumWindowWidth,
                      minHeight: 400)
    }
}

private struct NoteList: View {
    @EnvironmentObject private var model: VaultModel
    @FocusState private var searchFocused: Bool
    /// False in the two-column view, where folders and tags have their own column.
    var includesPlaces = true

    var body: some View {
        VStack(spacing: 0) {
            // In two columns, the name and sort are in the column's top bar (see
            // `NoteListTopBar`).
            if includesPlaces, model.place != .allNotes { PlaceHeader() }
            browser
        }
        // Floating at the foot, in glass, with the list going on beneath it.
        .overlay(alignment: .bottom) { filterField }
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

    /// The filter field's height and the space around it.
    private static let fieldHeight = VaultModel.SidebarDensity.comfortable.rowHeight
    private static let fieldPadding: CGFloat = 10

    /// Narrows the list to what's named with what's typed: in one column, the folders, tags
    /// and notes showing; in two, the notes, with how they're sorted on its right (in one
    /// column, that's in the Notes section's label). Searching the whole vault is the explorer's.
    private var filterField: some View {
        HStack(spacing: 8) {
            SearchField(text: $model.noteFilter, prompt: "Filter", isFocused: $searchFocused, height: Self.fieldHeight) {
                // Return opens the top note.
                if let first = model.sidebarRows(collapsed: [], content: content).lazy.compactMap(\.noteID).first { model.selection = first }
            }
            if !includesPlaces, model.place != .trash {
                // In glass too, a circle as tall as the field.
                SortButton(opensUpward: true)
                    .frame(width: Self.fieldHeight, height: Self.fieldHeight)
                    .modifier(NoticeBackground())
            }
        }
        .padding(Self.fieldPadding)
    }

    private var content: SidebarTable.Content { includesPlaces ? .everything : .notes }

    /// Whether the list shows places as well as notes: always in one column, and in two for the
    /// lists of tags and types, which are places.
    private var listsPlaces: Bool { includesPlaces || model.place == .types || model.place == .tags }

    /// Pins, folders (or nested tags), tags and notes for the current place.
    private var browser: some View {
        SidebarTable(model: model, content: content, bottomInset: Self.fieldHeight + Self.fieldPadding * 2)
            .overlay {
                if model.place == .trash ? model.store.trashedNotes.isEmpty : model.notes(in: model.place).isEmpty, model.store.images(in: model.place).isEmpty, !listsPlaces || model.subplaces(of: model.place).isEmpty, model.place != .allNotes {
                    if let message = emptyMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                } else if !model.noteFilter.isEmpty, !model.sidebarRows(collapsed: [], content: content).contains(where: \.isItem) {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                }
            }
    }
}

extension NoteList {
    /// What an empty place says, or nothing while the index is still being asked.
    fileprivate var emptyMessage: String? {
        switch model.place {
        case .tag: return "No notes have this tag."
        case .properties: return "No notes have properties."
        case .types: return "No notes have a type."
        case .tags: return "No notes have tags."
        case .trash: return "The trash is empty."
        case .lists: return "No notes are lists."
        case .property, .propertyValue, .kind:
            guard let query = model.place.query, model.store.noteIDs(matching: query) != nil else { return nil }
            if case .property = model.place { return "No notes have this property." }
            if case .kind = model.place { return "No notes are of this type." }
            return "No notes have this value."
        default: return "This folder has no notes."
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
            Text(model.title(for: model.place))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if model.place == .lists {
                Button { model.createList() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New list")
            }
            if model.place == .trash {
                EmptyTrashButton()
            } else if model.place != .everything && model.place != .bookmarks {
                Button { model.togglePin(model.place) } label: {
                    Image(systemName: model.isPinned(model.place) ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.isPinned(model.place) ? "Unpin" : "Pin to the top of the sidebar")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

/// Empties the trash, after asking: the notes in it go for good.
struct EmptyTrashButton: View {
    @EnvironmentObject private var model: VaultModel
    @State private var isConfirming = false

    var body: some View {
        Button("Empty") { isConfirming = true }
            .buttonStyle(.borderless)
            .disabled(model.trashedNotes.isEmpty)
            .help("Delete every note in the trash now")
            .confirmationDialog("Delete the \(model.trashedNotes.count) notes in the trash for good?", isPresented: $isConfirming) {
                Button("Empty trash", role: .destructive) { model.store.emptyTrash() }
            } message: {
                Text("This can't be undone.")
            }
    }
}

extension SidebarPlace {
    var isTag: Bool {
        if case .tag = self { return true }
        return false
    }

    /// "Work", "Projects" or "work/imprint" (a tag without its "#": its symbol says it's a tag).
    var title: String {
        switch self {
        case .allNotes: "All notes"
        case .folder(let path): FolderTree.name(of: path)
        case .tag(let tag): tag
        case .everything: "All notes"
        case .bookmarks: "Bookmarks"
        case .trash: "Trash"
        case .properties: "Properties"
        case .property(let name): name
        case .propertyValue(_, let value): PropertyValueText.shown(value)
        case .types: "Types"
        case .tags: "Tags"
        case .kind(_, let name): NoteKinds.plural(name)
        case .lists: "Lists"
        }
    }

    /// The last part only: "imprint" for work/imprint, under its parent in the tag list.
    var shortName: String {
        switch self {
        case .tag(let tag): tag.split(separator: "/").last.map(String.init) ?? tag
        default: title
        }
    }
}

/// The filter field at the foot of the sidebar's list.
private struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var isFocused: FocusState<Bool>.Binding
    /// The sidebar's row height, so the field is as tall as a selected row.
    let height: CGFloat
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
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
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .modifier(NoticeBackground())
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename note")
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

/// Renames a property, a value or a tag in every note that has it.
/// The images no note shows, found from the index: each can be shown in the Finder, and all
/// moved to the Trash, from where the Finder can put them back.
private struct UnusedImagesSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var images: [VaultImage]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unused images")
                .font(.headline)
            Group {
                if let images, images.isEmpty {
                    Text("Every image in the vault is shown in a note.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let images {
                    List(images) { image in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(image.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text((image.path as NSString).deletingLastPathComponent.isEmpty ? "Top of the vault" : (image.path as NSString).deletingLastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                                .buttonStyle(.link)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 440, height: 280)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 440, alignment: .leading)
            HStack {
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    if let images { model.store.trashUnusedImages(images) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(images?.isEmpty ?? true)
            }
        }
        .padding(20)
        .task { images = await model.store.unusedImages() }
    }

    private var detail: String {
        guard let images, !images.isEmpty else { return "No note embeds or links to these." }
        let count = images.count == 1 ? "This image isn’t" : "These \(images.count) images aren’t"
        return "\(count) embedded or linked in any note. Moved to the Trash, they can be put back from the Finder."
    }
}

/// Renames a tag or property, or changes a value, in every note: from the sidebar, or a
/// property from Settings (with no window to follow it in).
struct RenameAcrossVaultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rename: VaultStore.VaultRename
    let store: VaultStore
    var model: VaultModel?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
            TextField("Name", text: $name)
                .frame(width: 320)
                .onSubmit(apply)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isValue ? "Change" : "Rename", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == rename.current)
            }
        }
        .padding(20)
        .onAppear { name = rename.current }
    }

    private var isValue: Bool {
        if case .value = rename { return true }
        return false
    }

    private var heading: String {
        switch rename {
        case .property: "Rename property"
        case .value(let name, _): "Change value of \(name)"
        case .tag: "Rename tag"
        }
    }

    private var place: SidebarPlace {
        switch rename {
        case .property(let name): .property(name)
        case .value(let name, let value): .propertyValue(name, value)
        case .tag(let tag): .tag(tag)
        }
    }

    private var detail: String {
        let count = store.noteCount(of: place)
        let notes = count == 1 ? "1 note" : "\(count) notes"
        return switch rename {
        case .property: "Renamed in \(notes). Their values stay as they are."
        case .value: "Changed in \(notes)."
        case .tag: "Renamed in \(notes), and tags inside it too."
        }
    }

    private func apply() {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != rename.current else { return }
        dismiss()
        store.rename(rename, to: new)
        // Listed in the sidebar: listed by its new name.
        if case .property(let old) = rename, store.showsInSidebar(property: old) {
            store.sidebarProperties = store.sidebarProperties.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }
        // Still browsing what was renamed: follow it to its new name.
        guard let model else { return }
        switch (rename, model.place) {
        case (.property(let old), .property(let current)) where old == current: model.browse(.property(new))
        case (.value(let property, let old), .propertyValue(let name, let current)) where old == current && property == name:
            model.browse(.propertyValue(property, new))
        case (.tag(let old), .tag(let current)) where old.lowercased() == current.lowercased(): model.browse(.tag(new))
        default: break
        }
    }
}

private struct NewFolderSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let parent: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New folder")
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

/// Choosing a template to start a new note from, with a name. (Applying one to a note is
/// done in the palette.)
private struct TemplatePicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?
    @State private var name = ""

    /// The sheet's width; everything in it spans it, inside even margins.
    private static let width: CGFloat = 400
    private static let margin: CGFloat = 20

    var body: some View {
        let templates = model.templates
        let density = model.sidebarDensity
        VStack(alignment: .leading, spacing: 14) {
            Text("New note from template")
                .font(.headline)
            if templates.isEmpty {
                Text(model.settings.templatesFolder.isEmpty
                     ? "No templates folder is set. Choose one in Settings, under Templates."
                     : "There are no templates in “\(model.settings.templatesFolder)”.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // As the sidebar's list: its row size (compact or comfortable) and its selection.
                List(templates, id: \.url, selection: $selection) { template in
                    Label(template.name, systemImage: "doc.text")
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .environment(\.sidebarRowSize, density == .compact ? .small : .medium)
                .contextMenu(forSelectionType: URL.self, menu: { _ in }, primaryAction: { _ in choose() })
                // As tall as its rows, up to about eight; then it scrolls.
                .frame(height: min(CGFloat(templates.count), 8) * density.rowHeight + 16)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
                .onAppear { selection = templates.first?.url }
                TextField("Name (or leave it to the first line)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(choose)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: choose)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(Self.margin)
        .frame(width: Self.width)
    }

    private func choose() {
        guard let selection else { return }
        dismiss()
        model.createNote(fromTemplate: selection, titled: name)
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
            // The rows' edges on the field's, their icons where its text starts.
            List(folders, id: \.self, selection: $selection) { folder in
                Label(folder.isEmpty ? "Vault (top level)" : folder, systemImage: "folder")
                    .lineLimit(1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: 260)
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
        .frame(width: 400)
        .onChange(of: filter) { _ in selection = folders.first }
    }

    private func move() {
        guard let selection else { return }
        dismiss()
        model.move(noteID: note.id, toFolder: selection)
    }
}

/// "Updated links in 12 notes", after a rename or move. Click it to see which (each opens);
/// it goes after a few seconds, unless the pointer is on it or it's open.
private struct LinkUpdateNotice: View {
    @EnvironmentObject private var model: VaultModel
    @EnvironmentObject private var store: VaultStore
    let update: VaultStore.LinkUpdate
    @State private var isShowingNotes = false
    @State private var isHovering = false

    var body: some View {
        Button { isShowingNotes.toggle() } label: {
            Label(text, systemImage: "link")
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(NoticeBackground())
        .onHover { isHovering = $0 }
        .help("Show the notes")
        .popover(isPresented: $isShowingNotes, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(update.notes, id: \.self) { id in
                    Button(model.note(id)?.title ?? (id as NSString).deletingPathExtension) {
                        model.selection = id
                        isShowingNotes = false
                    }
                    .buttonStyle(.link)
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
            .frame(minWidth: 220, maxHeight: 360, alignment: .topLeading)
        }
        .task(id: update.id) { await dismissLater() }
    }

    private var text: String {
        update.notes.count == 1 ? "Updated the link in 1 note" : "Updated links in \(update.notes.count) notes"
    }

    private func dismissLater() async {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        while isHovering || isShowingNotes {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
        if store.linkUpdate?.id == update.id { store.linkUpdate = nil }
    }
}

/// "Renamed #work to #job in 12 notes", with Undo; it goes after a few seconds, unless the
/// pointer is on it.
private struct VaultChangeNoticeView: View {
    @EnvironmentObject private var store: VaultStore
    let notice: VaultStore.VaultChangeNotice
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            if notice.isWorking {
                ProgressView().controlSize(.small)
                Text(notice.text)
            } else {
                Label(notice.text, systemImage: notice.symbol)
            }
            if notice.canUndo, store.lastVaultChange != nil {
                Button("Undo") { store.undoLastVaultChange() }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .modifier(NoticeBackground())
        .onHover { isHovering = $0 }
        .task(id: notice.id) {
            if notice.isWorking { return } // Replaced when the work is done.
            try? await Task.sleep(nanoseconds: notice.canUndo ? 8_000_000_000 : 3_000_000_000)
            while isHovering {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
            if store.vaultChangeNotice?.id == notice.id { store.vaultChangeNotice = nil }
        }
    }
}

/// Glass on macOS 26, a material before.
private struct NoticeBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}

/// The `#tag` words in a search, which filter its results by tag.
enum SearchTags {
    static func tags(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
    }

    static func removing(_ tag: String, from query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).filter { $0 != "#" + tag }.joined(separator: " ")
    }
}

/// A property value as the sidebar names it: a link without its brackets.
enum PropertyValueText {
    static func shown(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return trimmed.isEmpty ? "Empty" : trimmed }
        let inside = String(trimmed.dropFirst(2).dropLast(2))
        return inside.split(separator: "|", maxSplits: 1).last.map(String.init) ?? inside
    }
}
