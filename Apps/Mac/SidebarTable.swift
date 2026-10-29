import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// One row of the sidebar: a section label, a divider, a folder or tag, or a note.
enum SidebarRow: Hashable {
    /// A section's label, which folds the section away or opens it again.
    case header(SidebarSection)
    case divider
    case place(SidebarPlace, depth: Int)
    case note(Note.ID)
    /// A note in the trash.
    case trashed(VaultTrash.Item)
    /// The switch between folders and tags, when they show one at a time.
    case treeSwitch
    /// A heading over notes by date ("Today", "October", "2025"), with the first note under it
    /// (so two headings with the same name, in an odd order, are still two rows).
    case dateGroup(String, first: Note.ID)

    /// The note a row opens, if it's a note's row.
    var noteID: Note.ID? {
        if case .note(let id) = self { return id }
        return nil
    }
}

/// The sidebar's sections at the vault's top level, each of which can be folded away.
enum SidebarSection: String, CaseIterable {
    case pinned = "Pinned", folders = "Folders", tags = "Tags", notes = "Notes"
}

extension VaultModel {
    /// The rows to show for the current place, in order. A folded section shows only its label.
    /// How an unfolded folder or tag is remembered: a folder by its path, a tag as `#tag`.
    static func expansionKey(_ place: SidebarPlace) -> String {
        switch place {
        case .folder(let path): path
        case .tag(let tag): "#" + tag
        case .allNotes, .everything, .bookmarks, .trash: ""
        }
    }

    /// `expanded` holds the folders and tags unfolded to show the ones inside them.
    func sidebarRows(collapsed: Set<SidebarSection>, expanded: Set<String> = [], content: SidebarTable.Content = .everything) -> [SidebarRow] {
        // The two-column view's tree is always the top level, wherever its notes are.
        let place = content == .places ? SidebarPlace.allNotes : place
        if content != .places, place == .trash { return trashedNotes.map { .trashed($0) } }
        guard content != .notes else { return noteRows(notes(in: place)) }
        var sections: [[SidebarRow]] = []
        func section(_ name: SidebarSection, _ rows: [SidebarRow]) -> [SidebarRow] {
            [.header(name)] + (collapsed.contains(name) ? [] : rows)
        }
        // Folders, each followed by its subfolders if it's unfolded.
        func folderRows(_ places: [SidebarPlace], depth: Int) -> [SidebarRow] {
            places.flatMap { place -> [SidebarRow] in
                guard case .folder = place, expanded.contains(Self.expansionKey(place)) else { return [.place(place, depth: depth)] }
                return [.place(place, depth: depth)] + folderRows(self.subplaces(of: place), depth: depth + 1)
            }
        }
        let subplaces = subplaces(of: place)
        if place == .allNotes {
            // Special places first, with no heading: every note, and the trash. Then the switch
            // between folders and tags, if they show one at a time: below these, which it
            // doesn't change.
            let oneAtATime = treeLayout == .toggle
            sections.append([.place(.everything, depth: 0), .place(.bookmarks, depth: 0), .place(.trash, depth: 0)]
                            + (oneAtATime ? [.treeSwitch] : []))
            if !pins.isEmpty { sections.append(section(.pinned, pins.map { .place($0, depth: 0) })) }
            // Shown one at a time, folders or tags have no label of their own, and can't be
            // folded away: the switch names them, and folding the only one would leave nothing.
            func tree(_ name: SidebarSection, _ rows: [SidebarRow]) -> [SidebarRow] {
                oneAtATime ? rows : section(name, rows)
            }
            if !oneAtATime || treeKind == .folders {
                // The tree starts with the vault itself, for the notes at its top level.
                let top: [SidebarRow] = content == .places ? [.place(.allNotes, depth: 0)] : []
                if !subplaces.isEmpty || !top.isEmpty { sections.append(tree(.folders, top + folderRows(subplaces, depth: 0))) }
            }
            if !tagTree.entries.isEmpty, !oneAtATime || treeKind == .tags {
                // Nested tags show beneath a tag that's unfolded, as subfolders do.
                let tags = sortedTagEntries.filter { entry in
                    let parts = entry.tag.split(separator: "/")
                    return (1..<max(parts.count, 1)).allSatisfy { expanded.contains(Self.expansionKey(.tag(parts.prefix($0).joined(separator: "/")))) }
                }
                sections.append(tree(.tags, tags.map { .place(.tag($0.tag), depth: $0.depth) }))
            }
        } else if !subplaces.isEmpty {
            // Inside a folder (or tag) with folders (or tags) in it: labelled, as at the top.
            let rows = place.isTag ? subplaces.map { SidebarRow.place($0, depth: 0) } : folderRows(subplaces, depth: 0)
            sections.append(section(place.isTag ? .tags : .folders, rows))
        }
        // The notes, always under their label, which holds the sort menu.
        let notes = content == .places ? [] : notes(in: place)
        if !notes.isEmpty {
            sections.append(section(.notes, noteRows(notes)))
        }
        // Thin dividers between sections.
        return sections.enumerated().flatMap { index, rows in index == 0 ? rows : [.divider] + rows }
    }

