import IndexKit
import SwiftUI
import VaultKit

/// Where the app can go: a note, or one of the lists of notes.
enum Route: Hashable {
    case note(Note.ID)
    case notes, bookmarks, recent, folders, tags, types
    /// Every list note.
    case lists
    /// A kind's notes: those whose `type` is its name.
    case kind(String)
    case tag(String)
    case folder(String)
    case deleted
}

/// Home, for writing first and browsing when needed: a panel of Folders, Tags and Bookmarks,
/// each a page of its own; Favourites, if any; then the notes last opened on this phone.
/// Settings at the top right. Along the bottom: New note (blue), the search field and the
/// actions. Every other list has Sort (where it can be sorted) in New note's place.
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
    /// How many of the notes last opened home shows.
    static let recentOnHome = 10

    var body: some View {
        NavigationStack(path: $path) {
            home
                .pageTitle("Home")
                .navigationDestination(for: Route.self, destination: destination)
                .refreshable { await store.reload() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gear") { showsSettings = true }
                    }
                }
                .pageBar(add { createNote() })
        }
        // Search, over the bars and pages, opening out from the bar's field. Nothing under it moves.
        .overlay { SearchLayerHost() }
        .alert("New folder", isPresented: Binding(get: { newFolderParent != nil }, set: { if !$0 { newFolderParent = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create", action: createFolder)
        } message: {
            Text(newFolderParent.map { $0.isEmpty ? "In the vault root." : "Inside “\(($0 as NSString).lastPathComponent)”." } ?? "")
        }
        .alert("Couldn’t make the folder", isPresented: Binding(get: { folderProblem != nil }, set: { if !$0 { folderProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(folderProblem ?? "")
        }
        .alert("Couldn’t move the folder", isPresented: Binding(get: { moveProblem != nil }, set: { if !$0 { moveProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveProblem ?? "")
        }
        .sheet(isPresented: Binding(get: { movingFolder != nil }, set: { if !$0 { movingFolder = nil } })) {
            if let movingFolder {
                FolderPicker(title: "Move folder", current: FolderTree.parent(of: movingFolder), moving: movingFolder) { moveFolder(movingFolder, into: $0) }
                    .environmentObject(store)
            }
        }
        .alert("Couldn’t delete the note", isPresented: Binding(get: { store.trashProblem != nil }, set: { if !$0 { store.trashProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.trashProblem ?? "")
        }
        .alert("Open this link?", isPresented: Binding(get: { store.linkToConfirm != nil }, set: { if !$0 { store.linkToConfirm = nil } }),
               presenting: store.linkToConfirm) { url in
            Button("Cancel", role: .cancel) {}
            Button("Open") { store.openConfirmed(url) }
        } message: { url in
            Text(url.absoluteString.count > 200 ? String(url.absoluteString.prefix(200)) + "…" : url.absoluteString)
        }
        .alert("No app opens this link", isPresented: $store.linkDidNotOpen) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showsSettings) { SettingsScreen().environmentObject(store) }
        .onChange(of: quickActions.newNoteRequests) { _, _ in if quickActions.takeNewNote() { quickNote() } }
        .onChange(of: store.linkedRoute) { _, route in
            guard let route else { return }
            store.linkedRoute = nil
            go(to: route)
        }
        .onAppear { if quickActions.takeNewNote() { quickNote() } }
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
            #if DEBUG
            // `-PhoneOpenNote "Folder/Note.md"` opens that note at launch, for trying it out.
            if let id = UserDefaults.standard.string(forKey: "PhoneOpenNote"), path.isEmpty, notes.contains(where: { $0.id == id }) {
                path = [.note(id)]
            }
            #endif
        }
    }

    /// The blue New note, making a note with `create`; a long press offers the kinds, and
    /// clipping a copied link.
    private func add(_ create: @escaping () -> Void) -> PageTool {
        .add(create, more: AnyView(kindsMenu))
    }

    /// New note's long press: a note of each kind, and of each of a kind's templates; then
    /// Clip copied link.
    @ViewBuilder private var kindsMenu: some View {
        kindButtons
        Divider()
        Button("Clip copied link", systemImage: "scissors") { store.clipCopiedLink() }
    }

    @ViewBuilder private var kindButtons: some View {
        ForEach(store.kinds.offered) { kind in
            let templates = store.templates(of: kind)
            if templates.count > 1 {
                Menu(kind.name, systemImage: kind.shownSymbol) {
                    ForEach(templates, id: \.url) { template in
                        Button(template.label) { createNote(kind: kind, template: template.url) }
                    }
                }
            } else {
                Button(kind.name, systemImage: kind.shownSymbol) { createNote(kind: kind) }
            }
        }
    }

    private func newFolderButton(in parent: String) -> some View {
        Button("New folder", systemImage: "folder.badge.plus") {
            newFolderName = ""
            newFolderParent = parent
        }
    }

    private var home: some View {
        List {
            Section {
                HomePanel(open: { path.append($0) })
                    // Which notes are lists, for its Lists and to mark them, and how many notes
                    // are of each kind: again as the index changes.
                    .task(id: store.indexUpdates) {
                        await store.loadLists()
                        if !store.homeKinds.isEmpty { await store.loadPropertyValues() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            let tagCounts = Dictionary(store.tags.map { ($0.tag, $0.count) }, uniquingKeysWith: { first, _ in first })
            FavouritesSection(tagCounts: tagCounts)
            let recent = store.recentlyOpened(limit: Self.recentOnHome, excluding: nil)
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { note in NoteLink(note: note) }
                    NavigationLink(value: Route.recent) {
                        Text("Show all").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        // Not until the vault's been read: at launch, it showed for a moment before the notes.
        .overlay { if store.hasScanned, store.notes.isEmpty { ContentUnavailableView("No notes", systemImage: "doc.text",
            description: Text(PhoneVault.isOwnFolder ? "Copy notes into Point’s folder in the Files app, or choose your vault in Settings."
                              : "This folder has no notes yet. Choose another vault in Settings.")) } }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .note(let id):
            // By its ID now: renamed from its title, it keeps its screen.
            if let note = store.note(store.currentID(id)) {
                NoteScreen(note: note, store: store, isNew: id == newNote) { folder in createNote(in: folder) }
            }
        case .notes: NotesScreen().pageBar(add { createNote() }, sorts: true) { newFolderButton(in: "") }
        case .bookmarks: BookmarksScreen().pageBar(add { createNote() })
        case .recent: RecentScreen().pageBar(add { createNote() })
        case .folders: FoldersScreen().pageBar(add { createNote() }) { newFolderButton(in: "") }
        case .tags: TagsScreen().pageBar(add { createNote() })
        case .types: TypesScreen().pageBar(add { createNote() })
        case .lists: ListsScreen().pageBar(add { createNote() }, sorts: true)
        case .kind(let name):
            KindScreen(name: name).pageBar(add {
                if let kind = store.kinds.kind(named: name) { createNote(kind: kind) } else { createNote() }
            }, sorts: true)
        case .tag(let tag):
            TagScreen(tag: tag).pageBar(add { createNote(text: Frontmatter.edit(adding: "tags", values: [tag], isList: true).1) }, sorts: true) {
                FavouriteButton(favourite: .tag(tag))
            }
        case .folder(""):
            FolderScreen(folder: "").pageBar(add { createNote() }, sorts: true) {
                newFolderButton(in: "")
                FavouriteButton(favourite: .folder(""))
            }
        case .folder(let folder):
            FolderScreen(folder: folder).pageBar(add { createNote(in: folder) }, sorts: true) {
                newFolderButton(in: folder)
                Button("Move folder", systemImage: "folder") { movingFolder = folder }
                FavouriteButton(favourite: .folder(folder))
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
        PhoneVault.log("made \(id) with New note")
        newNote = id
        if case .note(let below)? = path.last, store.isUntitled(store.currentID(below)) { path.removeLast() }
        path.append(.note(id))
    }

    /// Makes a note of a kind and opens it, as New note does.
    private func createNote(kind: NoteKinds.Kind, template: URL? = nil) {
        guard let id = store.createNote(kind: kind, template: template) else { return }
        PhoneVault.log("made \(id) with New \(kind.name)")
        newNote = id
        path.append(.note(id))
    }

    /// Makes a note and opens it straight from home, from wherever you were.
    private func quickNote() {
        guard let id = store.createNote() else { return }
        PhoneVault.log("made \(id) with the icon's New note")
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
            .overlay { if notes.isEmpty { ContentUnavailableView("No notes", systemImage: "doc.text") } }
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
        .overlay { if store.bookmarks.isEmpty { ContentUnavailableView("No bookmarks", systemImage: "bookmark",
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
        .overlay { if groups.isEmpty { ContentUnavailableView("No notes", systemImage: "doc.text") } }
    }
}

/// Home's panel: Folders, Tags, Bookmarks and Types, each opening its page, as many as
/// Settings shows, then any kinds of note chosen to show by themselves. In rows of up to three
/// (see `rows(of:across:)`), or two where three won't fit; stacked at the largest text sizes.
private struct HomePanel: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(HomeTile.folders.key) private var showsFolders = true
    @AppStorage(HomeTile.tags.key) private var showsTags = true
    @AppStorage(HomeTile.bookmarks.key) private var showsBookmarks = true
    @AppStorage(HomeTile.types.key) private var showsTypes = true
    @AppStorage(HomeTile.lists.key) private var showsLists = true
    let open: (Route) -> Void

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 12
    @State private var width: CGFloat = 0

    /// A tile: one of home's places, or a kind of note chosen to show by itself.
    private enum Tile: Hashable {
        case place(HomeTile)
        case kind(String)
    }

    private var tiles: [Tile] {
        let places: [HomeTile] = [showsFolders ? .folders : nil, showsTags ? .tags : nil, showsBookmarks ? .bookmarks : nil,
                                  showsTypes && !store.kinds.isEmpty ? .types : nil,
                                  showsLists && !store.listNoteIDs.isEmpty ? .lists : nil].compactMap { $0 }
        // Chosen kinds, in the vault's order of kinds (one no longer in it isn't shown).
        let kinds = store.kinds.kinds.map(\.name).filter(store.homeKinds.contains)
        return places.map(Tile.place) + kinds.map(Tile.kind)
    }

    var body: some View {
        let tiles = tiles
        if typeSize.isAccessibilitySize {
            VStack(spacing: Self.spacing) { ForEach(tiles, id: \.self, content: tile) }
        } else {
            // Three across where every title fits whole, at larger text sizes two.
            rows(of: tiles, across: fitsThree(tiles) ? 3 : 2)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    /// Whether each tile, a third of the width, has room for its title and its count.
    private func fitsThree(_ tiles: [Tile]) -> Bool {
        guard width > 0 else { return true }
        let room = (width - 2 * Self.spacing) / 3 - 2 * Self.padding
        let titleFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
        let countFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)
        return tiles.allSatisfy { tile in
            let (title, _, count, _) = details(tile)
            let countWidth = ("\(count)" as NSString).size(withAttributes: [.font: countFont]).width
            return (title as NSString).size(withAttributes: [.font: titleFont]).width <= room
                && countWidth + countFont.pointSize * 1.5 <= room // The glyph beside it.
        }
    }

    private func rows(of tiles: [Tile], across: Int) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(Self.rows(of: tiles, across: across), id: \.self) { row in
                HStack(spacing: Self.spacing) { ForEach(row, id: \.self, content: tile) }
            }
        }
    }

    /// Rows of at most `across`, as even as they'll go, any longer ones first: across three,
    /// 4 as 2 over 2, 5 as 3 over 2, 7 as 3, 2 and 2.
    private static func rows(of tiles: [Tile], across: Int) -> [[Tile]] {
        guard !tiles.isEmpty else { return [] }
        let count = (tiles.count + across - 1) / across
        var rows: [[Tile]] = []
        var start = 0
        for index in 0..<count {
            let length = tiles.count / count + (index < tiles.count % count ? 1 : 0)
            rows.append(Array(tiles[start..<start + length]))
            start += length
        }
        return rows
    }

    /// A tile's title, glyph, count, and where it goes.
    private func details(_ tile: Tile) -> (String, String, Int, Route) {
        switch tile {
        case .place(.folders): ("Folders", "folder", store.subfolders(of: "").count, .folders)
        case .place(.tags): ("Tags", symbol("number.sign.circle", or: "number.circle"), store.tags.count, .tags)
        case .place(.bookmarks): ("Bookmarks", "bookmark", store.bookmarks.count, .bookmarks)
        case .place(.types): ("Types", "square.grid.2x2", store.kinds.kinds.count, .types)
        case .place(.lists): ("Lists", "list.bullet.rectangle.portrait", store.listNoteIDs.count, .lists)
        case .kind(let name): (NoteKinds.plural(name), store.kinds.kinds.first { $0.name == name }?.shownSymbol ?? "doc.text",
                               store.kindCounts[name.lowercased()] ?? 0, .kind(name))
        }
    }

    private func tile(_ tile: Tile) -> some View {
        let (title, glyph, count, route) = details(tile)
        return Button { open(route) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: glyph)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    // Every title the same size: a long one is cut short rather than made smaller.
                    .lineLimit(1)
            }
            .padding(Self.padding)
            // Every tile in a row as wide as the others, whatever its title.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(.isButton)
    }
}

/// What home's panel can show, each turned on or off in Settings.
enum HomeTile: CaseIterable {
    case folders, tags, bookmarks, types, lists

    var key: String {
        switch self {
        case .folders: "homeShowsFolders"
        case .tags: "homeShowsTags"
        case .bookmarks: "homeShowsBookmarks"
        case .types: "homeShowsTypes"
        case .lists: "homeShowsLists"
        }
    }

    var title: String {
        switch self {
        case .folders: "Folders"
        case .tags: "Tags"
        case .bookmarks: "Bookmarks"
        case .types: "Types"
        case .lists: "Lists"
        }
    }
}

/// Every list note, wherever it is, marked as one.
struct ListsScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let notes = store.notes.filter { store.listNoteIDs.contains($0.id) }.sorted(by: store.sort)
        List { NoteSections(notes: notes) }
            .pageTitle("Lists")
            .task { await store.loadLists() }
            .overlay { if notes.isEmpty { ContentUnavailableView("No lists", systemImage: "list.bullet.rectangle.portrait") } }
    }
}

/// The vault's kinds of note (`.point/kinds.json`), each with how many notes are of it.
struct TypesScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let counts = store.kindCounts
        List {
            ForEach(store.kinds.kinds) { kind in
                NavigationLink(value: Route.kind(kind.name)) {
                    PlaceRow(title: NoteKinds.plural(kind.name), symbol: kind.shownSymbol, count: counts[kind.name.lowercased()] ?? 0)
                }
            }
        }
        .pageTitle("Types")
        .task { await store.loadPropertyValues() }
        .overlay { if store.kinds.isEmpty { ContentUnavailableView("No types", systemImage: "square.grid.2x2",
            description: Text("Kinds of note are set in the vault’s .point/kinds.json.")) } }
    }
}

/// A kind's notes, in the chosen order.
struct KindScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let name: String

    var body: some View {
        KindNotes(name: name, embeds: store.embeds)
    }
}

/// Watches the query, which runs in the background, and lists what it finds.
private struct KindNotes: View {
    @EnvironmentObject private var store: PhoneStore
    let name: String
    @ObservedObject var embeds: PhoneEmbeds

    var body: some View {
        let ids = embeds.noteIDs(matching: NoteQuery([.property(store.kinds.property, .equals(name))]))
        let found = Set(ids ?? [])
        let notes = store.notes.filter { found.contains($0.id) }.sorted(by: store.sort)
        List { NoteSections(notes: notes) }
            .pageTitle(NoteKinds.plural(name))
            .overlay { if ids != nil, notes.isEmpty { ContentUnavailableView("No notes", systemImage: "doc.text") } }
    }
}

/// Browsing by folder: All notes and the vault root, the vault's folders, then Deleted notes.
struct FoldersScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let folders = store.sorted(folders: store.subfolders(of: ""))
        List {
            Section {
                NavigationLink(value: Route.notes) { PlaceRow(title: "All notes", symbol: "doc.text", count: store.notes.count) }
                // The notes in no folder.
                NavigationLink(value: Route.folder("")) {
                    PlaceRow(title: "Vault root", symbol: "tray", count: store.notes(in: "").count)
                }
                .favouriteMenu(.folder(""))
            }
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                            .favouriteMenu(.folder(folder))
                    }
                }
            }
            Section {
                NavigationLink(value: Route.deleted) { PlaceRow(title: "Deleted notes", symbol: "trash", count: store.deletedNotes.count, tint: .red) }
            }
        }
        .pageTitle("Folders")
    }
}

/// Every tag, nested tags under their parents.
struct TagsScreen: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let tags = store.sorted(tags: store.tags)
        List {
            ForEach(tags, id: \.tag) { entry in
                NavigationLink(value: Route.tag(entry.tag)) {
                    let depth = entry.tag.split(separator: "/").count - 1
                    PlaceRow(title: depth > 0 ? String(entry.tag.split(separator: "/").last ?? "") : entry.tag,
                             symbol: symbol("number.sign.circle", or: "number.circle"), count: entry.count)
                        .padding(.leading, CGFloat(depth) * 20)
                }
                .favouriteMenu(.tag(entry.tag))
            }
        }
        .pageTitle("Tags")
        .overlay { if tags.isEmpty { ContentUnavailableView("No tags", systemImage: "number") } }
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
            .overlay { if notes.isEmpty { ContentUnavailableView("No notes", systemImage: "doc.text") } }
    }
}

