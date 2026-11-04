import IndexKit
import SwiftUI
import VaultKit

/// Where the app can go: a note, or one of the lists of notes.
enum Route: Hashable {
    case note(Note.ID)
    case notes, bookmarks, recent
    case tag(String)
    case folder(String)
    case deleted
}

/// Home, as the Notes app's list of folders: All notes, Bookmarks and Recent, each a page of its
/// own; the vault's folders; then its tags; then Deleted Notes. Settings at the top right; along the bottom, on every
/// list, Sort (where the list can be sorted), the system's search field and the actions for
/// where you are.
struct HomeScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @ObservedObject private var quickActions = QuickActions.shared
    @State private var path: [Route] = []
    /// The note just made with New Note, which opens with the cursor in its title.
    @State private var newNote: Note.ID?
    @State private var showsSettings = false
    /// Whether the note being worked on has had its chance to reopen, once, at launch.
    @State private var hasResumed = false
    /// New Folder: where it goes ("" for the top level), and the name being typed.
    @State private var newFolderParent: String?
    @State private var newFolderName = ""
    @State private var folderProblem: String?
    /// The folder being moved, while choosing where to.
    @State private var movingFolder: String?
    @State private var moveProblem: String?

    var body: some View {
        NavigationStack(path: $path) {
            home
                .pageTitle("Point")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Route.self, destination: destination)
                .refreshable { await store.reload() }
                .toolbar {
                    // Not on Search, which is over the page.
                    if !store.isSearching {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Settings", systemImage: "gear") { showsSettings = true }
                        }
                    }
                }
                .pageBar(.sort) { topLevelActions }
        }
        .alert("New Folder", isPresented: Binding(get: { newFolderParent != nil }, set: { if !$0 { newFolderParent = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create", action: createFolder)
        } message: {
            Text(newFolderParent.map { $0.isEmpty ? "At the top level." : "Inside “\(($0 as NSString).lastPathComponent)”." } ?? "")
        }
        .alert("Couldn’t Make the Folder", isPresented: Binding(get: { folderProblem != nil }, set: { if !$0 { folderProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(folderProblem ?? "")
        }
        .alert("Couldn’t Move the Folder", isPresented: Binding(get: { moveProblem != nil }, set: { if !$0 { moveProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveProblem ?? "")
        }
        .sheet(isPresented: Binding(get: { movingFolder != nil }, set: { if !$0 { movingFolder = nil } })) {
            if let movingFolder {
                FolderPicker(title: "Move Folder", current: FolderTree.parent(of: movingFolder), moving: movingFolder) { moveFolder(movingFolder, into: $0) }
                    .environmentObject(store)
            }
        }
        .alert("Couldn’t Delete the Note", isPresented: Binding(get: { store.trashProblem != nil }, set: { if !$0 { store.trashProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.trashProblem ?? "")
        }
        .alert("Open This Link?", isPresented: Binding(get: { store.linkToConfirm != nil }, set: { if !$0 { store.linkToConfirm = nil } }),
               presenting: store.linkToConfirm) { url in
            Button("Cancel", role: .cancel) {}
            Button("Open") { store.openConfirmed(url) }
        } message: { url in
            Text(url.absoluteString.count > 200 ? String(url.absoluteString.prefix(200)) + "…" : url.absoluteString)
        }
        .alert("No App Opens This Link", isPresented: $store.linkDidNotOpen) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showsSettings) { SettingsScreen().environmentObject(store) }
        .onChange(of: quickActions.newNoteRequests) { _, _ in quickNote() }
        .onChange(of: store.linkedRoute) { _, route in
            guard let route else { return }
            store.linkedRoute = nil
            go(to: route)
        }
        .onAppear { if quickActions.newNoteRequests > 0 { quickNote() } }
        .onChange(of: path) { _, path in
            // Home, or another note: that's the end of coming back to this one.
            guard let working = store.workingOn?.note.id else { return }
            if case .note(let id)? = path.last, store.currentID(id) == working { return }
            store.stopWorking()
        }
        .onChange(of: store.notes) { _, notes in
            if !hasResumed, !notes.isEmpty {
                hasResumed = true
                if path.isEmpty, let id = store.resumeWorking() { path = [.note(id)] }
            }
            // `-SpikeTypeTest YES` opens the long note by itself, to time typing in it.
            if UserDefaults.standard.bool(forKey: "SpikeTypeTest"), path.isEmpty,
               let long = notes.first(where: { $0.title == PhoneVault.longTitle }) {
                path = [.note(long.id)]
            }
        }
    }

    /// At the top level, and on the pages that aren't a place of their own.
    @ViewBuilder private var topLevelActions: some View {
        newNoteButton(in: "")
        newFolderButton(in: "")
    }

    private func newNoteButton(in folder: String) -> some View {
        Button("New Note", systemImage: "square.and.pencil") { createNote(in: folder) }
    }

    private func newFolderButton(in parent: String) -> some View {
        Button("New Folder", systemImage: "folder.badge.plus") {
            newFolderName = ""
            newFolderParent = parent
        }
    }

    private var home: some View {
        List {
            Section {
                NavigationLink(value: Route.notes) { PlaceRow(title: "All notes", symbol: "doc.text", count: store.notes.count) }
                NavigationLink(value: Route.bookmarks) { PlaceRow(title: "Bookmarks", symbol: "bookmark", count: store.bookmarks.count) }
                NavigationLink(value: Route.recent) { PlaceRow(title: "Recent", symbol: "clock", count: nil) }
            }
            let folders = store.sorted(folders: store.subfolders(of: ""))
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                    }
                }
            }
            let tags = store.sorted(tags: store.tags)
            if !tags.isEmpty {
                // Nested tags under their parents.
                Section("Tags") {
                    ForEach(tags, id: \.tag) { entry in
                        NavigationLink(value: Route.tag(entry.tag)) {
                            let depth = entry.tag.split(separator: "/").count - 1
                            PlaceRow(title: depth > 0 ? String(entry.tag.split(separator: "/").last ?? "") : entry.tag,
                                     symbol: symbol("number.sign.circle", or: "number.circle"), count: entry.count)
                                .padding(.leading, CGFloat(depth) * 20)
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: Route.deleted) { PlaceRow(title: "Deleted Notes", symbol: "trash", count: store.deletedNotes.count) }
            }
        }
        .overlay { if store.notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text",
            description: Text("Copy notes into Point’s folder in the Files app.")) } }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .note(let id):
            // By its ID now: renamed from its title, it keeps its screen.
            if let note = store.note(store.currentID(id)) {
                NoteScreen(note: note, store: store, isNew: id == newNote) { folder in createNote(in: folder) }
            }
        case .notes: NotesScreen().pageBar(.sort) { topLevelActions }
        case .bookmarks: BookmarksScreen().pageBar { topLevelActions }
        case .recent: RecentScreen().pageBar { topLevelActions }
        case .tag(let tag):
            TagScreen(tag: tag).pageBar(.sort) {
                Button("New Note", systemImage: "square.and.pencil") {
                    createNote(text: Frontmatter.edit(adding: "tags", values: [tag], isList: true).1)
                }
            }
        case .folder(let folder):
            FolderScreen(folder: folder).pageBar(.sort) {
                newNoteButton(in: folder)
                newFolderButton(in: folder)
                Button("Move Folder", systemImage: "folder") { movingFolder = folder }
            }
        case .deleted: DeletedNotesScreen()
        }
    }

    /// Back to a route if it's open already, or on to it.
    private func go(to route: Route) {
        if let index = path.firstIndex(of: route) {
            path.removeSubrange((index + 1)...)
        } else {
            path.append(route)
        }
    }

    private func createFolder() {
        guard let parent = newFolderParent else { return }
        newFolderParent = nil
        do {
            _ = try store.createFolder(named: newFolderName, in: parent)
        } catch {
            folderProblem = error.localizedDescription
        }
    }

    /// Moves a folder, and the page showing it with it.
    private func moveFolder(_ folder: String, into parent: String) {
        do {
            let new = try store.moveFolder(folder, into: parent)
            path = path.map { route in
                guard case .folder(let open) = route, open == folder || open.hasPrefix(folder + "/") else { return route }
                return .folder(new + open.dropFirst(folder.count))
            }
        } catch {
            moveProblem = error.localizedDescription
        }
    }

    /// Makes a note and opens it, on top of the page you're on. A new note still untitled goes
    /// from under it: left, it may go altogether.
    private func createNote(in folder: String = "", text: String = "") {
        guard let id = store.createNote(in: folder, text: text) else { return }
        newNote = id
        if case .note(let below)? = path.last, store.isUntitled(store.currentID(below)) { path.removeLast() }
        path.append(.note(id))
    }

    /// Makes a note and opens it straight from home, from wherever you were.
    private func quickNote() {
        guard let id = store.createNote() else { return }
        newNote = id
        path = [.note(id)]
    }

    /// Today's time, this week's day, or an older date, as on the Mac.
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// Every note, in the chosen order.
struct NotesScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let notes = store.notes.sorted(by: store.sort)
        List { NoteSections(notes: notes) }
            .pageTitle("All notes")
            .overlay { if notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text") } }
    }
}

/// Bookmarks: Obsidian's, in its order. Drag to reorder; long-press to remove.
struct BookmarksScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        List {
            ForEach(store.bookmarks, id: \.path) { bookmark in
                if let note = store.note(bookmark.path) {
                    NoteLink(note: note, title: bookmark.title)
                }
            }
            .onMove(perform: store.moveBookmarks)
        }
        .pageTitle("Bookmarks")
        .overlay { if store.bookmarks.isEmpty { ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
            description: Text("Press and hold a note to bookmark it.")) } }
    }
}

