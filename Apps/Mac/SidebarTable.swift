import AppKit
import EditorKit
import IndexKit
import SwiftUI
import VaultKit

/// One row of the sidebar: a section label, a divider, a folder or tag, or a note.
enum SidebarRow: Hashable {
    /// A section's label, which folds the section away or opens it again.
    case header(SidebarSection)
    case divider
    case place(SidebarPlace, depth: Int)
    case note(Note.ID)
    /// An image in the folder, by its path from the vault's root.
    case image(String)
    /// A note in the trash.
    case trashed(VaultTrash.Item)
    /// The switch between folders and tags, when they show one at a time.
    case treeSwitch
    /// A heading over notes by date ("Today", "October", "2025"), with the first note under it
    /// (so two headings with the same name, in an odd order, are still two rows).
    case dateGroup(String, first: Note.ID)
    /// How much is here ("12 notes"), first in the two-column note list.
    case count(String)
    /// What filters the two-column note list, as chips, while its filter tools are put away:
    /// under the count, scrolling with the notes. A click shows the tools.
    case filters([FilterSummaryItem])

    /// What a row opens in a tab, if it's a note's row (its ID) or an image's (its path).
    var noteID: Note.ID? {
        switch self {
        case .note(let id): id
        case .image(let path): path
        default: nil
        }
    }

    /// A folder, tag or note (in the trash too), rather than a label, divider or switch.
    var isItem: Bool {
        switch self {
        case .place, .note, .image, .trashed: true
        case .header, .divider, .treeSwitch, .dateGroup, .count, .filters: false
        }
    }
}

/// One thing filtering the note list, as its chip shows it ("Topics: Planning", "Unread").
struct FilterSummaryItem: Hashable {
    let label: String
    /// Leaving notes out ("Without read"): drawn quieter.
    let negated: Bool
}

/// The sidebar's sections, each of which can be folded away.
enum SidebarSection: Hashable {
    case pinned, folders, tags, types, properties, values, notes, images
    /// The note a property's value links to (a topic's own note), above the notes giving it.
    case linkedNote
    /// A property the sidebar lists, by name, with its values (in two columns).
    case property(String)

    /// Its label.
    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .folders: "Folders"
        case .tags: "Tags"
        case .types: "Types"
        case .properties: "Properties"
        case .values: "Values"
        case .notes: "Notes"
        case .images: "Images"
        case .linkedNote: "Linked note"
        case .property(let name): name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// How its folding is remembered: by its label (as always), a property's by its name.
    var key: String {
        if case .property(let name) = self { return "property:" + name.lowercased() }
        return title
    }

    static let fixed: [SidebarSection] = [.pinned, .folders, .tags, .types, .properties, .values, .notes, .images, .linkedNote]
}

extension VaultModel {
    /// The rows to show for the current place, in order. A folded section shows only its label.
    /// How an unfolded folder or tag is remembered: a folder by its path, a tag as `#tag`.
    static func expansionKey(_ place: SidebarPlace) -> String {
        switch place {
        case .folder(let path): path
        case .tag(let tag): "#" + tag
        case .allNotes, .everything, .bookmarks, .trash, .properties, .property, .propertyValue, .types, .kind, .tags, .lists, .recent: ""
        }
    }

    /// `expanded` holds the folders and tags unfolded to show the ones inside them. Narrowed by
    /// the filter field below the list: of what would show, only what's named with what's typed
    /// (not the two-column view's tree).
    func sidebarRows(collapsed: Set<SidebarSection>, expanded: Set<String> = [], content: SidebarTable.Content = .everything) -> [SidebarRow] {
        // The two-column view's tree is always the top level, wherever its notes are.
        let place = content == .places ? SidebarPlace.allNotes : place
        let filterText = content == .places ? FilterText("") { _ in false } : filterText
        let filtering = !filterText.isEmpty
        // Folders, tags and images by name, while the filter is plain words; terms are about
        // notes, so with any, only notes show.
        func shows(_ name: String) -> Bool { !filterText.hasTerms && filterText.matchesTitle(name) }
        let matches = filterMatches
        // Only the unread, if asked here or typed (`is:unread`), and the note open from the
        // list while it's open: marking it read doesn't whisk it away. (The button is two
        // columns only: one has nowhere to turn it off.)
        let unread: Bool? = filterText.unread ?? (content == .notes && showsOnlyUnread ? true : nil)
        // Read once, not for each note: each is a published property, slow to read thousands
        // of times.
        let selected = selection, looks = store.listLooks
        func shows(_ note: Note) -> Bool {
            guard filterText.matchesTitle(note.title) else { return false }
            if let matches, !matches.contains(note.id) { return false }
            guard let unread, note.id != selected else { return true }
            let look = looks[note.id]
            return unread ? look?.isUnread == true : look?.readProperty != nil && look?.isUnread != true
        }
        if content != .places, place == .trash { return trashedNotes.filter { shows($0.title) }.map { .trashed($0) } }
        let images = content == .places ? [] : store.images(in: place).filter { shows($0.name) }
        // In two columns, the notes column has only notes, except under Types and Properties:
        // the left column has no kinds, properties or values to show, so they're listed here,
        // above the notes.
        guard content != .notes || place.isProperty || place == .types else { return noteRows(notes(in: place).filter { shows($0) }) + images.map { .image($0.path) } }
        // Filtering, folded sections open, so what matches in them shows.
        let collapsed = filtering ? [] : collapsed
        var sections: [[SidebarRow]] = []
        func section(_ name: SidebarSection, _ rows: [SidebarRow]) -> [SidebarRow] {
            // A section with nothing left that matches goes, label and all.
            if filtering, rows.isEmpty { return [] }
            return [.header(name)] + (collapsed.contains(name) ? [] : rows)
        }
        func places(_ rows: [SidebarRow]) -> [SidebarRow] {
            rows.filter { row in
                guard case .place(let place, _) = row else { return true }
                return shows(self.title(for: place))
            }
        }
        // Folders, each followed by its subfolders if it's unfolded.
        func folderRows(_ places: [SidebarPlace], depth: Int) -> [SidebarRow] {
            places.flatMap { place -> [SidebarRow] in
                guard case .folder = place, expanded.contains(Self.expansionKey(place)) else { return [.place(place, depth: depth)] }
                return [.place(place, depth: depth)] + folderRows(self.subplaces(of: place), depth: depth + 1)
            }
        }
        let subplaces = subplaces(of: place)
        // Tags, nested ones beneath a tag that's unfolded, as subfolders are.
        func tagRows() -> [SidebarRow] {
            sortedTagEntries.filter { entry in
                let parts = entry.tag.split(separator: "/")
                return (1..<max(parts.count, 1)).allSatisfy { expanded.contains(Self.expansionKey(.tag(parts.prefix($0).joined(separator: "/")))) }
            }.map { .place(.tag($0.tag), depth: $0.depth) }
        }
        let twoColumns = content == .places
        let showsTags = store.showsTagsInSidebar && !tagTree.entries.isEmpty
        if place == .allNotes {
            // Special places first, with no heading: every note, bookmarks, and the trash; in
            // one column, Tags, Types and the properties chosen too, each opening its own list
            // (in two, they're sections of the tree, under folders). Then the switch between
            // folders and tags, if they show one at a time: below these, which it doesn't change.
            let oneAtATime = twoColumns && treeLayout == .toggle
            var special: [SidebarPlace] = [.everything] + (store.showsRecentInSidebar ? [.recent] : []) + (store.showsBookmarksInSidebar ? [.bookmarks] : [])
            // The types chosen in Settings, then every list, under Bookmarks.
            special += store.shownSidebarKinds.map { .kind(store.kinds.property, $0.name) }
            if store.showsListsInSidebar, !store.listNoteIDs.isEmpty { special.append(.lists) }
            // The templates and attachments folders, as places of their own (not in the tree).
            special += store.shownSpecialFolders.map { .folder($0.path) }
            // Tags open their own list in one column (in two, they're under folders). Types
            // are only those chosen, above; properties are managed in Settings, not here.
            if !twoColumns, showsTags { special.append(.tags) }
            special.append(.trash)
            sections.append(places(special.map { .place($0, depth: 0) })
                            + (oneAtATime && !filtering ? [.treeSwitch] : []))
            if !pins.isEmpty { sections.append(section(.pinned, places(pins.map { .place($0, depth: 0) }))) }
            // Shown one at a time, folders or tags have no label of their own, and can't be
            // folded away: the switch names them, and folding the only one would leave nothing.
            // Straight below the switch (no pins between), they go on from it with no divider.
            func addTree(_ name: SidebarSection, _ rows: [SidebarRow]) {
                if !oneAtATime {
                    sections.append(section(name, rows))
                } else if pins.isEmpty {
                    sections[0] += rows
                } else {
                    sections.append(rows)
                }
            }
            if !oneAtATime || treeKind == .folders {
                // The tree starts with the vault itself, for the notes at its top level.
                let top: [SidebarRow] = content == .places ? [.place(.allNotes, depth: 0)] : []
                if !subplaces.isEmpty || !top.isEmpty { addTree(.folders, places(top + folderRows(subplaces, depth: 0))) }
            }
            if twoColumns, showsTags, !oneAtATime || treeKind == .tags {
                addTree(.tags, places(tagRows()))
            }
        } else if place == .tags {
            sections.append(section(.tags, places(tagRows())))
        } else if !subplaces.isEmpty {
            // Inside a folder (or tag) with folders (or tags) in it: labelled, as at the top.
            let rows = place.unfolds && !place.isTag ? folderRows(subplaces, depth: 0) : subplaces.map { SidebarRow.place($0, depth: 0) }
            let label: SidebarSection = switch place {
            case .tag: .tags
            case .properties: .properties
            case .property(let name): .property(name)
            case .types: .types
            default: .folders
            }
            sections.append(section(label, places(rows)))
        }
        // A value that links to a note (a topic, say): that note, to open it, above those
        // giving the value.
        if case .propertyValue(_, let value) = place, let linked = store.linkedNote(ofValue: value), shows(linked.title) {
            sections.append(section(.linkedNote, [.note(linked.id)]))
        }
        // The notes, always under their label, which holds the sort menu.
        let notes = content == .places ? [] : notes(in: place).filter { shows($0) }
        if !notes.isEmpty {
            sections.append(section(.notes, noteRows(notes)))
        }
        // A folder's images, after its notes.
        if !images.isEmpty {
            sections.append(section(.images, images.map { .image($0.path) }))
        }
        // Thin dividers between sections.
        return sections.filter { !$0.isEmpty }.enumerated().flatMap { index, rows in index == 0 ? rows : [.divider] + rows }
    }

