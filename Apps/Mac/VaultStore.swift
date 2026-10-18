import AppKit
import CryptoKit
import EditorKit
import IndexKit
import MarkdownKit
import VaultKit

extension Notification.Name {
    /// A note moved or was renamed: `userInfo` has "old" and "new" IDs. Windows follow it.
    static let imprintNoteMoved = Notification.Name("ImprintNoteMoved")
    /// A different vault was opened. Windows start afresh.
    static let imprintVaultOpened = Notification.Name("ImprintVaultOpened")
}

/// The open vault, shared by every window and tab: its notes, search index, tags, file
/// watching and file operations, and the app's display settings.
///
/// Per-window state (the note shown, the folder browsed, search, history) lives in
/// `VaultModel`, one per window.
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var notes: [Note] = [] {
        didSet { folderTree = FolderTree(notes: notes) }
    }
    @Published var errorMessage: String?
    @Published var sort: NoteSort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Keys.sort)
            notes = notes.sorted(by: sort)
        }
    }

    private var watcher: VaultWatcher?
    private(set) var settings = ObsidianSettings()
    /// Notes created untitled, to be named by their first line when left.
    private var untitled: Set<Note.ID> = []

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let sort = "noteSort"
    }

    init() {
        sort = UserDefaults.standard.string(forKey: Keys.sort).flatMap(NoteSort.init) ?? .modified
        restoreVault()
    }

    // MARK: Opening the vault

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose the folder that holds your notes. It can be an existing Obsidian vault."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try VaultLocation.bookmark(for: url), forKey: Keys.bookmark)
        } catch {
            errorMessage = "Imprint couldn't remember this folder: \(error.localizedDescription)"
        }
        open(url)
    }

    func reload() async {
        guard let root else { return }
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try VaultScanner.scan(root)
            }.value
            notes = scanned.sorted(by: sort)
            errorMessage = nil
            refreshTags()
            updateIndex()
        } catch {
            errorMessage = "Imprint couldn't read the vault: \(error.localizedDescription)"
        }
    }

    private func restoreVault() {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "ImprintVault") {
            open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return
        }
        #endif
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.bookmark) else { return }
        do {
            let (url, isStale) = try VaultLocation.resolve(bookmark)
            open(url)
            if isStale, let fresh = try? VaultLocation.bookmark(for: url) {
                UserDefaults.standard.set(fresh, forKey: Keys.bookmark)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: Keys.bookmark)
            errorMessage = "Imprint lost access to your vault. Open it again."
        }
    }

    private func open(_ url: URL) {
        watcher?.stop()
        root?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        root = url
        notes = []
        settings = ObsidianSettings.load(vault: url)
        indexedTags = [:]
        tagTree = TagTree(tagsByNote: [])
        pins = (UserDefaults.standard.stringArray(forKey: "pins." + Self.vaultKey(url)) ?? []).compactMap(SidebarPlace.init(key:))
        openIndex(for: url)
        watcher = VaultWatcher(root: url) { [weak self] urls in
            Task { @MainActor in self?.filesChanged(urls) }
        }
        NotificationCenter.default.post(name: .imprintVaultOpened, object: self)
        Task { await reload() }
    }

    /// Something in the vault changed, here or elsewhere: rescan, and tell open notes.
    private func filesChanged(_ urls: [URL]) {
        NotificationCenter.default.post(name: .imprintFilesChanged, object: self, userInfo: ["urls": urls])
        Task { await reload() }
    }

    // MARK: Creating, renaming and deleting

    /// Creates an untitled note in `folder` ("" is the vault root) and returns its ID.
    func createNote(text: String = "", inFolder folder: String) -> Note.ID? {
        guard let root else { return nil }
        do {
            let url = try NoteFiles.create(title: NoteFiles.untitledName(), text: text,
                                           in: folder.isEmpty ? root : root.appendingPathComponent(folder))
            let id = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
            add(Note(id: id, url: url, title: url.deletingPathExtension().lastPathComponent,
                     modified: Date(), created: Date(), isDownloaded: true))
            untitled.insert(id)
            return id
        } catch {
            errorMessage = "Couldn't create a note: \(error.localizedDescription)"
            return nil
        }
    }

    private func add(_ note: Note) {
        notes = (notes + [note]).sorted(by: sort)
    }

    /// Names a note created untitled after its first line, or removes it if it stayed empty.
    func finishUntitledNote(_ id: Note.ID) {
        guard untitled.remove(id) != nil, let note = notes.first(where: { $0.id == id }) else { return }
        releaseFile(note.url)
        let text = (try? NoteReader.read(contentsOf: note.url)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: note.url) // Empty, and created by us moments ago.
            notes.removeAll { $0.id == id }
            return
        }
        guard let line = PlainText.firstLine(of: text) else { return }
        let title = NoteFiles.sanitizedTitle(line)
        guard !title.isEmpty, title != note.title else { return }
        let available = NoteFiles.availableURL(for: title, in: note.url.deletingLastPathComponent())
        _ = try? NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent)
        Task { await reload() }
    }

    /// Renames a note, updating links to it everywhere. Windows showing it follow along.
    func rename(_ note: Note, to title: String) {
        do {
            releaseFile(note.url)
            untitled.remove(note.id)
            let vaultBeforeRename = notes
            let url = try NoteFiles.rename(note.url, to: title)
            updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, vault: vaultBeforeRename)
            let folders = note.id.split(separator: "/").dropLast().joined(separator: "/")
            let newID = folders.isEmpty ? url.lastPathComponent : "\(folders)/\(url.lastPathComponent)"
            replace(note, with: newID, url: url)
            Task { await reload() }
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    /// Updates a note's place in the list and tells windows its new ID.
    private func replace(_ note: Note, with newID: Note.ID, url: URL) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = Note(id: newID, url: url, title: url.deletingPathExtension().lastPathComponent,
                                modified: note.modified, created: note.created, isDownloaded: true)
        }
        if untitled.remove(note.id) != nil { untitled.insert(newID) }
        NotificationCenter.default.post(name: .imprintNoteMoved, object: self, userInfo: ["old": note.id, "new": newID])
    }

    func moveToTrash(_ note: Note) {
        guard let root else { return }
        releaseFile(note.url)
        untitled.remove(note.id)
        do {
            try NoteFiles.trash(note.url, vault: root, option: settings.trashOption)
            notes.removeAll { $0.id == note.id }
        } catch {
            errorMessage = "Couldn't move “\(note.title)” to the trash: \(error.localizedDescription)"
        }
    }

    /// Moves a note into a folder ("" is the vault root), keeping links to it working.
    func move(noteID: Note.ID, toFolder folder: String) {
        guard let root, let note = notes.first(where: { $0.id == noteID }),
              FolderTree.folder(of: note.id) != folder else { return }
        releaseFile(note.url)
        let vaultBeforeMove = notes
        do {
            let url = try NoteFiles.move(note.url, toFolder: folder.isEmpty ? root : root.appendingPathComponent(folder))
            let newID = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
            replace(note, with: newID, url: url)
            NotificationCenter.default.post(name: .imprintSaveNow, object: self)
            Task.detached(priority: .userInitiated) {
                let result = LinkUpdater.updateLinks(afterMoving: note, to: newID, notes: vaultBeforeMove, root: root)
                if !result.skippedNotes.isEmpty {
                    NSLog("Imprint: links not updated in \(result.skippedNotes) (changed while updating)")
                }
            }
            Task { await reload() }
        } catch {
            errorMessage = "Couldn't move “\(note.title)”: \(error.localizedDescription)"
        }
    }

    /// Points every link to `note` at its new title, in the background. Open notes save
    /// first, and pick up the rewritten links through the vault watcher.
    private func updateLinks(to note: Note, newTitle: String, vault: [Note]) {
        NotificationCenter.default.post(name: .imprintSaveNow, object: self)
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newTitle, notes: vault)
            if !result.skippedNotes.isEmpty {
                NSLog("Imprint: links not updated in \(result.skippedNotes) (changed while updating)")
            }
        }
    }

    /// Asks any editor showing this file to save now and stop writing to it.
    private func releaseFile(_ url: URL) {
        NotificationCenter.default.post(name: .imprintReleaseFile, object: self, userInfo: ["url": url])
    }

    /// Creates the note a link points to but which doesn't exist yet, and returns its ID.
    func createLinkedNote(named target: String) -> Note.ID? {
        guard let root else { return nil }
        let name = target.split(separator: "#").first.map(String.init) ?? target
        let title = NoteFiles.sanitizedTitle((name as NSString).lastPathComponent)
        guard !title.isEmpty, let url = try? NoteFiles.create(title: title, in: root) else { return nil }
        let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                        modified: Date(), created: Date(), isDownloaded: true)
        add(note)
        return note.id
    }

    /// Note titles for completing a `[[wikilink]]`: names starting with the typed text first,
    /// then names with a word starting with it, then names containing it anywhere.
    func titleSuggestions(for partial: String) -> [String] {
        let query = partial.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return Array(notes.sorted(by: .modified).prefix(20).map(\.title))
        }
        func rank(_ title: String) -> Int? {
            let lowered = title.lowercased()
            if lowered.hasPrefix(query) { return 0 }
            if lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) { return 1 }
            if lowered.contains(query) { return 2 }
            return nil
        }
        var ranked: [(title: String, rank: Int)] = []
        for note in notes {
            if let rank = rank(note.title) { ranked.append((note.title, rank)) }
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.title.count < $1.title.count }
        var seen = Set<String>()
        var titles: [String] = []
        for entry in ranked where titles.count < 20 && seen.insert(entry.title.lowercased()).inserted {
            titles.append(entry.title)
        }
        return titles
    }

    // MARK: Daily notes and templates

    /// Today's daily note, created (from its template, if one is set) if needed.
    func todaysNote() -> Note.ID? {
        guard let root else { return nil }
        let url = Templates.dailyNoteURL(in: root, settings: settings)
        if let existing = notes.first(where: { $0.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path }) {
            return existing.id
        }
        do {
            let title = url.deletingPathExtension().lastPathComponent
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = Templates.dailyNoteText(title: title, in: root, settings: settings)
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            let id = String(url.resolvingSymlinksInPath().path.dropFirst(root.resolvingSymlinksInPath().path.count + 1))
            add(Note(id: id, url: url, title: title, modified: Date(), created: Date(), isDownloaded: true))
            return id
        } catch {
            errorMessage = "Couldn't create today's note: \(error.localizedDescription)"
            return nil
        }
    }

    /// The templates in the vault's templates folder, for Insert Template.
    var templates: [(name: String, url: URL)] {
        root.map { Templates.available(in: $0, settings: settings) } ?? []
    }

    // MARK: Display settings (shared by every window)

    @Published var showsDateInList = UserDefaults.standard.bool(forKey: "showsDateInList") {
        didSet { UserDefaults.standard.set(showsDateInList, forKey: "showsDateInList") }
    }
    @Published var listDate = VaultModel.ListDate(rawValue: UserDefaults.standard.string(forKey: "listDate") ?? "") ?? .edited {
        didSet { UserDefaults.standard.set(listDate.rawValue, forKey: "listDate") }
    }
    @Published var showsTagsInList = UserDefaults.standard.bool(forKey: "showsTagsInList") {
        didSet {
            UserDefaults.standard.set(showsTagsInList, forKey: "showsTagsInList")
            if showsTagsInList { refreshTags() }
        }
    }
    @Published var showsMarkdown = false
    /// Note text size relative to normal, kept between launches (⌘+ / ⌘−).
    @Published var textScale: Double = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(textScale, forKey: "textScale") }
    }
    @Published var browsingStyle = VaultModel.BrowsingStyle(rawValue: UserDefaults.standard.string(forKey: "browsingStyle") ?? "") ?? .singleColumn {
        didSet { UserDefaults.standard.set(browsingStyle.rawValue, forKey: "browsingStyle") }
    }
    /// How folders and tags are sorted, in both layouts.
    @Published var tagOrder = VaultModel.TagOrder(rawValue: UserDefaults.standard.string(forKey: "tagOrder") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(tagOrder.rawValue, forKey: "tagOrder") }
    }
    /// The two-column view's left column: folders and tags together, or one at a time.
    @Published var treeLayout = VaultModel.TreeLayout(rawValue: UserDefaults.standard.string(forKey: "treeLayout") ?? "") ?? .stacked {
        didSet { UserDefaults.standard.set(treeLayout.rawValue, forKey: "treeLayout") }
    }

    func makeTextBigger() { textScale = min(textScale + 0.1, 2.5) }
    func makeTextSmaller() { textScale = max(textScale - 0.1, 0.6) }

    // MARK: Tags

    /// Each note's tags, read from its file in the background while tags are shown in the list.
    @Published private(set) var tagsByNote: [Note.ID: [String]] = [:]
    private var tagsReadAt: [Note.ID: Date] = [:]
    /// Every note's tags, from the search index (which keeps them between launches).
    @Published private(set) var indexedTags: [Note.ID: [String]] = [:]
    @Published private(set) var tagTree = TagTree(tagsByNote: [])

    /// Reads tags for notes that are new or changed since they were last read.
    func refreshTags() {
        Trace.mark("refreshTags called")
        guard showsTagsInList else { return }
        let stale = notes.filter { $0.isDownloaded && tagsReadAt[$0.id] != $0.modified }
        guard !stale.isEmpty else { return }
        Task {
            let read = await Task.detached(priority: .utility) {
                stale.map { note in (note, (try? NoteReader.read(contentsOf: note.url)).map(NoteTags.tags(in:)) ?? []) }
            }.value
            for (note, tags) in read {
                tagsByNote[note.id] = tags
                tagsReadAt[note.id] = note.modified
            }
            Trace.mark("tagsByNote updated: \(read.count) notes read")
        }
    }

    /// A note's tags for the list: read from its file, or (until that's done, as at launch)
    /// from the search index.
    func listTags(for id: Note.ID) -> [String] {
        tagsByNote[id] ?? indexedTags[id] ?? []
    }

    // MARK: Search index

    private(set) var index: SearchIndex?
    /// Goes up whenever the index changes, so windows can refresh their searches.
    @Published private(set) var indexGeneration = 0

    /// Opens (creating if needed) the search index for the vault at `url`. It lives in the
    /// app's own storage, never in the vault, named by a hash of the vault's path.
    private func openIndex(for url: URL) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imprint/Index", isDirectory: true)
        index = try? SearchIndex(url: folder.appendingPathComponent("\(Self.vaultKey(url)).sqlite"))
    }

    /// A short, stable name for a vault, from a hash of its path.
    static func vaultKey(_ url: URL) -> String {
        SHA256.hash(data: Data(url.resolvingSymlinksInPath().path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Brings the index up to date after a scan.
    private func updateIndex() {
        guard let index else { return }
        let notes = notes
        Task {
            let changed = (try? await index.update(notes: notes)) ?? 0
            if changed > 0 { indexGeneration += 1 }
            if changed > 0 || tagTree.entries.isEmpty {
                let tags = (try? await index.tagsByNote()) ?? [:]
                indexedTags = tags
                tagTree = TagTree(tagsByNote: Array(tags.values))
                Trace.mark("index tags ready: \(tags.count) notes")
            }
        }
    }

    // MARK: Folders, tags and pins

    /// Worked out once per change to the notes, not every time the sidebar draws.
    @Published private(set) var folderTree = FolderTree(notes: [])
    /// Folders and tags pinned to the top of the sidebar, in the order they were pinned.
    @Published private(set) var pins: [SidebarPlace] = []

    /// The notes listed in a place: those not in a folder (at the top level), those directly
    /// in a folder, or those with a tag (or a tag under it).
    func notes(in place: SidebarPlace) -> [Note] {
        switch place {
        case .allNotes: notes.filter { !$0.id.contains("/") }
        case .folder(let path): notes.filter { FolderTree.folder(of: $0.id) == path }
        case .tag(let tag): notes.filter { TagTree.tags(indexedTags[$0.id] ?? [], include: tag) }
        }
    }

    /// The folders or tags to show above the notes in a place, in the chosen order.
    func subplaces(of place: SidebarPlace) -> [SidebarPlace] {
        switch place {
        case .allNotes: sortedFolders(folderTree.subfolders(of: "")).map(SidebarPlace.folder)
        case .folder(let path): sortedFolders(folderTree.subfolders(of: path)).map(SidebarPlace.folder)
        case .tag(let tag): sortedTags(tagTree.children(of: tag)).map { .tag($0.tag) }
        }
    }

    /// When each folder, and each tag, last had a note in it edited (counting subfolders
    /// and nested tags), for sorting by date modified. Worked out once per change.
    private var latestEdits: (folders: [String: Date], tags: [String: Date]) {
        if let cached = latestEditsCache, cached.notes == notes.count, cached.generation == indexGeneration { return cached.value }
        var folders: [String: Date] = [:], tags: [String: Date] = [:]
        for note in notes {
            var folder = FolderTree.folder(of: note.id)
            while !folder.isEmpty {
                folders[folder] = max(folders[folder] ?? .distantPast, note.modified)
                folder = FolderTree.parent(of: folder)
            }
            for tag in listTags(for: note.id) {
                var parts = tag.lowercased().split(separator: "/").map(String.init)
                while !parts.isEmpty {
                    let key = parts.joined(separator: "/")
                    tags[key] = max(tags[key] ?? .distantPast, note.modified)
                    parts.removeLast()
                }
            }
        }
        latestEditsCache = (notes.count, indexGeneration, (folders, tags))
        return (folders, tags)
    }
    private var latestEditsCache: (notes: Int, generation: Int, value: (folders: [String: Date], tags: [String: Date]))?

    func sortedFolders(_ paths: [String]) -> [String] {
        guard tagOrder == .modified else { return paths } // Already in Finder order.
        let latest = latestEdits.folders
        return paths.sorted { (latest[$0] ?? .distantPast) > (latest[$1] ?? .distantPast) }
    }

    func sortedTags(_ entries: [TagTree.Entry]) -> [TagTree.Entry] {
        if tagOrder == .name {
            return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let latest = latestEdits.tags
        return entries.sorted { (latest[$0.id] ?? .distantPast) > (latest[$1.id] ?? .distantPast) }
    }

    /// Every tag in tree order (each parent followed by its children), in the chosen order.
    var sortedTagEntries: [TagTree.Entry] {
        func walk(_ entries: [TagTree.Entry]) -> [TagTree.Entry] {
            sortedTags(entries).flatMap { [$0] + walk(tagTree.children(of: $0.tag)) }
        }
        return walk(tagTree.entries.filter { $0.depth == 0 })
    }

    /// How many notes a folder or tag holds, including in its subfolders or nested tags.
    func noteCount(of place: SidebarPlace) -> Int {
        switch place {
        case .allNotes: notes.count
        case .folder(let path): folderTree.noteCounts[path] ?? 0
        case .tag(let tag): tagTree.entries.first { $0.id == tag.lowercased() }?.count ?? 0
        }
    }

    func isPinned(_ place: SidebarPlace) -> Bool { pins.contains(place) }

    func togglePin(_ place: SidebarPlace) {
        if let index = pins.firstIndex(of: place) { pins.remove(at: index) } else { pins.append(place) }
        if let root { UserDefaults.standard.set(pins.map(\.key), forKey: "pins." + Self.vaultKey(root)) }
    }

    /// The vault's top level, then its folders as a tree.
    var folderNodes: [VaultModel.PlaceNode] {
        func nodes(in path: String) -> [VaultModel.PlaceNode]? {
            let subfolders = sortedFolders(folderTree.subfolders(of: path))
            guard !subfolders.isEmpty else { return nil }
            return subfolders.map { VaultModel.PlaceNode(place: .folder($0), name: FolderTree.name(of: $0), children: nodes(in: $0)) }
        }
        let rootName = root?.lastPathComponent ?? "Vault"
        return [VaultModel.PlaceNode(place: .allNotes, name: rootName, children: nil)] + (nodes(in: "") ?? [])
    }

    /// Tags as a tree, in the chosen order.
    var tagNodes: [VaultModel.PlaceNode] {
        func nodes(under parent: String?) -> [VaultModel.PlaceNode]? {
            let entries = parent.map { tagTree.children(of: $0) } ?? tagTree.entries.filter { $0.depth == 0 }
            guard !entries.isEmpty else { return nil }
            return sortedTags(entries).map { VaultModel.PlaceNode(place: .tag($0.tag), name: "#" + $0.name, children: nodes(under: $0.tag)) }
        }
        return nodes(under: nil) ?? []
    }

    // MARK: Swipes

    /// The window in front, which swipes act on.
    weak var activeWindow: VaultModel?

    /// Two-finger swipes: left hides the front window's note list, right shows it.
    private lazy var swipe = SwipeToToggleNoteList(
        isNoteListShowing: { [weak self] in self?.activeWindow?.showsNoteList ?? true },
        onSwipe: { [weak self] toTheLeft in
            guard let window = self?.activeWindow, !window.isFocused, window.showsNoteList == toTheLeft else { return }
            window.showsNoteList = !toTheLeft
        }
    )

    /// Starts listening for swipes. Called when a window appears: AppKit doesn't deliver
    /// events to monitors added while the app is still starting up.
    func startSwipeTracking() {
        _ = swipe
    }
}