/// Every note, the most recently edited or opened first, under date headings.
struct RecentScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let groups = store.recentGroups
        List {
            ForEach(groups, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.notes) { note in NoteLink(note: note) }
                }
            }
        }
        .pageTitle("Recent")
        .overlay { if groups.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text") } }
    }
}

/// A tag's notes, in the chosen order.
struct TagScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let tag: String

    var body: some View {
        let notes = store.notes(taggedWith: tag)
        List { NoteSections(notes: notes) }
            .pageTitle("#" + tag)
            .overlay { if notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text") } }
    }
}

/// A folder: the folders inside it, then its notes.
struct FolderScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let folder: String

    var body: some View {
        let folders = store.sorted(folders: store.subfolders(of: folder))
        let notes = store.notes(in: folder)
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                    }
                }
            }
            NoteSections(notes: notes)
        }
        .pageTitle((folder as NSString).lastPathComponent)
        .overlay { if folders.isEmpty && notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "folder") } }
    }
}

/// The notes in the vault's trash, the latest deleted first: put back, or deleted for good. The
/// Mac's Trash, and Obsidian's.
struct DeletedNotesScreen: View {
    @EnvironmentObject private var store: PhoneStore
    /// The note tapped, to put back or delete.
    @State private var chosen: VaultTrash.Item?
    @State private var confirmsDeleteAll = false