    /// Notes' rows: under headings by date, when the list shows dates that way and is sorted
    /// by a date.
    func noteRows(_ notes: [Note]) -> [SidebarRow] {
        // Recent keeps the order they were opened in, newest first, without dates.
        guard listDateStyle == .groups, sort != .title, place != .recent else { return notes.map { .note($0.id) } }
        return NoteDateGroup.grouped(notes, by: sort).flatMap { group in
            [SidebarRow.dateGroup(group.label, first: group.notes[0].id)] + group.notes.map { .note($0.id) }
        }
    }
}

/// The sidebar's list of folders, tags and notes: an AppKit table, so every row has its exact
/// height before it's drawn, and moving between folders can slide.
struct SidebarTable: NSViewRepresentable {
    @ObservedObject var model: VaultModel
    /// What it lists: everything (one column), or in two columns the notes, or the folders
    /// and tags beside them.
    enum Content { case everything, notes, places }
    var content = Content.everything
    /// Room at the foot, for the filter field floating over the list.
    var bottomInset: CGFloat = 0
    /// Room at the top below the column's top bar, for the filter controls (and the chips of
    /// what's filtering) pinned there; the list scrolls up beneath them, blurred with the bar.
    var topInset: CGFloat = 0
    /// Told whether the list has any notes, folders or tags in it (not only labels), when that
    /// changes: for "No matches", without working out the rows again.
    var onHasItems: ((Bool) -> Void)?
    /// Told how many notes the list shows, when that changes: for the count in the column's
    /// top bar, which says how many the filter leaves.
    var onNoteCount: ((Int) -> Void)?
    /// What filters the list (its terms, then what's typed). The filter isn't published by the
    /// model (see `FilterToolsState`), so it's handed in: a change updates the table.
    var filter: [String] = []
    /// The folded sections, comma separated, each as the place it's folded in and its name
    /// (`folder:Projects|Notes`): folding a section in one place leaves it open in others. A
    /// name alone (as saved before) is one folded at the top level.
    @AppStorage("collapsedSidebarSections") var collapsedSections = UserDefaults.standard.object(forKey: "tagsSectionExpanded") as? Bool == false ? "Tags" : ""

    private var collapsedEntries: [String] { collapsedSections.split(separator: ",").map(String.init) }

    private static func entry(_ section: SidebarSection, in place: SidebarPlace) -> String {
        place.key + "|" + section.key
    }

    /// Where the sidebar is: the top level, always, for the two-column view's tree.
    private var shownPlace: SidebarPlace { content == .places ? .allNotes : model.place }

    /// The sections folded where the sidebar is now.
    var collapsed: Set<SidebarSection> {
        let entries = Set(collapsedEntries)
        let place = shownPlace
        return Set((SidebarSection.fixed + model.store.sidebarProperties.map { .property($0) }).filter { section in
            entries.contains(Self.entry(section, in: place)) || (place == .allNotes && entries.contains(section.key))
        })
    }

    /// Folders unfolded to show their subfolders, by path, one per line.
    @AppStorage("expandedSidebarFolders") var expandedFolders = ""

    var expanded: Set<String> { Set(expandedFolders.split(separator: "\n").map(String.init)) }

    func toggleExpanded(_ path: String) {
        var folders = expanded
        if folders.remove(path) == nil { folders.insert(path) }
        expandedFolders = folders.sorted().joined(separator: "\n")
    }

    /// Folds a section where the sidebar is now, or opens it again.
    func toggle(_ section: SidebarSection) {
        let place = shownPlace
        let entry = Self.entry(section, in: place)
        let wasCollapsed = collapsed.contains(section)
        // Drops this section's entries here, including the old form at the top level.
        var entries = collapsedEntries.filter { $0 != entry && !(place == .allNotes && $0 == section.key) }
        if !wasCollapsed { entries.append(entry) }
        collapsedSections = entries.joined(separator: ",")
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = SidebarTableView()
        table.emphasizesOnlyWithKeyboard = content == .places
        table.headerView = nil
        table.style = .sourceList
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAutomaticRowHeights = false
        table.allowsEmptySelection = true
        table.addTableColumn(NSTableColumn(identifier: .init("main")))
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        // The two-column note list scrolls up beneath its see-through top bar, as a note does,
        // and the lists with a filter field down beneath that, softly blurred.
        let scrollView = BarEdgeScrollView()
        // On the sidebar's material, the blur alone; on the page's colour, washed with it.
        scrollView.footWash = content == .notes ? .textBackgroundColor : nil
        // The tree scrolls up under the window buttons too, softly blurred.
        scrollView.softTop = content == .places
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = insets
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        context.coordinator.table = table
        table.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.widthChanged() }
        context.coordinator.update(animated: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.setInsets(insets, on: scrollView)
        context.coordinator.parent = self
        context.coordinator.update(animated: true)
    }

