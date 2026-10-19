import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// One row of the sidebar: a section label, a divider, a folder or tag, or a note.
enum SidebarRow: Hashable {
    case header(String)
    case tagsHeader
    case divider
    case place(SidebarPlace, depth: Int)
    case note(Note.ID)
}

extension VaultModel {
    /// The rows to show for the current place, in order.
    func sidebarRows(tagsExpanded: Bool, includesPlaces: Bool = true) -> [SidebarRow] {
        guard includesPlaces else { return notes(in: place).map { .note($0.id) } }
        var sections: [[SidebarRow]] = []
        let subplaces = subplaces(of: place)
        if place == .allNotes {
            if !pins.isEmpty { sections.append([.header("Pinned")] + pins.map { .place($0, depth: 0) }) }
            if !subplaces.isEmpty { sections.append([.header("Folders")] + subplaces.map { .place($0, depth: 0) }) }
            if !tagTree.entries.isEmpty {
                sections.append([.tagsHeader] + (tagsExpanded ? sortedTagEntries.map { .place(.tag($0.tag), depth: $0.depth) } : []))
            }
        } else if !subplaces.isEmpty {
            sections.append(subplaces.map { .place($0, depth: 0) })
        }
        let notes = notes(in: place)
        if !notes.isEmpty {
            sections.append((place == .allNotes && !sections.isEmpty ? [SidebarRow.header("Notes")] : []) + notes.map { .note($0.id) })
        }
        // Thin dividers between sections.
        return sections.enumerated().flatMap { index, rows in index == 0 ? rows : [.divider] + rows }
    }
}

/// The sidebar's list of folders, tags and notes: an AppKit table, so every row has its exact
/// height before it's drawn, and moving between folders can slide.
struct SidebarTable: NSViewRepresentable {
    @ObservedObject var model: VaultModel
    /// False in the two-column view, where folders and tags have their own column.
    var includesPlaces = true
    @AppStorage("tagsSectionExpanded") var tagsExpanded = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = SidebarTableView()
        table.headerView = nil
        table.style = .sourceList
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAutomaticRowHeights = false
        table.allowsEmptySelection = true
        table.addTableColumn(NSTableColumn(identifier: .init("main")))
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

        static func noteHeight(hasTags: Bool) -> CGFloat { hasTags ? 38 : 24 }

        init(_ parent: SidebarTable) { self.parent = parent }

        var model: VaultModel { parent.model }

        /// Rebuilds the rows. Moving to another place slides the list: in from the right when
        /// going deeper, from the left when going back up.
        func update(animated: Bool) {
            guard let table else { return }
            let newRows = model.sidebarRows(tagsExpanded: parent.tagsExpanded, includesPlaces: parent.includesPlaces)
            let place = model.place
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
                if animated, placeChanged, parent.includesPlaces, let layer = table.enclosingScrollView?.layer {
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
                case .folder(let path), .tag(let path): path.split(separator: "/").count
                }
            }
            return depth(place) > depth(old)
        }

        private func syncSelection() {
            guard let table else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
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
            case .header, .tagsHeader: 24
            case .divider: 11
            case .place: 24
            case .note(let id):
                // Two lines only for a note that has tags to show.
                Self.noteHeight(hasTags: model.showsTagsInList && !model.listTags(for: id).isEmpty)
            }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard case .note(let id) = rows[row] else { return false }
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

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("row")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? HostingCell ?? HostingCell()
            cell.identifier = identifier
            cell.show(SidebarRowView(row: rows[row], model: model, tagsExpanded: parent.tagsExpanded))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table, table.selectedRow >= 0, case .note(let id) = rows[table.selectedRow] else { return }
            model.selectFromList(id)
        }

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row) else { return }
            switch rows[row] {
            case .place(let place, _): model.browse(place)
            case .tagsHeader: parent.tagsExpanded.toggle()
            default: break
            }
        }

        // MARK: Dragging notes onto folders

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            if case .note(let id) = rows[row] { return id as NSString }
            return nil
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard operation == .on, rows.indices.contains(row), case .place(.folder, _) = rows[row] else { return [] }
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard case .place(.folder(let path), _) = rows[row],
                  let id = info.draggingPasteboard.string(forType: .string) else { return false }
            model.move(noteID: id, toFolder: path)
            return true
        }

        // MARK: Right-click menus

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            switch rows[table.clickedRow] {
            case .note(let id):
                guard let note = model.notes.first(where: { $0.id == id }) else { return }
                menu.addItem(item("Open in New Tab") { $0.newTab(noteID: note.id) })
                menu.addItem(item("Open to the Side") { $0.openToTheSide(note.id) })
                menu.addItem(.separator())
                menu.addItem(item("Rename…") { $0.renaming = note })
                menu.addItem(item("Move to Folder…") { $0.moving = note })
                menu.addItem(item("Add Tag…") { $0.tagging = note })
                menu.addItem(item("Show in Finder") { $0.showInFinder(note) })
                menu.addItem(.separator())
                menu.addItem(item("Move to Trash") { $0.moveToTrash(note) })
            case .header, .tagsHeader:
                // Right-click a section label to choose how folders and tags are sorted.
                let byName = item("Sort Folders and Tags by Name") { $0.tagOrder = .name }
                byName.state = model.tagOrder == .name ? .on : .off
                let byDate = item("Sort Folders and Tags by Date Modified") { $0.tagOrder = .modified }
                byDate.state = model.tagOrder == .modified ? .on : .off
                menu.addItem(byName)
                menu.addItem(byDate)
            case .place(let place, _):
                menu.addItem(item(model.isPinned(place) ? "Unpin" : "Pin to Sidebar") { $0.togglePin(place) })
                if case .folder(let path) = place, let root = model.root {
                    menu.addItem(item("Show in Finder") { _ in
                        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(path)])
                    })
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

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A table cell showing a SwiftUI view.
final class HostingCell: NSTableCellView {
    private var hosting: PassthroughHostingView<SidebarRowView>?

    func show(_ view: SidebarRowView) {
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
    let tagsExpanded: Bool

    var body: some View {
        switch row {
        case .header(let title):
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 8)
                .padding(.bottom, 3)
        case .tagsHeader:
            HStack(spacing: 4) {
                Text("Tags")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(tagsExpanded ? 90 : 0))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 8)
            .padding(.bottom, 3)
            .help(tagsExpanded ? "Hide tags" : "Show tags")
        case .divider:
            Divider()
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
        case .place(let place, let depth):
            HStack(spacing: 6) {
                Image(systemName: place.isTag ? "number" : "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(depth > 0 ? place.shortName : place.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(model.noteCount(of: place))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
        case .note(let id):
            if let note = model.notes.first(where: { $0.id == id }) {
                SidebarNoteRow(note: note, model: model)
            }
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
                if model.showsDateInList {
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