    var body: some View {
        List {
            Section {
                ForEach(store.deletedNotes) { item in
                    Button { chosen = item } label: { row(item) }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .leading) {
                            Button("Put Back", systemImage: "arrow.uturn.backward") { store.restore(item) }
                                .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing) {
                            // Asks first: it's for good.
                            Button("Delete", systemImage: "trash") { chosen = item }
                                .tint(.red)
                        }
                }
            } footer: {
                if !store.deletedNotes.isEmpty {
                    Text("Notes stay here for \(PhoneStore.keepsDeletedNotesDays) days, then go for good. Notes deleted in Obsidian stay until they’re deleted here.")
                }
            }
        }
        .pageTitle("Deleted Notes")
        .overlay { if store.deletedNotes.isEmpty { ContentUnavailableView("No Deleted Notes", systemImage: "trash") } }
        .onAppear { store.refreshTrash() }
        .confirmationDialog(chosen?.title ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { item in
            Button("Put Back") { store.restore(item) }
            Button("Delete Now", role: .destructive) { store.deleteForever(item) }
        } message: { _ in
            Text("Deleting it now can’t be undone.")
        }
        .confirmationDialog("Delete the \(store.deletedNotes.count) deleted notes for good?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.deleteAllForever() }
        }
        .alert("Deleted Notes", isPresented: Binding(get: { store.deletedNotesProblem != nil }, set: { if !$0 { store.deletedNotesProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.deletedNotesProblem ?? "")
        }
        .pageBar {
            Button("Delete All", systemImage: "trash", role: .destructive) { confirmsDeleteAll = true }
                .disabled(store.deletedNotes.isEmpty)
        }
    }

    /// Its title, where it was and when it was deleted.
    private func row(_ item: VaultTrash.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
            Text(subtitle(item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ item: VaultTrash.Item) -> String {
        let when = HomeScreen.label(for: item.deleted)
        guard let folder = item.folder, !folder.isEmpty else { return when }
        return "\(when) · \((folder as NSString).lastPathComponent)"
    }
}

/// A symbol, or for systems without it, the nearest they have.
func symbol(_ name: String, or older: String) -> String {
    UIImage(systemName: name) == nil ? older : name
}

/// What goes at the left of a page's bottom bar: on a list that can be sorted, Sort; in a note,
/// finding in it, in place of search.
enum PageTool {
    case none, sort
    case find(() -> Void)
}

/// What every page has along the bottom, as Apple's own apps have it: at the left, Sort or Find
/// (`PageTool`); on a list, the system's search field, with Search over the page while it's in
/// use; and at the right, a menu of what can be done here.
private struct PageBar<Actions: View>: ViewModifier {
    @EnvironmentObject private var store: PhoneStore
    let tool: PageTool
    @ViewBuilder let actions: Actions

    func body(content: Content) -> some View {
        switch tool {
        case .find(let find):
            // A note: finding in it, not searching the vault.
            content.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Find in Note", systemImage: "text.page.badge.magnifyingglass", action: find)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { menu }
            }
        case .none, .sort:
            content
                // The page stays its size under the keyboard: shrunk, the rows below were left
                // undrawn, and showed blank as the keyboard went down.
                .ignoresSafeArea(.keyboard)
                .overlay { SearchScreen() }
                .searchable(text: $store.searchText, prompt: "Search")
                // The navigation bar isn't hidden by the system while searching: it went at once,
                // without animating, and the page jumped up under Search as it faded in. It stays,
                // with the page's title and Settings left out meanwhile.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .toolbar {
                    if case .sort = tool {
                        ToolbarItem(placement: .bottomBar) { SortMenu() }
                        ToolbarSpacer(.fixed, placement: .bottomBar)
                    }
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { menu }
                }
        }
    }

    private var menu: some View {
        Menu("Actions", systemImage: symbol("text.menu", or: "line.3.horizontal")) { actions }
            // In the order given, top to bottom: from the bottom bar, the system would turn it
            // over, putting the first item nearest the thumb.
            .menuOrder(.fixed)
    }
}

/// A page's title, which Search, over the page, goes without. The large title is the page's own,
/// to fade with Search: emptying the system's wiped it back in, out of step. The system's is
/// still set, for the back button and the small title on scrolling; that one is emptied while
/// searching (a small title of the page's own showed under the large one all the time).
private struct PageTitle: ViewModifier {
    @EnvironmentObject private var store: PhoneStore
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.isSearching ? "" : title)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(store.isSearching ? 0 : 1)
                }
            }
    }
}

