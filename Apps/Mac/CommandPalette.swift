import AppKit
import IndexKit
import EditorKit
import SwiftUI
import VaultKit

/// ⌘E, Search Vault: one place to open notes and folders, search tags and run commands, all from
/// the keyboard, narrowed with ⌘1 to ⌘4 (see `PaletteScope`): everything, only notes, folders
/// and tags (browsed a place at a time, see `PaletteBrowse`), or only commands (as after ">").
/// Run Command and Browse Folders open it narrowed to commands or to folders.
/// ⌃Tab: only the open tabs, in number order, to switch between them. Letting go of ⌃ goes to
/// the one highlighted, which starts as the tab shown before this.
/// An empty tab shows the same palette as a page: the start page.
struct CommandPalette: View {
    @EnvironmentObject private var model: VaultModel
    @State private var query = ""
    @State private var items: [PaletteItem] = []
    /// Section labels, by the index of the item each one comes before.
    @State private var headers: [Int: String] = [:]
    @State private var highlighted = 0
    /// Notes open in tabs, marked in the list.
    @State private var openIDs: Set<Note.ID> = []
    @State private var tags: [(tag: String, count: Int)] = []
    @State private var searchTask: Task<Void, Never>?
    /// While browsing: the place shown.
    @State private var browsePlace: SidebarPlace = .allNotes
    /// Shown as a tab's start page rather than over the window.
    var isPage = false
    /// For a start page, the side it's on: what's picked on it opens there, in its own tab,
    /// even if the other side was being worked on since.
    var paneID: VaultModel.NotePane.ID?
    /// Doing something to a result: its actions (⌘K or Tab), then what an action asks for
    /// (a folder, a template). Each step back (←, ⌫ or Escape) goes back one.
    @State private var steps: [PaletteStep] = []
    /// Opened by Move Note or Apply Template, for the note being viewed: closes rather than
    /// going back to the results.
    @State private var openedForStep = false
    /// What was typed, and the row highlighted, before the actions were shown, to go back to.
    @State private var beforeSteps: (query: String, highlighted: Int) = ("", 0)
    /// What it's narrowed to, once changed in it (⌘1 to ⌘4, the bar, a folder picked); until
    /// then, what it was opened for.
    @State private var chosenScope: PaletteScope?
    /// With nothing typed, every bookmark rather than the first few (Show All Bookmarks).
    @State private var showsAllBookmarks = false
    /// Narrowed to commands with nothing typed, every command rather than the usual few
    /// (Show All Commands).
    @State private var showsAllCommands = false
    /// The floating palette's widest: narrower over a narrow window or side.
    var maxWidth: CGFloat = CommandPalette.widest

