import AppKit
import CryptoKit
import EditorKit
import IndexKit
import MarkdownKit
import VaultKit

extension Notification.Name {
    /// A note moved or was renamed: `userInfo` has "old" and "new" IDs. Windows follow it.
    static let pointNoteMoved = Notification.Name("PointNoteMoved")
    /// A folder moved: `old` and `new` are its paths.
    static let pointFolderMoved = Notification.Name("PointFolderMoved")
    /// A different vault was opened. Windows start afresh.
    static let pointVaultOpened = Notification.Name("PointVaultOpened")
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
        didSet {
            folderTree = FolderTree(notes: notes, folders: folders)
            // Only when notes come, go or are renamed, not when one is saved.
            let ids = Set(notes.map(\.id))
            if ids != noteIDs {
                noteIDs = ids
                linkResolver = LinkResolver(notes: notes)
                notesGeneration += 1
            }
        }
    }
    /// Resolves links against the notes as they are now.
    private(set) var linkResolver = LinkResolver(notes: [])
    /// Counts changes to the notes, so editors know to restyle their links.
    private(set) var notesGeneration = 0
    private var noteIDs: Set<Note.ID> = []
    /// Every folder on disk, including empty ones (which the notes alone wouldn't show).
    private var folders: [String] = [] {
        didSet { folderTree = FolderTree(notes: notes, folders: folders) }
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
            errorMessage = "Point couldn't remember this folder: \(error.localizedDescription)"
        }
        open(url)
    }

    func reload() async {
        guard let root else { return }
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try VaultScanner.scanWithFolders(root)
            }.value
            folders = scanned.folders
            notes = scanned.notes.sorted(by: sort)
            errorMessage = nil
            refreshTags()
            updateIndex()
        } catch {
            errorMessage = "Point couldn't read the vault: \(error.localizedDescription)"
        }
    }

    private func restoreVault() {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "PointVault") {
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
            errorMessage = "Point lost access to your vault. Open it again."
        }
    }

    private func open(_ url: URL) {
        watcher?.stop()
        root?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        root = url
        folders = []
        notes = []
        settings = ObsidianSettings.load(vault: url)
        indexedTags = [:]
        tagTree = TagTree(tagsByNote: [])
        pins = (UserDefaults.standard.stringArray(forKey: "pins." + Self.vaultKey(url)) ?? []).compactMap(SidebarPlace.init(key:))
        bookmarks = UserDefaults.standard.stringArray(forKey: "bookmarks." + Self.vaultKey(url)) ?? []
        openIndex(for: url)
        watcher = VaultWatcher(root: url) { [weak self] urls in
            Task { @MainActor in self?.filesChanged(urls) }
        }
        NotificationCenter.default.post(name: .pointVaultOpened, object: self)
        refreshTrash()
        Task { await reload() }
    }

    /// Something in the vault changed, here or elsewhere: rescan, and tell open notes.
    private func filesChanged(_ urls: [URL]) {
        NotificationCenter.default.post(name: .pointFilesChanged, object: self, userInfo: ["urls": urls])
        Task { await reload() }
    }

    // MARK: Creating, renaming and deleting

    /// Creates a folder called `name` inside `parent` ("" is the vault root) and returns its
    /// path, or nil (with a message) if it can't.
    func createFolder(named name: String, in parent: String) -> String? {
        guard let root else { return nil }
        // Folder names can't contain the path separators macOS and Obsidian use.
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else {
            errorMessage = "A folder needs a name that doesn't start with a dot."
            return nil
        }
        let path = parent.isEmpty ? clean : parent + "/" + clean
        let url = root.appendingPathComponent(path, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "There's already a folder or file called \"\(clean)\" there."
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            folders.append(path)
            return path
        } catch {
            errorMessage = "Point couldn't make the folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// Creates a note in `folder` ("" is the vault root) and returns its ID: untitled (to be
    /// named by its first line), unless given a title.
    func createNote(text: String = "", titled title: String? = nil, inFolder folder: String) -> Note.ID? {
        guard let root else { return nil }
        do {
            let url = try NoteFiles.create(title: title ?? NoteFiles.untitledName(), text: text,
                                           in: folder.isEmpty ? root : root.appendingPathComponent(folder))
            let id = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
            add(Note(id: id, url: url, title: url.deletingPathExtension().lastPathComponent,
                     modified: Date(), created: Date(), isDownloaded: true))
            if title == nil { untitled.insert(id) }
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
        // A bookmark follows its note.
        if let index = bookmarks.firstIndex(of: note.id) {
            bookmarks[index] = newID
            saveBookmarks()
        }
        NotificationCenter.default.post(name: .pointNoteMoved, object: self, userInfo: ["old": note.id, "new": newID])
    }

    /// Moves a note to the vault's trash (its `.trash` folder, whatever Obsidian is set to:
    /// only notes there can be listed and put back), remembering when, and where from.
    func moveToTrash(_ note: Note) {
        guard let root else { return }
        releaseFile(note.url)
        untitled.remove(note.id)
        do {
            let name = try VaultTrash.move(note.url, vault: root)
            trashRecords[name] = VaultTrash.Record(deleted: Date(), folder: FolderTree.folder(of: note.id))
            notes.removeAll { $0.id == note.id }
            refreshTrash()
        } catch {
            errorMessage = "Couldn't move “\(note.title)” to the trash: \(error.localizedDescription)"
        }
    }

    // MARK: Trash

    /// The notes in the vault's trash, newest first.
    @Published private(set) var trashedNotes: [VaultTrash.Item] = []
    /// How long deleted notes are kept before they go for good.
    @Published var trashRetentionDays: Int = UserDefaults.standard.object(forKey: "trashRetentionDays") as? Int ?? 30 {
        didSet {
            UserDefaults.standard.set(trashRetentionDays, forKey: "trashRetentionDays")
            refreshTrash()
        }
    }

    /// When each note in the trash was deleted, and where from, by its name there. Kept by
    /// the app, per vault, not in the vault.
    private var trashRecords: [String: VaultTrash.Record] {
        get {
            guard let root, let data = UserDefaults.standard.data(forKey: "trash." + Self.vaultKey(root)) else { return [:] }
            return (try? JSONDecoder().decode([String: VaultTrash.Record].self, from: data)) ?? [:]
        }
        set {
            guard let root else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "trash." + Self.vaultKey(root))
        }
    }

    /// Lists the trash, removing for good the notes kept longer than the set number of days.
    /// A note found there with no record (put there by Obsidian, say) starts its days now.
    func refreshTrash() {
        guard let root else { return trashedNotes = [] }
        var records = trashRecords
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(max(trashRetentionDays, 1)) * 86_400)
        var items: [VaultTrash.Item] = []
        for item in VaultTrash.items(in: root, records: records, now: now) {
            if item.deleted < cutoff {
                try? VaultTrash.delete(item)
                records[item.name] = nil
            } else {
                if records[item.name] == nil { records[item.name] = VaultTrash.Record(deleted: now, folder: item.folder ?? "") }
                items.append(item)
            }
        }
        // Forget notes no longer there (emptied or put back elsewhere).
        let names = Set(items.map(\.name))
        records = records.filter { names.contains($0.key) }
        if records != trashRecords { trashRecords = records }
        if items != trashedNotes { trashedNotes = items }
    }

    /// Puts a note back where it was (or at the top level, if its folder is gone).
    func restore(_ item: VaultTrash.Item) {
        guard let root else { return }
        do {
            _ = try VaultTrash.restore(item, vault: root)
            trashRecords[item.name] = nil
            refreshTrash()
            Task { await reload() }
        } catch {
            errorMessage = "Couldn't put back “\(item.title)”: \(error.localizedDescription)"
        }
    }

    func deleteForever(_ item: VaultTrash.Item) {
        do {
            try VaultTrash.delete(item)
            refreshTrash()
        } catch {
            errorMessage = "Couldn't delete “\(item.title)”: \(error.localizedDescription)"
        }
    }

    func emptyTrash() {
        trashedNotes.forEach { try? VaultTrash.delete($0) }
        refreshTrash()
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
            NotificationCenter.default.post(name: .pointSaveNow, object: self)
            Task.detached(priority: .userInitiated) {
                let result = LinkUpdater.updateLinks(afterMoving: note, to: newID, notes: vaultBeforeMove, root: root)
                if !result.skippedNotes.isEmpty {
                    NSLog("Point: links not updated in \(result.skippedNotes) (changed while updating)")
                }
            }
            Task { await reload() }
        } catch {
            errorMessage = "Couldn't move “\(note.title)”: \(error.localizedDescription)"
        }
    }

    /// Moves a folder, with its notes and folders, into another folder ("" is the vault
    /// root). Open notes save first and keep showing, under their new paths. Links by name,
    /// as Obsidian makes them, keep working; links written as paths aren't rewritten.
    func moveFolder(_ path: String, into parent: String) {
        guard let root, !path.isEmpty, FolderTree.parent(of: path) != parent else { return }
        let prefix = path + "/"
        let moving = notes.filter { $0.id.hasPrefix(prefix) }
        NotificationCenter.default.post(name: .pointSaveNow, object: self)
        moving.forEach { releaseFile($0.url) }
        do {
            let url = try NoteFiles.moveFolder(root.appendingPathComponent(path),
                                               into: parent.isEmpty ? root : root.appendingPathComponent(parent))
            let newPath = parent.isEmpty ? url.lastPathComponent : parent + "/" + url.lastPathComponent
            for note in moving {
                let newID = newPath + "/" + note.id.dropFirst(prefix.count)
                replace(note, with: newID, url: root.appendingPathComponent(newID))
            }
            // Pins to the folder, or to folders inside it, follow it.
            let moved = pins.map { pin -> SidebarPlace in
                guard case .folder(let pinned) = pin, pinned == path || pinned.hasPrefix(prefix) else { return pin }
                return .folder(newPath + pinned.dropFirst(path.count))
            }
            if moved != pins {
                pins = moved
                UserDefaults.standard.set(pins.map(\.key), forKey: "pins." + Self.vaultKey(root))
            }
            NotificationCenter.default.post(name: .pointFolderMoved, object: self, userInfo: ["old": path, "new": newPath])
            Task { await reload() }
        } catch {
            errorMessage = "Couldn't move “\(FolderTree.name(of: path))”: \(error.localizedDescription)"
        }
    }

    /// Points every link to `note` at its new title, in the background. Open notes save
    /// first, and pick up the rewritten links through the vault watcher.
    private func updateLinks(to note: Note, newTitle: String, vault: [Note]) {
        NotificationCenter.default.post(name: .pointSaveNow, object: self)
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newTitle, notes: vault)
            if !result.skippedNotes.isEmpty {
                NSLog("Point: links not updated in \(result.skippedNotes) (changed while updating)")
            }
        }
    }

    /// Asks any editor showing this file to save now and stop writing to it.
    private func releaseFile(_ url: URL) {
        NotificationCenter.default.post(name: .pointReleaseFile, object: self, userInfo: ["url": url])
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

    /// Narrowing the window past a width hides the sidebar, and widening it again brings it
    /// back. On unless turned off.
    @Published var autoHidesSidebar = UserDefaults.standard.object(forKey: "autoHidesSidebar") == nil || UserDefaults.standard.bool(forKey: "autoHidesSidebar") {
        didSet { UserDefaults.standard.set(autoHidesSidebar, forKey: "autoHidesSidebar") }
    }
    /// The window width, in points, below which the sidebar hides.
    @Published var sidebarAutoHideWidth: Double = UserDefaults.standard.object(forKey: "sidebarAutoHideWidth") == nil ? 760 : UserDefaults.standard.double(forKey: "sidebarAutoHideWidth") {
        didSet { UserDefaults.standard.set(sidebarAutoHideWidth, forKey: "sidebarAutoHideWidth") }
    }
    /// A two-finger swipe shows and hides the sidebar. Off unless turned on: it's easily
    /// set off by accident.
    @Published var swipesSidebar = UserDefaults.standard.bool(forKey: "swipesSidebar") {
        didSet { UserDefaults.standard.set(swipesSidebar, forKey: "swipesSidebar") }
    }
    /// On unless turned off.
    @Published var showsDateInList = UserDefaults.standard.object(forKey: "showsDateInList") == nil || UserDefaults.standard.bool(forKey: "showsDateInList") {
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
    /// Whether each note's properties are open, this session. Not published: each strip
    /// keeps its own state and only writes here.
    var propertiesOpen: [Note.ID: Bool] = [:]
    /// The body's size and line height, and each heading's size and style.
    @Published var typography: Typography = UserDefaults.standard.data(forKey: "typography")
        .flatMap { try? JSONDecoder().decode(Typography.self, from: $0) } ?? Typography() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(typography), forKey: "typography") }
    }
    /// The widest a note's text column gets, in points (Settings › Text). Wider windows
    /// centre it.
    @Published var textColumnWidth: Double = UserDefaults.standard.object(forKey: "textColumnWidth") as? Double ?? 720 {
        didSet { UserDefaults.standard.set(textColumnWidth, forKey: "textColumnWidth") }
    }
    static let textColumnWidths: ClosedRange<Double> = 480...1200
    @Published var textScale: Double = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(textScale, forKey: "textScale") }
    }
    /// The saved sidebar layout. The draft "Minimal" layout became "one column, with the
    /// sidebar hidden", so a saved Minimal turns into just that.
    private static func savedBrowsingStyle() -> VaultModel.BrowsingStyle {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "browsingStyle") == "minimal" {
            defaults.set(VaultModel.BrowsingStyle.singleColumn.rawValue, forKey: "browsingStyle")
            defaults.set(false, forKey: "showsNoteList")
        }
        return VaultModel.BrowsingStyle(rawValue: defaults.string(forKey: "browsingStyle") ?? "") ?? .singleColumn
    }

    @Published var browsingStyle = VaultStore.savedBrowsingStyle() {
        didSet { UserDefaults.standard.set(browsingStyle.rawValue, forKey: "browsingStyle") }
    }
    /// How folders and tags are sorted, in both layouts.
    @Published var tagOrder = VaultModel.TagOrder(rawValue: UserDefaults.standard.string(forKey: "tagOrder") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(tagOrder.rawValue, forKey: "tagOrder") }
    }
    /// The two-column view's left column: folders and tags together, or one at a time.
    /// How tightly the sidebar's rows are packed, in both layouts.
    @Published var sidebarDensity = VaultModel.SidebarDensity(rawValue: UserDefaults.standard.string(forKey: "sidebarDensity") ?? "") ?? .comfortable {
        didSet { UserDefaults.standard.set(sidebarDensity.rawValue, forKey: "sidebarDensity") }
    }
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
            // Still where it was when the app was called Imprint, so it isn't built again.
            .appendingPathComponent("Imprint/Index", isDirectory: true)
        index = try? SearchIndex(url: folder.appendingPathComponent("\(Self.vaultKey(url)).sqlite"))
    }

    /// A short, stable name for a vault, from a hash of its path.
    /// Whether a window has already opened the way the app was left, this launch: only the
    /// first window does. Later ones start fresh.
    private var hasRestoredWindow = false

    func claimWindowRestore() -> Bool {
        defer { hasRestoredWindow = true }
        return !hasRestoredWindow
    }

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
        case .everything: notes
        case .bookmarks: bookmarkedNotes
        case .trash: []
        case .folder(let path): notes.filter { FolderTree.folder(of: $0.id) == path }
        case .tag(let tag): notes.filter { TagTree.tags(indexedTags[$0.id] ?? [], include: tag) }
        }
    }

    /// The folders or tags to show above the notes in a place, in the chosen order.
    func subplaces(of place: SidebarPlace) -> [SidebarPlace] {
        switch place {
        case .allNotes: sortedFolders(folderTree.subfolders(of: "")).map(SidebarPlace.folder)
        case .everything, .bookmarks, .trash: []
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
        case .allNotes, .everything: notes.count
        case .trash: trashedNotes.count
        case .bookmarks: bookmarkedNotes.count
        case .folder(let path): folderTree.noteCounts[path] ?? 0
        case .tag(let tag): tagTree.entries.first { $0.id == tag.lowercased() }?.count ?? 0
        }
    }

    func isPinned(_ place: SidebarPlace) -> Bool { pins.contains(place) }

    /// Notes bookmarked, in the order they were bookmarked, for the vault. Kept by ID, so a
    /// bookmark to a note moved outside Point (or deleted) is simply not listed.
    @Published private(set) var bookmarks: [Note.ID] = []

    /// The bookmarked notes that exist.
    var bookmarkedNotes: [Note] {
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return bookmarks.compactMap { byID[$0] }
    }

    func isBookmarked(_ id: Note.ID) -> Bool { bookmarks.contains(id) }

    func toggleBookmark(_ id: Note.ID) {
        if let index = bookmarks.firstIndex(of: id) { bookmarks.remove(at: index) } else { bookmarks.append(id) }
        saveBookmarks()
    }

    private func saveBookmarks() {
        if let root { UserDefaults.standard.set(bookmarks, forKey: "bookmarks." + Self.vaultKey(root)) }
    }

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

    /// Two-finger swipes, when turned on: left hides the front window's note list, right
    /// shows it.
    private lazy var swipe = SwipeToToggleNoteList(
        acceptsSwipe: { [weak self] event in
            guard let self, swipesSidebar, let model = activeWindow, let window = event.window, window === model.window else { return false }
            // Not over the top bars, where the tabs scroll sideways.
            return event.locationInWindow.y < window.frame.height - model.topBarHeight
        },
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