extension View {
    func pageTitle(_ title: String) -> some View { modifier(PageTitle(title: title)) }

    /// `tool` is what goes at the bar's left.
    func pageBar<Actions: View>(_ tool: PageTool = .none, @ViewBuilder actions: () -> Actions) -> some View {
        modifier(PageBar(tool: tool, actions: actions))
    }
}

/// Where a note or a folder can move to: the top level, or any folder but the one it's in (and,
/// for a folder, not itself or anything inside it).
struct FolderPicker: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let current: String
    var moving: String?
    let pick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                row("Top Level", folder: "", depth: 0)
                ForEach(tree(of: "", depth: 0), id: \.folder) { row(FolderTree.name(of: $0.folder), folder: $0.folder, depth: $0.depth) }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemBackground))
    }

    private func tree(of parent: String, depth: Int) -> [(folder: String, depth: Int)] {
        store.subfolders(of: parent).filter { $0 != moving }.flatMap { [($0, depth)] + tree(of: $0, depth: depth + 1) }
    }

    private func row(_ name: String, folder: String, depth: Int) -> some View {
        Button {
            pick(folder)
            dismiss()
        } label: {
            Label(name, systemImage: "folder")
                .padding(.leading, CGFloat(depth) * 20)
        }
        .foregroundStyle(.primary)
        .disabled(folder == current)
    }
}

/// Notes in the chosen order: under date headings, or, sorted by title, together with each
/// note's date below its title.
private struct NoteSections: View {
    @EnvironmentObject private var store: PhoneStore
    let notes: [Note]

    var body: some View {
        if store.sort == .title {
            if !notes.isEmpty {
                Section {
                    ForEach(notes) { note in NoteLink(note: note, detail: HomeScreen.label(for: note.modified)) }
                }
            }
        } else {
            ForEach(NoteDateGroup.grouped(notes, by: store.sort), id: \.label) { group in
                Section(group.label) {
                    ForEach(group.notes) { note in NoteLink(note: note) }
                }
            }
        }
    }
}

/// How the note lists are sorted, as on the Mac.
private struct SortMenu: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Sort", selection: $store.sort) {
                Text("Date Edited").tag(NoteSort.modified)
                Text("Date Created").tag(NoteSort.created)
                Text("Title").tag(NoteSort.title)
            }
        }
    }
}

/// A note in a list, with a bookmark on long-press.
private struct NoteLink: View {
    @EnvironmentObject private var store: PhoneStore
    let note: Note
    var title: String?
    var detail: String?

    var body: some View {
        NavigationLink(value: Route.note(note.id)) {
            NoteRow(title: title ?? note.title, detail: detail)
        }
        .contextMenu {
            let bookmarked = store.isBookmarked(note.id)
            Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                store.toggleBookmark(note.id)
            }
        }
    }
}

/// Bookmarks, Recent, Tags, or a tag: its symbol, its name, and how many.
private struct PlaceRow: View {
    let title: String
    let symbol: String
    let count: Int?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let count {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var store: PhoneStore
    let folder: String

    var body: some View {
        PlaceRow(title: (folder as NSString).lastPathComponent, symbol: "folder", count: store.noteCount(inFolder: folder))
    }
}

/// A note's title, as many lines as it needs, and anything to say below it.
struct NoteRow: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
