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
        center.addObserver(self, selector: #selector(noteMoved(_:)), name: .pointNoteMoved, object: nil)
        center.addObserver(self, selector: #selector(folderMoved(_:)), name: .pointFolderMoved, object: nil)
        center.addObserver(self, selector: #selector(vaultOpened), name: .pointVaultOpened, object: nil)
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
    var sidebarDensity: SidebarDensity { get { store.sidebarDensity } set { store.sidebarDensity = newValue } }
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
    var bookmarkedNotes: [Note] { store.bookmarkedNotes }
    func isBookmarked(_ id: Note.ID) -> Bool { store.isBookmarked(id) }
    func toggleBookmark(_ id: Note.ID) { store.toggleBookmark(id) }
    func titleSuggestions(for partial: String) -> [String] { store.titleSuggestions(for: partial) }
    func makeTextBigger() { store.makeTextBigger() }
    func makeTextSmaller() { store.makeTextSmaller() }
    func rename(_ note: Note, to title: String) { store.rename(note, to: title) }
    func move(noteID: Note.ID, toFolder folder: String) { store.move(noteID: noteID, toFolder: folder) }
    func moveFolder(_ path: String, into parent: String) { store.moveFolder(path, into: parent) }
    var trashedNotes: [VaultTrash.Item] { store.trashedNotes }

    /// What a dragged sidebar row carries: a note's ID, or for a folder, this and its path.
    static let folderDragPrefix = "point-folder:"

    /// Something dropped on a folder ("" is the vault root): a note or a folder goes inside.
    func drop(_ dragged: String, onFolder folder: String) {
        if dragged.hasPrefix(Self.folderDragPrefix) {
            moveFolder(String(dragged.dropFirst(Self.folderDragPrefix.count)), into: folder)
        } else {
            move(noteID: dragged, toFolder: folder)
        }
    }

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
        /// The notes this tab showed before (and, after going back, after) its current one,
        /// for its back and forward arrows, ⌘[ and ⌘].
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
        didSet {
            tracePanes()
            saveWindowState()
            noteRecentTab()
        }
    }
    /// The pane last clicked or typed in, which the list, palette and menus act on.
    @Published private(set) var activePane = 0 {
        didSet {
            tracePanes()
            saveWindowState()
            noteRecentTab()
        }
    }

    /// The tabs, most recently shown first, for ⌃Tab.
    private(set) var recentTabs: [NoteTab.ID] = []

    private func noteRecentTab() {
        // Skips the moment in the middle of a change (a tab removed, its side's current one
        // not yet moved back) when the indices don't line up.
        guard panes.indices.contains(activePane), panes[activePane].tabs.indices.contains(panes[activePane].current) else { return }
        let id = panes[activePane].tab.id
        guard recentTabs.first != id else { return }
        recentTabs.removeAll { $0 == id }
        recentTabs.insert(id, at: 0)
        if recentTabs.count > 100 { recentTabs.removeLast() }
    }

    /// The side whose tab menu is showing, if any.
    @Published var tabMenuPane: NotePane.ID?

    /// ⇧⌘T: shows (or hides) the active side's tab menu. It lists nothing to switch to with
    /// only one tab, so it doesn't open then.
    func toggleTabMenu() {
        let pane = panes[activePane]
        if tabMenuPane != nil {
            tabMenuPane = nil
        } else if pane.tabs.count > 1 {
            tabMenuPane = pane.id
        } else {
            NSSound.beep()
        }
    }

    // MARK: Opening as it was left

    /// What's kept of the window last used, so the app opens the way it was left: its tabs on
    /// each side, the tab showing on each, the side being worked on and the folder browsed.
    private struct SavedWindow: Codable {
        var tabs: [[Note.ID?]]
        var current: [Int]
        var activePane: Int
        var place: String
    }

    private var savedStateKey: String? { root.map { "windowState." + VaultStore.vaultKey($0) } }

    /// Saves this window's state, if it's the one in use (or the only one).
    func saveWindowState() {
        guard let key = savedStateKey, store.activeWindow == nil || store.activeWindow === self else { return }
        let saved = SavedWindow(tabs: panes.map { $0.tabs.map(\.noteID) }, current: panes.map(\.current),
                                activePane: activePane, place: place.key)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Opens the window as the last one was left.
    func restoreWindowState() {
        guard let key = savedStateKey, let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(SavedWindow.self, from: data), !saved.tabs.isEmpty else { return }
        var restored: [NotePane] = saved.tabs.prefix(2).enumerated().compactMap { index, ids in
            guard !ids.isEmpty else { return nil }
            var pane = NotePane(tabs: ids.map { NoteTab(noteID: $0) })
            pane.current = min(max(saved.current.indices.contains(index) ? saved.current[index] : 0, 0), ids.count - 1)
            return pane
        }
        if restored.isEmpty { restored = [NotePane()] }
        if let place = SidebarPlace(key: saved.place) { self.place = place }
        panes = restored
        activePane = min(max(saved.activePane, 0), restored.count - 1)
    }

    private func tracePanes() {
        Trace.mark("panes: " + panes.enumerated().map { p, pane in
            (p == activePane ? "*" : "") + "[" + pane.tabs.enumerated().map { t, tab in
                (t == pane.current ? ">" : "") + (tab.noteID ?? "blank")
            }.joined(separator: ", ") + "]"
        }.joined(separator: " | "))
    }

    var isSplit: Bool { panes.count > 1 }
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

    /// The window's sidebar and notes, side by side; shows and hides the sidebar by widening
    /// and narrowing the window (see `SidebarSplitController`).
    lazy var sidebarSplit: SidebarSplitController = {
        let split = SidebarSplitController()
        split.slidingChanged = { [weak self] sliding in self?.isSidebarSliding = sliding }
        split.sidebarWidthChanged = { [weak self] width in self?.sidebarWidth = width }
        split.onToggle = { [weak self] in
            guard let self else { return }
            // As the system's button did: out of focus mode, else show or hide the sidebar.
            if self.isFocused { self.isFocused = false } else { self.showsNoteList.toggle() }
        }
        return split
    }()

    /// The width the sidebar shows at.
    @Published private(set) var sidebarWidth: CGFloat = 240

    /// The narrowest the window can be: the notes' narrowest, plus the sidebar while it shows.
    var minimumWindowWidth: CGFloat {
        SidebarSplitController.minimumNotesWidth + (showsNoteList && !isFocused ? sidebarWidth : 0)
    }

    /// While the sidebar slides in or out (see `SidebarSplitController.slidingChanged`).
    @Published private(set) var isSidebarSliding = false
    /// Counts the sidebar's toggles by hand, so a fallback for one leaves later ones alone.
    private var slideToggles = 0

    /// The window this model shows in.
    weak var window: NSWindow? {
        didSet {
            measureTopBar()
            // Again once the window has its toolbar (the sidebar button's), which can come
            // after the window does and makes the top row taller.
            DispatchQueue.main.async { [weak self] in self?.measureTopBar() }
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            resizeObserver = nil
            if let window {
                lastWidth = window.frame.width
                resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.windowResized() }
                }
            }
        }
    }

    // MARK: Hiding the sidebar in a narrow window

    private var resizeObserver: NSObjectProtocol?
    private var lastWidth: CGFloat = 0
    /// The sidebar was hidden by narrowing the window, so widening it brings it back.
    private var sidebarAutoHidden = false
    private var isAutoToggling = false
    /// Whether the sidebar last showed or hid because the window crossed the set width, which
    /// doesn't resize the window (the person is resizing it). Kept until the next change, as
    /// the view reacts to the change after it's made.
    private(set) var lastToggleWasAutomatic = false

    /// The top bars' height and inset, from where the window buttons are.
    private func measureTopBar() {
        if let height = TopBar.height(for: window), height != topBarHeight {
            Trace.mark("top bar height \(height)")
            topBarHeight = height
        }
        if let inset = TopBar.windowButtonsInset(for: window), inset != windowButtonsInset { windowButtonsInset = inset }
    }

    /// Hides the sidebar as the window narrows past the set width, and shows it again as it
    /// widens past it, if narrowing hid it. Only on crossing the width, so showing or hiding
    /// it by hand in between sticks.
    private func windowResized() {
        measureTopBar()
        guard let window else { return }
        // The set width, or the narrowest the window can be with the sidebar if that's wider
        // (the window can't narrow past it): narrowed to it, the sidebar hides.
        let width = window.frame.width
        let limit = max(CGFloat(store.sidebarAutoHideWidth), SidebarSplitController.minimumNotesWidth + sidebarWidth)
        defer { lastWidth = width }
        // Not while the window is resizing itself to show or hide the sidebar.
        guard store.autoHidesSidebar, !isFocused, !sidebarSplit.isResizing else { return }
        if lastWidth > limit, width <= limit, showsNoteList {
            setSidebarAutomatically(false)
            sidebarAutoHidden = true
        } else if lastWidth <= limit, width > limit, sidebarAutoHidden {
            setSidebarAutomatically(true)
        }
    }

    private func setSidebarAutomatically(_ shown: Bool) {
        isAutoToggling = true
        showsNoteList = shown
        isAutoToggling = false
    }
    /// The height of the bars along the window's top, lined up with its window buttons.
    @Published private(set) var topBarHeight: CGFloat = 38
    /// How far in from the window's left edge the top bar's contents start, clear of the
    /// window buttons.
    @Published private(set) var windowButtonsInset: CGFloat = 92

    /// Where a note is open, if it is.
    private func location(of id: Note.ID) -> (pane: Int, tab: Int)? {
        for p in panes.indices {
            if let t = panes[p].tabs.firstIndex(where: { $0.noteID == id }) { return (p, t) }
        }
        return nil
    }

    /// Opens a note in the active tab (recording it in the tab's history), unless it's already
    /// open on this side, or showing on the other, in which case that tab comes forward. A
    /// note in a tab behind on the other side moves here: a note is open in one place only.
    private func show(_ id: Note.ID?) {
        let old = selection
        guard id != old else { return }
        if let id, let (p, t) = location(of: id) {
            if p == activePane || panes[p].current == t {
                activePane = p
                panes[p].current = t
                return
            }
            // Not the other side's current tab, so that side keeps showing the same one.
            _ = Self.remove(t, from: &panes[p])
        }
        // The tab's history: the note it showed goes on its back list, and its forward list
        // empties, as in a browser. (Bringing another tab forward isn't history: that tab's
        // note doesn't change.)
        var tab = panes[activePane].tab
        if let old {
            tab.backStack.append(old)
            if tab.backStack.count > 200 { tab.backStack.removeFirst() }
        }
        tab.forwardStack.removeAll()
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

    /// The notes open in tabs, side by side and left to right.
    var openNoteIDs: [Note.ID] { panes.flatMap { $0.tabs.compactMap(\.noteID) } }

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

    /// Goes to the tab a note is open in, wherever it is (unlike `selection`, which moves a
    /// note from behind the other side into this one).
    func goToTab(of id: Note.ID) {
        if let (p, t) = location(of: id) { selectTab(t, inPane: p) }
    }

    /// Closes the tab a note is open in.
    func closeTab(of id: Note.ID) {
        if let (p, t) = location(of: id) { closeTab(t, inPane: p) }
    }

    /// ⌃⌘T: a new tab (a start page) on the other side, splitting the window if needed.
    func newTabOnOtherSide() {
        if isSplit { newTab(inPane: 1 - activePane) } else { toggleSplit() }
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
        // Kept for ⌘Z, while closing it is the last thing done.
        let closing = panes[p].tabs[t], wasSplit = isSplit
        defer { closedTab = ClosedTab(tab: closing, pane: p, index: t, wasSplit: wasSplit, panesAfter: panes, edits: edits) }
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

    // MARK: Reopening a closed tab

    /// The tab last closed, and the window as closing it left it.
    private struct ClosedTab {
        let tab: NoteTab
        let pane: Int
        let index: Int
        let wasSplit: Bool
        let panesAfter: [NotePane]
        let edits: Int
    }
    private var closedTab: ClosedTab?
    /// Counts edits to notes in this window, so ⌘Z only reopens a tab if nothing was typed since.
    private var edits = 0

    func noteEdited() { edits += 1 }

    /// Whether closing a tab was the last thing done in this window: nothing typed, and no
    /// tab opened, closed, moved or switched to, since.
    var canReopenClosedTab: Bool {
        guard let closedTab else { return false }
        return closedTab.panesAfter == panes && closedTab.edits == edits
    }

    /// ⌘Z straight after closing a tab: puts it back where it was, with its history.
    @discardableResult func reopenClosedTab() -> Bool {
        guard canReopenClosedTab, let closed = closedTab else { return false }
        closedTab = nil
        if closed.wasSplit, !isSplit {
            // Its side closed with it: the side comes back.
            let side = min(closed.pane, panes.count)
            panes.insert(NotePane(tabs: [closed.tab]), at: side)
            activePane = side
        } else {
            let p = min(closed.pane, panes.count - 1)
            let index = min(closed.index, panes[p].tabs.count)
            panes[p].tabs.insert(closed.tab, at: index)
            panes[p].current = index
            activePane = p
        }
        return true
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

    // MARK: Dragging tabs

    /// Where a tab is, by its ID.
    func location(ofTab id: NoteTab.ID) -> (pane: Int, tab: Int)? {
        for p in panes.indices {
            if let t = panes[p].tabs.firstIndex(where: { $0.id == id }) { return (p, t) }
        }
        return nil
    }

    /// Whether a dragged tab can make a split: only when the window isn't split yet.
    func canSplit(withTab id: NoteTab.ID) -> Bool {
        !isSplit && location(ofTab: id) != nil
    }

    /// A tab dropped on one half of an unsplit window's page: splits the window, with the
    /// tab alone on that side. If it was the only tab, the other side gets an empty one (a
    /// start page), as with ⇧⌘S.
    func split(withTab id: NoteTab.ID, onLeading: Bool) {
        guard canSplit(withTab: id), let (_, t) = location(ofTab: id) else { return }
        var source = panes[0]
        let moving = Self.remove(t, from: &source)
        if source.tabs.isEmpty { source = NotePane() }
        let side = NotePane(tabs: [moving])
        panes = onLeading ? [side, source] : [source, side]
        activePane = onLeading ? 0 : 1
    }

    /// A tab dropped among a side's tabs (`at` counts the tabs there before the drop). A side
    /// left with no tabs closes. It becomes the side's current tab unless `selects` is false
    /// and it stays on the same side (reordering in the tab menu doesn't change the note shown).
    func moveTab(_ id: NoteTab.ID, toPane target: Int, at index: Int, selects: Bool = true) {
        guard let (p, t) = location(ofTab: id), panes.indices.contains(target) else { return }
        var panes = panes
        let showing = panes[target].tab.id
        let moving = Self.remove(t, from: &panes[p])
        // The tab's own removal shifts the places after it along by one.
        let dest = min(p == target && index > t ? index - 1 : index, panes[target].tabs.count)
        panes[target].tabs.insert(moving, at: dest)
        panes[target].current = !selects && p == target ? panes[target].tabs.firstIndex { $0.id == showing } ?? dest : dest
        commitMove(panes, target: target)
    }

    /// A tab dropped on the other side's page: it becomes that side's current tab, taking
    /// the place of an empty one.
    func moveTab(_ id: NoteTab.ID, intoPane target: Int) {
        guard let (p, t) = location(ofTab: id), p != target, panes.indices.contains(target) else { return }
        var panes = panes
        let moving = Self.remove(t, from: &panes[p])
        if panes[target].tab.noteID == nil {
            panes[target].tab = moving
        } else {
            panes[target].tabs.insert(moving, at: panes[target].current + 1)
            panes[target].current += 1
        }
        commitMove(panes, target: target)
    }

    /// Takes a tab out of a pane, keeping the pane's current tab where it was (or its
    /// neighbour, if it was the one taken). May leave the pane without tabs.
    private static func remove(_ t: Int, from pane: inout NotePane) -> NoteTab {
        let tab = pane.tabs.remove(at: t)
        if pane.current > t { pane.current -= 1 }
        pane.current = max(0, min(pane.current, pane.tabs.count - 1))
        return tab
    }

    /// Shows the panes after a move in one go, closing a side left without tabs.
    private func commitMove(_ moved: [NotePane], target: Int) {
        var moved = moved
        var target = target
        if let empty = moved.firstIndex(where: { $0.tabs.isEmpty }) {
            moved.remove(at: empty)
            if empty < target { target -= 1 }
        }
        panes = moved
        activePane = target
    }

    /// Opens a note on the other side (splitting the window first if needed).
    func openToTheSide(_ id: Note.ID) {
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

    // MARK: History

    /// The active tab's history, for the Back and Forward menu items.
    var backStack: [Note.ID] { panes[activePane].tab.backStack }
    var forwardStack: [Note.ID] { panes[activePane].tab.forwardStack }

    /// Whether a side's current tab has a note to go back (or forward) to: one that still
    /// exists and isn't the one showing. The arrows are off otherwise.
    func canTravel(back: Bool, inPane pane: Int) -> Bool {
        guard panes.indices.contains(pane) else { return false }
        let tab = panes[pane].tab
        let stack = back ? tab.backStack : tab.forwardStack
        return stack.contains { id in id != tab.noteID && notes.contains { $0.id == id } }
    }

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

    /// A folder moved: if this window is showing it (or a folder inside it), follow it.
    @objc private func folderMoved(_ notification: Notification) {
        guard let old = notification.userInfo?["old"] as? String, let new = notification.userInfo?["new"] as? String,
              case .folder(let shown) = place, shown == old || shown.hasPrefix(old + "/") else { return }
        place = .folder(new + shown.dropFirst(old.count))
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

    /// Back or forward in one side's current tab (from its bar's arrows).
    func travel(back: Bool, inPane pane: Int) {
        guard panes.indices.contains(pane) else { return }
        activePane = pane
        travel(back: back)
    }

    /// Goes back (or forward) in the active tab's own history. A note is open in at most one
    /// tab, so if the note gone back to is open in another tab, it moves here, and that tab
    /// goes back a step itself (or, with nothing to go back to, becomes a start page).
    private func travel(back: Bool) {
        var panes = panes
        var tab = panes[activePane].tab
        while let id = back ? tab.backStack.popLast() : tab.forwardStack.popLast() {
            // Skip notes deleted since, and the one already showing.
            guard id != tab.noteID, notes.contains(where: { $0.id == id }) else { continue }
            if let current = tab.noteID {
                if back { tab.forwardStack.append(current) } else { tab.backStack.append(current) }
            }
            if let (p, t) = location(of: id), !(p == activePane && t == panes[p].current) {
                var other = panes[p].tabs[t]
                other.noteID = nil
                while let previous = other.backStack.popLast() {
                    if previous != id, notes.contains(where: { $0.id == previous }), location(of: previous) == nil, previous != tab.noteID {
                        other.noteID = previous
                        break
                    }
                }
                panes[p].tabs[t] = other
            }
            let old = tab.noteID
            tab.noteID = id
            panes[activePane].tab = tab
            self.panes = panes
            if let old { store.finishUntitledNote(old) }
            return
        }
        // Nothing (left) to go to: keep the stacks as tidied, and say so.
        panes[activePane].tab = tab
        self.panes = panes
        NSSound.beep()
    }

    /// Creates an untitled note in the folder being browsed (or the vault root) and opens it.
    func createNote(text: String = "", titled title: String? = nil) {
        var folder = ""
        if case .folder(let path) = place { folder = path }
        guard let id = store.createNote(text: text, titled: title, inFolder: folder) else { return }
        // A new tab, unless this one is empty, and templates on offer until typing starts.
        freshNoteID = id
        if selection == nil { selection = id } else { newTab(noteID: id) }
    }

    /// Opens today's daily note, creating it if needed.
    func openTodaysNote() {
        if let id = store.todaysNote() { selection = id }
    }

    /// Inserts a template, filled in, at the cursor in this window's note.
    func insertTemplate(at url: URL) {
        guard let note = selectedNote, let template = try? NoteReader.read(contentsOf: url) else { return NSSound.beep() }
        let text = Templates.render(template, title: note.title, settings: settings)
        NotificationCenter.default.post(name: .pointInsertText, object: self, userInfo: ["text": text, "noteID": note.id])
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
    /// Where a new folder is being made, while the New Folder sheet is showing.
    @Published var creatingFolder: FolderRequest?

    struct FolderRequest: Identifiable {
        /// The folder it goes in ("" for the vault root).
        let parent: String
        var id: String { parent }
    }

    /// Asks for a new folder's name. It goes in `parent`, or the folder being browsed.
    func newFolder(in parent: String? = nil) {
        var folder = ""
        if case .folder(let path) = place { folder = path }
        creatingFolder = FolderRequest(parent: parent ?? folder)
    }

    /// Makes the folder and browses into it, so ⌘N then puts a note there.
    func createFolder(named name: String, in parent: String) {
        guard let path = store.createFolder(named: name, in: parent) else { return }
        browse(.folder(path))
    }
    @Published var moving: Note?
    @Published var tagging: Note?
    /// Whether the Insert Template picker is showing.
    @Published var isChoosingTemplate = false
    /// The keyboard shortcuts sheet (⌘/).
    @Published var isShowingShortcuts = false

    // MARK: Window

    /// Focus mode: just the text, with all other interface hidden.
    @Published var isFocused = false
    /// Whether the sidebar is showing (⌘S, or a two-finger swipe if turned on in Settings,
    /// hides and shows it).
    /// Remembered, so new windows open the way the last one was left: hiding the sidebar
    /// is how Point becomes a single, compact note.
    @Published var showsNoteList = UserDefaults.standard.object(forKey: "showsNoteList") == nil || UserDefaults.standard.bool(forKey: "showsNoteList") {
        didSet {
            UserDefaults.standard.set(showsNoteList, forKey: "showsNoteList")
            lastToggleWasAutomatic = isAutoToggling
            if !isAutoToggling { sidebarAutoHidden = false } // Shown or hidden by hand.
            // Sliding from now, before anything is laid out for the change (the split view says
            // when it has finished; in case it doesn't animate at all, not for long).
            if !isAutoToggling && !isFocused {
                isSidebarSliding = true
                slideToggles += 1
                let toggle = slideToggles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    // Only for this toggle: not one made since, which may be sliding now.
                    guard let self, self.slideToggles == toggle, !self.sidebarSplit.isResizing else { return }
                    self.isSidebarSliding = false
                }
            }
        }
    }

    func startSwipeTracking() { store.startSwipeTracking() }

    // MARK: Search

    /// What's typed in the search field. Searching starts as soon as it changes.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    /// Results for `searchText`, or nil when not searching.
    @Published private(set) var searchResults: [SearchResult]?
    /// Whether the command palette is showing.
    @Published var isPaletteShown = false
    /// Whether the palette searches (⌘F) or browses folders and tags (⌘E).
    @Published var paletteMode = PaletteMode.search
    /// Text to start the palette with, such as a tag clicked in a note.
    @Published var paletteSeed: String?
    /// Where the palette's explorer was left (place, column, note), to start there next time.
    var explorerPlace: SidebarPlace = .allNotes
    var explorerInNotes = false
    var explorerNote: Note.ID?
    /// ⌘F or ⌘E pressed while a start page is showing: the page switches to that mode.
    @Published private(set) var startPageRequest: (mode: PaletteMode, count: Int) = (.search, 0)

    /// Searching (⌘F), browsing folders and tags (⌘E), only the open tabs (⌃Tab), or the
    /// folders to move the note to (Move Note).
    enum PaletteMode { case search, explorer, tabs, moveNote }
    /// ⌃Tab pressed again while the tabs palette shows: it moves to the next tab down.
    @Published private(set) var paletteCycleRequest = 0

    /// The palette, listing folders to move the note to.
    func moveNoteInPalette() {
        guard selectedNote != nil else { return NSSound.beep() }
        paletteMode = .moveNote
        isPaletteShown = true
    }

    /// Shows the palette in a mode, or hides it if it's already showing that.
    func togglePalette(_ mode: PaletteMode) {
        if mode == .tabs {
            if isPaletteShown && paletteMode == .tabs {
                paletteCycleRequest += 1
            } else if openNoteIDs.isEmpty {
                NSSound.beep()
            } else {
                paletteMode = .tabs
                isPaletteShown = true
            }
            return
        }
        // On a start page, ⌘F and ⌘E switch the page itself between searching and
        // exploring, rather than opening a palette on top of it.
        if selection == nil, !isPaletteShown {
            startPageRequest = (mode, startPageRequest.count + 1)
            return
        }
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

    /// Puts the cursor in the sidebar's search field, showing the sidebar if it's hidden.
    func focusSearch() {
        isFocused = false
        searchFocusRequest += 1
    }

    /// Shows a folder (clicked in a side's path): in the sidebar if it's showing, otherwise in
    /// the explorer, with the note open there highlighted.
    func reveal(folder path: String) {
        if showsNoteList && !isFocused {
            browse(.folder(path))
            return
        }
        explorerPlace = .folder(path)
        explorerNote = selection.flatMap { id in notes(in: .folder(path)).contains { $0.id == id } ? id : nil }
        explorerInNotes = explorerNote != nil
        isPaletteShown = false
        DispatchQueue.main.async { [weak self] in
            self?.paletteMode = .explorer
            self?.isPaletteShown = true
        }
    }

    /// Searches for a tag, for example after a tag is clicked in a note.
    func search(tag: String) {
        // With the sidebar hidden, show the tag's notes in the explorer rather than bringing
        // the sidebar back.
        if !showsNoteList || isFocused {
            explorerPlace = .tag(tag)
            explorerInNotes = true
            explorerNote = nil
            isPaletteShown = false
            DispatchQueue.main.async { [weak self] in
                self?.paletteMode = .explorer
                self?.isPaletteShown = true
            }
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
    @Published var place: SidebarPlace = .allNotes {
        didSet { saveWindowState() }
    }

    func browse(_ place: SidebarPlace) {
        Trace.mark("browse \(place.key)")
        if place.isTag { lastTagPlace = place } else { lastFolderPlace = place }
        searchText = ""
        if place == .trash { store.refreshTrash() } // Obsidian may have added to it.
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
    /// How tightly the sidebar's rows are packed. The same heights in one column and in both
    /// columns of two, so the layouts match.
    enum SidebarDensity: String {
        case compact, comfortable

        /// A folder, tag or note without tags to show: the system's small and medium sidebar
        /// rows, which the two-column view's tree uses.
        var rowHeight: CGFloat { self == .compact ? 24 : 32 }
        /// A note with its tags on a second line.
        var twoLineHeight: CGFloat { self == .compact ? 38 : 48 }
        /// A section heading ("Folders", "Tags").
        var headerHeight: CGFloat { self == .compact ? 24 : 30 }
        /// The line between sections, with room above it.
        var dividerHeight: CGFloat { self == .compact ? 11 : 19 }
    }

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
