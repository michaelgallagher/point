import AppKit
import CryptoKit
import EditorKit
import IndexKit
import MarkdownKit
import UniformTypeIdentifiers
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
            listVersion += 1
            notesByID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            folderTree = FolderTree(notes: notes, folders: folders)
            // Only when notes come, go or are renamed, not when one is saved.
            let ids = Set(notes.map(\.id))
            if ids != noteIDs {
                noteIDs = ids
                linkResolver = LinkResolver(notes: notes)
                titleIndex = nil
                notesGeneration += 1
            }
        }
    }
    /// Goes up whenever a note, or its tags, changes, so the list can tell when nothing it
    /// shows has (as when only the tab shown has changed).
    private(set) var listVersion = 0
    /// The notes by ID, to find one without going through them all.
    private(set) var notesByID: [Note.ID: Note] = [:]
    /// Resolves links against the notes as they are now.
    private(set) var linkResolver = LinkResolver(notes: [])
    /// Counts changes to the notes, so editors know to restyle their links.
    private(set) var notesGeneration = 0
    private var noteIDs: Set<Note.ID> = []
    /// The vault's images, wherever they are.
    @Published private(set) var images: [VaultImage] = [] {
        didSet {
            imagesByPath = Dictionary(images.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            let byName = VaultImages.byName(images)
            // Editors restyle when an image comes or goes, as when a note does.
            if Set(byName.keys) != Set(imagesByName.keys) { notesGeneration += 1 }
            imagesByName = byName
        }
    }
    /// The images by file name, in lowercase, as embeds find them.
    private(set) var imagesByName: [String: VaultImage] = [:]
    private var imagesByPath: [String: VaultImage] = [:]

    /// The image at a path from the vault's root (what a tab showing it holds).
    func image(_ path: String?) -> VaultImage? { path.flatMap { imagesByPath[$0] } }

    /// The images straight inside a folder, by name.
    func images(in place: SidebarPlace) -> [VaultImage] {
        guard case .folder(let folder) = place else { return [] }
        return images.filter { ($0.path as NSString).deletingLastPathComponent == folder }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Every note's title, lowercased and in words, for completing links as they're typed
    /// without going through every title again at each keystroke. Built when first needed
    /// after notes come, go or are renamed.
    private var titleIndex: [(title: String, lowered: String, words: [Substring])]?
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
    #if DEBUG
    func isUntitled(_ id: Note.ID) -> Bool { untitled.contains(id) }
    #endif

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let sort = "noteSort"
    }

    init() {
        sort = UserDefaults.standard.string(forKey: Keys.sort).flatMap(NoteSort.init) ?? .modified
        restoreVault()
        // Changes can go unreported while the Mac sleeps: the whole vault is looked at again
        // when it wakes. If the vault can't be watched at all, whenever Point comes to the front.
        // (A scan reads only what's changed; the rest costs a file listing.)
        appObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.missedChanges() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in if self?.watcher?.isWatching == false { self?.missedChanges() } }
            },
        ]
    }

    private var appObservers: [NSObjectProtocol] = []

    // MARK: Opening the vault

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open vault"
        panel.message = "Choose the folder that holds your notes. It can be an existing Obsidian vault."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try VaultLocation.bookmark(for: url), forKey: Keys.bookmark)
        } catch {
            errorMessage = "Point couldn't remember this folder: \(error.localizedDescription)"
        }
        open(url)
    }

    /// Counts the vaults opened, so work started for one is dropped if another opens first.
    private var vaultGeneration = 0
    /// The scan running now, which a reload asked for meanwhile waits for.
    private var scanning: Task<Void, Never>?
    /// Whether something changed during the scan running now, so another is needed after it.
    private var rescanWanted = false

    /// Scans the vault again and shows what's there. One scan at a time: asked for while one
    /// is running (as a burst of changes from iCloud does), one more runs after it, which
    /// this waits for. (Each change started its own scan, and an older one finishing last
    /// showed the vault as it was; one finishing after another vault opened showed its notes
    /// in that vault.)
    func reload() async {
        if let scanning {
            rescanWanted = true
            return await scanning.value
        }
        let generation = vaultGeneration
        let task = Task { [weak self] in
            repeat {
                self?.rescanWanted = false
                await self?.scan(generation: generation)
            } while self?.rescanWanted == true && self?.vaultGeneration == generation
            // In the same step as the last check, so a reload asked for after it starts anew.
            if self?.vaultGeneration == generation { self?.scanning = nil }
        }
        scanning = task
        await task.value
    }

    #if DEBUG
    /// Scans started, and finished with their results shown, for checking coalescing.
    private(set) var debugScans = (started: 0, shown: 0)
    func debugOpen(_ url: URL) { open(url) }
    #endif

    private func scan(generation: Int) async {
        guard let root else { return }
        #if DEBUG
        debugScans.started += 1
        #endif
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try VaultScanner.scanAll(root)
            }.value
            guard generation == vaultGeneration else { return Trace.mark("scan dropped: another vault opened") }
            Trace.mark("rescanned: \(scanned.notes.count) notes")
            #if DEBUG
            debugScans.shown += 1
            #endif
            folders = scanned.folders
            if scanned.images != images { images = scanned.images }
            notes = scanned.notes.sorted(by: sort)
            forgetDeletedNotes()
            propertyTypes = PropertyTypes.load(vault: root) // Obsidian may have changed them.
            errorMessage = nil
            refreshTags()
            updateIndex()
        } catch {
            guard generation == vaultGeneration else { return }
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
        vaultGeneration += 1
        scanning = nil
        rescanWanted = false
        watcher?.stop()
        root?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        root = url
        folders = []
        notes = []
        settings = ObsidianSettings.load(vault: url)
        propertyTypes = PropertyTypes.load(vault: url)
        pointTypes = PointTypes.load(vault: url)
        indexedTags = [:]
        propertyValues = [:]
        propertySummaries = []
        queryResults = [:]
        valueListCache = [:]
        tagTree = TagTree(tagsByNote: [])
        pins = (UserDefaults.standard.stringArray(forKey: "pins." + Self.vaultKey(url)) ?? []).compactMap(SidebarPlace.init(key:))
        bookmarks = UserDefaults.standard.stringArray(forKey: "bookmarks." + Self.vaultKey(url)) ?? []
        openIndex(for: url)
        openSearchHistory(for: url)
        watcher = VaultWatcher(root: url, onChange: { [weak self] urls in
            Task { @MainActor in self?.filesChanged(urls) }
        }, onMissedChanges: { [weak self] in
            Task { @MainActor in self?.missedChanges() }
        })
        if watcher?.isWatching != true {
            Self.showProblem("Point can’t watch this vault for changes",
                             detail: "Changes made in Obsidian or on other devices will show when Point next comes to the front.")
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

    /// Changes may have gone unreported: rescan, and have every open note check its file.
    private func missedChanges() {
        guard root != nil else { return }
        Trace.mark("rescanning everything")
        NotificationCenter.default.post(name: .pointFilesChanged, object: self, userInfo: ["urls": [URL](), "all": true])
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
    /// named by its first line), unless given a title. Point names it with the day and its title
    /// (`2026-11-06-title.md`, the title in its `title:`), unless `dated` is false (templates,
    /// named as their title).
    func createNote(text: String = "", titled title: String? = nil, inFolder folder: String, dated: Bool = true) -> Note.ID? {
        guard let root else { return nil }
        do {
            let directory = folder.isEmpty ? root : root.appendingPathComponent(folder)
            let url = dated ? try NoteFiles.createDated(title: title, text: text, in: directory)
                : try NoteFiles.create(title: title ?? NoteFiles.untitledName(), text: text, in: directory)
            let id = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
            let name = url.deletingPathExtension().lastPathComponent
            add(Note(id: id, url: url, title: dated ? (title ?? NoteNames.fallbackTitle(for: name)) : name,
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
    func finishUntitledNote(_ id: Note.ID, removingIfEmpty: Bool = true) {
        guard untitled.contains(id), let note = notes.first(where: { $0.id == id }) else { return }
        // Its edits saved first, and read back: only a note known to be empty is removed. If
        // either fails, it stays as it is, untitled (the editor says why it couldn't save).
        guard EditorSession.save(note.url) else { return }
        let text: String
        do {
            text = try NoteReader.read(contentsOf: note.url)
        } catch {
            NSLog("Point: couldn't read \(note.id) to name it: \(error.localizedDescription)")
            return
        }
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Empty but kept (still open in a tab): stays untitled, to be named when it has text.
        if isEmpty, !removingIfEmpty { return }
        if isEmpty {
            do {
                try FileManager.default.removeItem(at: note.url) // Empty, and created by us moments ago.
            } catch {
                Self.showProblem("Couldn’t remove the empty note “\(note.title)”", error)
                return
            }
            untitled.remove(id)
            EditorSession.release(note.url)
            notes.removeAll { $0.id == id }
            return
        }
        untitled.remove(id)
        guard let line = PlainText.firstLine(of: text) else { return }
        // Named by Point: its first line is its title, and its name follows.
        if NoteNames.isDated(note.name) {
            retitle(note, to: line, text: text)
            return
        }
        let title = NoteFiles.sanitizedTitle(line)
        guard !title.isEmpty, title != note.title else { return }
        let available = NoteFiles.availableURL(for: title, in: note.url.deletingLastPathComponent())
        let url: URL
        do {
            url = try NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent)
        } catch {
            // Kept as it is, under its untitled name, and still saving.
            NSLog("Point: couldn't name \(note.id) “\(title)”: \(error.localizedDescription)")
            return
        }
        EditorSession.release(note.url)
        renameImages(of: note, to: url)
        // Windows (a tab still holding it, behind) follow it to its new name.
        let folder = FolderTree.folder(of: note.id)
        replace(note, with: folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent, url: url)
        Task { await reload() }
    }

    /// Renames a note, updating links to it everywhere. Windows showing it follow along.
    func rename(_ note: Note, to title: String) {
        // Saved first; only once it's renamed do its editors stop writing to it. (Let go of
        // first, a rename that failed, say to a name already taken, left the note open but
        // no longer saving.)
        guard saveBeforeMoving([note], "renamed") else { return }
        if NoteNames.isDated(note.name) {
            guard let text = try? NoteReader.read(contentsOf: note.url) else {
                return Self.showProblem("Couldn’t rename “\(note.title)”", detail: "Point couldn’t read the note.")
            }
            return retitle(note, to: title, text: text)
        }
        do {
            let vaultBeforeRename = notes
            let url = try NoteFiles.rename(note.url, to: title)
            EditorSession.release(note.url)
            untitled.remove(note.id)
            renameImages(of: note, to: url)
            updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, vault: vaultBeforeRename)
            let folders = note.id.split(separator: "/").dropLast().joined(separator: "/")
            let newID = folders.isEmpty ? url.lastPathComponent : "\(folders)/\(url.lastPathComponent)"
            replace(note, with: newID, url: url)
            Task { await reload() }
        } catch {
            Self.showProblem("Couldn’t rename “\(note.title)”", error)
        }
    }

    /// Gives a note Point named a new title: its `title:` set, and its name following, with the
    /// day it was made kept (`2026-11-06-new-title.md`). Links to it are updated, and their
    /// labels too where they were its old title. `text` is the note as it is on disk.
    private func retitle(_ note: Note, to newTitle: String, text: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !title.isEmpty, title != note.title || NoteNames.title(in: text) == nil else { return }
        let retitled = NoteNames.settingTitle(title, in: text)
        do {
            switch try NoteWriter.write(retitled, to: note.url, expecting: text, ifChanged: .report) {
            case .saved: break
            default: return Self.showProblem("Couldn’t rename “\(note.title)”", detail: "The note changed while Point was renaming it. Try again.")
            }
        } catch {
            return Self.showProblem("Couldn’t rename “\(note.title)”", error)
        }
        let vaultBefore = notes
        var url = note.url
        if let name = NoteNames.renamed(note.name, to: title), name != note.name {
            let available = NoteFiles.availableDatedURL(for: name, in: note.url.deletingLastPathComponent(), excluding: note.url)
            do {
                url = try NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent)
            } catch {
                // The title's set; the file keeps its name, which is fine (links still work).
                NSLog("Point: couldn't rename \(note.id) for its new title: \(error.localizedDescription)")
            }
        }
        if url != note.url {
            EditorSession.release(note.url)
            renameImages(of: note, to: url)
        }
        updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, vault: vaultBefore, retitling: (note.title, title))
        let folder = FolderTree.folder(of: note.id)
        replace(note, with: folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent, url: url, title: title)
        Task { await reload() }
    }

    /// Updates a note's place in the list and tells windows its new ID.
    private func replace(_ note: Note, with newID: Note.ID, url: URL, title: String? = nil) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            let name = url.deletingPathExtension().lastPathComponent
            notes[index] = Note(id: newID, url: url, title: title ?? NoteNames.shownTitle(name: name, url: url),
                                modified: note.modified, created: note.created, isDownloaded: true)
        }
        if untitled.remove(note.id) != nil { untitled.insert(newID) }
        // What search has learned about it follows it too.
        searchHistory.renamed(from: note.id, to: newID)
        if pendingOpen?.id == note.id { pendingOpen?.id = newID }
        saveSearchHistory()
        // A bookmark follows its note.
        if let index = bookmarks.firstIndex(of: note.id) {
            bookmarks[index] = newID
            saveBookmarks()
        }
        NotificationCenter.default.post(name: .pointNoteMoved, object: self, userInfo: ["old": note.id, "new": newID])
    }

    /// Moves a note to the vault's trash (its `.trash` folder, whatever Obsidian is set to:
    /// only notes there can be listed and put back), remembering when, and where from.
    /// Returns whether it was moved.
    @discardableResult
    func moveToTrash(_ note: Note) -> Bool {
        guard let root, saveBeforeMoving([note], "moved to the trash") else { return false }
        do {
            let shown = imagesShown(by: note)
            let name = try VaultTrash.move(note.url, vault: root)
            EditorSession.release(note.url)
            untitled.remove(note.id)
            trashRecords[name] = VaultTrash.Record(deleted: Date(), folder: FolderTree.folder(of: note.id), deletedByPoint: true)
            trashImages(shown, withNote: note, trashedAs: name)
            notes.removeAll { $0.id == note.id }
            refreshTrash()
            return true
        } catch {
            Self.showProblem("Couldn’t move “\(note.title)” to the trash", error)
            return false
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

    /// Lists the trash, removing for good the notes Point deleted longer ago than the set
    /// number of days. Notes found there (put there by Obsidian, say) stay until the trash is
    /// emptied, as they would in Obsidian. A note that can't be removed stays listed.
    func refreshTrash() {
        guard let root else { return trashedNotes = [] }
        var records = trashRecords
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(max(trashRetentionDays, 1)) * 86_400)
        let all = VaultTrash.items(in: root, records: records, now: now)
        var removed = Set<String>()
        for item in VaultTrash.expired(all, before: cutoff) {
            do {
                try VaultTrash.delete(item)
                VaultTrash.delete(records[item.name]?.images ?? [], vault: root)
                removed.insert(item.name)
            } catch {
                NSLog("Point: couldn't remove \(item.name) from the trash: \(error.localizedDescription)")
            }
        }
        var items: [VaultTrash.Item] = []
        for item in all where !removed.contains(item.name) {
            if records[item.name] == nil { records[item.name] = VaultTrash.Record(deleted: now, folder: item.folder ?? "", deletedByPoint: false) }
            items.append(item)
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
            VaultTrash.restore(trashRecords[item.name]?.images ?? [], vault: root)
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
            if let root { VaultTrash.delete(trashRecords[item.name]?.images ?? [], vault: root) }
            refreshTrash()
        } catch {
            errorMessage = "Couldn't delete “\(item.title)”: \(error.localizedDescription)"
        }
    }

    func emptyTrash() {
        var failed: [String] = []
        var firstError: Error?
        let records = trashRecords
        for item in trashedNotes {
            do {
                try VaultTrash.delete(item)
                if let root { VaultTrash.delete(records[item.name]?.images ?? [], vault: root) }
            } catch {
                failed.append(item.title)
                firstError = firstError ?? error
            }
        }
        refreshTrash()
        if let firstError {
            Self.showProblem("Couldn’t delete \(failed.count == 1 ? "“\(failed[0])”" : "\(failed.count) notes") from the trash", firstError)
        }
    }

    /// Moves a note into a folder ("" is the vault root), keeping links to it working.
    func move(noteID: Note.ID, toFolder folder: String) {
        guard let root, let note = notes.first(where: { $0.id == noteID }),
              FolderTree.folder(of: note.id) != folder, saveBeforeMoving([note], "moved") else { return }
        let vaultBeforeMove = notes
        do {
            let url = try NoteFiles.move(note.url, toFolder: folder.isEmpty ? root : root.appendingPathComponent(folder))
            EditorSession.release(note.url)
            let newID = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
            replace(note, with: newID, url: url)
            NotificationCenter.default.post(name: .pointSaveNow, object: self)
            Task.detached(priority: .userInitiated) {
                let result = LinkUpdater.updateLinks(afterMoving: note, to: newID, notes: vaultBeforeMove, root: root)
                await Self.report(result, for: note.title)
                await self.announce(result.updatedNotes.filter { $0 != newID }, to: note.title)
            }
            Task { await reload() }
        } catch {
            Self.showProblem("Couldn’t move “\(note.title)”", error)
        }
    }

    /// Moves a folder, with its notes and folders, into another folder ("" is the vault
    /// root). Open notes save first and keep showing, under their new paths. Links by name,
    /// as Obsidian makes them, keep working; links written as paths aren't rewritten.
    func moveFolder(_ path: String, into parent: String) {
        guard let root, !path.isEmpty, FolderTree.parent(of: path) != parent else { return }
        let prefix = path + "/"
        let moving = notes.filter { $0.id.hasPrefix(prefix) }
        guard saveBeforeMoving(moving, "moved") else { return }
        do {
            let url = try NoteFiles.moveFolder(root.appendingPathComponent(path),
                                               into: parent.isEmpty ? root : root.appendingPathComponent(parent))
            moving.forEach { EditorSession.release($0.url) }
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
            Self.showProblem("Couldn’t move “\(FolderTree.name(of: path))”", error)
        }
    }

    /// Points every link to `note` at its new title, in the background. Open notes save
    /// first, and pick up the rewritten links through the vault watcher.
    private func updateLinks(to note: Note, newTitle: String, vault: [Note], retitling: (from: String, to: String)? = nil) {
        NotificationCenter.default.post(name: .pointSaveNow, object: self)
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newTitle, notes: vault, retitling: retitling)
            await Self.report(result, for: note.title)
            await self.announce(result.updatedNotes.filter { $0 != note.id }, to: newTitle)
        }
    }

    // MARK: Changes across the vault

    /// What's renamed across the vault: a property, one of its values, or a tag.
    enum VaultRename: Identifiable, Equatable {
        case property(String)
        case value(property: String, value: String)
        case tag(String)

        var id: String {
            switch self {
            case .property(let name): "property:" + name
            case .value(let name, let value): "value:" + name + "\u{1F}" + value
            case .tag(let tag): "tag:" + tag
            }
        }

        /// The name as it is now.
        var current: String {
            switch self {
            case .property(let name): name
            case .value(_, let value): value
            case .tag(let tag): tag
            }
        }

        /// Which notes it may be in, as the index finds them.
        var query: NoteQuery {
            switch self {
            case .property(let name): NoteQuery([.property(name, .exists)])
            case .value(let name, let value) where ["tags", "tag"].contains(name.lowercased()): NoteQuery([.tag(value)])
            case .value(let name, let value): NoteQuery([.property(name, .equals(value))])
            case .tag(let tag): NoteQuery([.tag(tag)])
            }
        }
    }

    /// The last change made across the vault, until undone or another is made.
    @Published private(set) var lastVaultChange: VaultChange?
    /// "Renamed “status” to “state” in 12 notes", shown for a moment, with Undo.
    @Published var vaultChangeNotice: VaultChangeNotice?

    struct VaultChangeNotice: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// Whether it can still be undone.
        var canUndo: Bool
    }

    /// Renames a property, a value or a tag in every note that has it, as one change that can
    /// be undone. Open notes are saved first, and pick the change up from their files.
    func rename(_ rename: VaultRename, to newName: String) {
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard let index, !new.isEmpty, new != rename.current else { return }
        NotificationCenter.default.post(name: .pointSaveNow, object: self)
        let byID = notesByID
        let generation = vaultGeneration
        let label: String = switch rename {
        case .property: "Renamed the property “\(rename.current)” to “\(new)”"
        case .value(_, let value): "Changed “\(PropertyValueText.shown(value))” to “\(PropertyValueText.shown(new))”"
        case .tag(let tag): "Renamed #\(tag) to #\(new)"
        }
        Task {
            // The notes it's in, from the index; each is read again before it's changed.
            let ids = (try? await index.notes(matching: rename.query)) ?? []
            let candidates = ids.compactMap { byID[$0] }
            let change = await Task.detached(priority: .userInitiated) {
                VaultChanges.apply(label, to: candidates) { text in
                    switch rename {
                    case .property(let name): try VaultChanges.renamingProperty(name, to: new, in: text)
                    case .value(let name, let value) where ["tags", "tag"].contains(name.lowercased()):
                        VaultChanges.renamingTag(value, to: new, in: text)
                    case .value(let name, let value): VaultChanges.renamingValue(value, to: new, ofProperty: name, in: text)
                    case .tag(let tag): VaultChanges.renamingTag(tag, to: new, in: text)
                    }
                }
            }.value
            guard generation == vaultGeneration else { return }
            if case .property(let name) = rename, !change.edits.isEmpty { renamePropertyType(name, to: new) }
            lastVaultChange = change.edits.isEmpty ? nil : change
            let count = change.edits.count
            vaultChangeNotice = VaultChangeNotice(text: count == 0 ? "Nothing to change" : "\(label) in \(count == 1 ? "1 note" : "\(count) notes")",
                                                  canUndo: count > 0)
            Self.report(change)
            Task { await reload() }
        }
    }

    /// Undoes the last change across the vault, in the notes not changed since.
    func undoLastVaultChange() {
        guard let change = lastVaultChange else { return }
        lastVaultChange = nil
        NotificationCenter.default.post(name: .pointSaveNow, object: self)
        Task {
            let missed = await Task.detached(priority: .userInitiated) { VaultChanges.undo(change) }.value
            vaultChangeNotice = VaultChangeNotice(text: missed.isEmpty ? "Undone" : "Undone, except in \(missed.count == 1 ? "1 note" : "\(missed.count) notes") changed since",
                                                  canUndo: false)
            Task { await reload() }
        }
    }

    /// Says which notes a change across the vault left alone, and why.
    private static func report(_ change: VaultChange) {
        let missed = change.skippedNotes + change.unreadNotes
        guard !missed.isEmpty || !change.clashingNotes.isEmpty else { return }
        func names(_ ids: [String]) -> String {
            ids.prefix(8).map { "• " + ($0 as NSString).deletingPathExtension }.joined(separator: "\n") + (ids.count > 8 ? "\n…and \(ids.count - 8) more" : "")
        }
        var detail = ""
        if !change.clashingNotes.isEmpty {
            detail += "These notes already have a property with the new name, so they were left as they are:\n\n\(names(change.clashingNotes))"
        }
        if !missed.isEmpty {
            if !detail.isEmpty { detail += "\n\n" }
            detail += "These notes were changed while Point was updating them, or aren’t downloaded from iCloud yet:\n\n\(names(missed))"
        }
        showProblem("Some notes weren’t changed", detail: detail)
    }

    /// Notes whose links were just updated after a rename or move, shown for a moment.
    struct LinkUpdate: Identifiable, Equatable {
        let id = UUID()
        /// The note the links lead to, by its new name.
        let title: String
        let notes: [Note.ID]
    }

    @Published var linkUpdate: LinkUpdate?

    private func announce(_ notes: [Note.ID], to title: String) {
        guard !notes.isEmpty else { return }
        linkUpdate = LinkUpdate(title: title, notes: notes)
    }

    /// Says which notes' links couldn't be updated, so none are left pointing at the old
    /// name without anyone knowing.
    private static func report(_ result: LinkUpdater.Result, for title: String) {
        let missed = result.skippedNotes + result.unreadNotes
        guard !missed.isEmpty else { return }
        NSLog("Point: links to \(title) not updated in \(result.skippedNotes) (changed while updating) and \(result.unreadNotes) (unreadable)")
        let alert = NSAlert()
        alert.messageText = "Some links to “\(title)” weren’t updated"
        let names = missed.prefix(8).map { "• " + ($0 as NSString).deletingPathExtension }.joined(separator: "\n")
        alert.informativeText = """
            These notes were changed while Point was updating them, or aren’t downloaded from \
            iCloud yet, so they may still link to the old place:

            \(names)\(missed.count > 8 ? "\n…and \(missed.count - 8) more" : "")
            """
        alert.runModal()
    }

    /// Saves the open edits of notes about to be moved or deleted. If any can't be saved, says
    /// so and returns false, and nothing is moved: moved anyway, their edits would be lost.
    private func saveBeforeMoving(_ notes: [Note], _ action: String) -> Bool {
        let unsaved = notes.filter { !EditorSession.save($0.url) }
        guard let first = unsaved.first else { return true }
        Self.showProblem(unsaved.count == 1 ? "“\(first.title)” wasn’t \(action)" : "\(unsaved.count) notes weren’t \(action)",
                         detail: "Point couldn’t save the changes to \(unsaved.count == 1 ? "it" : "them") first. Your changes are kept.")
        return false
    }

    /// Where edits that can't be saved are kept, outside the vault.
    var drafts: NoteDrafts? {
        guard let root else { return nil }
        let storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Point/Drafts", isDirectory: true)
        return NoteDrafts(storage: storage, vaultKey: Self.vaultKey(root))
    }

    /// A note closed with edits that couldn't be saved: they're kept, and offered when it's
    /// next opened.
    func reportUnsaved(_ note: Note) {
        Self.showProblem("Your changes to “\(note.title)” couldn’t be saved",
                         detail: "They’re kept, and Point will offer them when you open the note again.")
    }

    /// Says something went wrong, over the window in front (or on its own, with none).
    static func showProblem(_ message: String, _ error: Error? = nil, detail: String? = nil) {
        NSLog("Point: \(message)\(error.map { ": \($0.localizedDescription)" } ?? "")")
        #if DEBUG
        // `-PointNoAlerts YES`: to the trace instead, for tests run in the background.
        if UserDefaults.standard.bool(forKey: "PointNoAlerts") { return Trace.mark("alert: \(message)") }
        #endif
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = message
            alert.informativeText = detail ?? error?.localizedDescription ?? ""
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
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

    /// What goes between `[[` and `]]` for a link to the note with this title: its name, and
    /// for a note Point named (whose name isn't its title), the title as the link's label,
    /// `2026-11-06-questions|Questions?`, which reads well in any app.
    func linkText(forTitle title: String) -> String {
        guard let note = notes.first(where: { $0.title == title }) ?? notes.first(where: { $0.title.lowercased() == title.lowercased() }),
              note.name != note.title else { return title }
        // A label can't hold `]]` or `|`.
        let label = note.title.replacingOccurrences(of: "]]", with: "] ]").replacingOccurrences(of: "|", with: "-")
        return note.name + "|" + label
    }

    /// Note titles for completing a `[[wikilink]]`: names starting with the typed text first,
    /// then names with a word starting with it, then names containing it anywhere.
    func titleSuggestions(for partial: String) -> [String] {
        let query = partial.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return Array(notes.sorted(by: .modified).prefix(20).map(\.title))
        }
        let index = titleIndex ?? notes.map { note in
            let lowered = note.title.lowercased()
            return (note.title, lowered, lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        }
        titleIndex = index
        var ranked: [(title: String, rank: Int)] = []
        for entry in index {
            if entry.lowered.hasPrefix(query) {
                ranked.append((entry.title, 0))
            } else if entry.words.contains(where: { $0.hasPrefix(query) }) {
                ranked.append((entry.title, 1))
            } else if entry.lowered.contains(query) {
                ranked.append((entry.title, 2))
            }
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

    /// Changes one of the settings Point shares with Obsidian (in `.obsidian/`), for both apps.
    func setObsidianSetting(_ key: ObsidianSettings.Key, to value: String?) {
        guard let root else { return }
        do {
            try ObsidianSettings.set(key, to: value, vault: root)
            objectWillChange.send()
            settings = ObsidianSettings.load(vault: root)
        } catch {
            Self.showProblem("Couldn’t change the setting", error)
        }
    }

    /// The vault's folders, by path, for choosing one.
    var folderPaths: [String] {
        folderTree.noteCounts.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A new template, in the templates folder, opened in the window in front.
    func createTemplate() {
        guard !settings.templatesFolder.isEmpty, let id = createNote(inFolder: settings.templatesFolder, dated: false) else { return NSSound.beep() }
        activeWindow?.selection = id
    }

    /// The templates in the vault's templates folder.
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
    /// In groups unless chosen otherwise, or unless dates were turned off (when they were on
    /// or off, before they could be grouped).
    @Published var listDateStyle = VaultModel.ListDateStyle(rawValue: UserDefaults.standard.string(forKey: "listDateStyle") ?? "")
        ?? (UserDefaults.standard.object(forKey: "showsDateInList") as? Bool == false ? .off : .groups) {
        didSet { UserDefaults.standard.set(listDateStyle.rawValue, forKey: "listDateStyle") }
    }
    @Published var listDate = VaultModel.ListDate(rawValue: UserDefaults.standard.string(forKey: "listDate") ?? "") ?? .edited {
        didSet { UserDefaults.standard.set(listDate.rawValue, forKey: "listDate") }
    }
    /// Whether the sidebar lists Bookmarks beside All Notes and the trash. (Bookmarked notes
    /// still come first in the palette.)
    @Published var showsBookmarksInSidebar = UserDefaults.standard.object(forKey: "showsBookmarksInSidebar") == nil || UserDefaults.standard.bool(forKey: "showsBookmarksInSidebar") {
        didSet { UserDefaults.standard.set(showsBookmarksInSidebar, forKey: "showsBookmarksInSidebar") }
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
    @Published private(set) var tagsByNote: [Note.ID: [String]] = [:] { didSet { listVersion += 1 } }
    private var tagsReadAt: [Note.ID: Date] = [:]
    /// Every note's tags, from the search index (which keeps them between launches).
    @Published private(set) var indexedTags: [Note.ID: [String]] = [:] { didSet { listVersion += 1 } }
    @Published private(set) var tagTree = TagTree(tagsByNote: [])

    /// Reads tags for notes that are new or changed since they were last read.
    func refreshTags() {
        Trace.mark("refreshTags called")
        guard showsTagsInList else { return }
        let stale = notes.filter { $0.isDownloaded && tagsReadAt[$0.id] != $0.modified }
        guard !stale.isEmpty else { return }
        let generation = vaultGeneration
        Task {
            let read = await Task.detached(priority: .utility) {
                stale.map { note in (note, (try? NoteReader.read(contentsOf: note.url)).map(NoteTags.tags(in:))) }
            }.value
            guard generation == vaultGeneration else { return }
            // In one change: set note by note, the published dictionary sent thousands of
            // changes (and could copy itself for each), holding up the main thread for half a
            // second a few seconds after launch. A note that couldn't be read keeps the tags it
            // had, and is read again next time (taken as having none, it lost them until it
            // next changed).
            var updated = tagsByNote
            for case let (note, tags?) in read {
                updated[note.id] = tags
                tagsReadAt[note.id] = note.modified
            }
            tagsByNote = updated
            Trace.mark("tagsByNote updated: \(read.count) notes read")
        }
    }

    /// A note's tags for the list: read from its file, or (until that's done, as at launch)
    /// from the search index.
    func listTags(for id: Note.ID) -> [String] {
        tagsByNote[id] ?? indexedTags[id] ?? []
    }

    // MARK: Images

    /// Where the image an embed in the note `noteID` names is, if it's in the vault and here
    /// (one still in iCloud is fetched, and shown once it's arrived).
    func imageURL(for target: String, from noteID: Note.ID) -> URL? {
        if WebImageCache.isWeb(target) { return webImageURL(target) }
        guard let root, let image = VaultImages.resolve(target, from: noteID, images: imagesByName, root: root) else { return nil }
        guard image.isDownloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: image.url)
            return nil
        }
        return image.url
    }

    // MARK: Images from the web

    /// Whether images on the web that notes show are loaded and shown.
    @Published var showsWebImages = UserDefaults.standard.object(forKey: "showsWebImages") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsWebImages, forKey: "showsWebImages")
            imagesArrived()
        }
    }
    /// Web images being loaded, and those that couldn't be (not tried again until next launch).
    private var webImagesLoading: Set<URL> = []
    private var webImagesFailed: Set<URL> = []
    private var isRestyleQueued = false

    /// The kept copy of a web image, or nil while it's loaded (in the background, its notes
    /// restyled once it's here) or if it can't be.
    private func webImageURL(_ target: String) -> URL? {
        guard showsWebImages, let address = URL(string: target) ?? target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init) else { return nil }
        let cache = WebImageCache.standard
        if let file = cache.cached(address) { return file }
        guard !webImagesLoading.contains(address), !webImagesFailed.contains(address) else { return nil }
        webImagesLoading.insert(address)
        Task {
            do {
                _ = try await cache.load(address)
                imagesArrived()
            } catch {
                webImagesFailed.insert(address)
                Trace.mark("web image not loaded: \(address.host() ?? "") \(error)")
            }
            webImagesLoading.remove(address)
        }
        return nil
    }

    /// Restyles open notes, once, for images that have just arrived.
    private func imagesArrived() {
        guard !isRestyleQueued else { return }
        isRestyleQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            isRestyleQueued = false
            objectWillChange.send()
            notesGeneration += 1
        }
    }

    /// Saves an image pasted or dropped into a note, named after it, in the attachment folder
    /// Obsidian is set to. Returns its name, for the embed.
    func saveImage(_ data: Data, type: UTType?, for note: Note) -> String? {
        guard let root else { return nil }
        do {
            let image = try VaultImages.save(data, type: type, forNote: note, vault: root, setting: settings.attachmentFolder)
            images.append(image)
            return image.name
        } catch {
            Self.showProblem("Couldn’t add the image to “\(note.title)”", error)
            return nil
        }
    }

    /// The notes that show or link to an image, as the index knows them, by title.
    func notesShowing(_ image: VaultImage) async -> [Note] {
        guard let index, let links = try? await index.linking(to: image.name) else { return [] }
        let ids = Set(links.map(\.note))
        return notes.filter { ids.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Renames an image (`name` without its extension, which it keeps), and its embeds in every
    /// note that shows it. Tabs showing it follow. Returns it renamed, or nil if it couldn't be.
    @discardableResult
    func renameImage(_ image: VaultImage, to name: String) -> VaultImage? {
        let stem = NoteFiles.sanitizedTitle(name)
        let ext = (image.name as NSString).pathExtension
        let newName = ext.isEmpty ? stem : stem + "." + ext
        guard !stem.isEmpty, newName != image.name else { return nil }
        let destination = image.url.deletingLastPathComponent().appendingPathComponent(newName)
        // A change of case alone is allowed; any other existing file is not overwritten.
        if FileManager.default.fileExists(atPath: destination.path), newName.lowercased() != image.name.lowercased() {
            Self.showProblem("Couldn’t rename “\(image.name)”", detail: "There’s already a file called “\(newName)” in its folder.")
            return nil
        }
        do {
            try FileManager.default.moveItem(at: image.url, to: destination)
        } catch {
            Self.showProblem("Couldn’t rename “\(image.name)”", error)
            return nil
        }
        let folder = (image.path as NSString).deletingLastPathComponent
        let renamed = VaultImage(path: folder.isEmpty ? newName : folder + "/" + newName, url: destination)
        images = images.map { $0.path == image.path ? renamed : $0 }
        NotificationCenter.default.post(name: .pointNoteMoved, object: self, userInfo: ["old": image.path, "new": renamed.path])
        if let index {
            Task {
                let ids = Set(((try? await index.linking(to: image.name)) ?? []).map(\.note))
                let showing = notes.filter { ids.contains($0.id) }
                guard !showing.isEmpty else { return }
                NotificationCenter.default.post(name: .pointSaveNow, object: self)
                Self.renameEmbeds([(image, renamed)], in: showing)
            }
        }
        return renamed
    }

    /// Moves an image to the Trash (the Finder's: no note goes with it).
    func trashImage(_ image: VaultImage) {
        trashUnusedImages([image])
    }

    /// The images no note embeds or links to, as the index knows them.
    func unusedImages() async -> [VaultImage] {
        guard let index, let linked = try? await index.linkedNames() else { return [] }
        return VaultImages.unused(images, linkedNames: linked)
    }

    /// Moves images to the Trash (the Finder's, since no note goes with them).
    func trashUnusedImages(_ unused: [VaultImage]) {
        var gone = Set<String>()
        for image in unused {
            do {
                try FileManager.default.trashItem(at: image.url, resultingItemURL: nil)
                gone.insert(image.path)
            } catch {
                NSLog("Point: couldn't move \(image.path) to the Trash: \(error.localizedDescription)")
            }
        }
        images.removeAll { gone.contains($0.path) }
        if gone.count < unused.count {
            Self.showProblem("Couldn’t move \(unused.count - gone.count) of the images to the Trash")
        }
    }

    /// The images a note shows, as they are in the vault.
    private func imagesShown(by note: Note) -> [VaultImage] {
        guard let root, let text = try? NoteReader.read(contentsOf: note.url) else { return [] }
        var found: [VaultImage] = []
        for embed in VaultImages.embeds(in: text) where !embed.isWeb {
            if let image = VaultImages.resolve(embed.target, from: note.id, images: imagesByName, root: root), !found.contains(image) {
                found.append(image)
            }
        }
        return found
    }

    /// Moves to the trash, with the note trashed as `name`, those of its images no other note
    /// shows (as the index knows them), and records them, to come back with it.
    private func trashImages(_ shown: [VaultImage], withNote note: Note, trashedAs name: String) {
        guard let root, let index, !shown.isEmpty else { return }
        Task {
            var onlyHere: [VaultImage] = []
            for image in shown {
                let others = ((try? await index.linking(to: image.name)) ?? []).filter { $0.note != note.id }
                if others.isEmpty { onlyHere.append(image) }
            }
            let trashed = VaultTrash.move(onlyHere, vault: root)
            guard !trashed.isEmpty else { return }
            let gone = Set(trashed.map(\.path))
            images.removeAll { gone.contains($0.path) }
            trashRecords[name]?.images = trashed
        }
    }

    /// Renames the images named after a note (`Meeting 1.png`) when the note is renamed (now
    /// at `url`), and their embeds in it and any other note showing them. An image whose new
    /// name is taken keeps its old one, which still works.
    private func renameImages(of note: Note, to url: URL) {
        let newName = url.deletingPathExtension().lastPathComponent
        guard newName != note.name else { return }
        var renamed: [(from: VaultImage, to: VaultImage)] = []
        for image in images {
            guard let name = VaultImages.renamed(image.name, fromNote: note.name, toNote: newName) else { continue }
            let destination = image.url.deletingLastPathComponent().appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            do {
                try FileManager.default.moveItem(at: image.url, to: destination)
            } catch {
                NSLog("Point: couldn't rename \(image.path): \(error.localizedDescription)")
                continue
            }
            let folder = (image.path as NSString).deletingLastPathComponent
            renamed.append((image, VaultImage(path: folder.isEmpty ? name : folder + "/" + name, url: destination)))
        }
        guard !renamed.isEmpty else { return }
        let moved = Dictionary(renamed.map { ($0.from.path, $0.to) }, uniquingKeysWith: { first, _ in first })
        images = images.map { moved[$0.path] ?? $0 }
        // The note itself, at its new name, now (before it's opened there), then any other the
        // index says shows them.
        let itself = Note(id: note.id, url: url, title: note.title, modified: note.modified, created: note.created, isDownloaded: true)
        Self.renameEmbeds(renamed, in: [itself])
        guard let index else { return }
        Task {
            var ids = Set<Note.ID>()
            for pair in renamed { ids.formUnion(((try? await index.linking(to: pair.from.name)) ?? []).map(\.note)) }
            ids.remove(note.id)
            let others = notes.filter { ids.contains($0.id) }
            guard !others.isEmpty else { return }
            NotificationCenter.default.post(name: .pointSaveNow, object: self)
            Self.renameEmbeds(renamed, in: others)
        }
    }

    /// Rewrites embeds of renamed images in notes, each only if unchanged meanwhile.
    private static func renameEmbeds(_ renamed: [(from: VaultImage, to: VaultImage)], in notes: [Note]) {
        let change = VaultChanges.apply("Renamed images", to: notes) { text in
            var result = text, changed = false
            for pair in renamed {
                if let rewritten = VaultImages.renamingEmbeds(of: pair.from.name, to: pair.to.name, in: result) {
                    result = rewritten
                    changed = true
                }
            }
            return changed ? result : nil
        }
        if !change.skippedNotes.isEmpty || !change.unreadNotes.isEmpty {
            NSLog("Point: couldn't update image embeds in \(change.skippedNotes + change.unreadNotes)")
        }
    }

    // MARK: Search index

    private(set) var index: SearchIndex?
    /// Goes up whenever the index changes, so windows can refresh their searches.
    @Published private(set) var indexGeneration = 0

    /// Opens (creating if needed) the search index for the vault at `url`. It lives in the
    /// app's own storage, never in the vault, named by a hash of the vault's path.
    private func openIndex(for url: URL) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Point/Index", isDirectory: true)
        index = try? SearchIndex(url: folder.appendingPathComponent("\(Self.vaultKey(url)).sqlite"))
    }

    // MARK: What search learns

    /// Which notes are opened, and which are picked for what's typed, on this Mac: search
    /// puts them first among results of similar quality (`SearchHistory.rank`).
    private(set) var searchHistory = SearchHistory()
    private var searchHistoryFile: SearchHistory.File?
    /// The note opened last, which counts once it has stayed open a moment: stepping through
    /// a list opens each note on the way, but chooses none of them.
    private var pendingOpen: (id: Note.ID, date: Date, query: String?)?
    private var pendingOpenTask: Task<Void, Never>?
    private var saveHistoryTask: Task<Void, Never>?
    /// How long a note must stay open to count as chosen.
    private static let openDwell: UInt64 = 2_000_000_000

    /// Kept next to the index, in the app's own storage, never in the vault.
    private func openSearchHistory(for url: URL) {
        pendingOpenTask?.cancel()
        pendingOpen = nil
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Point/History", isDirectory: true)
        let file = SearchHistory.File(url: folder.appendingPathComponent("\(Self.vaultKey(url)).json"))
        searchHistoryFile = file
        searchHistory = file.load()
    }

    /// A note opened on purpose (not restored at launch, nor gone back or forward to), and
    /// what had been typed to find it, if it was a search result.
    func noteOpened(_ id: Note.ID, searchedFor query: String? = nil) {
        pendingOpenTask?.cancel()
        pendingOpen = (id, Date(), query.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
        pendingOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.openDwell)
            guard !Task.isCancelled, let self, let open = self.pendingOpen else { return }
            self.pendingOpen = nil
            self.pendingOpenTask = nil
            if let query = open.query {
                self.searchHistory.picked(open.id, for: query, at: open.date)
            } else {
                self.searchHistory.opened(open.id, at: open.date)
            }
            self.saveSearchHistory()
        }
    }

    /// A search result chosen after typing `query`, from a list it isn't stepped through
    /// (the palette): counts at once, in place of the open it made.
    func resultPicked(_ id: Note.ID, for query: String) {
        if pendingOpen?.id == id {
            pendingOpenTask?.cancel()
            pendingOpenTask = nil
            pendingOpen = nil
        }
        searchHistory.picked(id, for: query)
        saveSearchHistory()
    }

    func forgetSearchHistory() {
        pendingOpenTask?.cancel()
        pendingOpen = nil
        searchHistory.forget()
        saveSearchHistory()
    }

    /// Notes that are gone take what was learned about them with them. Not while the vault
    /// reads as empty, which is more likely a folder that's unavailable for a moment.
    private func forgetDeletedNotes() {
        guard !notes.isEmpty else { return }
        let before = searchHistory
        searchHistory.keepOnly(Set(notes.map(\.id)))
        if searchHistory != before { saveSearchHistory() }
    }

    private func saveSearchHistory() {
        saveHistoryTask?.cancel()
        saveHistoryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, let file = self.searchHistoryFile else { return }
            file.save(self.searchHistory)
        }
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
        let generation = vaultGeneration
        Task {
            let changed: Int
            do {
                changed = try await index.update(notes: notes)
            } catch {
                // Searches go on using the index as it was; the next scan tries again.
                NSLog("Point: couldn't update the search index: \(error.localizedDescription)")
                return Trace.mark("index update failed: \(error.localizedDescription)")
            }
            let unreadable = await index.unreadableNotes
            Trace.mark("index updated: \(changed) notes changed\(unreadable.isEmpty ? "" : ", \(unreadable.count) unreadable")")
            if !unreadable.isEmpty { NSLog("Point: couldn't read \(unreadable.count) notes to index them; they'll be tried again") }
            guard generation == vaultGeneration else { return }
            if changed > 0 { indexGeneration += 1 }
            if changed > 0 || propertyValues.isEmpty, let values = try? await index.propertyValues(), generation == vaultGeneration {
                propertyValues = values
            }
            if changed > 0 || propertySummaries.isEmpty, let summaries = try? await index.propertySummaries(), generation == vaultGeneration {
                propertySummaries = summaries
            }
            if changed > 0 || tagTree.entries.isEmpty {
                guard let tags = try? await index.tagsByNote(), generation == vaultGeneration else { return }
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
        case .allNotes: return notes.filter { !$0.id.contains("/") }
        case .everything: return notes
        case .bookmarks: return bookmarkedNotes
        case .trash, .properties: return []
        case .folder(let path): return notes.filter { FolderTree.folder(of: $0.id) == path }
        case .tag(let tag): return notes.filter { TagTree.tags(indexedTags[$0.id] ?? [], include: tag) }
        case .property, .propertyValue:
            // From the index, in the list's own order.
            guard let query = place.query, let ids = noteIDs(matching: query) else { return [] }
            let found = Set(ids)
            return notes.filter { found.contains($0.id) }
        }
    }

    /// The folders or tags to show above the notes in a place, in the chosen order.
    func subplaces(of place: SidebarPlace) -> [SidebarPlace] {
        switch place {
        case .allNotes: sortedFolders(folderTree.subfolders(of: "")).map(SidebarPlace.folder)
        case .everything, .bookmarks, .trash, .propertyValue: []
        case .folder(let path): sortedFolders(folderTree.subfolders(of: path)).map(SidebarPlace.folder)
        case .tag(let tag): sortedTags(tagTree.children(of: tag)).map { .tag($0.tag) }
        case .properties: propertySummaries.map { .property($0.name) }
        case .property(let name): propertyValueList(name).map { .propertyValue(name, $0.value) }
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
        case .properties: propertySummaries.count
        case .property(let name): propertySummaries.first { $0.id == name.lowercased() }?.noteCount ?? 0
        case .propertyValue(let name, let value):
            propertyValueList(name).first { $0.value.lowercased() == value.lowercased() }?.count ?? 0
        }
    }

    // MARK: Properties across the vault

    /// Every property in the vault, most used first, from the index: for the properties view.
    @Published private(set) var propertySummaries: [SearchIndex.PropertySummary] = [] { didSet { listVersion += 1 } }

    /// A property's values, each once whatever its case (spelled as most notes spell it), with
    /// how many notes give it, most used first. Short values only, as for suggestions.
    func propertyValueList(_ name: String) -> [(value: String, count: Int)] {
        let key = name.lowercased()
        if let cached = valueListCache[key], cached.generation == indexGeneration { return cached.values }
        var merged: [String: (value: String, count: Int, best: Int)] = [:]
        var order: [String] = []
        for entry in propertyValues[key] ?? [] {
            let lowered = entry.value.lowercased()
            if var existing = merged[lowered] {
                if entry.count > existing.best { (existing.value, existing.best) = (entry.value, entry.count) }
                existing.count += entry.count
                merged[lowered] = existing
            } else {
                merged[lowered] = (entry.value, entry.count, entry.count)
                order.append(lowered)
            }
        }
        let values = order.compactMap { merged[$0] }.map { (value: $0.value, count: $0.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.value.localizedStandardCompare($1.value) == .orderedAscending }
        valueListCache[key] = (indexGeneration, values)
        return values
    }
    private var valueListCache: [String: (generation: Int, values: [(value: String, count: Int)])] = [:]

    // MARK: Queries

    /// What each query asked of the index last found, and as of which change to it.
    private var queryResults: [NoteQuery: (generation: Int, ids: [Note.ID])] = [:]
    private var runningQueries: Set<NoteQuery> = []

    /// The notes a query finds, in its order, from the index: what it last found at once (nil
    /// the first time), and asked again in the background if the index has changed since, the
    /// list updating when the answer comes. Never waits on the index on the main thread.
    func noteIDs(matching query: NoteQuery) -> [Note.ID]? {
        let cached = queryResults[query]
        if cached?.generation != indexGeneration, let index, runningQueries.insert(query).inserted {
            let generation = indexGeneration, vault = vaultGeneration
            Task {
                let ids = try? await index.notes(matching: query)
                runningQueries.remove(query)
                guard vault == vaultGeneration, let ids else { return }
                let changed = queryResults[query]?.ids != ids
                queryResults[query] = (generation, ids)
                if changed {
                    listVersion += 1
                    objectWillChange.send()
                }
            }
        }
        return cached?.ids
    }

    func isPinned(_ place: SidebarPlace) -> Bool { pins.contains(place) }

    // MARK: Property types

    /// The vault's property types, shared with Obsidian (`.obsidian/types.json`).
    @Published private(set) var propertyTypes = PropertyTypes()

    func setPropertyType(_ type: PropertyType, forKey key: String) {
        guard propertyTypes.type(forKey: key) != type, let root else { return }
        propertyTypes.set(type, forKey: key)
        save(propertyTypes, in: root)
    }

    /// A property renamed in a note: its type goes with the new name, for that name.
    func renamePropertyType(_ key: String, to newKey: String) {
        guard let root else { return }
        let before = propertyTypes
        propertyTypes.rename(key, to: newKey)
        if propertyTypes != before { save(propertyTypes, in: root) }
        let pointBefore = pointTypes
        pointTypes.rename(key, to: newKey)
        if pointTypes != pointBefore { try? pointTypes.save(vault: root) }
    }

    // MARK: Point's own types, and people

    /// Point's own kinds of property (choice, person, rating, link to note), from the
    /// vault's `.point/types.json`.
    @Published private(set) var pointTypes = PointTypes()

    /// Gives a property one of Point's own kinds (nil: back to Obsidian's types alone). It's
    /// kept in Obsidian's types too, as the type it's written as, for editing alongside.
    func setPointType(_ definition: PointTypes.Definition?, forKey key: String) {
        guard let root, pointTypes.definition(forKey: key) != definition else { return }
        pointTypes.set(definition, forKey: key)
        do { try pointTypes.save(vault: root) } catch {
            Self.showProblem("Couldn’t save the property’s type", error)
        }
        if let definition, propertyTypes.type(forKey: key) != definition.type.baseType {
            propertyTypes.set(definition.type.baseType, forKey: key)
            save(propertyTypes, in: root)
        }
        listVersion += 1
    }

    /// People, by their notes' titles: notes in the people folder, and whoever's linked in a
    /// property of the person kind, most linked first.
    var people: [String] {
        if let cached = peopleCache, cached.version == listVersion { return cached.names }
        var counts: [String: (name: String, count: Int)] = [:]
        if let folder = pointTypes.peopleFolder(among: folderTree.subfolders(of: "")) {
            for note in notes where FolderTree.folder(of: note.id) == folder || note.id.hasPrefix(folder + "/") {
                counts[note.title.lowercased()] = (note.title, 0)
            }
        }
        let personKeys = pointTypes.properties.filter { $0.value.type == .person }.map { $0.key.lowercased() }
        for key in personKeys {
            for entry in propertyValues[key] ?? [] {
                guard let name = PropertyLink.linkedName(entry.value) else { continue }
                let existing = counts[name.lowercased()]
                counts[name.lowercased()] = (existing?.name ?? name, (existing?.count ?? 0) + entry.count)
            }
        }
        let names = counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.name)
        peopleCache = (listVersion, names)
        return names
    }
    private var peopleCache: (version: Int, names: [String])?

    /// People whose names have a word starting with what's typed (all of them, with nothing
    /// typed), most linked first.
    func peopleSuggestions(for typed: String, excluding: [String] = [], limit: Int = 8) -> [String] {
        let query = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]@ "))
        let taken = Set(excluding.compactMap { PropertyLink.linkedName($0)?.lowercased() ?? $0.lowercased() })
        return Array(people.filter { name in
            !taken.contains(name.lowercased())
                && (query.isEmpty || name.lowercased().split(separator: " ").contains { $0.hasPrefix(query) } || name.lowercased().hasPrefix(query))
        }.prefix(limit))
    }

    /// Notes to link to from a property of the link-to-note kind: those in its folder (any,
    /// if none) whose titles fit what's typed.
    func noteSuggestions(inFolder folder: String?, typed: String, limit: Int = 8) -> [String] {
        let query = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return Array(notes.lazy.filter { note in
            (folder == nil || FolderTree.folder(of: note.id) == folder || note.id.hasPrefix(folder! + "/"))
                && (query.isEmpty || note.title.lowercased().contains(query))
        }.map(\.title).prefix(limit))
    }

    private func save(_ types: PropertyTypes, in root: URL) {
        do { try types.save(vault: root) } catch {
            Self.showProblem("Couldn’t save the property’s type", error)
        }
    }

    /// Tags in the vault starting with (or containing) what's typed, for completing a tag.
    /// The values each property is given across the vault (by its name, lowercased), most
    /// used first, from the index.
    private(set) var propertyValues: [String: [(value: String, count: Int)]] = [:] { didSet { listVersion += 1 } }

    /// Values given to the property `key` in other notes that fit what's typed, most used
    /// first: a field suggests what's been put in it before ("[[Ann]]" in people, "Design"
    /// in topics). Matched on the words shown, without a link's brackets.
    func propertySuggestions(forKey key: String, typed: String, excluding: [String] = []) -> [String] {
        let query = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !query.isEmpty else { return [] }
        let taken = Set(excluding.map { $0.lowercased() })
        func shown(_ value: String) -> String {
            value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        let values = (propertyValues[key.lowercased()] ?? []).filter { !taken.contains($0.value.lowercased()) }
        let starting = values.filter { shown($0.value).hasPrefix(query) }
        let wordStarting = values.filter { !shown($0.value).hasPrefix(query) && shown($0.value).split(separator: " ").contains { $0.hasPrefix(query) } }
        // The same name written as a link and as plain text is one suggestion, as most used.
        var seen = Set<String>()
        return Array((starting + wordStarting).map(\.value).filter { seen.insert(shown($0)).inserted }.prefix(6))
    }

    func tagSuggestions(for partial: String, excluding: [String] = []) -> [String] {
        let typed = partial.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard !typed.isEmpty else { return [] }
        let taken = Set(excluding.map { $0.lowercased() })
        let tags = tagTree.entries.map(\.tag).filter { !taken.contains($0.lowercased()) }
        let starting = tags.filter { $0.lowercased().hasPrefix(typed) }
        let containing = tags.filter { !$0.lowercased().hasPrefix(typed) && $0.lowercased().contains(typed) }
        return Array((starting.sorted() + containing.sorted()).prefix(6))
    }

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
            return sortedTags(entries).map { VaultModel.PlaceNode(place: .tag($0.tag), name: $0.name, children: nodes(under: $0.tag)) }
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

extension SidebarPlace {
    /// What the index is asked for the notes in a place made from properties.
    var query: NoteQuery? {
        switch self {
        case .property(let name): NoteQuery([.property(name, .exists)])
        case .propertyValue(let name, let value): NoteQuery([.property(name, .equals(value))])
        default: nil
        }
    }

    /// Whether it unfolds in the sidebar to show what's inside it (folders and tags do).
    var unfolds: Bool {
        switch self {
        case .folder, .tag: true
        default: false
        }
    }

    /// Made from properties: shown in their own section, in secondary colour like tags.
    var isProperty: Bool {
        switch self {
        case .properties, .property, .propertyValue: true
        default: false
        }
    }
}