    private var insets: NSEdgeInsets {
        NSEdgeInsets(top: (content == .everything ? 0 : model.topBarHeight) + topInset, left: 0, bottom: bottomInset, right: 0)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: SidebarTable
        weak var table: NSTableView?
        private var rows: [SidebarRow] = []
        private var shownPlace: SidebarPlace?
        private var isSyncingSelection = false
        /// The rows' heights, measured all at once whenever the rows or what their heights come
        /// from change, before the table is told: it asks for each row's from here (thousands of
        /// times on a reload), and rows whose height changed are spotted against them.
        private var shownHeights: [CGFloat] = []

        /// The count's row: a line of small type, a little room above it and below.
        static let countHeight: CGFloat = 26

        static func noteHeight(hasTags: Bool, density: VaultModel.SidebarDensity) -> CGFloat {
            hasTags ? density.twoLineHeight : density.rowHeight
        }

        /// In the sidebar's list of notes (one column or two), comfortable, a note's whole
        /// title shows, on as many lines as it takes, its row growing to fit.
        private var wrapsTitles: Bool { parent.content != .places && model.sidebarDensity == .comfortable }

        /// The table's width when its rows' heights were last worked out.
        private var measuredWidth: CGFloat = 0
        /// How much more than one line each title takes, wrapped to a width: measured once,
        /// not again at every update (each switch of tab, say).
        private var titleExtras: [TitleMeasure: CGFloat] = [:]
        private struct TitleMeasure: Hashable { let title: String; let width: CGFloat }


        /// Titles wrap to the column's width, so a new width can change rows' heights.
        func widthChanged() {
            guard let table, wrapsTitles, abs(table.bounds.width - measuredWidth) > 0.5 else { return }
            let notes = IndexSet(rows.indices.filter { if case .note = rows[$0] { true } else { false } })
            shownHeights = measuredHeights(in: table)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                table.noteHeightOfRows(withIndexesChanged: notes)
            }
            // Their titles are broken to the new width too.
            table.reloadData(forRowIndexes: notes, columnIndexes: [0])
        }

        init(_ parent: SidebarTable) { self.parent = parent }

        var model: VaultModel { parent.model }