    /// Notes' rows: under headings by date, when the list shows dates that way and is sorted
    /// by a date.
    func noteRows(_ notes: [Note]) -> [SidebarRow] {
        guard listDateStyle == .groups, sort != .title else { return notes.map { .note($0.id) } }
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
    /// The folded sections, comma separated, each as the place it's folded in and its name
    /// (`folder:Projects|Notes`): folding a section in one place leaves it open in others. A
    /// name alone (as saved before) is one folded at the top level.
    @AppStorage("collapsedSidebarSections") var collapsedSections = UserDefaults.standard.object(forKey: "tagsSectionExpanded") as? Bool == false ? "Tags" : ""

    private var collapsedEntries: [String] { collapsedSections.split(separator: ",").map(String.init) }

    private static func entry(_ section: SidebarSection, in place: SidebarPlace) -> String {
        place.key + "|" + section.rawValue
    }

    /// Where the sidebar is: the top level, always, for the two-column view's tree.
    private var shownPlace: SidebarPlace { content == .places ? .allNotes : model.place }

    /// The sections folded where the sidebar is now.
    var collapsed: Set<SidebarSection> {
        let entries = Set(collapsedEntries)
        let place = shownPlace
        return Set(SidebarSection.allCases.filter { section in
            entries.contains(Self.entry(section, in: place)) || (place == .allNotes && entries.contains(section.rawValue))
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
        var entries = collapsedEntries.filter { $0 != entry && !(place == .allNotes && $0 == section.rawValue) }
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

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        context.coordinator.table = table
        context.coordinator.update(animated: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: SidebarTable
        weak var table: NSTableView?
        private var rows: [SidebarRow] = []
        private var shownPlace: SidebarPlace?
        private var isSyncingSelection = false
        /// Row heights as last laid out, to spot rows whose height changed.
        private var shownHeights: [CGFloat] = []

        static func noteHeight(hasTags: Bool, density: VaultModel.SidebarDensity) -> CGFloat {
            hasTags ? density.twoLineHeight : density.rowHeight
        }

        init(_ parent: SidebarTable) { self.parent = parent }

        var model: VaultModel { parent.model }

        /// Rebuilds the rows. Moving to another place slides the list: in from the right when
        /// going deeper, from the left when going back up.
        func update(animated: Bool) {
            guard let table else { return }
            watchFocus(in: table.window)
            let newRows = model.sidebarRows(collapsed: parent.collapsed, expanded: parent.expanded, content: parent.content)
            // The tree doesn't move with the place it shows.
            let place = parent.content == .places ? SidebarPlace.allNotes : model.place
            let placeChanged = shownPlace != nil && shownPlace != place
            if !placeChanged, newRows == rows {
                // Same rows: refresh their contents, and let any that gained or lost a tags
                // line grow or shrink smoothly rather than jump.
                let heights = rows.indices.map { tableView(table, heightOfRow: $0) }
                let changed = IndexSet(heights.indices.filter { heights[$0] != shownHeights[safe: $0] })
                table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: [0])
                if !changed.isEmpty {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animated ? 0.25 : 0
                        context.allowsImplicitAnimation = true
                        table.noteHeightOfRows(withIndexesChanged: changed)
                    }
                }
                shownHeights = heights
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
                table.reloadData()
                shownHeights = rows.indices.map { tableView(table, heightOfRow: $0) }
                if placeChanged { table.scrollRowToVisible(0) }
            }
            shownPlace = place
            syncSelection()
        }

        static func isDeeper(_ place: SidebarPlace, than old: SidebarPlace) -> Bool {
            func depth(_ place: SidebarPlace) -> Int {
                switch place {
                case .allNotes: 0
                case .everything, .bookmarks, .trash: 1
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

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            switch rows[row] {
            case .header, .dateGroup: model.sidebarDensity.headerHeight
            case .divider: model.sidebarDensity.dividerHeight
            case .place, .trashed: model.sidebarDensity.rowHeight
            case .treeSwitch: model.sidebarDensity.rowHeight + 10
            case .note(let id):
                // Two lines only for a note that has tags to show.
                Self.noteHeight(hasTags: model.showsTagsInList && !model.listTags(for: id).isEmpty, density: model.sidebarDensity)
            }
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
            cell.show(SidebarRowView(row: rows[row], model: model, collapsed: parent.collapsed, expanded: parent.expanded))
            return cell
        }

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
            case .pinned:
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
            guard operation == .on, rows.indices.contains(row) else { return [] }
            switch rows[row] {
            case .place(.folder, _), .place(.allNotes, _): return .move
            // The heading over the folders: the top level.
            case .header(.folders) where model.place == .allNotes || parent.content == .places: return .move
            default: return []
            }
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard let dragged = info.draggingPasteboard.string(forType: .string) else { return false }
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

    /// Its one column always as wide as it is. (Columns only follow a table that resizes, from
    /// the width they start at: in the two-column view's narrow tree, the rows were drawn in
    /// a column narrower than the table, their names cut to a letter.)
    override func layout() {
        super.layout()
        if let column = tableColumns.first, abs(column.width - bounds.width) > 0.5 { sizeLastColumnToFit() }
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
    /// Selected, on the blue highlight: text and icons go white.
    var isEmphasized = false
    /// Where a folder's or tag's row starts (its icon), indented by depth.
    static func placeStart(depth: Int) -> CGFloat { 8 + CGFloat(depth) * 14 }
    static let iconWidth: CGFloat = 16
    static let arrowWidth: CGFloat = 12

    static func name(of place: SidebarPlace, depth: Int) -> String { depth > 0 ? place.shortName : place.title }

    /// A row's name: the vault's own, for the top of the two-column view's tree.
    private func name(of place: SidebarPlace, depth: Int) -> String {
        place == .allNotes ? (model.root?.lastPathComponent ?? "Vault") : Self.name(of: place, depth: depth)
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
                Text(section.rawValue)
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
                    .help("How \(section.rawValue.lowercased()) are sorted")
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
            .help(isOpen ? "Hide \(section.rawValue.lowercased())" : "Show \(section.rawValue.lowercased())")
        case .dateGroup(let label, _):
            // As a section's label, without its arrow: it doesn't fold.
            Text(label)
                .lineLimit(1)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
        case .divider:
            // Low in its row: the room above ends the section before it, which otherwise
            // looks cramped (most of all a collapsed section, its heading right on the line).
            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .place(let place, let depth):
            HStack(spacing: 6) {
                Image(systemName: place.symbol)
                    // White on the selection's blue (the tree's); otherwise blue, as in Finder.
                    .foregroundStyle(isEmphasized ? AnyShapeStyle(.primary)
                                     : place.isTag ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .frame(width: Self.iconWidth)
                Text(name(of: place, depth: depth))
                    .lineLimit(1)
                // A folder with folders in it, or a tag with tags under it, unfolds from the
                // arrow after its name, as a section does from the arrow after its label.
                if place != .allNotes, !model.subplaces(of: place).isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.contains(VaultModel.expansionKey(place)) ? 90 : 0))
                        .frame(width: Self.arrowWidth)
                        .padding(.leading, -2)
                }
                Spacer(minLength: 4)
                if place != .allNotes {
                    Text("\(model.noteCount(of: place))")
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
            if let note = model.notes.first(where: { $0.id == id }) {
                SidebarNoteRow(note: note, model: model)
            }
        case .treeSwitch:
            CapsuleToggle(selection: .constant(model.treeKind))
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
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

/// A note in the sidebar: its name, and optionally its date and tags.
struct SidebarNoteRow: View {
    let note: Note
    @ObservedObject var model: VaultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(note.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !note.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .help("In iCloud, not yet downloaded")
                }
                // In groups, the heading over it gives the date (unless sorted by title).
                if model.listDateStyle == .beside || (model.listDateStyle == .groups && model.sort == .title) {
                    Text(Self.label(for: model.listDate == .edited ? note.modified : note.created))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if model.showsTagsInList, case let tags = model.listTags(for: note.id), !tags.isEmpty {
                Text(tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
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
            case .modified: "Date Edited"
            case .created: "Date Created"
            case .title: "Title"
            }
        case .folders, .tags:
            tagOrder == .name ? "Name" : "Date Modified"
        case .pinned:
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
        }
    }
}