    private var isSwitchingTabs: Bool { !isPage && model.paletteMode == .tabs }
    private var isMovingNote: Bool { if case .moveTo = steps.last { true } else { false } }
    private var isApplyingTemplate: Bool { if case .applyTemplate = steps.last { true } else { false } }
    /// Choosing a tab, an action, a folder or a template: a job of its own, not narrowed.
    private var isPicking: Bool { isSwitchingTabs || !steps.isEmpty }
    private var scope: PaletteScope {
        chosenScope ?? (isPage ? .all : PaletteScope(mode: model.paletteMode))
    }
    private var isBrowsing: Bool { !isPicking && scope == .places }
    private var isRunningCommands: Bool { !isPicking && scope == .commands }
    private var isNotesOnly: Bool { !isPicking && scope == .notes }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isMovingNote ? "folder" : isApplyingTemplate ? "doc.on.doc" : !steps.isEmpty ? "ellipsis.circle" : isPicking ? "map" : scope.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                PaletteField(text: $query, placeholder: placeholder, fontSize: isPage ? 22 : 18,
                             onMove: move, onSubmit: run, onCancel: cancel, onCloseItem: closeHighlightedTab,
                             onLeft: isSwitchingTabs ? nil : { back() },
                             onRight: isPicking ? nil : { enterHighlightedPlace() },
                             onScope: isPicking ? nil : { number in PaletteScope(rawValue: number).map(setScope) },
                             scopeKeysNeedFocus: isPage,
                             onActions: isSwitchingTabs || isMovingNote || isApplyingTemplate ? nil : { toggleActions() })
            }
            .font(isPage ? .title2 : .title3)
            .padding(.horizontal, 16)
            .padding(.vertical, isPage ? 12 : 18)
            // On a start page, the field is a rounded box; in the floating palette, a line
            // below it divides it from the list.
            .background {
                if isPage {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .padding(.bottom, isPage ? 10 : 0)

            if !steps.isEmpty {
                PaletteStepTrail(titles: stepTitles, back: back)
                    .padding(.horizontal, isPage ? 16 : 18)
                    .padding(.top, isPage ? 4 : -2)
                    .padding(.bottom, isPage ? 10 : 10)
            } else if !isPicking {
                // Clear of the field, so the two don't read as one cramped block.
                PaletteScopeBar(scope: scope, choose: setScope)
                    .padding(.horizontal, isPage ? 10 : 12)
                    .padding(.top, isPage ? 4 : -2)
                    .padding(.bottom, isPage ? 10 : 10)
            }

            if isBrowsing {
                PaletteBrowseTrail(place: browsePlace, model: model) { go(to: $0) }
                    .padding(.horizontal, isPage ? 16 : 18)
                    .padding(.bottom, isPage ? 8 : 10)
            }

            if !items.isEmpty || !isPage || isBrowsing {
                // A line between the field (and the bar under it) and the list, on a start page too.
                Divider()
                    .padding(.horizontal, isPage ? 4 : 0)
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                if let header = headers[offset] {
                                    PaletteSectionHeader(title: header, isFirst: offset == 0)
                                }
                                // Open tabs have their own section, so aren't marked as well.
                                PaletteRow(item: item, isHighlighted: offset == highlighted,
                                           tabNumber: item.noteID.flatMap(model.tabNumber(of:)),
                                           isViewing: item.noteID != nil && item.noteID == model.selection,
                                           isBookmarked: item.noteID.map(model.isBookmarked) ?? false)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        highlighted = offset
                                        run()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    // One height, so the palette doesn't change size as it's typed in or
                    // browsed; as a page, it fills the tab.
                    .frame(height: isPage ? nil : Self.listHeight)
                    .frame(maxHeight: isPage ? .infinity : nil)
                    .overlay {
                        if isBrowsing, items.isEmpty {
                            Text(query.isEmpty ? "Nothing here" : "Nothing matches").foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: highlighted) { offset in
                        if items.indices.contains(offset) { scroller.scrollTo(items[offset].id) }
                    }
                }
            }
        }
        .modifier(PaletteChrome(isPage: isPage, maxWidth: maxWidth))
        .task {
            if !isPage, let seed = model.paletteSeed {
                query = seed
                model.paletteSeed = nil
            }
            startSteps(for: model.paletteMode)
            if isBrowsing { browsePlace = model.browsePlace }
            // At once: ⌃ can be let go at any moment, and a later refresh would lose the row.
            if isSwitchingTabs {
                refresh()
                tags = (try? await model.index?.allTags()) ?? []
                return
            }
            tags = (try? await model.index?.allTags()) ?? []
            refresh()
        }
        .onChange(of: query) { _ in refresh() }
        // A folder made, moved or gone while browsing: list it as it is now.
        .onReceive(model.store.$folderTree.dropFirst()) { _ in
            if isBrowsing { refresh(keeping: highlighted) }
        }
        // At launch the palette (or a start page) can appear before the notes have loaded.
        .onChange(of: model.notes.count) { _ in
            if query.isEmpty { refresh(keeping: isBrowsing ? highlighted : nil) }
        }
        .onChange(of: model.paletteMode) { _ in
            guard !isPage else { return }
            query = ""
            chosenScope = nil
            startSteps(for: model.paletteMode)
            if isBrowsing { browsePlace = model.browsePlace }
            refresh()
        }
        // ⌃Tab again: the next tab down.
        .onChange(of: model.paletteCycleRequest) { _ in
            if isSwitchingTabs { move(1) }
        }
        .onChange(of: model.paletteCommitRequest) { _ in
            if isSwitchingTabs { run() }
        }
        // Gone to another app with ⌃ down: its release won't be seen, so it can't choose a tab.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if isSwitchingTabs, model.isHoldingTabSwitch { close() }
        }
        .onChange(of: model.startPageRequest.count) { _ in
            // Search Vault or Browse Folders on a start page switches the page itself.
            guard isPage else { return }
            query = ""
            setScope(PaletteScope(mode: model.startPageRequest.mode))
        }
    }

    /// The palette's list height, searching or browsing.
    static let listHeight: CGFloat = 520
    /// The floating palette's width, where the window (or the side it's over) has room.
    static let widest: CGFloat = 680

    private var placeholder: String {
        if isBrowsing {
            return browsePlace == .allNotes ? "Filter folders, tags and notes" : "Filter \(PaletteBrowse.name(of: browsePlace, model: model))"
        }
        if isSwitchingTabs { return "Switch to a tab" }
        if isRunningCommands { return "Run a command" }
        if isNotesOnly { return "Search notes" }
        switch steps.last {
        case .actions(let subject): return "Do something with “\(subject.title(model: model))”"
        case .moveTo(let id): return "Move “\(model.note(id)?.title ?? "")” to…"
        case .applyTemplate(let id):
            return model.templates.isEmpty ? "No templates (choose a folder in Settings, under Templates)" : "Apply a template to “\(model.note(id)?.title ?? "")”"
        case nil: break
        }
        return "Search"
    }

    /// Escape closes the palette; on a start page, it clears what's typed, then searches
    /// everything again.
    private func cancel() {
        if !steps.isEmpty { return stepBack() }
        guard isPage else { return close() }
        if !query.isEmpty { query = "" } else if scope != .all { setScope(.all) }
    }

    /// Narrows the palette (⌘1 to ⌘4, or the bar), keeping what's typed; the one it's narrowed
    /// to already goes back to everything. Folders start where they were last browsed.
    private func setScope(_ new: PaletteScope) {
        let new = new == scope && new != .all ? .all : new
        if new == .places { browsePlace = model.browsePlace }
        chosenScope = new
        refresh()
    }

    /// ← at the start of what's typed, or ⌫ with nothing typed: up a folder while browsing;
    /// otherwise (or at the vault's top), back to everything.
    private func back() {
        if !steps.isEmpty { return stepBack() }
        if isBrowsing, let parent = PaletteBrowse.parent(of: browsePlace) {
            go(to: parent, highlighting: PaletteBrowse.item(browsePlace, from: parent, model: model).id)
        } else if scope != .all {
            setScope(.all)
        }
    }

    // MARK: Actions

    /// The trail above an action's list: what it's done to, then each step.
    private var stepTitles: [String] {
        steps.map { step in
            switch step {
            case .actions(let subject): subject.title(model: model)
            case .moveTo: "Move to"
            case .applyTemplate: "Apply Template"
            }
        }
    }

    /// Opened by Move Note or Apply Template: straight to the folders or templates, for the
    /// note being viewed.
    private func startSteps(for mode: VaultModel.PaletteMode) {
        guard !isPage else { return }
        switch (mode, model.selection) {
        case (.moveNote, let id?): steps = [.moveTo(id)]
        case (.applyTemplate, let id?): steps = [.applyTemplate(id)]
        default: steps = []
        }
        openedForStep = !steps.isEmpty
    }

    /// ⌘K or Tab: the highlighted result's actions; again, back to the results.
    private func toggleActions() {
        if case .actions = steps.last { return stepBack() }
        guard steps.isEmpty, items.indices.contains(highlighted),
              let subject = PaletteSubject(items[highlighted]) else { return NSSound.beep() }
        beforeSteps = (query, highlighted)
        push(.actions(subject))
    }

    private func push(_ step: PaletteStep) {
        steps.append(step)
        query = ""
        refresh()
    }

    /// One step back: from a folder or template to the actions, from the actions to the
    /// results as they were. Opened for a step, back from it closes.
    private func stepBack() {
        steps.removeLast()
        if steps.isEmpty, openedForStep { return close() }
        if steps.isEmpty {
            query = beforeSteps.query
            refresh(keeping: beforeSteps.highlighted)
        } else {
            query = ""
            refresh()
        }
    }

    private func refreshActions(for subject: PaletteSubject) {
        var actions = PaletteAction.all(for: subject, model: model)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { actions = Self.rank(actions, by: trimmed, name: \.name) }
        items = actions.map(PaletteItem.action)
        headers = [:]
        highlighted = 0
    }

    // MARK: Browsing

    /// Shows a place's folders and notes: browsing, if searching before.
    private func go(to place: SidebarPlace, highlighting row: String? = nil) {
        browsePlace = place
        model.browsePlace = place
        chosenScope = .places
        query = ""
        refresh()
        if let row, let index = items.firstIndex(where: { $0.id == row }) { highlighted = index }
    }

    /// → at the end of what's typed: into the place highlighted, if it's one.
    private func enterHighlightedPlace() {
        guard items.indices.contains(highlighted), case .place(let place, _, _, _, _) = items[highlighted] else { return }
        go(to: place)
    }

    /// A start page's side becomes the one being worked on, so what's picked opens in its tab.
    private func takeSide() {
        if isPage, let paneID { model.activate(pane: paneID) }
    }

    private func open(_ id: Note.ID, inNewTab: Bool) {
        takeSide()
        let typed = query.trimmingCharacters(in: .whitespaces)
        if !isPage { close() }
        // A start page opens the note in its own tab, which is the active one.
        if inNewTab { model.newTab(noteID: id) } else { model.selection = id }
        // Search learns which note was wanted for what was typed.
        if !typed.isEmpty { model.store.resultPicked(id, for: typed) }
    }

    // MARK: Results

    /// Lists what matches what's typed. `keeping` keeps the highlight at that row (or the
    /// last one) rather than going back to the top, as after closing a tab from the list.
    private func refresh(keeping: Int? = nil) {
        searchTask?.cancel()
        let query = query
        if isBrowsing { return refreshBrowse(keeping: keeping) }
        if isSwitchingTabs { return refreshTabs(keeping: keeping) }
        switch steps.last {
        case .actions(let subject): return refreshActions(for: subject)
        case .moveTo(let id): return refreshFolders(movingNote: id)
        case .applyTemplate: return refreshTemplates()
        case nil: break
        }
        if isRunningCommands { return refreshCommands() }
        let commandHistory = model.store.commandHistory
        let commands = PaletteCommand.all(for: model)
        // Notes open in tabs come first, in number order, wherever the one being viewed is.
        let openNotes = model.openNoteIDs.compactMap { model.note($0) }
        let openSet = Set(openNotes.map(\.id))
        openIDs = openSet
        let bookmarked = Self.byViews(model.bookmarkedNotes, history: model.store.searchHistory)
        let notesOnly = isNotesOnly
        let allBookmarks = showsAllBookmarks
        searchTask = Task {
            // Each kind of thing in its own labelled section, in this order.
            var open: [PaletteItem] = [], marked: [PaletteItem] = [], notes: [PaletteItem] = []
            var tagItems: [PaletteItem] = [], commandItems: [PaletteItem] = [], folderItems: [PaletteItem] = []
            var notesTitle = "Notes"
            var commandsFirst = false, foldersFirst = false
            let trimmed = query.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(">"), !notesOnly {
                commandItems = PaletteCommand.ranked(commands, by: String(trimmed.dropFirst()), history: commandHistory).map(PaletteItem.command)
            } else if trimmed.hasPrefix("#"), !trimmed.contains(where: \.isWhitespace) {
                // Only a tag so far: the matching tags. With more after it (`#design budget`),
                // the notes with that tag that match the rest, below.
                let tagQuery = String(trimmed.dropFirst())
                tagItems = tags.filter { tagQuery.isEmpty || $0.tag.lowercased().contains(tagQuery.lowercased()) || Fuzzy.score(query: tagQuery, name: $0.tag) != nil }
                    .prefix(30).map { PaletteItem.tag($0.tag, $0.count) }
            } else if trimmed.isEmpty {
                open = openNotes.map { PaletteItem.note($0.id, $0.title, nil) }
                // Bookmarks are listed only narrowed to notes (⌘2); with everything, a
                // bookmark comes up among the suggestions as any other note does.
                let markedNotes = notesOnly ? bookmarked.filter { !openSet.contains($0.id) } : []
                // A few, then a row to show the rest, so the suggestions stay in reach.
                let start = Self.startCount
                marked = markedNotes.prefix(allBookmarks ? markedNotes.count : start).map { PaletteItem.note($0.id, $0.title, nil) }
                if !allBookmarks, markedNotes.count > start {
                    marked.append(.action(PaletteAction(name: "Show All \(markedNotes.count) Bookmarks", symbol: "ellipsis",
                                                        perform: .here { showsAllBookmarks = true })))
                }
                // Bookmarks not listed yet stay out of the suggestions, to come up under Show All.
                let shown = openSet.union(markedNotes.map(\.id))
                notesTitle = "Suggested"
                // The notes opened and edited most lately (an edit counts as an open).
                let history = model.store.searchHistory, now = Date()
                let scores = Dictionary(model.notes.map { ($0.id, history.score(of: $0.id, modified: $0.modified, now: now)) }, uniquingKeysWith: { a, _ in a })
                notes = model.notes.filter { !shown.contains($0.id) }
                    .sorted { scores[$0.id]! != scores[$1.id]! ? scores[$0.id]! > scores[$1.id]! : $0.modified > $1.modified }
                    .prefix(Self.startCount).map { PaletteItem.note($0.id, $0.title, nil) }
                // The commands run most, or else the usual ones.
                commandItems = PaletteCommand.ordered(commands, history: commandHistory).prefix(Self.startCount).map(PaletteItem.command)
            } else {
                let hasTags = !SearchTags.tags(in: trimmed).isEmpty
                // More than are shown, so a note picked for this before can come up from lower down.
                let searched = (try? await model.index?.search(trimmed, limit: 30)) ?? []
                let results = Array(model.store.searchHistory.rank(searched, for: trimmed).prefix(8))
                let found = results.map { PaletteItem.note($0.id, $0.title, $0.snippet) }
                @MainActor func matching(_ candidates: [Note]) -> [PaletteItem] {
                    // By title, or found in the search (with its snippet). Filtered by a tag,
                    // only what the search found, which has the tag.
                    let byTitle = hasTags ? [] : Self.rank(candidates, by: trimmed, name: \.title).map(\.id)
                    let ids = Set(candidates.map(\.id))
                    let inSearch = found.compactMap(\.noteID).filter { ids.contains($0) && !byTitle.contains($0) }
                    return (byTitle + inSearch).compactMap { id in
                        found.first { $0.noteID == id } ?? model.note(id).map { PaletteItem.note($0.id, $0.title, nil) }
                    }
                }
                open = matching(openNotes)
                // Bookmarks have a section of their own only narrowed to notes; otherwise
                // they're found as other notes are.
                let markedNotes = notesOnly ? bookmarked.filter { !openSet.contains($0.id) } : []
                marked = matching(markedNotes)
                let shown = Set((open + marked).compactMap(\.noteID))
                notes = found.filter { !shown.contains($0.noteID ?? "") }
                // A name no note has yet: offer to make it, first if nothing else matched (so
                // typing a new name and pressing Return makes the note).
                let title = NoteFiles.sanitizedTitle(trimmed)
                if !hasTags, !title.isEmpty, !model.notes.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                    notes.append(.create(title))
                }
                tagItems = tags.filter { Fuzzy.score(query: trimmed, name: $0.tag) != nil }.prefix(3).map { PaletteItem.tag($0.tag, $0.count) }
                if !hasTags { folderItems = PaletteBrowse.folders(matching: trimmed, limit: 3, model: model) }
                // A folder whose name matches better than any note's title comes before the
                // notes, so typing a folder's name and pressing Return goes into it.
                if let best = folderItems.first.flatMap({ Fuzzy.score(query: trimmed, name: $0.name) }) {
                    let bestTitle = (open + marked + notes).filter { $0.noteID != nil }
                        .compactMap { Fuzzy.score(query: trimmed, name: $0.name) }.min()
                    foldersFirst = best < bestTitle ?? .max
                }
                // Commands whose names match better than any note's title come first, so "move"
                // goes to Move Note… rather than a note that only mentions moving. Only when
                // every word is a whole word or the start of one, so typing a new note's name
                // and pressing Return still makes it.
                let ranked = PaletteCommand.ranked(commands, by: trimmed, history: commandHistory)
                let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
                if !hasTags, trimmed.count >= 2, let best = ranked.first,
                   words.allSatisfy({ (Fuzzy.score(query: $0, name: best.name) ?? .max) <= 2 }),
                   let bestScore = Fuzzy.score(query: trimmed, name: best.name) {
                    let bestTitle = (open + marked + notes).filter { $0.noteID != nil }
                        .compactMap { Fuzzy.score(query: trimmed, name: $0.name) }.min()
                    commandsFirst = bestScore < bestTitle ?? .max
                }
                // A command picked for this before, and no note picked for it: first, as it
                // was wanted last time ("mo", then Move Note…).
                if !hasTags, !commandsFirst, let best = ranked.first, commandHistory.pick(for: trimmed) == best.key,
                   model.store.searchHistory.pick(for: trimmed) == nil {
                    commandsFirst = true
                }
                commandItems = ranked.prefix(commandsFirst ? 5 : 3).map(PaletteItem.command)
            }
            // Narrowed to notes (⌘2): nothing else.
            if notesOnly {
                (commandItems, tagItems, folderItems) = ([], [], [])
                (commandsFirst, foldersFirst) = (false, false)
            }
            guard !Task.isCancelled else { return }
            // Nothing matched but the new note (and no command first): it comes first, so
            // Return makes it.
            let groups = commandsFirst
                ? [("Commands", commandItems), ("Open Tabs", open), ("Bookmarks", marked), (notesTitle, notes), ("Folders", folderItems), ("Tags", tagItems)]
                : open.isEmpty && marked.isEmpty && notes.count == 1 && notes.first.map({ if case .create = $0 { true } else { false } }) == true
                ? [(notesTitle, notes), ("Folders", folderItems), ("Tags", tagItems), ("Commands", commandItems)]
                : foldersFirst
                ? [("Folders", folderItems), ("Open Tabs", open), ("Bookmarks", marked), (notesTitle, notes), ("Tags", tagItems), ("Commands", commandItems)]
                : notesOnly && trimmed.isEmpty
                // Narrowed to notes with nothing typed: the notes used lately before bookmarks.
                ? [("Open Tabs", open), (notesTitle, notes), ("Bookmarks", marked)]
                : [("Open Tabs", open), ("Bookmarks", marked), (notesTitle, notes), ("Folders", folderItems), ("Tags", tagItems), ("Commands", commandItems)]
            var all: [PaletteItem] = [], labels: [Int: String] = [:]
            for (title, group) in groups where !group.isEmpty {
                labels[all.count] = title
                all += group
            }
            items = all
            headers = labels
            // Past the note being viewed, as going to it does nothing.
            let first = !foldersFirst && open.count > 1 && all.first?.noteID == model.selection ? 1 : 0
            highlighted = keeping.map { max(0, min($0, items.count - 1)) } ?? first
        }
    }

    /// The place being browsed: its places and notes, filtered by what's typed. The note open
    /// now, or the one last opened from here, highlighted if it's in it.
    private func refreshBrowse(keeping: Int?) {
        openIDs = Set(model.openNoteIDs)
        var all: [PaletteItem] = [], labels: [Int: String] = [:]
        for (title, group) in PaletteBrowse.sections(at: browsePlace, filter: query, model: model) {
            labels[all.count] = title
            all += group
        }
        items = all
        headers = labels
        if let keeping {
            highlighted = max(0, min(keeping, items.count - 1))
        } else if query.isEmpty, let id = model.browseNote ?? model.selection,
                  let index = items.firstIndex(where: { $0.noteID == id }) {
            highlighted = index
        } else {
            highlighted = 0
        }
    }

    /// The open tabs' notes, in number order (both sides), filtered by what's typed. With
    /// nothing typed, the one shown before this is highlighted, so a quick ⌃Tab flips between
    /// two notes, and ⌃Tab again moves down from there.
    private func refreshTabs(keeping: Int?) {
        var notes = model.openNoteIDs.compactMap { model.note($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { notes = Self.rank(notes, by: trimmed, name: \.title) }
        openIDs = Set(notes.map(\.id))
        items = notes.map { PaletteItem.note($0.id, $0.title, nil) }
        headers = [:]
        if let keeping {
            highlighted = max(0, min(keeping, items.count - 1))
        } else {
            let previous = model.previousTab(withNote: true)?.noteID
            let first = trimmed.isEmpty ? items.firstIndex { $0.noteID == previous } ?? 0 : 0
            highlighted = items.isEmpty ? 0 : (first + model.tabSwitchSteps) % items.count
            model.tabSwitchSteps = 0
        }
    }

    /// The commands, filtered by what's typed (a leading ">", as in Search Vault, is ignored).
    /// With nothing typed, the ones run most (or else the usual ones), then a row to show the
    /// rest, so every command can be found without them all crowding the list.
    private func refreshCommands() {
        let commands = PaletteCommand.all(for: model)
        let history = model.store.commandHistory
        var trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if !trimmed.isEmpty {
            items = PaletteCommand.ranked(commands, by: trimmed, history: history).map(PaletteItem.command)
        } else {
            let ordered = PaletteCommand.ordered(commands, history: history)
            let shown = showsAllCommands ? ordered.count : Self.commandCount
            items = ordered.prefix(shown).map(PaletteItem.command)
            if ordered.count > shown {
                items.append(.action(PaletteAction(name: "Show All \(ordered.count) Commands", symbol: "ellipsis",
                                                   perform: .here { showsAllCommands = true })))
            }
        }
        headers = [:]
        highlighted = 0
    }

    /// Every folder ("" is the vault's top level) but the note's own, filtered by what's typed.
    /// The vault's templates, filtered by what's typed.
    private func refreshTemplates() {
        var templates = model.templates
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { templates = Self.rank(templates, by: trimmed, name: \.name) }
        items = templates.map { PaletteItem.template($0.name, $0.url) }
        headers = [:]
        highlighted = 0
    }

    private func refreshFolders(movingNote id: Note.ID) {
        let current = FolderTree.folder(of: id)
        let all = [""] + model.folderTree.noteCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var folders = all.filter { $0 != current }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { folders = Self.rank(folders.filter { !$0.isEmpty }, by: trimmed, name: \.self) }
        items = folders.map(PaletteItem.folder)
        headers = [:]
        highlighted = 0
    }

    /// ⌘⌫ on a note open in a tab closes that tab, and the palette stays open. Returns false
    /// for anything else, so ⌘⌫ deletes what's typed as usual.
    private func closeHighlightedTab() -> Bool {
        guard items.indices.contains(highlighted), let id = items[highlighted].noteID,
              openIDs.contains(id), model.openNoteIDs.contains(id) else { return false }
        let row = highlighted
        model.closeTab(of: id)
        refresh(keeping: row)
        return true
    }

    static func rank<T>(_ things: [T], by query: String, name: KeyPath<T, String>) -> [T] {
        things.compactMap { thing in Fuzzy.score(query: query, name: thing[keyPath: name]).map { (thing, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    // MARK: Keyboard

    private func move(_ step: Int) {
        guard !items.isEmpty else { return }
        highlighted = (highlighted + step + items.count) % items.count
    }

    private func run() {
        takeSide()
        let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        guard items.indices.contains(highlighted) else { return }
        let item = items[highlighted]
        // A place opens here, in the palette.
        if case .place(let place, _, _, _, _) = item { return go(to: place) }
        // An action that asks for something (a folder, a template) asks here.
        if case .action(let action) = item, case .step(let step) = action.perform { return push(step) }
        if case .action(let action) = item, case .here(let perform) = action.perform {
            perform()
            return refresh(keeping: highlighted)
        }
        if case .action(let action) = item, case .browse(let place) = action.perform {
            steps = []
            return go(to: place)
        }
        if isBrowsing, let id = item.noteID { model.browseNote = id }
        let step = steps.last
        if !isPage { close() } else { steps = [] }
        switch item {
        case .note(let id, _, _) where isSwitchingTabs:
            model.goToTab(of: id)
        case .note(let id, _, _):
            open(id, inNewTab: inNewTab)
        case .tag(let tag, _): model.search(tag: tag)
        case .create(let title): model.createNote(titled: title)
        case .command(let command):
            // Learned, so it comes up sooner next time.
            var typed = query.trimmingCharacters(in: .whitespaces)
            if typed.hasPrefix(">") { typed = String(typed.dropFirst()) }
            model.store.commandRun(command.key, for: typed)
            command.action()
        case .folder(let folder):
            if case .moveTo(let id) = step { model.move(noteID: id, toFolder: folder) }
        case .template(_, let url):
            if case .applyTemplate(let id) = step { model.applyTemplate(at: url, to: id) }
        case .action(let action):
            if case .run(let perform) = action.perform { perform() }
        case .place: break
        }
    }

    private func close() {
        model.isPaletteShown = false
    }

    /// With nothing typed, how many bookmarks, suggested notes and commands are listed.
    static let startCount = 4
    /// Narrowed to commands with nothing typed, how many are listed before Show All.
    static let commandCount = 8

    /// Bookmarks, the ones opened most (and most lately) first; those never opened here
    /// keep their bookmarked order, after.
    static func byViews(_ notes: [Note], history: SearchHistory) -> [Note] {
        let now = Date()
        let scores = notes.map { history.score(of: $0.id, now: now) }
        return notes.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }.map { notes[$0] }
    }
}

enum PaletteItem: Identifiable {
    case note(Note.ID, String, String?)
    case tag(String, Int)
    /// A new note with this name.
    case create(String)
    case command(PaletteCommand)
    /// A folder to move the note to, by path ("" for the vault's top level).
    case folder(String)
    /// A template to apply to the note.
    case template(String, URL)
    /// A folder, tag or other place to browse: its name, how many notes, its symbol, and
    /// where it is, if deeper than where it's listed.
    case place(SidebarPlace, String, Int, String, String?)
    /// Something to do to a result (see `PaletteAction`).
    case action(PaletteAction)

    var noteID: Note.ID? {
        if case .note(let id, _, _) = self { return id }
        return nil
    }

    var id: String {
        switch self {
        case .note(let id, _, _): "note:\(id)"
        case .tag(let tag, _): "tag:\(tag)"
        case .create(let title): "create:\(title)"
        case .command(let command): "command:\(command.name)"
        case .folder(let folder): "folder:\(folder)"
        case .template(_, let url): "template:\(url.path)"
        case .place(let place, _, _, _, _): "place:\(place.key)"
        case .action(let action): "action:\(action.name)"
        }
    }

    /// What filtering matches against.
    var name: String {
        switch self {
        case .note(_, let title, _): title
        case .tag(let tag, _): tag
        case .create(let title): title
        case .command(let command): command.name
        case .folder(let folder): folder
        case .template(let name, _): name
        case .place(_, let name, _, _, _): name
        case .action(let action): action.name
        }
    }
}

/// The palette's frame: a floating panel over the window, or as a page, a centred column
/// on the tab's own background.
private struct PaletteChrome: ViewModifier {
    let isPage: Bool
    /// The floating palette's widest.
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if isPage {
            content
                .frame(maxWidth: CommandPalette.widest)
                .padding(.top, 48)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            // As wide as it may be, within a narrow window or side.
            content
                .frame(maxWidth: maxWidth)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // One shadow for the whole panel, not one per row.
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        }
    }
}

/// A label above a section of the palette's list: open tabs, bookmarks, notes, tags, commands.
struct PaletteSectionHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, isFirst ? 2 : 10)
            .padding(.bottom, 3)
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let isHighlighted: Bool
    /// An open tab's number, shown in place of its icon.
    var tabNumber: Int?
    /// The note on screen now, marked as such.
    var isViewing = false
    /// A bookmarked note, shown with the bookmark symbol.
    var isBookmarked = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let tabNumber {
                    Text("\(tabNumber)")
                        .monospacedDigit()
                } else {
                    Image(systemName: icon)
                }
            }
            .frame(width: 18)
            .foregroundStyle(isHighlighted ? .white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if case .place(_, _, _, _, let path?) = item {
                    Text(path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                }
                if case .note(_, _, let snippet?) = item {
                    Text(snippet.filter { $0 != SearchResult.matchStart && $0 != SearchResult.matchEnd }.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                }
            }
            Spacer()
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }
            if case .place = item {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? Color.accentColor : .clear))
    }

    private var icon: String {
        switch item {
        case .note: isBookmarked ? "bookmark" : "doc.text"
        case .tag: "number.sign.circle"
        case .create: "plus"
        case .command(let command): command.symbol ?? "command"
        case .folder: "folder"
        case .template: "doc.on.doc"
        case .place(_, _, _, let symbol, _): symbol
        case .action(let action): action.symbol
        }
    }

    private var title: String {
        switch item {
        case .note(_, let title, _): title
        case .tag(let tag, _): "#\(tag)"
        case .create(let title): "New Note “\(title)”"
        case .command(let command): command.name
        case .folder(let folder): folder.isEmpty ? "Vault (top level)" : folder
        case .template(let name, _): name
        case .place(_, let name, _, _, _): name
        case .action(let action): action.name
        }
    }

    private var detail: String? {
        switch item {
        case .note: isViewing ? "Viewing" : nil
        case .tag(_, let count): "\(count) \(count == 1 ? "note" : "notes")"
        case .create, .folder, .template: nil
        case .place(_, _, let count, _, _): "\(count)"
        case .action(let action): action.shortcut
        case .command(let command): command.shortcut
        }
    }
}