        /// Rebuilds the rows. Moving to another place slides the list: in from the right when
        /// going deeper, from the left when going back up.
        func update(animated: Bool) {
            guard let table else { return }
            watchFocus(in: table.window)
            today = Calendar.current.startOfDay(for: Date())
            // Read once (each is worked out from a saved string), for the rows and their cells.
            let cellInputs = CellInputs(collapsed: parent.collapsed, expanded: parent.expanded)
            let cellsChanged = cellInputs != shownCellInputs
            shownCellInputs = cellInputs
            var newRows = model.sidebarRows(collapsed: cellInputs.collapsed, expanded: cellInputs.expanded, content: parent.content)
            // In two columns, how many notes show is in the column's top bar, under its name.
            if parent.content == .notes {
                let count = newRows.count { if case .note = $0 { true } else if case .trashed = $0 { true } else { false } }
                if count != shownNoteCount {
                    shownNoteCount = count
                    let report = parent.onNoteCount
                    DispatchQueue.main.async { report?(count) }
                }
            }
            let hasItems = newRows.contains(where: \.isItem)
            if hasItems != shownHasItems {
                shownHasItems = hasItems
                // After this update: it changes the view that's being updated.
                let report = parent.onHasItems
                DispatchQueue.main.async { report?(hasItems) }
            }
            // And what filters them, while the filter tools are away.
            if parent.content == .notes, case let items = model.filterSummary, !items.isEmpty { newRows.insert(.filters(items), at: 0) }
            // The tree doesn't move with the place it shows.
            let place = parent.content == .places ? SidebarPlace.allNotes : model.place
            let placeChanged = shownPlace != nil && shownPlace != place
            // What the rows' heights come from: if none of it has changed, nor have they.
            let heightInputs = heightInputs(for: table)
            defer { shownHeightInputs = heightInputs }
            if !placeChanged, newRows == rows, heightInputs == shownHeightInputs {
                // Same rows, made from the same notes: only the selection, or how sections and
                // folders are folded, can have changed. Each row watches the model, so it
                // redraws itself for anything else; made again, only if what it's handed changed
                // (a filter keystroke that leaves the list as it was costs nothing here).
                let wasSelected = table.selectedRow
                shownPlace = place
                syncSelection()
                let visible = table.rows(in: table.visibleRect).toIndexSet
                if cellsChanged {
                    table.reloadData(forRowIndexes: visible, columnIndexes: [0])
                } else if table.selectedRow != wasSelected {
                    // The rows coming on and off the highlight.
                    let both = IndexSet([wasSelected, table.selectedRow].filter { $0 >= 0 }).intersection(visible)
                    if !both.isEmpty { table.reloadData(forRowIndexes: both, columnIndexes: [0]) }
                }
                return
            }
            if !placeChanged, heightInputs == shownHeightInputs, newRows != rows,
               let changedFilters = Self.filtersRowChange(from: rows, to: newRows) {
                // Only the chips' row came, went or changed (the filter tools put away or
                // shown): that row alone, not the whole list again.
                rows = newRows
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    switch changedFilters {
                    case .inserted(let index):
                        shownHeights.insert(measuredHeight(ofRow: index, in: table, heightContext(for: table), secondLines: secondLines()), at: index)
                        table.insertRows(at: [index], withAnimation: [])
                    case .removed(let index):
                        shownHeights.remove(at: index)
                        table.removeRows(at: [index], withAnimation: [])
                    case .changed(let index):
                        shownHeights[index] = measuredHeight(ofRow: index, in: table, heightContext(for: table), secondLines: secondLines())
                        table.reloadData(forRowIndexes: [index], columnIndexes: [0])
                        table.noteHeightOfRows(withIndexesChanged: [index])
                    }
                }
                shownPlace = place
                syncSelection()
                return
            }
            if !placeChanged, newRows == rows {
                // Same rows: refresh their contents, and let any that gained or lost a tags
                // line grow or shrink smoothly rather than jump.
                let heights = measuredHeights(in: table)
                let changed = IndexSet(heights.indices.filter { heights[$0] != shownHeights[safe: $0] })
                shownHeights = heights
                table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: [0])
                if !changed.isEmpty {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animated ? 0.25 : 0
                        context.allowsImplicitAnimation = true
                        table.noteHeightOfRows(withIndexesChanged: changed)
                    }
                }
                shownPlace = place
                syncSelection()
                return
            }
            do {
                // Slide only when moving in or out of a level, not when picking from a tree.
                if animated, placeChanged, parent.content == .everything, let layer = table.enclosingScrollView?.layer {
                    let transition = CATransition()
                    transition.type = .push
                    transition.subtype = Self.isDeeper(place, than: shownPlace!) ? .fromRight : .fromLeft
                    transition.duration = 0.22
                    transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    layer.add(transition, forKey: "slide")
                }
                rows = newRows
                // Measured once, before the table asks for each.
                shownHeights = measuredHeights(in: table)
                table.reloadData()
                if placeChanged { table.scrollRowToVisible(0) }
            }
            shownPlace = place
            syncSelection()
        }

        enum FiltersRowChange { case inserted(Int), removed(Int), changed(Int) }

        /// How the rows differ, if only in the chips' row (which is near the top, so the rest
        /// is compared from there).
        static func filtersRowChange(from old: [SidebarRow], to new: [SidebarRow]) -> FiltersRowChange? {
            func filtersIndex(_ rows: [SidebarRow]) -> Int? {
                rows.prefix(3).firstIndex { if case .filters = $0 { true } else { false } }
            }
            switch (filtersIndex(old), filtersIndex(new)) {
            case (nil, let index?) where old.count + 1 == new.count:
                return old[..<index] == new[..<index] && old[index...] == new[(index + 1)...] ? .inserted(index) : nil
            case (let index?, nil) where old.count == new.count + 1:
                return old[..<index] == new[..<index] && old[(index + 1)...] == new[index...] ? .removed(index) : nil
            case (let a?, let b?) where a == b && old.count == new.count:
                return old[..<a] == new[..<a] && old[(a + 1)...] == new[(a + 1)...] ? .changed(a) : nil
            default:
                return nil
            }
        }

        static func isDeeper(_ place: SidebarPlace, than old: SidebarPlace) -> Bool {
            func depth(_ place: SidebarPlace) -> Int {
                switch place {
                case .allNotes: 0
                case .everything, .bookmarks, .trash, .properties, .types, .tags, .lists, .recent: 1
                case .property, .kind: 2
                case .propertyValue: 3
                case .folder(let path), .tag(let path): path.split(separator: "/").count
                }
            }
            return depth(place) > depth(old)
        }

        /// Whether the place shown was picked from Pinned rather than the tree below. A pinned
        /// place is in both; this says which copy to highlight, so only one ever is.
        private var pickedFromPins = false

        /// The section a row is in (nil for the top rows, which have no label).
        /// The labelled section a row is in (nil for one with no label: the special places at
        /// the top, and folders or tags shown one at a time).
        private func section(ofRow row: Int) -> SidebarSection? {
            for index in stride(from: row, through: 0, by: -1) {
                if case .header(let section) = rows[index] { return section }
                if case .divider = rows[index] { return nil }
            }
            return nil
        }

        /// The tree's row for the place shown.
        private var placeRow: Int? {
            let matches = rows.indices.filter { index in
                if case .place(let place, _) = rows[index] { return place == model.place }
                return false
            }
            let pinned = matches.filter { section(ofRow: $0) == .pinned }
            let tree = matches.filter { section(ofRow: $0) != .pinned }
            return pickedFromPins ? (pinned.first ?? tree.first) : (tree.first ?? pinned.first)
        }

        private func syncSelection() {
            guard let table else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if parent.content == .places {
                if let row = placeRow {
                    if table.selectedRow != row { table.selectRowIndexes([row], byExtendingSelection: false) }
                } else if table.selectedRow >= 0 {
                    table.deselectAll(nil)
                }
                return
            }
            if let id = model.selection, let row = rows.firstIndex(of: .note(id)) {
                if table.selectedRow != row { table.selectRowIndexes([row], byExtendingSelection: false) }
            } else if table.selectedRow >= 0 {
                table.deselectAll(nil)
            }
        }

        // MARK: Data

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        /// The rows' heights, as measured for the rows now shown (see `shownHeights`).
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            shownHeights[safe: row] ?? measuredHeight(ofRow: row, in: tableView, heightContext(for: tableView), secondLines: secondLines())
        }

        /// Whether a note has a line under its title (its kind's detail, or tags), as
        /// `VaultModel.listSecondLine` would give, without making the line: what it comes from
        /// read once for all the rows.
        private func secondLines() -> (Note.ID) -> Bool {
            // (Each a published property, slow to read: read once, not for each row.)
            let looks = model.store.listLooks, showsTags = model.showsTagsInList
            let tags = showsTags ? model.store.tagsByNote : [:], indexed = showsTags ? model.store.indexedTags : [:]
            return { id in
                if let detail = looks[id]?.detail, detail.count > 1 || detail.first?.isEmpty == false { return true }
                // As `VaultStore.listTags(for:)` finds them.
                return showsTags && !(tags[id] ?? indexed[id] ?? []).isEmpty
            }
        }

        /// What every note row's height depends on besides the note: read from the model once
        /// for all the rows, not again for each of thousands.
        private struct HeightContext: Equatable {
            let width: CGFloat
            let wraps: Bool
            let density: VaultModel.SidebarDensity
            let dateStyle: VaultModel.ListDateStyle
            let sort: NoteSort
            let listDate: VaultModel.ListDate
            /// Dates show differently from one day to the next (a time today, a weekday after).
            let day: Date
        }

        private func heightContext(for tableView: NSTableView) -> HeightContext {
            HeightContext(width: tableView.bounds.width, wraps: wrapsTitles, density: model.sidebarDensity, dateStyle: model.listDateStyle,
                          sort: model.sort, listDate: model.listDate, day: today)
        }

        private func heightInputs(for tableView: NSTableView) -> HeightInputs {
            HeightInputs(version: model.store.listVersion, width: tableView.bounds.width, wraps: wrapsTitles,
                         density: model.sidebarDensity, dateStyle: model.listDateStyle, sort: model.sort,
                         listDate: model.listDate, showsTags: model.showsTagsInList, day: today)
        }

        /// Every row's height, for the rows as they are now. A note's is looked up, while
        /// nothing it comes from has changed: thousands come back at once when a filter is
        /// cleared, and each would otherwise be worked out again.
        private func measuredHeights(in tableView: NSTableView) -> [CGFloat] {
            let inputs = heightInputs(for: tableView)
            if inputs != noteHeightsInputs { noteHeights = [:]; noteHeights.reserveCapacity(rows.count); noteHeightsInputs = inputs }
            let context = heightContext(for: tableView), secondLines = secondLines()
            return rows.indices.map { row in
                guard case .note(let id) = rows[row] else { return measuredHeight(ofRow: row, in: tableView, context, secondLines: secondLines) }
                if let known = noteHeights[id] { return known }
                let height = measuredHeight(ofRow: row, in: tableView, context, secondLines: secondLines)
                noteHeights[id] = height
                return height
            }
        }

        /// Each note's row height, for `noteHeightsInputs`.
        private var noteHeights: [Note.ID: CGFloat] = [:]
        private var noteHeightsInputs: HeightInputs?

        private func measuredHeight(ofRow row: Int, in tableView: NSTableView, _ context: HeightContext,
                                    secondLines hasSecondLine: (Note.ID) -> Bool) -> CGFloat {
            let density = context.density
            switch rows[row] {
            case .dateGroup: return density.headerHeight + (dividesAbove(row) ? Self.groupLineRoom : 0)
            case .header: return density.headerHeight
            case .divider: return density.dividerHeight
            case .place, .trashed, .image: return density.rowHeight
            case .treeSwitch: return density.rowHeight + 18
            case .count: return Self.countHeight
            case .filters(let items): return filtersHeight(items, width: tableView.bounds.width - SidebarTableView.rowInset * 2)
            case .note(let id):
                // Two lines only for a note that has something under its title: its kind's
                // detail, or tags.
                let hasTags = hasSecondLine(id)
                guard let note = model.note(id) else { return Self.noteHeight(hasTags: hasTags, density: density) }
                let key = RowHeight(title: note.title, modified: note.modified, created: note.created, isDownloaded: note.isDownloaded,
                                    hasTags: hasTags, context: context)
                if let known = rowHeights[id], known.key == key { return known.height }
                let height = Self.noteHeight(hasTags: hasTags, density: density) + (context.wraps ? extraTitleHeight(note, in: tableView) : 0)
                rowHeights[id] = (key, height)
                return height
            }
        }

        /// The chips' row: as tall as they wrap to at this width, measured once for each.
        private func filtersHeight(_ items: [FilterSummaryItem], width: CGFloat) -> CGFloat {
            let key = FiltersMeasure(items: items, width: width.rounded())
            if let known = filtersHeights[key] { return known }
            let measure = NSHostingController(rootView: FilterSummaryView(items: items))
            let height = ceil(measure.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            filtersHeights[key] = height
            return height
        }

        private struct FiltersMeasure: Hashable { let items: [FilterSummaryItem]; let width: CGFloat }
        private var filtersHeights: [FiltersMeasure: CGFloat] = [:]
        private var shownHasItems: Bool?
        private var shownNoteCount: Int?

        // MARK: Insets

        private var targetInsets: NSEdgeInsets?
        private var insetLink: CADisplayLink?
        private var insetStart = NSEdgeInsets(), insetBegan: CFTimeInterval = 0
        private weak var insetScrollView: NSScrollView?
        #if DEBUG
        private var insetFrames: [CFTimeInterval] = []
        #endif

        /// Sets the scroll view's insets. A change at the top of the note list (its filter tools
        /// sliding down or up, a line of chips coming or going) moves the notes with it, on the
        /// tools' curve and time, rather than jumping: an inset isn't animatable by AppKit or
        /// SwiftUI, so it's stepped each frame.
        func setInsets(_ target: NSEdgeInsets, on scrollView: NSScrollView) {
            guard !NSEdgeInsetsEqual(targetInsets ?? scrollView.contentInsets, target) else { return }
            targetInsets = target
            let current = scrollView.contentInsets
            guard parent.content == .notes, scrollView.window != nil, current.bottom == target.bottom,
                  abs(current.top - target.top) > 0.5 else {
                insetLink?.invalidate()
                insetLink = nil
                scrollView.contentInsets = target
                return
            }
            insetStart = current
            insetBegan = CACurrentMediaTime()
            #if DEBUG
            insetFrames = []
            #endif
            insetScrollView = scrollView
            if insetLink == nil {
                let link = scrollView.displayLink(target: self, selector: #selector(stepInsets(_:)))
                link.add(to: .main, forMode: .common)
                insetLink = link
            }
        }

        @objc private func stepInsets(_ link: CADisplayLink) {
            guard let scrollView = insetScrollView, let target = targetInsets else {
                link.invalidate()
                insetLink = nil
                return
            }
            let t = min(1, (CACurrentMediaTime() - insetBegan) / VaultModel.filterToolsDuration)
            // Ease in and out, as SwiftUI's `.easeInOut` does the tools.
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            var insets = target
            insets.top = insetStart.top + (target.top - insetStart.top) * eased
            scrollView.contentInsets = insets
            #if DEBUG
            insetFrames.append(CACurrentMediaTime())
            #endif
            if t >= 1 {
                link.invalidate()
                insetLink = nil
                #if DEBUG
                let gaps = zip(insetFrames.dropFirst(), insetFrames).map { ($0 - $1) * 1000 }
                Trace.mark("inset slide: \(insetFrames.count) frames, longest gap \(String(format: "%.1f", gaps.max() ?? 0)) ms")
                #endif
            }
        }

        /// Each note's row height, and what it was worked out from: worked out again only
        /// when one of those changes, not for every row at every update (each switch of tab).
        private var rowHeights: [Note.ID: (key: RowHeight, height: CGFloat)] = [:]
        /// What a note's row's height comes from: of the note, what the row shows (its title,
        /// its date, whether it's here or in iCloud), not the whole note (comparing its URL, for
        /// each of thousands of rows, was slow).
        private struct RowHeight: Equatable {
            let title: String
            let modified: Date
            let created: Date
            let isDownloaded: Bool
            let hasTags: Bool
            let context: HeightContext
        }
        private struct HeightInputs: Equatable {
            let version: Int
            let width: CGFloat
            let wraps: Bool
            let density: VaultModel.SidebarDensity
            let dateStyle: VaultModel.ListDateStyle
            let sort: NoteSort
            let listDate: VaultModel.ListDate
            let showsTags: Bool
            let day: Date
        }
        private var shownHeightInputs: HeightInputs?
        /// What a row's view is handed by the table, beyond its row and the model it watches
        /// (which redraws it by itself): if none of it has changed, the rows needn't be made again.
        private struct CellInputs: Equatable {
            let collapsed: Set<SidebarSection>
            let expanded: Set<String>
        }
        private var shownCellInputs: CellInputs?
        /// The start of today, looked up once an update rather than for every row.
        private var today = Calendar.current.startOfDay(for: Date())

        /// How much more than one line a note's title takes, wrapped.
        private func extraTitleHeight(_ note: Note, in tableView: NSTableView) -> CGFloat {
            guard wrapsTitles else { return 0 }
            measuredWidth = tableView.bounds.width
            let width = SidebarNoteRow.titleWidth(of: note, model: model, rowWidth: tableView.bounds.width - SidebarTableView.rowInset * 2)
            let measure = TitleMeasure(title: note.title, width: width)
            if let extra = titleExtras[measure] { return extra }
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let height = (note.title as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                               options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                               attributes: [.font: font]).height
            let line = font.ascender - font.descender + font.leading
            // Each line after the first, with the room the row puts between wrapped lines.
            let lines = max(1, (height / line).rounded())
            let extra = ceil((lines - 1) * (line + SidebarNoteRow.wrappedLineSpacing))
            titleExtras[measure] = extra
            return extra
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            if parent.content == .places {
                // A folder or tag, unless the click is on its unfold arrow.
                guard case .place(let place, let depth) = rows[row] else { return false }
                return !(hasArrow(place) && NSApp.currentEvent?.type == .leftMouseDown && clickedArrow(row: row, place: place, depth: depth, in: tableView))
            }
            guard let id = rows[row].noteID else { return false }
            // ⌥⌘-click opens the note beside this one; ⌘-click opens it in a new tab.
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .shift, .control]) ?? []
            if modifiers == [.command, .option] {
                model.openToTheSide(id)
                return false
            }
            if modifiers.contains(.command) {
                model.newTab(noteID: id)
                return false
            }
            return true
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SidebarTableRowView() }

        // MARK: Emphasis

        private var focusObservation: NSKeyValueObservation?
        private var keyObservers: [NSObjectProtocol] = []

        /// Watches where the keyboard is and whether the window is in front, which decide
        /// whether the selection is blue.
        func watchFocus(in window: NSWindow?) {
            guard let window, focusObservation == nil else { return }
            focusObservation = window.observe(\.firstResponder) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refreshEmphasis() }
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshEmphasis() }
                })
            }
        }

        private func refreshEmphasis() {
            table?.enumerateAvailableRowViews { rowView, _ in (rowView as? SidebarTableRowView)?.refreshEmphasis() }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("row")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? HostingCell ?? HostingCell()
            cell.identifier = identifier
            let inputs = shownCellInputs ?? CellInputs(collapsed: parent.collapsed, expanded: parent.expanded)
            cell.show(SidebarRowView(row: rows[row], model: model, collapsed: inputs.collapsed, expanded: inputs.expanded,
                                     wrapsTitles: wrapsTitles, rowWidth: tableView.bounds.width - SidebarTableView.rowInset * 2,
                                     dividesAbove: dividesAbove(row)))
            return cell
        }

        /// Whether a date's label has a line above it, to part its notes from the group before:
        /// only after another group's notes, not at the top of the list or under a label.
        private func dividesAbove(_ row: Int) -> Bool {
            guard case .dateGroup = rows[row], row > 0, case .note = rows[row - 1] else { return false }
            return true
        }

        /// The room above a date's label taken by its line.
        static let groupLineRoom: CGFloat = 8

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table, table.selectedRow >= 0 else { return }
            if case .place(let place, _) = rows[table.selectedRow], parent.content == .places {
                pickedFromPins = section(ofRow: table.selectedRow) == .pinned
                model.browse(place)
                return
            }
            guard let id = rows[table.selectedRow].noteID else { return }
            model.selectFromList(id)
        }

        /// Whether a folder or tag unfolds from an arrow after its name (the vault itself, at
        /// the top of the tree, doesn't: its folders are the tree).
        private func hasArrow(_ place: SidebarPlace) -> Bool {
            place != .allNotes && !model.subplaces(of: place).isEmpty
        }

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row) else { return }
            switch rows[row] {
            case .place(let place, let depth) where hasArrow(place)
                && clickedArrow(row: row, place: place, depth: depth, in: sender):
                parent.toggleExpanded(VaultModel.expansionKey(place))
            case .place(let place, _):
                // The tree browses as its selection changes (by click or arrow key).
                if parent.content != .places { model.browse(place) }
            case .filters:
                model.setFilterTools(shown: true)
            case .treeSwitch:
                // Its left half is Folders, its right half Tags.
                guard let event = NSApp.currentEvent, let cell = sender.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
                model.treeKind = cell.convert(event.locationInWindow, from: nil).x < cell.bounds.midX ? .folders : .tags
            case .header(let section):
                // The sort label at the section's right edge opens its menu; the rest of the
                // row folds the section. (It's drawn in a view that takes no clicks, so the
                // table sees them all.)
                if let menu = sortMenu(for: section), clickedSortLabel(row: row, section: section, in: sender) {
                    let point = sender.convert(NSApp.currentEvent?.locationInWindow ?? .zero, from: nil)
                    menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: sender.rect(ofRow: row).maxY), in: sender)
                } else {
                    parent.toggle(section)
                }
            default: break
            }
        }

        /// Whether the click was on a section's sort label, at the right end of its row.
        private func clickedSortLabel(row: Int, section: SidebarSection, in table: NSTableView) -> Bool {
            guard let event = NSApp.currentEvent, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false),
                  let label = model.sortLabel(for: section) else { return false }
            let x = cell.convert(event.locationInWindow, from: nil).x
            return x >= cell.bounds.width - SidebarRowView.sortLabelWidth(label) - 12
        }

        /// How a section is sorted: notes by date edited, date created or title; folders and tags
        /// by name or date modified.
        private func sortMenu(for section: SidebarSection) -> NSMenu? {
            let menu = NSMenu()
            switch section {
            case .notes:
                for (title, sort) in [("Date Edited", NoteSort.modified), ("Date Created", .created), ("Title", .title)] {
                    let entry = item(title) { $0.sort = sort }
                    entry.state = model.sort == sort ? .on : .off
                    menu.addItem(entry)
                }
            case .folders, .tags:
                for (title, order) in [("Name", VaultModel.TagOrder.name), ("Date Modified", .modified)] {
                    let entry = item(title) { $0.tagOrder = order }
                    entry.state = model.tagOrder == order ? .on : .off
                    menu.addItem(entry)
                }
            case .pinned, .types, .properties, .values, .images, .linkedNote, .property:
                return nil
            }
            return menu
        }

        /// Whether the click was on a folder's or tag's unfold arrow, after its name. Measured
        /// in the row's cell, which the source list style insets from the row.
        private func clickedArrow(row: Int, place: SidebarPlace, depth: Int, in table: NSTableView) -> Bool {
            guard let event = NSApp.currentEvent, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) else { return false }
            let x = cell.convert(event.locationInWindow, from: nil).x
            let start = SidebarRowView.arrowStart(of: place, depth: depth, rowWidth: cell.bounds.width)
            return x >= start - 6 && x <= start + SidebarRowView.arrowWidth + 6
        }

        // MARK: Dragging notes onto folders

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            switch rows[row] {
            case .note(let id): return id as NSString
            case .place(.folder(let path), _): return (VaultModel.folderDragPrefix + path) as NSString
            default: return nil
            }
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            // Only rows dragged within Point: text dragged in from another app isn't a note or
            // folder to move, even if it reads like one.
            guard operation == .on, rows.indices.contains(row), info.draggingSource != nil else { return [] }
            switch rows[row] {
            case .place(.folder, _), .place(.allNotes, _): return .move
            // The heading over the folders: the top level.
            case .header(.folders) where model.place == .allNotes || parent.content == .places: return .move
            default: return []
            }
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard info.draggingSource != nil, let dragged = info.draggingPasteboard.string(forType: .string) else { return false }
            switch rows[row] {
            case .place(.folder(let path), _): model.drop(dragged, onFolder: path)
            case .place(.allNotes, _), .header(.folders): model.drop(dragged, onFolder: "")
            default: return false
            }
            return true
        }

        // MARK: Right-click menus

        /// How folders and tags are sorted: by name or date modified.
        private func addTreeSortItems(to menu: NSMenu) {
            let byName = item("Sort Folders and Tags by Name") { $0.tagOrder = .name }
            byName.state = model.tagOrder == .name ? .on : .off
            let byDate = item("Sort Folders and Tags by Date Modified") { $0.tagOrder = .modified }
            byDate.state = model.tagOrder == .modified ? .on : .off
            menu.addItem(byName)
            menu.addItem(byDate)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            switch rows[table.clickedRow] {
            case .trashed(let trashed):
                menu.addItem(item("Put Back") { $0.store.restore(trashed) })
                menu.addItem(item("Delete Now") { $0.store.deleteForever(trashed) })
            case .note(let id):
                guard let note = model.notes.first(where: { $0.id == id }) else { return }
                menu.addItem(item("Open in New Tab") { $0.newTab(noteID: note.id) })
                menu.addItem(item("Open to the Side") { $0.openToTheSide(note.id) })
                menu.addItem(.separator())
                if model.canMarkRead(id) {
                    menu.addItem(item(model.isUnread(id) ? "Mark as Read" : "Mark as Unread") { $0.toggleRead(id) })
                }
                menu.addItem(item(model.isBookmarked(id) ? "Remove Bookmark" : "Add Bookmark") { $0.toggleBookmark(id) })
                menu.addItem(item("Rename…") { $0.renaming = note })
                menu.addItem(item("Move to Folder…") { $0.moving = note })
                menu.addItem(item("Add Tag…") { $0.tagging = note })
                menu.addItem(item("Show in Finder") { $0.showInFinder(note) })
                menu.addItem(.separator())
                menu.addItem(item("Move to Trash") { $0.moveToTrash(note) })
            case .header:
                // Right-click a section label to choose how folders and tags are sorted.
                addTreeSortItems(to: menu)
            case .treeSwitch:
                // Folders or tags one at a time have no label: their switch has the sort instead.
                addTreeSortItems(to: menu)
            case .place(let place, _):
                if place != .allNotes {
                    menu.addItem(item(model.isPinned(place) ? "Unpin" : "Pin to Sidebar") { $0.togglePin(place) })
                }
                // Renamed in every note that has it.
                let rename: VaultStore.VaultRename? = switch place {
                case .tag(let tag): .tag(tag)
                case .property(let name): .property(name)
                case .propertyValue(let name, let value): .value(property: name, value: value)
                default: nil
                }
                // A list note of the notes here, named after the place.
                switch place {
                case .folder(let path) where !path.isEmpty:
                    menu.addItem(item("New List of These Notes") { $0.createList(of: place) })
                case .tag, .kind, .propertyValue:
                    menu.addItem(item("New List of These Notes") { $0.createList(of: place) })
                default: break
                }
                if let rename {
                    let title = switch rename {
                    case .tag: "Rename Tag…"
                    case .property: "Rename Property…"
                    case .value: "Change Value…"
                    }
                    menu.addItem(item(title) { $0.renamingAcrossVault = rename })
                }
                let path: String? = switch place {
                case .folder(let path): path
                case .allNotes: ""
                default: nil
                }
                if let path, let root = model.root {
                    menu.addItem(item("New Folder Inside…") { $0.newFolder(in: path) })
                    menu.addItem(item("Show in Finder") { _ in
                        NSWorkspace.shared.activateFileViewerSelecting([path.isEmpty ? root : root.appendingPathComponent(path)])
                    })
                }
                // And on the folders and tags themselves, when they have no label.
                if place.isTag || path?.isEmpty == false, section(ofRow: table.clickedRow) == nil {
                    menu.addItem(.separator())
                    addTreeSortItems(to: menu)
                }
            default:
                break
            }
        }

        private func item(_ title: String, _ action: @escaping (VaultModel) -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title) { [weak self] in
                guard let model = self?.model else { return }
                action(model)
            }
            return item
        }
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("Not used") }

    @objc private func run() { handler() }
}