/// A folder: the folders inside it, then its notes. The top level ("") is just its notes.
struct FolderScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let folder: String

    var body: some View {
        // At the top level, just its notes: home has its folders.
        let folders = folder.isEmpty ? [] : store.sorted(folders: store.subfolders(of: folder))
        let notes = store.notes(in: folder)
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(folder)) { FolderRow(folder: folder) }
                            .favouriteMenu(.folder(folder))
                    }
                }
            }
            NoteSections(notes: notes)
        }
        .pageTitle(folder.isEmpty ? "Vault root" : (folder as NSString).lastPathComponent)
        .overlay { if folders.isEmpty && notes.isEmpty { ContentUnavailableView("No notes", systemImage: "folder") } }
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
                            Button("Put back", systemImage: "arrow.uturn.backward") { store.restore(item) }
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
        .pageTitle("Deleted notes")
        .overlay { if store.deletedNotes.isEmpty { ContentUnavailableView("No deleted notes", systemImage: "trash") } }
        .onAppear { store.refreshTrash() }
        .confirmationDialog(chosen?.title ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { item in
            Button("Put back") { store.restore(item) }
            Button("Delete now", role: .destructive) { store.deleteForever(item) }
        } message: { _ in
            Text("Deleting it now can’t be undone.")
        }
        .confirmationDialog("Delete the \(store.deletedNotes.count) deleted notes for good?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { store.deleteAllForever() }
        }
        .alert("Deleted notes", isPresented: Binding(get: { store.deletedNotesProblem != nil }, set: { if !$0 { store.deletedNotesProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.deletedNotesProblem ?? "")
        }
        .pageBar {
            Button("Delete all", systemImage: "trash", role: .destructive) { confirmsDeleteAll = true }
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

/// What a page's bottom bar has besides search: in a note, finding in it; on a list, the
/// blue New note.
enum PageTool {
    case none
    case find(() -> Void)
    /// New note, the bar's one blue button, at its right. `more`, if given, is what a long
    /// press offers (new notes of each kind).
    case add(() -> Void, more: AnyView? = nil)
}

/// What every page has, as Apple's own apps have it. A list: the search field along the bottom,
/// with Search over the page while it's in use, and New note at its right; at the top right,
/// a menu of what can be done here, with sorting in it on a list of notes. A note: finding in it, a map
/// that opens Search, and the menu, along the bottom.
private struct PageBar<Actions: View>: ViewModifier {
    @EnvironmentObject private var search: PhoneSearch
    let tool: PageTool
    let sorts: Bool
    @ViewBuilder let actions: Actions
    private var hasActions: Bool { Actions.self != EmptyView.self }

    func body(content: Content) -> some View {
        switch tool {
        case .find(let find):
            // A note: finding in it, and, with the map, Search, as on the lists.
            content
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Find in note", systemImage: "text.page.badge.magnifyingglass", action: find)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Search", systemImage: "map") { search.present(from: nil) }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { menu(symbol: symbol("text.menu", or: "line.3.horizontal")) }
                }
        case .none, .add:
            content
                // The page stays its size under the keyboard: shrunk, the rows below were left
                // undrawn, and showed blank as the keyboard went down.
                .ignoresSafeArea(.keyboard)
                // No scrim behind the search field and New note: the rows run under them, as
                // in Apple's own apps, and the glass is enough to set them apart.
                .scrollEdgeEffectHidden(true, for: .bottom)
                .toolbar {
                    if hasActions || sorts {
                        ToolbarItem(placement: .topBarTrailing) { menu(symbol: "ellipsis") }
                    }
                    // Point's own search field, not the system's: Search opens out from it.
                    ToolbarItem(placement: .bottomBar) {
                        SearchCapsule(besides: { if case .add = tool { 1 } else { 0 } }())
                    }
                    if case .add(let add, let more) = tool {
                        if let more {
                            // A tap makes a note; a long press offers the kinds. The bar draws
                            // a menu plain whatever its style, so this one draws its own blue.
                            ToolbarItem(placement: .bottomBar) {
                                Menu { more } label: {
                                    Image(systemName: "plus")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                                } primaryAction: { add() }
                                    .menuOrder(.fixed)
                                    .accessibilityLabel("New note")
                            }
                            .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .bottomBar) {
                                Button("New note", systemImage: "plus", action: add)
                                    .buttonStyle(.glassProminent)
                                    .tint(.blue)
                            }
                        }
                    }
                }
        }
    }

    private func menu(symbol: String) -> some View {
        Menu("Actions", systemImage: symbol) {
            actions
            // Sorting goes in the menu, as in Apple's own apps, not a button of its own.
            if sorts {
                Section { SortPicker() }
            }
        }
            // In the order given, top to bottom: from the bottom bar, the system would turn it
            // over, putting the first item nearest the thumb.
            .menuOrder(.fixed)
    }
}

/// A page's large title, the page's own, at the top of its list and scrolling with it, and the
/// system's small title once it's scrolled away. The system's large title collapsed as Search
/// started, and the page jumped up with it; one of the page's own in the bar didn't slide with
/// the page on going in and back. This one is part of the page: it slides and fades with it.
private struct PageTitle: ViewModifier {
    let title: String
    /// How far the list has scrolled from the top.
    @State private var scrolled: CGFloat = 0

    /// The room the title takes above the list, as the system's did.
    static let height: CGFloat = 52

    func body(content: Content) -> some View {
        let showsSmallTitle = scrolled > Self.height - 12
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(showsSmallTitle ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: showsSmallTitle)
                }
            }
            .contentMargins(.top, Self.height, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                scrolled = offset
            }
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                    .frame(height: Self.height, alignment: .bottomLeading)
                    .offset(y: -scrolled)
                    // Goes as it scrolls under the bar.
                    .opacity(1 - min(max(scrolled / (Self.height - 12), 0), 1))
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
            }
    }
}