/// Something the palette can do.
struct PaletteCommand {
    let name: String
    let shortcut: String?
    /// Its icon, if not the command symbol.
    var symbol: String?
    /// What it's learned under, if not its name: one key for a command named for what it'll
    /// do now (Show Markdown, Hide Markdown), so using either counts for both.
    var learnedAs: String?
    let action: () -> Void

    var key: String { learnedAs ?? name }

    /// Offered first until the palette has learned what's used: the usual things to do.
    static let usual = ["New Note", "Move Note…", "Show in Finder", "Insert List", "New List", "Insert Table", "bookmark", "Enclosing Folder"]

    /// A command run once counts for this little after about a month: forgotten, so it
    /// doesn't stay ahead of the usual ones.
    static let forgottenScore = 0.25

    /// In the order they're offered with nothing typed: those run most, and most lately,
    /// first; then the usual ones; then the rest by name.
    static func ordered(_ commands: [PaletteCommand], history: SearchHistory) -> [PaletteCommand] {
        let now = Date()
        let scores = commands.map { history.score(of: $0.key, now: now) }.map { $0 < forgottenScore ? 0 : $0 }
        let usual = commands.map { Self.usual.firstIndex(of: $0.key) ?? .max }
        return commands.indices.sorted { a, b in
            if scores[a] != scores[b] { return scores[a] > scores[b] }
            if usual[a] != usual[b] { return usual[a] < usual[b] }
            return commands[a].name.localizedStandardCompare(commands[b].name) == .orderedAscending
        }.map { commands[$0] }
    }