/// Shows a SwiftUI view but lets every click through to the table underneath, so the table
/// handles selection, right-click menus and dragging. (A plain hosting view keeps right-clicks
/// for itself, which stopped the table's menu appearing.)
/// The note list's table. Return or Tab moves the keyboard into the open note.
final class SidebarTableView: NSTableView {
    /// The two-column view's tree: its selection is blue only while it has the keyboard, as
    /// the last thing picked (the note list's is blue whenever the window's in front).
    var emphasizesOnlyWithKeyboard = false

    /// How far in from each side the source list style puts its cells.
    static let rowInset: CGFloat = 16

    /// Called when its width changes.
    var onWidthChange: (() -> Void)?

    /// Its one column always as wide as it is. (Columns only follow a table that resizes, from
    /// the width they start at: in the two-column view's narrow tree, the rows were drawn in
    /// a column narrower than the table, their names cut to a letter.)
    override func layout() {
        super.layout()
        if let column = tableColumns.first, abs(column.width - bounds.width) > 0.5 { sizeLastColumnToFit() }
        onWidthChange?()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 48 || event.keyCode == 76, // Return, Tab, Enter
           let editor = window.flatMap({ Self.firstTextView(in: $0.contentView) }) {
            window?.makeFirstResponder(editor)
            return
        }
        super.keyDown(with: event)
    }

