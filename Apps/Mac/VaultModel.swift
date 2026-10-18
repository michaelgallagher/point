import AppKit
import CryptoKit
import EditorKit
import IndexKit
import MarkdownKit
import VaultKit

/// The open vault and its notes.
@MainActor
final class VaultModel: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var notes: [Note] = []
    @Published private(set) var errorMessage: String?
    @Published var selection: Note.ID? {
        didSet {
            guard let oldValue, oldValue != selection else { return }
            if !isMovingThroughHistory {
                backStack.append(oldValue)
                forwardStack.removeAll()
            }
            finishUntitledNote(oldValue)
        }
    }
    /// Notes visited before and after the current one, for ⌘[ and ⌘].
    @Published private(set) var backStack: [Note.ID] = []
    @Published private(set) var forwardStack: [Note.ID] = []
    private var isMovingThroughHistory = false
    /// The note being renamed, while the rename dialog is showing.
    @Published var renaming: Note?
    @Published var sort: NoteSort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Keys.sort)
            notes = notes.sorted(by: sort)
        }
    }

    private var watcher: VaultWatcher?
    private(set) var settings = ObsidianSettings()
    /// Notes created untitled in this session, to be named by their first line when left.
    private var untitled: Set<Note.ID> = []

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let sort = "noteSort"
    }

    init() {
        sort = UserDefaults.standard.string(forKey: Keys.sort).flatMap(NoteSort.init) ?? .modified
        restoreVault()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let selection = self?.selection { self?.finishUntitledNote(selection) }
            }
        }
    }

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

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
            if let selection, !notes.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
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
        selection = nil
        settings = ObsidianSettings.load(vault: url)
        searchText = ""
        openIndex(for: url)
        watcher = VaultWatcher(root: url) { [weak self] urls in
            Task { @MainActor in self?.filesChanged(urls) }
        }
        Task { await reload() }
    }

    /// Something in the vault changed, here or elsewhere: rescan, and tell open notes.
    private func filesChanged(_ urls: [URL]) {
        NotificationCenter.default.post(name: .imprintFilesChanged, object: self, userInfo: ["urls": urls])
        Task { await reload() }
    }

    // MARK: Creating, renaming and deleting

    /// Creates an untitled note in the vault root and opens it.
    func createNote(text: String = "") {
        guard let root else { return }
        do {
            let url = try NoteFiles.create(title: NoteFiles.untitledName(), text: text, in: root)
            let now = Date()
            let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                            modified: now, created: now, isDownloaded: true)
            notes = (notes + [note]).sorted(by: sort)
            untitled.insert(note.id)
            selection = note.id
        } catch {
            errorMessage = "Couldn't create a note: \(error.localizedDescription)"
        }
    }

    /// Names a note created untitled after its first line, or removes it if it stayed empty.
    private func finishUntitledNote(_ id: Note.ID) {
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

    func rename(_ note: Note, to title: String) {
        do {
            releaseFile(note.url)
            untitled.remove(note.id)
            let vaultBeforeRename = notes
            let url = try NoteFiles.rename(note.url, to: title)
            updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, vault: vaultBeforeRename)
            let folders = note.id.split(separator: "/").dropLast().joined(separator: "/")
            let newID = folders.isEmpty ? url.lastPathComponent : "\(folders)/\(url.lastPathComponent)"
            let wasSelected = selection == note.id
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = Note(id: newID, url: url, title: url.deletingPathExtension().lastPathComponent,
                                    modified: note.modified, created: note.created, isDownloaded: true)
            }
            backStack = backStack.map { $0 == note.id ? newID : $0 }
            forwardStack = forwardStack.map { $0 == note.id ? newID : $0 }
            if wasSelected { selection = newID }
            Task { await reload() }
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    func moveToTrash(_ note: Note) {
        guard let root else { return }
        releaseFile(note.url)
        untitled.remove(note.id)
        do {
            try NoteFiles.trash(note.url, vault: root, option: settings.trashOption)
            notes.removeAll { $0.id == note.id }
            if selection == note.id { selection = nil }
        } catch {
            errorMessage = "Couldn't move “\(note.title)” to the trash: \(error.localizedDescription)"
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

    /// Asks the editor showing this file to save now and stop writing to it.
    private func releaseFile(_ url: URL) {
        NotificationCenter.default.post(name: .imprintReleaseFile, object: self, userInfo: ["url": url])
    }

    // MARK: Links and history

    /// Follows a clicked link: notes open here (missing ones are created, as in Obsidian),
    /// web addresses open in the browser.
    func open(_ link: LinkTarget, from sourceID: Note.ID) {
        let resolver = LinkResolver(notes: notes)
        switch link {
        case .note(let target):
            if let note = resolver.resolve(wikiTarget: target, from: sourceID) {
                selection = note.id
            } else {
                createLinkedNote(named: target)
            }
        case .file(let destination):
            if let note = resolver.resolve(markdownDestination: destination, from: sourceID) {
                selection = note.id
            } else {
                NSSound.beep()
            }
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .tag(let tag):
            search(tag: tag)
        }
    }

    /// Creates the note a link points to but which doesn't exist yet.
    private func createLinkedNote(named target: String) {
        guard let root else { return }
        let name = target.split(separator: "#").first.map(String.init) ?? target
        let title = NoteFiles.sanitizedTitle((name as NSString).lastPathComponent)
        guard !title.isEmpty, let url = try? NoteFiles.create(title: title, in: root) else { return NSSound.beep() }
        let now = Date()
        let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                        modified: now, created: now, isDownloaded: true)
        notes = (notes + [note]).sorted(by: sort)
        selection = note.id
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

    func goBack() {
        move(from: &backStack, to: &forwardStack)
    }

    func goForward() {
        move(from: &forwardStack, to: &backStack)
    }

    private func move(from source: inout [Note.ID], to destination: inout [Note.ID]) {
        // Skip notes deleted since they were visited.
        while let id = source.popLast() {
            guard notes.contains(where: { $0.id == id }) else { continue }
            if let selection { destination.append(selection) }
            isMovingThroughHistory = true
            selection = id
            isMovingThroughHistory = false
            return
        }
        NSSound.beep()
    }

    // MARK: Daily notes and templates

    /// Opens today's daily note, creating it (from its template, if one is set) if needed.
    func openTodaysNote() {
        guard let root else { return }
        let url = Templates.dailyNoteURL(in: root, settings: settings)
        if let existing = notes.first(where: { $0.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path }) {
            selection = existing.id
            return
        }
        do {
            let title = url.deletingPathExtension().lastPathComponent
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = Templates.dailyNoteText(title: title, in: root, settings: settings)
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            let id = String(url.resolvingSymlinksInPath().path.dropFirst(root.resolvingSymlinksInPath().path.count + 1))
            let now = Date()
            notes = (notes + [Note(id: id, url: url, title: title, modified: now, created: now, isDownloaded: true)]).sorted(by: sort)
            selection = id
        } catch {
            errorMessage = "Couldn't create today's note: \(error.localizedDescription)"
        }
    }

    /// The templates in the vault's templates folder, for Insert Template.
    var templates: [(name: String, url: URL)] {
        root.map { Templates.available(in: $0, settings: settings) } ?? []
    }

    /// Inserts a template, filled in, at the cursor in the open note.
    func insertTemplate(at url: URL) {
        guard let template = try? NoteReader.read(contentsOf: url) else { return NSSound.beep() }
        let text = Templates.render(template, title: selectedNote?.title ?? "", settings: settings)
        NotificationCenter.default.post(name: .imprintInsertText, object: self, userInfo: ["text": text])
    }

    /// Whether the Insert Template picker is showing.
    @Published var isChoosingTemplate = false

    // MARK: Display options

    enum ListDate: String { case edited, created }

    @Published var showsDateInList = UserDefaults.standard.bool(forKey: "showsDateInList") {
        didSet { UserDefaults.standard.set(showsDateInList, forKey: "showsDateInList") }
    }
    @Published var listDate = ListDate(rawValue: UserDefaults.standard.string(forKey: "listDate") ?? "") ?? .edited {
        didSet { UserDefaults.standard.set(listDate.rawValue, forKey: "listDate") }
    }
    @Published var showsTagsInList = UserDefaults.standard.bool(forKey: "showsTagsInList") {
        didSet {
            UserDefaults.standard.set(showsTagsInList, forKey: "showsTagsInList")
            if showsTagsInList { refreshTags() }
        }
    }
    @Published var showsMarkdown = false
    /// Focus mode: just the text, with all other interface hidden.
    @Published var isFocused = false

    /// Each note's tags, read in the background while tags are shown in the list.
    @Published private(set) var tagsByNote: [Note.ID: [String]] = [:]
    private var tagsReadAt: [Note.ID: Date] = [:]

    /// Reads tags for notes that are new or changed since they were last read.
    func refreshTags() {
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
        }
    }

    // MARK: Search

    /// What's typed in the search field. Searching starts as soon as it changes.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    /// Results for `searchText`, or nil when not searching.
    @Published private(set) var searchResults: [SearchResult]?
    /// Whether the ⌘E command palette is showing.
    @Published var isPaletteShown = false
    /// Incremented to ask the search field to take focus.
    @Published private(set) var searchFocusRequest = 0
    private var searchTask: Task<Void, Never>?
    private(set) var index: SearchIndex?

    func focusSearch() {
        isFocused = false
        searchFocusRequest += 1
    }

    /// Searches for a tag, for example after a tag is clicked in a note.
    func search(tag: String) {
        searchText = "#" + tag
        focusSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // Let a burst of typing settle.
            guard !Task.isCancelled, let index = self?.index else { return }
            let results = (try? await index.search(query)) ?? []
            guard !Task.isCancelled else { return }
            self?.searchResults = results
        }
    }

    /// Opens (creating if needed) the search index for the vault at `url`. It lives in the
    /// app's own storage, never in the vault, named by a hash of the vault's path.
    private func openIndex(for url: URL) {
        let digest = SHA256.hash(data: Data(url.resolvingSymlinksInPath().path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imprint/Index", isDirectory: true)
        index = try? SearchIndex(url: folder.appendingPathComponent("\(digest).sqlite"))
    }

    /// Brings the index up to date after a scan, then refreshes any search showing.
    private func updateIndex() {
        guard let index else { return }
        let notes = notes
        Task {
            let changed = (try? await index.update(notes: notes)) ?? 0
            if changed > 0 { scheduleSearch() }
        }
    }
}
