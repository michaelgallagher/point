import AppKit
import Combine
import EditorKit
import IndexKit
import VaultKit

/// One window's (or tab's) view of the vault: the note it shows, the folder it's browsing, its
/// search, history and sheets. Everything about the vault itself (notes, index, tags, file
/// operations, display settings) lives in the shared `VaultStore`; this model passes it through,
/// so views use one object.
@MainActor
final class VaultModel: ObservableObject {
    let store: VaultStore
    private var storeChanges: AnyCancellable?
    private var indexChanges: AnyCancellable?

    init(store: VaultStore) {
        self.store = store
        // Redraw this window's views whenever the shared vault changes.
        storeChanges = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        indexChanges = store.$indexGeneration.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.scheduleSearch() }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(noteMoved(_:)), name: .imprintNoteMoved, object: nil)
        center.addObserver(self, selector: #selector(vaultOpened), name: .imprintVaultOpened, object: nil)
        center.addObserver(self, selector: #selector(appWillTerminate), name: NSApplication.willTerminateNotification, object: nil)
    }

    // MARK: The vault, shared

    var root: URL? { store.root }
    var notes: [Note] { store.notes }
    var errorMessage: String? { store.errorMessage }
    var settings: ObsidianSettings { store.settings }
    var index: SearchIndex? { store.index }
    var tagsByNote: [Note.ID: [String]] { store.tagsByNote }
    var indexedTags: [Note.ID: [String]] { store.indexedTags }
    var tagTree: TagTree { store.tagTree }
    var pins: [SidebarPlace] { store.pins }
    var folderTree: FolderTree { store.folderTree }
    var folderNodes: [PlaceNode] { store.folderNodes }
    var tagNodes: [PlaceNode] { store.tagNodes }
    var templates: [(name: String, url: URL)] { store.templates }

    var sort: NoteSort { get { store.sort } set { store.sort = newValue } }
    var showsDateInList: Bool { get { store.showsDateInList } set { store.showsDateInList = newValue } }
    var listDate: ListDate { get { store.listDate } set { store.listDate = newValue } }
    var showsTagsInList: Bool { get { store.showsTagsInList } set { store.showsTagsInList = newValue } }
    var showsMarkdown: Bool { get { store.showsMarkdown } set { store.showsMarkdown = newValue } }
    var textScale: Double { get { store.textScale } set { store.textScale = newValue } }
    var browsingStyle: BrowsingStyle { get { store.browsingStyle } set { store.browsingStyle = newValue } }
    var tagOrder: TagOrder { get { store.tagOrder } set { store.tagOrder = newValue } }

    func chooseVault() { store.chooseVault() }
    func reload() async { await store.reload() }
    func refreshTags() { store.refreshTags() }
    func listTags(for id: Note.ID) -> [String] { store.listTags(for: id) }
    func notes(in place: SidebarPlace) -> [Note] { store.notes(in: place) }
    func subplaces(of place: SidebarPlace) -> [SidebarPlace] { store.subplaces(of: place) }
    func noteCount(of place: SidebarPlace) -> Int { store.noteCount(of: place) }
    func isPinned(_ place: SidebarPlace) -> Bool { store.isPinned(place) }
    func togglePin(_ place: SidebarPlace) { store.togglePin(place) }
    func titleSuggestions(for partial: String) -> [String] { store.titleSuggestions(for: partial) }
    func makeTextBigger() { store.makeTextBigger() }
    func makeTextSmaller() { store.makeTextSmaller() }
    func rename(_ note: Note, to title: String) { store.rename(note, to: title) }
    func move(noteID: Note.ID, toFolder folder: String) { store.move(noteID: noteID, toFolder: folder) }

    func moveToTrash(_ note: Note) {
        store.moveToTrash(note)
        if selection == note.id { selection = nil }
    }

    func showInFinder(_ note: Note) {
        NSWorkspace.shared.activateFileViewerSelecting([note.url])
    }

    // MARK: This window's note and history

    @Published var selection: Note.ID? {
        didSet {
            guard let oldValue, oldValue != selection else { return }
            if !isMovingThroughHistory {
                backStack.append(oldValue)
                forwardStack.removeAll()
            }
            store.finishUntitledNote(oldValue)
        }
    }
    /// Notes visited before and after the current one, for ⌘[ and ⌘].
    @Published private(set) var backStack: [Note.ID] = []
    @Published private(set) var forwardStack: [Note.ID] = []
    private var isMovingThroughHistory = false

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    /// Changes the note shown without counting it as a visit (the same note, moved).
    private func follow(to id: Note.ID?) {
        isMovingThroughHistory = true
        selection = id
        isMovingThroughHistory = false
    }

    /// A note moved or was renamed (perhaps from another window): keep showing it.
    @objc private func noteMoved(_ notification: Notification) {
        guard let old = notification.userInfo?["old"] as? String, let new = notification.userInfo?["new"] as? String else { return }
        backStack = backStack.map { $0 == old ? new : $0 }
        forwardStack = forwardStack.map { $0 == old ? new : $0 }
        if selection == old { follow(to: new) }
    }

    @objc private func vaultOpened() {
        follow(to: nil)
        backStack = []
        forwardStack = []
        searchText = ""
        place = .allNotes
    }

    @objc private func appWillTerminate() {
        if let selection { store.finishUntitledNote(selection) }
    }

    func goBack() { move(from: &backStack, to: &forwardStack) }
    func goForward() { move(from: &forwardStack, to: &backStack) }

    private func move(from source: inout [Note.ID], to destination: inout [Note.ID]) {
        // Skip notes deleted since they were visited.
        while let id = source.popLast() {
            guard notes.contains(where: { $0.id == id }) else { continue }
            if let selection { destination.append(selection) }
            follow(to: id)
            return
        }
        NSSound.beep()
    }

    /// Creates an untitled note in the folder being browsed (or the vault root) and opens it.
    func createNote(text: String = "") {
        var folder = ""
        if case .folder(let path) = place { folder = path }
        if let id = store.createNote(text: text, inFolder: folder) { selection = id }
    }

    /// Opens today's daily note, creating it if needed.
    func openTodaysNote() {
        if let id = store.todaysNote() { selection = id }
    }

    /// Inserts a template, filled in, at the cursor in this window's note.
    func insertTemplate(at url: URL) {
        guard let note = selectedNote, let template = try? NoteReader.read(contentsOf: url) else { return NSSound.beep() }
        let text = Templates.render(template, title: note.title, settings: settings)
        NotificationCenter.default.post(name: .imprintInsertText, object: self, userInfo: ["text": text, "noteID": note.id])
    }

    // MARK: Links and tabs

    /// Opens a note in a new tab of this window. Set by the window, which can open tabs.
    var openTab: ((Note.ID?) -> Void)?

    /// Follows a clicked link: notes open here (missing ones are created, as in Obsidian),
    /// or in a new tab when asked; web addresses open in the browser.
    func open(_ link: LinkTarget, from sourceID: Note.ID, inNewTab: Bool = false) {
        let resolver = LinkResolver(notes: notes)
        func show(_ id: Note.ID) {
            if inNewTab, let openTab { openTab(id) } else { selection = id }
        }
        switch link {
        case .note(let target):
            if let note = resolver.resolve(wikiTarget: target, from: sourceID) {
                show(note.id)
            } else if let id = store.createLinkedNote(named: target) {
                show(id)
            } else {
                NSSound.beep()
            }
        case .file(let destination):
            if let note = resolver.resolve(markdownDestination: destination, from: sourceID) {
                show(note.id)
            } else {
                NSSound.beep()
            }
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .tag(let tag):
            search(tag: tag)
        }
    }

    // MARK: Sheets

    /// The note being renamed, moved or tagged, while that sheet is showing.
    @Published var renaming: Note?
    @Published var moving: Note?
    @Published var tagging: Note?
    /// Whether the Insert Template picker is showing.
    @Published var isChoosingTemplate = false

    // MARK: Window

    /// Focus mode: just the text, with all other interface hidden.
    @Published var isFocused = false
    /// Whether the note list is showing (⌘S, or a two-finger swipe, hides and shows it).
    @Published var showsNoteList = true

    func startSwipeTracking() { store.startSwipeTracking() }

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

    // MARK: Browsing folders and tags

    /// Where the sidebar is: the top level, a folder or a tag.
    @Published var place: SidebarPlace = .allNotes

    func browse(_ place: SidebarPlace) {
        Trace.mark("browse \(place.key)")
        if place.isTag { lastTagPlace = place } else { lastFolderPlace = place }
        searchText = ""
        self.place = place
    }

    /// Back up to the enclosing folder or parent tag.
    func goUp() {
        guard place != .allNotes else { return NSSound.beep() }
        browse(place.parent)
    }

    /// Opens the previous (-1) or next (+1) note in the list showing (⌥⌘↑ / ⌥⌘↓).
    func selectAdjacentNote(_ offset: Int) {
        let ids = searchResults?.map(\.id) ?? notes(in: place).map(\.id)
        guard !ids.isEmpty else { return NSSound.beep() }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = offset > 0 ? ids.first : ids.last
            return
        }
        let next = index + offset
        guard ids.indices.contains(next) else { return NSSound.beep() }
        selection = ids[next]
    }

    // MARK: Browsing styles

    enum ListDate: String { case edited, created }

    /// One list you move through, or folders and tags beside a list of notes.
    enum BrowsingStyle: String, CaseIterable, Identifiable {
        case singleColumn, twoColumns
        var id: String { rawValue }
    }

    enum TreeKind: String { case folders, tags }
    enum TagOrder: String { case name, modified }

    /// What the two-column view's left column shows, in this window.
    @Published var treeKind = TreeKind(rawValue: UserDefaults.standard.string(forKey: "treeKind") ?? "") ?? .folders {
        didSet {
            UserDefaults.standard.set(treeKind.rawValue, forKey: "treeKind") // The default for new windows.
            guard treeKind != oldValue else { return }
            // Show what was last chosen in this tree, so the highlight and the notes match.
            switch treeKind {
            case .folders:
                if place.isTag { browse(lastFolderPlace) }
            case .tags:
                if !place.isTag { browse(lastTagPlace ?? tagTree.entries.first.map { .tag($0.tag) } ?? .allNotes) }
            }
        }
    }
    /// The folder (or top level) and tag last browsed, to return to when switching trees.
    private var lastFolderPlace: SidebarPlace = .allNotes
    private var lastTagPlace: SidebarPlace?

    /// A folder or tag in the two-column view's tree.
    struct PlaceNode: Identifiable, Hashable {
        let place: SidebarPlace
        let name: String
        /// Nil for a leaf, so the tree shows no disclosure triangle.
        var children: [PlaceNode]?
        var id: SidebarPlace { place }
    }
}