    /// The first note editor in the window (the main one, left of any side note).
    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? MarkdownTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }
}

/// A sidebar row. Its selection is blue whenever the window is in front, unless another list
/// (the two-column view's tree) has the keyboard: the note open is the thing picked, whether
/// the keyboard is in the list or in the note. (A table's own rule, blue only while it has
/// the keyboard, made the open note grey as soon as it was being edited.)
final class SidebarTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get {
            guard let window, window.isKeyWindow else { return false }
            if (superview as? SidebarTableView)?.emphasizesOnlyWithKeyboard == true { return window.firstResponder === superview }
            if let list = window.firstResponder as? NSTableView, list !== superview { return false }
            return true
        }
        set {
            super.isEmphasized = newValue
            refreshCells()
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && isEmphasized ? .emphasized : .normal
    }

    override var isSelected: Bool {
        didSet { refreshEmphasis() }
    }

    /// Just before drawing, the cells take the highlight about to be drawn. Whether it's blue
    /// is worked out as it's drawn (from the window and where the keyboard is), and nothing
    /// tells the row when that changes in every case: in the two-column view a note's row could
    /// be drawn blue with its text still black, as for a grey highlight.
    override func viewWillDraw() {
        refreshCells()
        super.viewWillDraw()
    }

    private func refreshCells() {
        for case let cell as HostingCell in subviews { cell.matchRow() }
    }

    /// A cell put in the row (new, or reused from another) takes the row's highlight.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? HostingCell)?.matchRow()
    }

    /// Redraws the highlight and tells the cells, after focus moves or the window changes.
    func refreshEmphasis() {
        needsDisplay = true
        refreshCells()
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A table cell showing a SwiftUI view.
final class HostingCell: NSTableCellView {
    private var hosting: PassthroughHostingView<SidebarRowView>?
    private var view: SidebarRowView?

    /// Whether the view was last shown on the blue highlight.
    private var shownEmphasized = false

    /// Emphasized when its row is selected on the blue highlight. Worked out from the row
    /// itself, not from the style AppKit hands the cell, which can be the table's own idea
    /// (blue only while the list has the keyboard): a selected note could be drawn blue with
    /// its text still black.
    private var isEmphasized: Bool {
        guard let row = superview as? SidebarTableRowView else { return backgroundStyle == .emphasized }
        return row.isSelected && row.isEmphasized
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { matchRow() }
    }

    /// Redraws the view if its row's highlight has changed since it was shown.
    func matchRow() {
        guard let view, isEmphasized != shownEmphasized else { return }
        show(view)
    }

    func show(_ view: SidebarRowView) {
        self.view = view
        var view = view
        view.isEmphasized = isEmphasized
        shownEmphasized = view.isEmphasized
        if let hosting {
            hosting.rootView = view
        } else {
            let hosting = PassthroughHostingView(rootView: view)
            // Fill the row, whatever its height: without this the hosting view pins itself to
            // the height its content had when first made, so a row that later grows (when its
            // tags arrive) keeps a one-line view and the tags line is cut off.
            hosting.sizingOptions = []
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.hosting = hosting
        }
    }
}

/// What one sidebar row looks like.
struct SidebarRowView: View {
    let row: SidebarRow
    /// Observed, so a row redraws when tags or dates change. (Handing the cell a new view
    /// with the same plain reference wouldn't: SwiftUI sees nothing different and skips it.)
    @ObservedObject var model: VaultModel
    let collapsed: Set<SidebarSection>
    /// Folders unfolded to show their subfolders.
    var expanded: Set<String> = []
    /// Notes' titles on as many lines as they take.
    var wrapsTitles = false
    /// How wide the row is, which a wrapped title's lines are broken to fit, exactly as its
    /// height was measured (so a title never wraps onto more lines than its row has room for).
    var rowWidth: CGFloat?
    /// Selected, on the blue highlight: text and icons go white.
    var isEmphasized = false
    /// For a date's label after another group's notes: a line above it.
    var dividesAbove = false
    /// Where a folder's or tag's row starts (its icon), indented by depth.
    static func placeStart(depth: Int) -> CGFloat { 8 + CGFloat(depth) * 14 }
    static let iconWidth: CGFloat = 16
    static let arrowWidth: CGFloat = 12

    static func name(of place: SidebarPlace, depth: Int) -> String { depth > 0 ? place.shortName : place.title }

    /// A row's name: the vault's own, for the top of the two-column view's tree.
    /// The templates and attachments folders by their job, whatever the folders are called.
    private func name(of place: SidebarPlace, depth: Int) -> String {
        if place == .allNotes { return model.root?.lastPathComponent ?? "Vault" }
        return depth == 0 ? model.title(for: place) : Self.name(of: place, depth: depth)
    }

    /// Where a folder's or tag's unfold arrow starts in its row: just after its name, which
    /// is measured as the row draws it. (The table takes the clicks, so it needs to know.)
    static func arrowStart(of place: SidebarPlace, depth: Int, rowWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let nameWidth = ceil((name(of: place, depth: depth) as NSString).size(withAttributes: [.font: font]).width)
        // A long name is cut short before the count, so the arrow is never past that.
        return min(placeStart(depth: depth) + iconWidth + 6 + nameWidth + 4, rowWidth - 40)
    }

    /// The width of a section's sort label and its arrows.
    static func sortLabelWidth(_ label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        return ceil((label as NSString).size(withAttributes: [.font: font]).width) + 2 + 8
    }

    var body: some View {
        // Dark's colours are white and light grey, as on the system's blue highlight.
        if isEmphasized {
            content.environment(\.colorScheme, .dark)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch row {
        case .header(let section):
            let isOpen = !collapsed.contains(section)
            HStack(spacing: 4) {
                Text(section.title)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Spacer(minLength: 4)
                if let label = model.sortLabel(for: section) {
                    // Drawn only: the table takes the click and shows the menu.
                    HStack(spacing: 2) {
                        Text(label)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    // On one line, however narrow the column: the label is cut short instead.
                    .fixedSize()
                    .help("How \(section.title.lowercased()) are sorted")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 8)
            // The arrows' right edge on the counts' (the symbol has a little room at its side).
            .padding(.trailing, 7.5)
            // As much room below the label as above it, down to the line when it's folded.
            .padding(.bottom, 5)
            .help(isOpen ? "Hide \(section.title.lowercased())" : "Show \(section.title.lowercased())")
        case .dateGroup(let label, _):
            // As a section's label, without its arrow: it doesn't fold.
            Text(label)
                .lineLimit(1)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
                // A line at the top, parting this group from the one before, a little below
                // the last note so it doesn't crowd it.
                .overlay(alignment: .top) {
                    if dividesAbove {
                        Divider()
                            .padding(.horizontal, 8)
                            .padding(.top, SidebarTable.Coordinator.groupLineRoom - 1)
                    }
                }
        case .filters(let items):
            FilterSummaryView(items: items)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .count(let label):
            Text(label)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        case .divider:
            // Low in its row: the room above ends the section before it, which otherwise
            // looks cramped (most of all a collapsed section, its heading right on the line).
            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .place(let place, let depth):
            HStack(spacing: 6) {
                Image(systemName: model.symbol(for: place))
                    // White on the selection's blue (the tree's); otherwise blue, as in Finder.
                    .foregroundStyle(isEmphasized ? AnyShapeStyle(.primary)
                                     : place.isTag || place.isPropertyValue ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .frame(width: Self.iconWidth)
                Text(name(of: place, depth: depth))
                    .lineLimit(1)
                // A folder with folders in it, or a tag with tags under it, unfolds from the
                // arrow after its name, as a section does from the arrow after its label.
                if place != .allNotes, place.unfolds, !model.subplaces(of: place).isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.contains(VaultModel.expansionKey(place)) ? 90 : 0))
                        .frame(width: Self.arrowWidth)
                        .padding(.leading, -2)
                }
                Spacer(minLength: 4)
                if place != .allNotes {
                    Text("\(model.store.sidebarCount(of: place))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            // The icon lines up with the section's label and the notes' text.
            .padding(.leading, Self.placeStart(depth: depth))
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
        case .note(let id):
            // By its ID, not by going through every note (rows are drawn again and again).
            if let note = model.store.notesByID[id] {
                SidebarNoteRow(note: note, model: model, wrapsTitle: wrapsTitles, rowWidth: rowWidth, isEmphasized: isEmphasized)
            }
        case .treeSwitch:
            CapsuleToggle(selection: .constant(model.treeKind))
                .padding(.horizontal, 8)
                // Some room above, apart from the trash.
                .padding(.top, 8)
                .frame(maxHeight: .infinity)
        case .image(let path):
            if let image = model.store.image(path) {
                SidebarImageRow(image: image)
            }
        case .trashed(let trashed):
            HStack(spacing: 6) {
                Text(trashed.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(trashed.deleted, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .help("Right-click to put it back, or delete it now")
        }
    }
}

/// A note in the sidebar: its name, and optionally its date and tags. Its kind can mark it
/// unread (a dot before it) and put some of its properties under its name.
struct SidebarNoteRow: View {
    let note: Note
    @ObservedObject var model: VaultModel
    /// On as many lines as it takes, rather than cut short.
    var wrapsTitle = false
    /// The row's width, which a wrapped title's lines are broken to fit.
    var rowWidth: CGFloat?
    /// Selected, on the blue highlight: the unread dot goes white.
    var isEmphasized = false

    /// Between a wrapped title's lines: the system's own spacing was too tight to read.
    static let wrappedLineSpacing: CGFloat = 3
    private static let padding: CGFloat = 8
    private static let spacing: CGFloat = 6
    private static let iCloudWidth: CGFloat = 16
    private static let unreadDot: CGFloat = 6
    /// Down to the middle of the title's first line.
    private static var unreadDotTop: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ((font.ascender - font.descender + font.leading) - unreadDot) / 2
    }

    private var showsDate: Bool {
        // In groups, the heading over it gives the date (unless sorted by title).
        model.listDateStyle == .beside || (model.listDateStyle == .groups && model.sort == .title)
    }

    /// Notes stand in from their date headings; and wherever a note may be unread, so its dot
    /// has room in the margin (in Recent, say, or sorted by title).
    private var indent: CGFloat {
        let grouped = model.listDateStyle == .groups && model.sort != .title && model.place != .recent
        return grouped || model.store.tracksReading ? 12 : 0
    }

    /// A list note is marked: with "List" at the row's right where that's free (under date
    /// headings, or with dates off), else with a symbol before its title.
    private var isList: Bool { model.store.listNoteIDs.contains(note.id) }
    private var listMark: ListMark? { isList ? (showsDate ? .symbol : .label) : nil }
    enum ListMark { case symbol, label }
    private static let listSymbolWidth: CGFloat = 14
    @MainActor private static var listLabelWidth: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        return ceil(("List" as NSString).size(withAttributes: [.font: font]).width) + 12
    }()

    /// Each date label's width, measured once (the same dates come up again and again).
    @MainActor private static var dateWidths: [String: CGFloat] = [:]

    /// The room a row `rowWidth` wide leaves its title.
    @MainActor static func titleWidth(of note: Note, model: VaultModel, rowWidth: CGFloat) -> CGFloat {
        let row = SidebarNoteRow(note: note, model: model)
        var width = rowWidth - padding * 2 - row.indent
        if !note.isDownloaded { width -= iCloudWidth + spacing }
        switch row.listMark {
        case .symbol: width -= listSymbolWidth + spacing
        case .label: width -= listLabelWidth + spacing
        case nil: break
        }
        if row.showsDate {
            let label = row.dateLabel
            let labelWidth = dateWidths[label] ?? {
                let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
                let measured = ceil((label as NSString).size(withAttributes: [.font: font]).width)
                dateWidths[label] = measured
                return measured
            }()
            width -= labelWidth + spacing
        }
        // The spacer's least, and the gap before it (left out before, which squeezed a date
        // at the right onto two lines).
        width -= 4 + spacing
        return max(width, 20)
    }

    private var dateLabel: String { Self.label(for: model.listDate == .edited ? note.modified : note.created) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                if listMark == .symbol {
                    Image(systemName: "list.bullet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.listSymbolWidth)
                        .help("A list")
                }
                Text(note.title)
                    .lineLimit(wrapsTitle ? nil : 1)
                    .lineSpacing(wrapsTitle ? Self.wrappedLineSpacing : 0)
                    .fixedSize(horizontal: false, vertical: wrapsTitle)
                    // Broken at the width the row's height was measured for.
                    .frame(width: wrapsTitle ? rowWidth.map { Self.titleWidth(of: note, model: model, rowWidth: $0) } : nil, alignment: .leading)
                Spacer(minLength: 4)
                if !note.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .frame(width: Self.iCloudWidth)
                        .help("In iCloud, not yet downloaded")
                }
                if listMark == .label {
                    Text("List")
                        .font(.caption)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .help("A list")
                }
                if showsDate {
                    Text(dateLabel)
                        .font(.caption)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let line = model.listSecondLine(for: note.id) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        // Unread, as Mail marks it: a dot in the margin, so titles stay lined up.
        .overlay(alignment: .topLeading) {
            if model.listLook(for: note.id)?.isUnread == true {
                Circle()
                    .fill(isEmphasized ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.accentColor))
                    .frame(width: Self.unreadDot, height: Self.unreadDot)
                    // In the middle of the margin before the title.
                    .offset(x: -(Self.padding + indent + Self.unreadDot) / 2, y: Self.unreadDotTop)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.horizontal, Self.padding)
        // Under date headings, indented, so the headings stand out.
        .padding(.leading, indent)
        .frame(maxHeight: .infinity, alignment: .center)
        .help(note.id)
    }

    /// Today's notes show the time, this week's the weekday, older ones the date.
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension VaultModel {
    /// The name of how a section is sorted, shown at the right of its label (nothing for
    /// sections that aren't sorted).
    func sortLabel(for section: SidebarSection) -> String? {
        switch section {
        case .notes:
            switch sort {
            case .modified: "Date edited"
            case .created: "Date created"
            case .title: "Title"
            }
        case .folders, .tags:
            tagOrder == .name ? "Name" : "Date modified"
        case .pinned, .types, .properties, .values, .images, .linkedNote, .property:
            nil
        }
    }
}

extension SidebarPlace {
    /// The sidebar's symbol for a place.
    var symbol: String {
        switch self {
        case .allNotes: "tray"
        case .folder: "folder"
        case .tag: "number.sign.circle"
        case .everything: "tray.full"
        case .bookmarks: "bookmark"
        case .trash: "trash"
        case .properties: "list.bullet.rectangle"
        case .property: "text.alignleft"
        case .propertyValue: "equal"
        case .types: "square.grid.2x2"
        case .tags: "number"
        case .kind: "doc.text"
        case .lists: "list.bullet.rectangle.portrait"
        case .recent: "clock"
        }
    }
}

extension VaultModel {
    /// A place's name as shown: the templates and attachments folders by their job, whatever
    /// the folders are called.
    func title(for place: SidebarPlace) -> String {
        if case .folder(let path) = place, let special = store.specialFolder(at: path) { return special.title }
        return place.title
    }

    /// A place's symbol: a property's says its type, as in the properties strip.
    func symbol(for place: SidebarPlace) -> String {
        switch place {
        case .folder(let path) where store.specialFolder(at: path) != nil: store.specialFolder(at: path)!.symbol
        case .property(let name): store.propertyTypes.type(forKey: name)?.symbol ?? guessedSymbol(name)
        case .kind(_, let name): store.kinds.kind(named: name)?.shownSymbol ?? place.symbol
        default: place.symbol
        }
    }

    /// For a property with no type set: from how its values read.
    private func guessedSymbol(_ name: String) -> String {
        store.guessedType(ofProperty: name).symbol
    }
}

private extension NSRange {
    /// The rows a range covers, as indexes.
    var toIndexSet: IndexSet { location == NSNotFound ? [] : IndexSet(integersIn: location..<(location + length)) }
}

/// An image in the sidebar: a small picture of it, and its name.
struct SidebarImageRow: View {
    let image: VaultImage
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(image.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .task(id: image.url) {
            guard image.isDownloaded else { return }
            thumbnail = await withCheckedContinuation { done in
                EditorImages.shared.picture(of: image.url, pixels: 40) { done.resume(returning: $0) }
            }
        }
    }
}