    /// Those matching `query`, best match first; among matches about as good, the one picked
    /// for this before, then those run most, then the usual ones.
    static func ranked(_ commands: [PaletteCommand], by query: String, history: SearchHistory) -> [PaletteCommand] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let ordered = Self.ordered(commands, history: history)
        guard !query.isEmpty else { return ordered }
        let scored: [(offset: Int, command: PaletteCommand, score: Int)] = ordered.enumerated().compactMap { offset, command in
            guard let score = Fuzzy.score(query: query, name: command.name) else { return nil }
            return (offset, command, score)
        }
        let matches = scored.sorted { $0.score != $1.score ? $0.score < $1.score : $0.offset < $1.offset }.map(\.command)
        return history.rank(matches, for: query, id: { $0.key }, titleQuality: { Fuzzy.score(query: query, name: $0.name) })
    }

    @MainActor static func all(for model: VaultModel) -> [PaletteCommand] {
        var commands = [
            PaletteCommand(name: "New Note", shortcut: ShortcutStore.shared.label(for: .newNote)) { model.createNote() },
            PaletteCommand(name: "Today's Note", shortcut: nil) { model.openTodaysNote() },
            PaletteCommand(name: "New Note from Template…", shortcut: nil) { model.isCreatingFromTemplate = true },
            PaletteCommand(name: "New List", shortcut: nil) { model.createList() },
            PaletteCommand(name: "New Folder…", shortcut: ShortcutStore.shared.label(for: .newFolder)) { model.newFolder() },
            PaletteCommand(name: model.showsNoteList ? "Hide Note List" : "Show Note List", shortcut: ShortcutStore.shared.label(for: .toggleNoteList), learnedAs: "note list") { model.showsNoteList.toggle() },
            PaletteCommand(name: "Bigger Text", shortcut: ShortcutStore.shared.label(for: .biggerText)) { model.makeTextBigger() },
            PaletteCommand(name: "Smaller Text", shortcut: ShortcutStore.shared.label(for: .smallerText)) { model.makeTextSmaller() },
            PaletteCommand(name: model.showsMarkdown ? "Hide Markdown" : "Show Markdown", shortcut: ShortcutStore.shared.label(for: .showMarkdown), learnedAs: "markdown") { model.showsMarkdown.toggle() },
            PaletteCommand(name: model.showsTagsInList ? "Hide Tags in List" : "Show Tags in List", shortcut: nil, learnedAs: "tags in list") { model.showsTagsInList.toggle() },
            PaletteCommand(name: "Sort by Date Edited", shortcut: nil) { model.sort = .modified },
            PaletteCommand(name: "Sort by Date Created", shortcut: nil) { model.sort = .created },
            PaletteCommand(name: "Sort by Title", shortcut: nil) { model.sort = .title },
            PaletteCommand(name: "Back", shortcut: ShortcutStore.shared.label(for: .back)) { model.goBack() },
            PaletteCommand(name: "Forward", shortcut: ShortcutStore.shared.label(for: .forward)) { model.goForward() },
            PaletteCommand(name: "Open Vault…", shortcut: ShortcutStore.shared.label(for: .openVault)) { model.chooseVault() },
            PaletteCommand(name: "All Notes", shortcut: nil) { model.browse(.allNotes) },
            PaletteCommand(name: "Enclosing Folder", shortcut: ShortcutStore.shared.label(for: .enclosingFolder)) { model.goUp() },
            PaletteCommand(name: "Find Unused Images…", shortcut: nil) { model.isShowingUnusedImages = true },
        ]
        // A new note of each kind ("New Meeting"), and of each of its templates after the
        // first ("New Meeting: 1-1").
        for kind in model.store.kinds.offered {
            let templates = model.store.templates(of: kind)
            commands.append(PaletteCommand(name: "New \(kind.name)", shortcut: nil) { model.createNote(kind: kind) })
            for template in templates.dropFirst() {
                commands.append(PaletteCommand(name: "New \(kind.name): \(template.label)", shortcut: nil) {
                    model.createNote(kind: kind, template: template.url)
                })
            }
        }
        // What's browsed renamed everywhere, and the last such change undone.
        switch model.place {
        case .tag(let tag): commands.append(PaletteCommand(name: "Rename Tag…", shortcut: nil) { model.renamingAcrossVault = .tag(tag) })
        case .property(let name): commands.append(PaletteCommand(name: "Rename Property…", shortcut: nil) { model.renamingAcrossVault = .property(name) })
        case .propertyValue(let name, let value):
            commands.append(PaletteCommand(name: "Change Value…", shortcut: nil) { model.renamingAcrossVault = .value(property: name, value: value) })
        default: break
        }
        if let change = model.store.lastVaultChange {
            commands.append(PaletteCommand(name: "Undo “\(change.name)”", shortcut: nil) { model.store.undoLastVaultChange() })
        }
        // The two ways of showing dates in the list that aren't the one in use.
        for (style, name) in [(VaultModel.ListDateStyle.beside, "Show Dates Beside Titles"), (.groups, "Group Notes by Date"), (.off, "Hide Dates in List")]
        where style != model.listDateStyle {
            commands.append(PaletteCommand(name: name, shortcut: nil) { model.listDateStyle = style })
        }
        commands += [
            PaletteCommand(name: "New Tab", shortcut: ShortcutStore.shared.label(for: .newTab)) { model.newTab() },
            PaletteCommand(name: "New Tab on Other Side", shortcut: ShortcutStore.shared.label(for: .newTabOnOtherSide)) { model.newTabOnOtherSide() },
            PaletteCommand(name: "Close Tab", shortcut: ShortcutStore.shared.label(for: .closeTab)) { model.closeTab() },
            PaletteCommand(name: "Switch to Tab…", shortcut: ShortcutStore.shared.label(for: .switchToTab)) {
                // After the palette running this has closed.
                DispatchQueue.main.async { model.togglePalette(.tabs) }
            },
        ]
        commands += [
            PaletteCommand(name: model.isSplit ? "Merge Split into Tabs" : "Split", shortcut: ShortcutStore.shared.label(for: .split), learnedAs: "split") { model.toggleSplit() },
            PaletteCommand(name: model.isSplit ? "Move Tab to Other Side" : "Move Tab to New Split", shortcut: nil) { model.moveTabToOtherSide() },
        ]
        commands.append(PaletteCommand(name: "Filter List", shortcut: ShortcutStore.shared.label(for: .searchInList)) { model.focusSearch() })
        commands.append(PaletteCommand(name: "Keyboard Shortcuts", shortcut: ShortcutStore.shared.label(for: .keyboardShortcuts)) { model.isShowingShortcuts = true })
        commands.append(PaletteCommand(name: "Forget What Search Has Learned", shortcut: nil) { model.forgetSearchHistory() })
        commands.append(model.sidebarDensity == .compact
            ? PaletteCommand(name: "Use Comfortable Sidebar", shortcut: nil) { model.sidebarDensity = .comfortable }
            : PaletteCommand(name: "Use Compact Sidebar", shortcut: nil) { model.sidebarDensity = .compact })
        for (style, name) in [(VaultModel.BrowsingStyle.singleColumn, "Use One Column Sidebar"), (.twoColumns, "Use Two Column Sidebar")]
            where model.browsingStyle != style {
            commands.append(PaletteCommand(name: name, shortcut: nil) { model.browsingStyle = style })
        }
        if let note = model.selectedNote {
            commands += [
                PaletteCommand(name: "Move Note…", shortcut: nil) {
                    // After the palette running this has closed.
                    DispatchQueue.main.async { model.moveNoteInPalette() }
                },
                PaletteCommand(name: "Apply Template…", shortcut: ShortcutStore.shared.label(for: .applyTemplate)) {
                    // After the palette running this has closed.
                    DispatchQueue.main.async { model.applyTemplateInPalette() }
                },
                PaletteCommand(name: "Add Property…", shortcut: nil) { NotificationCenter.default.post(name: .pointAddProperty, object: model) },
                PaletteCommand(name: "Rename Note…", shortcut: nil) { model.renaming = note },
                PaletteCommand(name: "Add Tag…", shortcut: nil) { model.tagging = note },
                PaletteCommand(name: model.isBookmarked(note.id) ? "Remove Bookmark" : "Add Bookmark", shortcut: nil, learnedAs: "bookmark") { model.toggleBookmark(note.id) },
                PaletteCommand(name: "Show in Finder", shortcut: ShortcutStore.shared.label(for: .showInFinder)) { model.showInFinder(note) },
            ]
            if model.canMarkRead(note.id) {
                commands.append(PaletteCommand(name: model.isUnread(note.id) ? "Mark as Read" : "Mark as Unread",
                                               shortcut: ShortcutStore.shared.label(for: .toggleRead), learnedAs: "read") { model.toggleRead(note.id) })
            }
            if WebImageNotes.shared.canSave(note.id) {
                commands.append(PaletteCommand(name: "Save Web Images to Vault", shortcut: nil) { model.store.saveWebImages(in: note) })
            }
            commands += [
                PaletteCommand(name: "Move Note to Trash", shortcut: nil) { model.moveToTrash(note) },
                PaletteCommand(name: "Find in Note", shortcut: ShortcutStore.shared.label(for: .findInNote)) { FindInNote.show() },
            ]
        }
        commands.append(PaletteCommand(name: "Browse Folders", shortcut: ShortcutStore.shared.label(for: .searchVault), symbol: "folder") {
            DispatchQueue.main.async { model.togglePalette(.browse) }
        })
        if let note = model.selectedNote {
            // Each template, straight into the note.
            for template in model.templates {
                commands.append(PaletteCommand(name: "Apply Template “\(template.name)”", shortcut: nil) { model.applyTemplate(at: template.url) })
            }
            // Formatting, done to the note's selection, as the Format menu does.
            let formats: [(String, String?, Selector)] = [
                ("Bold", "⌘B", #selector(MarkdownTextView.toggleBold(_:))),
                ("Italic", "⌘I", #selector(MarkdownTextView.toggleItalic(_:))),
                ("Highlight", "⌘U", #selector(MarkdownTextView.toggleHighlight(_:))),
                ("Strikethrough", "⇧⌘X", #selector(MarkdownTextView.toggleStrikethrough(_:))),
                ("Inline Code", "⌥⌘C", #selector(MarkdownTextView.toggleCode(_:))),
                ("Block Quote", "⌘'", #selector(MarkdownTextView.toggleBlockQuote(_:))),
                ("Body Text", "⌘0", #selector(MarkdownTextView.makeBodyText(_:))),
                ("Heading 1", "⌘1", #selector(MarkdownTextView.makeHeading1(_:))),
                ("Heading 2", "⌘2", #selector(MarkdownTextView.makeHeading2(_:))),
                ("Heading 3", "⌘3", #selector(MarkdownTextView.makeHeading3(_:))),
                ("Heading 4", "⌘4", #selector(MarkdownTextView.makeHeading4(_:))),
                ("Heading 5", "⌘5", #selector(MarkdownTextView.makeHeading5(_:))),
                ("Heading 6", "⌘6", #selector(MarkdownTextView.makeHeading6(_:))),
                ("Bulleted List", "⌘L", #selector(MarkdownTextView.toggleBulletList(_:))),
                ("Numbered List", "⌥⌘L", #selector(MarkdownTextView.toggleNumberedList(_:))),
                ("Checklist", "⇧⌘L", #selector(MarkdownTextView.toggleChecklist(_:))),
                ("Indent", "⌥⌘→", #selector(MarkdownTextView.indentLines(_:))),
                ("Outdent", "⌥⌘←", #selector(MarkdownTextView.outdentLines(_:))),
                ("Move Line Up", "⌥⌘↑", #selector(MarkdownTextView.moveLinesUp(_:))),
                ("Move Line Down", "⌥⌘↓", #selector(MarkdownTextView.moveLinesDown(_:))),
                ("Fold", "⌥⌘[", #selector(MarkdownTextView.foldLine(_:))),
                ("Unfold", "⌥⌘]", #selector(MarkdownTextView.unfoldLine(_:))),
                ("Add Link…", "⌘K", #selector(MarkdownTextView.addLink(_:))),
                ("Insert Table", ShortcutStore.shared.label(for: .insertTable), #selector(MarkdownTextView.insertTable(_:))),
                ("Insert List", ShortcutStore.shared.label(for: .insertList), #selector(MarkdownTextView.insertListBlock(_:))),
            ]
            for (name, shortcut, action) in formats {
                commands.append(PaletteCommand(name: name, shortcut: shortcut) {
                    NotificationCenter.default.post(name: .pointEditorCommand, object: nil,
                                                    userInfo: ["noteID": note.id, "action": NSStringFromSelector(action)])
                })
            }
        }
        return commands
    }
}

/// The palette's text field. AppKit, so arrow keys, Return and Escape can drive the list
/// (SwiftUI on macOS 13 can't intercept them in a text field).
private struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 18
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// ⌘⌫: closes the highlighted tab, if it is one (returning true); otherwise the text
    /// field deletes to the start of the line as usual.
    var onCloseItem: (() -> Bool)?
    /// ← at the start of the text (or ⌫ with nothing typed), and → at its end: to go up a
    /// level while browsing, or into the place highlighted.
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    /// ⌘1 to ⌘4 while typing in it: narrows the palette (1 to 4), before the menus see them
    /// (⌘1 is also Heading 1).
    var onScope: ((Int) -> Void)?
    /// Whether ⌘1 to ⌘4 are taken only while it's being typed in: on a start page, where the
    /// other side's note keeps them (⌘1 is Heading 1). Over the window, it has them as it shows.
    var scopeKeysNeedFocus = false
    /// ⌘K or Tab: the highlighted result's actions (⌘K before the menus see it: it's also
    /// Add Link).
    var onActions: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = PaletteTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.delegate = context.coordinator
        context.coordinator.field = field
        context.coordinator.watchScopeKeys()
        return field
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopWatchingScopeKeys()
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField
        weak var field: NSTextField?
        private var monitor: Any?
        init(parent: PaletteField) { self.parent = parent }

        /// ⌘1 to ⌘4, taken while the field is being typed in, in the key window.
        func watchScopeKeys() {
            // On the main thread, as every local monitor is.
            nonisolated(unsafe) weak var coordinator = self
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                      let key = event.charactersIgnoringModifiers?.lowercased(), ["1", "2", "3", "4", "k"].contains(key)
                else { return event }
                let taken = MainActor.assumeIsolated { coordinator?.takeKey(key) ?? false }
                return taken ? nil : event
            }
        }

        /// ⌘1 to ⌘4 and ⌘K, while the palette shows (on a start page, while it's typed in).
        @MainActor private func takeKey(_ key: String) -> Bool {
            guard let field, field.window?.isKeyWindow == true,
                  !parent.scopeKeysNeedFocus || field.currentEditor() != nil else { return false }
            if key == "k" {
                guard let onActions = parent.onActions else { return false }
                onActions()
            } else {
                guard let onScope = parent.onScope, let number = Int(key) else { return false }
                onScope(number)
            }
            return true
        }

        func stopWatchingScopeKeys() {
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)) where parent.onActions != nil: parent.onActions?()
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            // ⌘Return reaches a text field as "noop:"; it opens the note in a new tab.
            case NSSelectorFromString("noop:") where NSApp.currentEvent?.keyCode == 36: parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            case #selector(NSResponder.deleteToBeginningOfLine(_:)) where NSApp.currentEvent?.modifierFlags.contains(.command) == true:
                return parent.onCloseItem?() ?? false
            case #selector(NSResponder.moveLeft(_:)) where parent.onLeft != nil && textView.selectedRange() == NSRange(location: 0, length: 0):
                parent.onLeft?()
            case #selector(NSResponder.deleteBackward(_:)) where parent.onLeft != nil && textView.string.isEmpty:
                parent.onLeft?()
            case #selector(NSResponder.moveRight(_:)) where parent.onRight != nil && textView.selectedRange() == NSRange(location: (textView.string as NSString).length, length: 0):
                parent.onRight?()
            default: return false
            }
            return true
        }
    }
}

/// What the palette is narrowed to, ⌘1 to ⌘4.
enum PaletteScope: Int, CaseIterable {
    case all = 1, notes, places, commands

    /// How it opens for a palette mode: Browse Folders to folders, Run Command to commands.
    init(mode: VaultModel.PaletteMode) {
        switch mode {
        case .browse: self = .places
        case .commands: self = .commands
        default: self = .all
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .notes: "Notes"
        case .places: "Folders"
        case .commands: "Commands"
        }
    }

    var symbol: String {
        switch self {
        case .all: "magnifyingglass"
        case .notes: "doc.text"
        case .places: "folder"
        case .commands: "command"
        }
    }
}

/// Under the field: what the palette can be narrowed to, the one it is marked, each a click
/// or its ⌘ number away.
struct PaletteScopeBar: View {
    let scope: PaletteScope
    let choose: (PaletteScope) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PaletteScope.allCases, id: \.self) { each in
                let isOn = each == scope
                Button { choose(each) } label: {
                    HStack(spacing: 5) {
                        Text(each.title)
                        Text("⌘\(each.rawValue)")
                            .foregroundStyle(isOn ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.7))
                    }
                    .font(.callout)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.15) : .clear))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            // What ⌘K does, so it's found.
            Text("Actions ⌘K")
                .font(.callout)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineLimit(1)
                .padding(.trailing, 6)
        }
    }
}

/// The palette's field: it takes the keyboard as it's put in its window (not a moment after
/// it's made, when it may not be in one yet, so typing and Escape would go nowhere).
final class PaletteTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