extension View {
    func pageTitle(_ title: String) -> some View { modifier(PageTitle(title: title)) }

    /// `tool` is what the bottom bar has besides search; `sorts`, whether the page lists notes
    /// to sort; `actions`, the menu of what can be done here.
    func pageBar<Actions: View>(_ tool: PageTool = .none, sorts: Bool = false, @ViewBuilder actions: () -> Actions) -> some View {
        modifier(PageBar(tool: tool, sorts: sorts, actions: actions))
    }

    func pageBar(_ tool: PageTool = .none, sorts: Bool = false) -> some View {
        modifier(PageBar(tool: tool, sorts: sorts) { EmptyView() })
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
                row("Vault root", folder: "", depth: 0)
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

/// How the note lists are sorted, as on the Mac: a submenu of the page's ••• menu, showing the
/// current order under its name.
private struct SortPicker: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        Picker(selection: $store.sort) {
            Text("Date edited").tag(NoteSort.modified)
            Text("Date created").tag(NoteSort.created)
            Text("Title").tag(NoteSort.title)
        } label: {
            Label("Sort by", systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
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
            NoteRow(title: title ?? note.title, detail: detail, isList: store.listNoteIDs.contains(note.id))
        }
        .contextMenu {
            let bookmarked = store.isBookmarked(note.id)
            Button(bookmarked ? "Remove bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
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
    /// The title and symbol's colour, if not the usual.
    var tint: Color?
    /// The count's, if not the usual.
    var countColor: Color?

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(tint ?? .primary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint ?? .accentColor)
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .foregroundStyle(countColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .monospacedDigit()
            }
        }
    }
}

/// Home's Favourites: folders and tags chosen from their menus (`favouriteMenu`), on the
/// highlight colour, in white. Not there until something's added. Missing ones (a folder
/// gone, a tag no note has now) aren't shown, but are kept, in case they come back.
private struct FavouritesSection: View {
    @EnvironmentObject private var store: PhoneStore
    let tagCounts: [String: Int]
    @State private var edits = false

    var body: some View {
        let shown = store.favourites.filter { favourite in
            switch favourite {
            case .folder(let folder): folder.isEmpty || store.folders.contains(folder)
            case .tag(let tag): tagCounts[tag] != nil
            }
        }
        if !shown.isEmpty {
            Section {
                ForEach(shown, id: \.self) { favourite in
                    NavigationLink(value: favourite.route) {
                        HStack(spacing: 14) {
                            row(favourite)
                            // The system's own was grey on the blue.
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                        .navigationLinkIndicatorVisibility(.hidden)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.accentColor)
                        .listRowSeparatorTint(.white.opacity(0.3))
                        .favouriteMenu(favourite)
                        .swipeActions {
                            Button("Remove", systemImage: "star.slash", role: .destructive) { store.toggleFavourite(favourite) }
                        }
                }
            } header: {
                // Reordered here, not by dragging: a long press is Remove from Favourites, and
                // a drag let go over it removed the row.
                HStack {
                    Text("Favourites")
                    Spacer()
                    Button("Edit") { edits = true }
                        .font(.subheadline)
                }
            }
            .sheet(isPresented: $edits) {
                FavouritesEditor(shown: shown, label: label).environmentObject(store)
            }
        }
    }

    /// A favourite's name and symbol.
    private func label(_ favourite: Favourite) -> (title: String, symbol: String) {
        switch favourite {
        case .folder(let folder):
            (folder.isEmpty ? "Vault root" : (folder as NSString).lastPathComponent, folder.isEmpty ? "tray" : "folder")
        case .tag(let tag): (tag, symbol("number.sign.circle", or: "number.circle"))
        }
    }

    private func row(_ favourite: Favourite) -> some View {
        let count = switch favourite {
        case .folder(let folder): folder.isEmpty ? store.notes(in: "").count : store.noteCount(inFolder: folder)
        case .tag(let tag): tagCounts[tag]
        }
        let (title, symbol) = label(favourite)
        return PlaceRow(title: title, symbol: symbol, count: count, tint: .white, countColor: .white.opacity(0.6))
    }
}

/// Favourites, to put in order and take off.
private struct FavouritesEditor: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State var shown: [Favourite]
    let label: (Favourite) -> (title: String, symbol: String)

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown, id: \.self) { favourite in
                    let (title, symbol) = label(favourite)
                    Label(title, systemImage: symbol)
                }
                .onMove { offsets, destination in
                    shown.move(fromOffsets: offsets, toOffset: destination)
                    store.reorderFavourites(shown)
                }
                .onDelete { offsets in
                    for favourite in offsets.map({ shown[$0] }) { store.toggleFavourite(favourite) }
                    shown.remove(atOffsets: offsets)
                    if shown.isEmpty { dismiss() }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Adds a folder or tag to Favourites, or takes it off, in an action menu.
private struct FavouriteButton: View {
    @EnvironmentObject private var store: PhoneStore
    let favourite: Favourite

    var body: some View {
        let isFavourite = store.isFavourite(favourite)
        Button(isFavourite ? "Remove from favourites" : "Add to favourites", systemImage: isFavourite ? "star.slash" : "star") {
            store.toggleFavourite(favourite)
        }
    }
}

extension View {
    /// Add to Favourites (or Remove), on a long press.
    fileprivate func favouriteMenu(_ favourite: Favourite) -> some View {
        contextMenu { FavouriteButton(favourite: favourite) }
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
    /// A list note, marked "List" at the right.
    var isList = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if isList {
                Spacer(minLength: 8)
                Text("List")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
    }
}
