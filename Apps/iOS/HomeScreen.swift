import IndexKit
import SwiftUI
import VaultKit

/// Where the app can go: a note, or one of the lists of notes.
enum Route: Hashable {
    case note(Note.ID)
    case bookmarks, recent, tags
    case tag(String)
    case folder(String)
}

/// Home, as the Notes app's list of folders: Bookmarks, Recent and Tags, each a page of its
/// own; the vault's folders; then the notes at its top level. Settings at the top right; along
/// the bottom, the system's toolbar, with Add (a note or a folder) on the left and search on
/// the right.
/// Searching shows results in place.
struct HomeScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @ObservedObject private var quickActions = QuickActions.shared
    @State private var path: [Route] = []
    /// The note just made with New Note, which opens with the cursor in its title.
    @State private var newNote: Note.ID?
    @State private var showsSettings = false
    /// New Folder: where it goes ("" for the top level), and the name being typed.
    @State private var newFolderParent: String?
    @State private var newFolderName = ""
    @State private var folderProblem: String?

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Route.self, destination: destination)
                .searchable(text: $store.searchText, prompt: "Search")
                .searchToolbarBehavior(.minimize)
                .refreshable { await store.reload() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gear") { showsSettings = true }
                    }
                }
                .toolbar { bottomBar() }
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
        .sheet(isPresented: $showsSettings) { SettingsScreen().environmentObject(store) }
        .onChange(of: quickActions.newNoteRequests) { _, _ in createNote() }
        .onAppear { if quickActions.newNoteRequests > 0 { createNote() } }
        .onChange(of: store.notes) { _, notes in
            // `-SpikeTypeTest YES` opens the long note by itself, to time typing in it.
            if UserDefaults.standard.bool(forKey: "SpikeTypeTest"), path.isEmpty,
               let long = notes.first(where: { $0.title == PhoneVault.longTitle }) {
                path = [.note(long.id)]
            }
        }
    }

    /// Add (a note, or a folder where you are) on the left, search on the right, on every page.
    @ToolbarContentBuilder private func bottomBar(in folder: String = "") -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu("Add", systemImage: "plus") {
                Button("New Note", systemImage: "square.and.pencil", action: createNote)
                Button("New Folder", systemImage: "folder.badge.plus") {
                    newFolderName = ""
                    newFolderParent = folder
                }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
    }

    @ViewBuilder private var home: some View {
        if let results = store.searchResults {
            SearchResults(results: results, searchText: store.searchText)
        } else {
            List {
                Section {
                    NavigationLink(value: Route.bookmarks) { PlaceRow(title: "Bookmarks", symbol: "bookmark", count: store.bookmarks.count) }
                    NavigationLink(value: Route.recent) { PlaceRow(title: "Recent", symbol: "clock", count: nil) }
                    NavigationLink(value: Route.tags) { PlaceRow(title: "Tags", symbol: "number", count: store.tags.count) }
                }
                let folders = store.subfolders(of: "")
                if !folders.isEmpty {
                    Section {
                        ForEach(folders, id: \.self) { folder in
                            NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                        }
                    }
                }
                let notes = store.notes(in: "")
                if !notes.isEmpty {
                    Section {
                        ForEach(notes) { note in NoteLink(note: note) }
                    }
                }
            }
            .overlay { if store.notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text",
                description: Text("Copy notes into Point’s folder in the Files app.")) } }
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .note(let id):
            // By its ID now: renamed from its title, it keeps its screen.
            if let note = store.note(store.currentID(id)) {
                NoteScreen(note: note, store: store, isNew: id == newNote)
            }
        case .bookmarks: BookmarksScreen().toolbar { bottomBar() }
        case .recent: NoteListScreen(title: "Recent", notes: store.recent).toolbar { bottomBar() }
        case .tags: TagsScreen().toolbar { bottomBar() }
        case .tag(let tag): NoteListScreen(title: "#" + tag, notes: store.notes(taggedWith: tag)).toolbar { bottomBar() }
        case .folder(let folder): FolderScreen(folder: folder).toolbar { bottomBar(in: folder) }
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

    /// Makes a note and opens it, from home or anywhere deeper (the quick action).
    private func createNote() {
        guard let id = store.createNote() else { return }
        newNote = id
        store.searchText = ""
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
        .navigationTitle("Bookmarks")
        .overlay { if store.bookmarks.isEmpty { ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
            description: Text("Press and hold a note to bookmark it.")) } }
    }
}

/// A list of notes (Recent, or a tag's), newest first.
struct NoteListScreen: View {
    let title: String
    let notes: [Note]

    var body: some View {
        List(notes) { note in NoteLink(note: note) }
            .navigationTitle(title)
            .overlay { if notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text") } }
    }
}

/// Every tag, with how many notes have it; nested tags under their parents.
struct TagsScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let tags = store.tags
        List(tags, id: \.tag) { entry in
            NavigationLink(value: Route.tag(entry.tag)) {
                let depth = entry.tag.split(separator: "/").count - 1
                PlaceRow(title: depth > 0 ? String(entry.tag.split(separator: "/").last ?? "") : entry.tag,
                         symbol: "number", count: entry.count)
                    .padding(.leading, CGFloat(depth) * 20)
            }
        }
        .navigationTitle("Tags")
        .overlay { if tags.isEmpty { ContentUnavailableView("No Tags", systemImage: "number") } }
    }
}

/// A folder: the folders inside it, then its notes.
struct FolderScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let folder: String

    var body: some View {
        let folders = store.subfolders(of: folder)
        let notes = store.notes(in: folder)
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                    }
                }
            }
            if !notes.isEmpty {
                Section {
                    ForEach(notes) { note in NoteLink(note: note) }
                }
            }
        }
        .navigationTitle((folder as NSString).lastPathComponent)
        .overlay { if folders.isEmpty && notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "folder") } }
    }
}

/// A note in a list, with when it was last edited or opened, and a bookmark on long-press.
private struct NoteLink: View {
    @EnvironmentObject private var store: PhoneStore
    let note: Note
    var title: String?

    var body: some View {
        NavigationLink(value: Route.note(note.id)) {
            NoteRow(title: title ?? note.title, detail: HomeScreen.label(for: store.lastTouched(note)))
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

/// Search results, in place of the lists.
private struct SearchResults: View {
    let results: [SearchResult]
    let searchText: String

    var body: some View {
        List(results) { result in
            NavigationLink(value: Route.note(result.id)) { SearchRow(result: result) }
        }
        .listStyle(.plain)
        .overlay { if results.isEmpty { ContentUnavailableView.search(text: searchText) } }
    }
}

private struct NoteRow: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// A search result: its title, and the matching text with the matches in bold.
private struct SearchRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .fontWeight(result.matchedTitle ? .semibold : .regular)
                .lineLimit(1)
            if let snippet = result.snippet {
                Text(Self.marked(snippet))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// The snippet with each match (between `SearchResult.matchStart` and `matchEnd`) bold.
    static func marked(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var bold = false
        var run = ""
        func flush() {
            var part = AttributedString(run)
            if bold { part.inlinePresentationIntent = .stronglyEmphasized }
            result += part
            run = ""
        }
        for character in snippet {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                bold = character == SearchResult.matchStart
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }
}
