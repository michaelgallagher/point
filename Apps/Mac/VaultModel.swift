import AppKit
import Combine
import EditorKit
import IndexKit
import VaultKit

/// One window's view of the vault: the notes it shows (in panes and tabs), the folder it's browsing, its
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
    var treeLayout: TreeLayout { get { store.treeLayout } set { store.treeLayout = newValue } }
    var sortedTagEntries: [TagTree.Entry] { store.sortedTagEntries }

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
        // Tabs showing it go blank; histories forget it.
        for p in panes.indices {
            for t in panes[p].tabs.indices {
                if panes[p].tabs[t].noteID == note.id { panes[p].tabs[t].noteID = nil }
                panes[p].tabs[t].backStack.removeAll { $0 == note.id }
                panes[p].tabs[t].forwardStack.removeAll { $0 == note.id }
            }
        }
    }

    func showInFinder(_ note: Note) {
        NSWorkspace.shared.activateFileViewerSelecting([note.url])
    }

    // MARK: Panes and tabs

    /// One tab: a note (or none yet) and its own history.
    struct NoteTab: Identifiable, Equatable {
        let id = UUID()
        var noteID: Note.ID?
        /// Notes visited before and after this one in this tab, for ⌘[ and ⌘].
        var backStack: [Note.ID] = []
        var forwardStack: [Note.ID] = []
    }

    /// One side of the window: its tabs, one of them showing.
    struct NotePane: Identifiable, Equatable {
        let id = UUID()
        var tabs: [NoteTab]
        var current = 0

        init(tabs: [NoteTab] = [NoteTab()]) { self.tabs = tabs }

        var tab: NoteTab {
            get { tabs[current] }
            set { tabs[current] = newValue }
        }
    }

    /// The window's notes: one pane, or two side by side. Each note is open in at most one
    /// tab, so two editors never write the same file.
    @Published private(set) var panes = [NotePane()] {
        didSet { tracePanes() }
    }
    /// The pane last clicked or typed in, which the list, palette and menus act on.
    @Published private(set) var activePane = 0 {
        didSet { tracePanes() }
    }

    private func tracePanes() {
        Trace.mark("panes: " + panes.enumerated().map { p, pane in
            (p == activePane ? "*" : "") + "[" + pane.tabs.enumerated().map { t, tab in
                (t == pane.current ? ">" : "") + (tab.noteID ?? "blank")
            }.joined(separator: ", ") + "]"
        }.joined(separator: " | "))
    }

    var isSplit: Bool { panes.count > 1 }
    /// The Minimal layout: one note, tabs down the side, no sidebar and no splitting.
    var isMinimal: Bool { browsingStyle == .minimal }
    /// Opens a note in a new window. Set by the window, which can open others.
    var openWindowHandler: ((Note.ID?) -> Void)?
    /// A note just made with ⌘N in the Minimal layout, which offers templates while empty.
    @Published var freshNoteID: Note.ID?

    /// The note in the active pane's current tab. Setting it opens a note there, or moves to
    /// the tab where it's already open.
    var selection: Note.ID? {
        get { panes[activePane].tab.noteID }
        set { show(newValue) }
    }

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    func note(_ id: Note.ID?) -> Note? {
        id.flatMap { id in notes.first { $0.id == id } }
    }

    /// The window this model shows in.
    weak var window: NSWindow? {
        didSet {
            if let height = TopBar.height(for: window) {
                Trace.mark("top bar height \(height)")
                topBarHeight = height
            }
        }
    }
    /// The height of the bars along the window's top, lined up with its window buttons.
    @Published private(set) var topBarHeight: CGFloat = 38

    /// Where a note is open, if it is.
    private func location(of id: Note.ID) -> (pane: Int, tab: Int)? {
        for p in panes.indices {
            if let t = panes[p].tabs.firstIndex(where: { $0.noteID == id }) { return (p, t) }
        }
        return nil
    }

    /// Opens a note in the active tab (counting the visit in its history), unless it's
    /// already open somewhere, in which case that tab comes forward.
    private func show(_ id: Note.ID?, recordsVisit: Bool = true) {
        let old = selection
        guard id != old else { return }
        if let id, let (p, t) = location(of: id) {
            activePane = p
            panes[p].current = t
            return
        }
        var tab = panes[activePane].tab
        if recordsVisit, let old {
            tab.backStack.append(old)
            tab.forwardStack.removeAll()
        }
        tab.noteID = id
        panes[activePane].tab = tab
        if let old { store.finishUntitledNote(old) }
    }

    /// Makes a pane the active one (when its note gets the keyboard, or it's clicked).
    func activate(pane id: NotePane.ID) {
        guard let index = panes.firstIndex(where: { $0.id == id }), index != activePane else { return }
        activePane = index
    }

    func paneIndex(_ id: NotePane.ID) -> Int? { panes.firstIndex { $0.id == id } }

    /// Opens a note (or a blank tab) in a new tab of a pane, the active one unless given.
    func newTab(noteID: Note.ID? = nil, inPane pane: Int? = nil) {
        if let noteID, let (p, t) = location(of: noteID) {
            activePane = p
            panes[p].current = t
            return
        }
        let p = pane ?? activePane
        let insertAt = panes[p].current + 1
        panes[p].tabs.insert(NoteTab(noteID: noteID), at: insertAt)
        panes[p].current = insertAt
        activePane = p
    }

    func selectTab(_ tab: Int, inPane pane: Int) {
        guard panes.indices.contains(pane), panes[pane].tabs.indices.contains(tab) else { return }
        activePane = pane
        panes[pane].current = tab
    }

    /// Moves to the next (+1) or previous (-1) tab in the active pane.
    func cycleTab(_ step: Int) {
        let count = panes[activePane].tabs.count
        guard count > 1 else { return NSSound.beep() }
        panes[activePane].current = (panes[activePane].current + step + count) % count
    }

    /// Closes a tab (the active one unless given). The last tab of a side closes that side;
    /// the window's very last tab closes the window.
    func closeTab(_ tab: Int? = nil, inPane pane: Int? = nil) {
        let p = pane ?? activePane
        let t = tab ?? panes[p].current
        guard panes.indices.contains(p), panes[p].tabs.indices.contains(t) else { return }
        if let id = panes[p].tabs[t].noteID { store.finishUntitledNote(id) }
        if panes[p].tabs.count == 1 {
            if isSplit {
                panes.remove(at: p)
                activePane = 0
            } else {
                window?.performClose(nil)
            }
            return
        }
        panes[p].tabs.remove(at: t)
        if panes[p].current >= t, panes[p].current > 0 { panes[p].current -= 1 }
        activePane = p
    }

    /// Closes one side of a split, with its tabs.
    func closePane(_ pane: Int) {
        guard isSplit, panes.indices.contains(pane) else { return }
        for tab in panes[pane].tabs { if let id = tab.noteID { store.finishUntitledNote(id) } }
        panes.remove(at: pane)
        activePane = 0
    }

    func closeOtherTabs(_ tab: Int, inPane pane: Int) {
        guard panes.indices.contains(pane), panes[pane].tabs.indices.contains(tab) else { return }
        for other in panes[pane].tabs.indices where other != tab {
            if let id = panes[pane].tabs[other].noteID { store.finishUntitledNote(id) }
        }
        panes[pane].tabs = [panes[pane].tabs[tab]]
        panes[pane].current = 0
    }

    /// ⇧⌘S: splits the window, with an empty side that gets the next note picked; or, when
    /// already split, puts every note back into one side's tabs.
    func toggleSplit() {
        guard !isMinimal else { return NSSound.beep() } // Two notes means two windows there.
        if isSplit { mergeIntoTabs() } else {
            panes.append(NotePane())
            activePane = 1
        }
    }

    /// Ends the split, keeping both sides' notes as tabs of one.
    func mergeIntoTabs() {
        guard isSplit else { return }
        let activeTabID = panes[activePane].tab.id
        var tabs = panes[0].tabs + panes[1].tabs
        // Drop empty tabs, unless that would leave none.
        let filled = tabs.filter { $0.noteID != nil }
        if !filled.isEmpty { tabs = filled }
        var merged = NotePane(tabs: tabs)
        merged.current = tabs.firstIndex { $0.id == activeTabID } ?? 0
        panes = [merged]
        activePane = 0
    }

    /// Moves a tab to the other side, splitting the window if it isn't already.
    func moveTabToOtherSide(_ tab: Int? = nil, inPane pane: Int? = nil) {
        guard !isMinimal else { return NSSound.beep() }
        let p = pane ?? activePane
        let t = tab ?? panes[p].current
        guard panes.indices.contains(p), panes[p].tabs.indices.contains(t) else { return }
        let moving = panes[p].tabs[t]
        if !isSplit {
            guard panes[0].tabs.count > 1 else { return NSSound.beep() } // Nothing would be left.
            panes[0].tabs.remove(at: t)
            panes[0].current = min(panes[0].current, panes[0].tabs.count - 1)
            panes.append(NotePane(tabs: [moving]))
            activePane = 1
            return
        }
        let other = 1 - p
        panes[p].tabs.remove(at: t)
        // Fill an empty tab on the other side rather than adding beside it.
        if panes[other].tab.noteID == nil {
            panes[other].tab = moving
        } else {
            panes[other].tabs.insert(moving, at: panes[other].current + 1)
            panes[other].current += 1
        }
        if panes[p].tabs.isEmpty {
            panes.remove(at: p)
            activePane = 0
        } else {
            panes[p].current = min(panes[p].current, panes[p].tabs.count - 1)
            activePane = other
        }
    }

    /// Opens a note on the other side (splitting the window first if needed).
    func openToTheSide(_ id: Note.ID) {
        if isMinimal, location(of: id) == nil, let openWindowHandler {
            return openWindowHandler(id)
        }
        if let (p, t) = location(of: id) {
            activePane = p
            panes[p].current = t
            return
        }
        if !isSplit { panes.append(NotePane()) }
        activePane = 1 - activePane
        show(id)
    }

    /// Set when a note is picked in the list, so its editor leaves the keyboard there.
    private var keepsListFocus = false

    /// Opens a note picked in the list, leaving the keyboard in the list.
    func selectFromList(_ id: Note.ID) {
        guard selection != id else { return }
        keepsListFocus = true
        selection = id
    }

    /// Whether the editor opening now should leave the keyboard in the list (asked once).
    func consumeListFocus() -> Bool {
        defer { keepsListFocus = false }
        return keepsListFocus
    }

    /// The active tab's history, for the Back and Forward menu items.
    var backStack: [Note.ID] { panes[activePane].tab.backStack }
    var forwardStack: [Note.ID] { panes[activePane].tab.forwardStack }

    /// A note moved or was renamed (perhaps from another window): keep showing it.
    @objc private func noteMoved(_ notification: Notification) {
        guard let old = notification.userInfo?["old"] as? String, let new = notification.userInfo?["new"] as? String else { return }
        for p in panes.indices {
            for t in panes[p].tabs.indices {
                var tab = panes[p].tabs[t]
                if tab.noteID == old { tab.noteID = new }
                tab.backStack = tab.backStack.map { $0 == old ? new : $0 }
                tab.forwardStack = tab.forwardStack.map { $0 == old ? new : $0 }
                panes[p].tabs[t] = tab
            }
        }
    }

    @objc private func vaultOpened() {
        panes = [NotePane()]
        activePane = 0
        searchText = ""
        place = .allNotes
    }

    @objc private func appWillTerminate() {
        for pane in panes { for tab in pane.tabs { if let id = tab.noteID { store.finishUntitledNote(id) } } }
    }

    func goBack() { travel(back: true) }
    func goForward() { travel(back: false) }

    private func travel(back: Bool) {
        var tab = panes[activePane].tab
        // Skip notes deleted since, or open in another tab now.
        while let id = back ? tab.backStack.popLast() : tab.forwardStack.popLast() {
            guard notes.contains(where: { $0.id == id }), location(of: id) == nil else { continue }
            if let current = tab.noteID {
                if back { tab.forwardStack.append(current) } else { tab.backStack.append(current) }
                store.finishUntitledNote(current)
            }
            tab.noteID = id
            panes[activePane].tab = tab
            return
        }
        panes[activePane].tab = tab
        NSSound.beep()
    }

    /// Creates an untitled note in the folder being browsed (or the vault root) and opens it.
    func createNote(text: String = "") {
        var folder = ""
        if case .folder(let path) = place { folder = path }
        guard let id = store.createNote(text: text, inFolder: folder) else { return }
        if isMinimal {
            // A new tab, unless this one is empty, and templates on offer until typing starts.
            freshNoteID = id
            if selection == nil { selection = id } else { newTab(noteID: id) }
        } else {
            selection = id
        }
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

    // MARK: Links

    /// Where a followed link opens, relative to the pane it was clicked in.
    enum LinkDestination { case here, newTab, otherSide }

    /// Follows a clicked link: notes open in the pane (missing ones are created, as in
    /// Obsidian), in a new tab, or on the other side; web addresses open in the browser.
    func open(_ link: LinkTarget, from sourceID: Note.ID, inPane paneID: NotePane.ID, as destination: LinkDestination = .here) {
        let resolver = LinkResolver(notes: notes)
        func show(_ id: Note.ID) {
            if let pane = paneIndex(paneID) { activePane = pane }
            switch destination {
            case .here: selection = id
            case .newTab: newTab(noteID: id)
            case .otherSide: openToTheSide(id)
            }
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
    /// Whether the palette searches (⌘E) or browses folders and tags (⇧⌘E).
    @Published var paletteMode = PaletteMode.search
    /// Text to start the palette with, such as a tag clicked in a note.
    @Published var paletteSeed: String?
    /// Where the palette's explorer was left, to start there next time.
    var explorerLevel = ExplorerLevel.place(.allNotes)

    enum PaletteMode { case search, explorer }

    /// Shows the palette in a mode, or hides it if it's already showing that.
    func togglePalette(_ mode: PaletteMode) {
        if isPaletteShown && paletteMode == mode {
            isPaletteShown = false
        } else {
            paletteMode = mode
            isPaletteShown = true
        }
    }
    /// Incremented to ask the search field to take focus.
    @Published private(set) var searchFocusRequest = 0
    private var searchTask: Task<Void, Never>?

    func focusSearch() {
        if isMinimal {
            // No list to search in: the palette is the search.
            paletteMode = .search
            isPaletteShown = true
            return
        }
        isFocused = false
        searchFocusRequest += 1
    }

    /// Searches for a tag, for example after a tag is clicked in a note.
    func search(tag: String) {
        if isMinimal {
            paletteSeed = "#" + tag
            isPaletteShown = false
            DispatchQueue.main.async { [weak self] in self?.focusSearch() }
            return
        }
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
        /// No sidebar: tabs down the side, and a start page in every empty tab.
        case minimal
        case singleColumn, twoColumns
        var id: String { rawValue }
    }

    enum TreeKind: String { case folders, tags }
    enum TagOrder: String { case name, modified }
    /// The two-column view's left column: folders and tags stacked, or one at a time.
    enum TreeLayout: String { case stacked, toggle }

    /// What the two-column view's left column shows, in this window.
    @Published var treeKind = TreeKind(rawValue: UserDefaults.standard.string(forKey: "treeKind") ?? "") ?? .folders {
        didSet {
            UserDefaults.standard.set(treeKind.rawValue, forKey: "treeKind") // The default for new windows.
            guard treeKind != oldValue else { return }
            matchPlaceToTree()
        }
    }

    /// With one tree showing at a time, shows what was last chosen in that tree, so the
    /// highlight and the notes match. (Stacked, both trees show, so anything goes.)
    func matchPlaceToTree() {
        guard browsingStyle == .twoColumns, treeLayout == .toggle else { return }
        switch treeKind {
        case .folders:
            if place.isTag { browse(lastFolderPlace) }
        case .tags:
            if !place.isTag { browse(lastTagPlace ?? tagTree.entries.first.map { .tag($0.tag) } ?? .allNotes) }
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
