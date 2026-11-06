import AppKit
import IndexKit
import SwiftUI
import VaultKit

/// The notes a list finds, in a Mac table: a heading for each column (the title first),
/// clicked to sort and clicked again to reverse, dragged to reorder (the title stays first),
/// and its edge dragged to resize; titles that turn link blue under the pointer, a click
/// opening the note. Text too long for its column runs onto more lines, or, where the table
/// must be a set height (a list embedded in a note), is cut short.
struct ListTable: NSViewRepresentable {
    struct Row: Equatable {
        let id: Note.ID
        let title: String
        /// Each column's text, in the columns' order.
        let cells: [String]
    }

    /// The columns after the title, as the list names them.
    let columns: [String]
    let rows: [Row]
    /// The list's order, shown by the heading's arrow.
    let sort: NoteQuery.Sort
    /// Whether long text runs onto more lines.
    let wraps: Bool
    /// The list's note, by which column widths are remembered.
    let listID: Note.ID
    /// How tall the table is, laid out at its width.
    @Binding var height: CGFloat
    let open: (Note.ID, VaultModel.LinkDestination) -> Void
    /// Sorting by a column (its name, or "title"), descending or not; nil if it can't be.
    let sortBy: ((String, Bool) -> Void)?
    /// The columns after the title, in a new order; nil if they can't be moved.
    let reorder: (([String]) -> Void)?

    static let titleID = "title"
    static let headerHeight: CGFloat = 28
    /// A row's height when it's one line, with the space between rows.
    static let rowHeight: CGFloat = 20
    static let rowGap: CGFloat = 4
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    func makeNSView(context: Context) -> NSScrollView {
        let table = ListNSTableView()
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 12, height: Self.rowGap)
        table.rowHeight = Self.rowHeight
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnReordering = reorder != nil
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.focusRingType = .none
        let header = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: Self.headerHeight))
        table.headerView = header
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))

        let scroll = PassThroughScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.widthChanged() }
        context.coordinator.table = table
        context.coordinator.parent = self
        context.coordinator.sync()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.table?.allowsColumnReordering = reorder != nil
        context.coordinator.sync()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: Widths, remembered for each list

    private static let widthsKey = "listColumnWidths"

    static func savedWidths(for listID: Note.ID) -> [String: CGFloat] {
        let all = UserDefaults.standard.dictionary(forKey: widthsKey) as? [String: [String: Double]] ?? [:]
        return (all[listID] ?? [:]).mapValues { CGFloat($0) }
    }

    static func saveWidths(_ widths: [String: CGFloat], for listID: Note.ID) {
        var all = UserDefaults.standard.dictionary(forKey: widthsKey) as? [String: [String: Double]] ?? [:]
        all[listID] = widths.mapValues { Double($0) }
        UserDefaults.standard.set(all, forKey: widthsKey)
    }

    /// A column's heading: its name in sentence case.
    static func heading(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ListTable
        weak var table: ListNSTableView?
        private var shownRows: [Row] = []
        private var shownColumns: [String] = []
        private var shownWraps = false
        /// Set while the table is changed to match the list, so its changes aren't taken
        /// as the person's.
        private var isSyncing = false
        private var lastWidth: CGFloat = 0

        init(parent: ListTable) {
            self.parent = parent
        }

        /// Makes the table show the list as it is now.
        func sync() {
            guard let table else { return }
            isSyncing = true
            defer { isSyncing = false }
            let wanted = [ListTable.titleID] + parent.columns
            if table.tableColumns.map(\.identifier.rawValue) != wanted {
                let widths = ListTable.savedWidths(for: parent.listID)
                for column in table.tableColumns { table.removeTableColumn(column) }
                for name in wanted {
                    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
                    column.title = name == ListTable.titleID ? "Title" : ListTable.heading(name)
                    column.headerToolTip = column.title
                    column.minWidth = name == ListTable.titleID ? 120 : 50
                    column.width = widths[name] ?? (name == ListTable.titleID ? 240 : 120)
                    column.resizingMask = [.autoresizingMask, .userResizingMask]
                    column.sortDescriptorPrototype = parent.sortBy == nil ? nil : NSSortDescriptor(key: name, ascending: true)
                    table.addTableColumn(column)
                }
                table.sizeToFit()
                shownColumns = parent.columns
            }
            // The heading's arrow: the list's order.
            let key = sortKey(parent.sort)
            let descriptors = parent.sortBy == nil ? [] : [NSSortDescriptor(key: key, ascending: !parent.sort.descending)]
            if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
            for column in table.tableColumns {
                let isSorted = column.identifier.rawValue.lowercased() == key.lowercased()
                table.setIndicatorImage(isSorted ? NSImage(named: parent.sort.descending ? "NSDescendingSortIndicator" : "NSAscendingSortIndicator") : nil,
                                        in: column)
            }
            if parent.rows != shownRows || parent.wraps != shownWraps {
                shownRows = parent.rows
                shownWraps = parent.wraps
                table.hoveredRow = -1
                table.reloadData()
            }
            measure()
        }

        /// The sort's column: "title", a note fact's name, or the property's.
        private func sortKey(_ sort: NoteQuery.Sort) -> String {
            switch sort.key {
            case .field(.title): ListTable.titleID
            case .field(let field): parent.columns.first { ListDefinition.field(named: $0) == field } ?? ListDefinition.name(of: field)
            case .property(let name): parent.columns.first { $0.lowercased() == name.lowercased() } ?? name
            }
        }

        /// Works out the table's height, laid out at its width, and passes it on.
        func measure() {
            guard let table else { return }
            let rowsHeight = shownRows.isEmpty ? 0 : table.rect(ofRow: shownRows.count - 1).maxY
            let height = ListTable.headerHeight + rowsHeight
            if abs(height - parent.height) > 0.5 {
                DispatchQueue.main.async { [weak self] in self?.parent.height = height }
            }
            table.window?.invalidateCursorRects(for: table)
        }

        /// The table was laid out at a new width: wrapped rows take new heights.
        func widthChanged() {
            guard let table, let width = table.enclosingScrollView?.contentSize.width, abs(width - lastWidth) > 0.5 else { return }
            lastWidth = width
            // The columns share the width, keeping their proportions.
            isSyncing = true
            table.sizeToFit()
            isSyncing = false
            if shownWraps, !shownRows.isEmpty {
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<shownRows.count))
            }
            measure()
        }

        // MARK: Rows

        func numberOfRows(in tableView: NSTableView) -> Int { shownRows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, shownRows.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ListCellView ?? ListCellView(identifier: id)
            let isTitle = tableColumn.identifier.rawValue == ListTable.titleID
            cell.show(text(at: row, in: tableColumn), isTitle: isTitle, isHovered: isTitle && (tableView as? ListNSTableView)?.hoveredRow == row,
                      wraps: shownWraps)
            return cell
        }

        private func text(at row: Int, in column: NSTableColumn) -> String {
            let name = column.identifier.rawValue
            if name == ListTable.titleID { return shownRows[row].title }
            guard let index = shownColumns.firstIndex(of: name), shownRows[row].cells.indices.contains(index) else { return "" }
            return shownRows[row].cells[index]
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard shownWraps, shownRows.indices.contains(row) else { return ListTable.rowHeight }
            // As tall as its longest text, wrapped in its column.
            var height = ListTable.rowHeight
            for column in tableView.tableColumns {
                let text = text(at: row, in: column)
                guard !text.isEmpty else { continue }
                let width = max(column.width - ListCellView.inset * 2, 20)
                let rect = (text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                           attributes: [.font: ListTable.font])
                height = max(height, ceil(rect.height) + 3)
            }
            return height
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = ListRowView()
            view.isHovered = (tableView as? ListNSTableView)?.hoveredRow == row
            view.isLast = row == shownRows.count - 1
            return view
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard shownRows.indices.contains(row) else { return }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            parent.open(shownRows[row].id, flags.contains(.command) ? .newTab : flags.contains(.option) ? .otherSide : .here)
        }

        // MARK: Columns

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isSyncing, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            // A new column sorts from A (or the lowest) first; the same one again reverses.
            let isSame = key.lowercased() == sortKey(parent.sort).lowercased()
            parent.sortBy?(key, isSame ? !parent.sort.descending : false)
        }

        func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
            // The title stays first.
            columnIndex != 0 && newColumnIndex != 0
        }

        func tableViewColumnDidMove(_ notification: Notification) {
            guard !isSyncing, let table else { return }
            let order = table.tableColumns.map(\.identifier.rawValue).filter { $0 != ListTable.titleID }
            shownColumns = order
            if order != parent.columns { parent.reorder?(order) }
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard !isSyncing, let table else { return }
            // Remembered only when a column's edge is dragged, not as the table fits its width.
            if (table.headerView?.resizedColumn ?? -1) >= 0 {
                var widths = ListTable.savedWidths(for: parent.listID)
                for column in table.tableColumns { widths[column.identifier.rawValue] = column.width }
                ListTable.saveWidths(widths, for: parent.listID)
            }
            if shownWraps, !shownRows.isEmpty {
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<shownRows.count))
            }
            measure()
        }
    }
}

/// The table, with the row under the pointer known (its title turns link blue) and a
/// pointing hand over every row, since every row opens its note.
final class ListNSTableView: NSTableView {
    var hoveredRow = -1 {
        didSet {
            guard hoveredRow != oldValue else { return }
            for row in [oldValue, hoveredRow] where row >= 0 && row < numberOfRows {
                (view(atColumn: 0, row: row, makeIfNecessary: false) as? ListCellView)?.isHovered = row == hoveredRow
                (rowView(atRow: row, makeIfNecessary: false) as? ListRowView)?.isHovered = row == hoveredRow
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hoveredRow = row(at: convert(event.locationInWindow, from: nil))
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hoveredRow = row(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredRow = -1
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard numberOfRows > 0 else { return }
        // Only where rows show: AppKit throws on a rect that's null (no rows in view).
        let rows = rect(ofRow: 0).union(rect(ofRow: numberOfRows - 1)).intersection(visibleRect)
        guard !rows.isNull, !rows.isEmpty, rows.origin.x.isFinite, rows.origin.y.isFinite else { return }
        addCursorRect(rows, cursor: .pointingHand)
    }
}

/// A row: a faint line between it and the next, and a faint fill under the pointer.
final class ListRowView: NSTableRowView {
    var isLast = false
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
    }

    override func drawSeparator(in dirtyRect: NSRect) {}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isLast else { return }
        // The line, at the row's foot (rows are drawn top down).
        NSColor.separatorColor.withAlphaComponent(0.3).setFill()
        let line = 1 / (window?.backingScaleFactor ?? 2)
        NSRect(x: 0, y: isFlipped ? bounds.maxY - line : 0, width: bounds.width, height: line).fill()
    }
}

/// A cell: its text, which wraps or is cut short; the title's in link blue under the pointer.
final class ListCellView: NSTableCellView {
    static let inset: CGFloat = 2
    private let label = NSTextField(wrappingLabelWithString: "")
    private var isTitle = false
    var isHovered = false {
        didSet { if isTitle { label.textColor = isHovered ? .linkColor : .labelColor } }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.font = ListTable.font
        label.isSelectable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ text: String, isTitle: Bool, isHovered: Bool, wraps: Bool) {
        self.isTitle = isTitle
        label.stringValue = text
        label.maximumNumberOfLines = wraps ? 0 : 1
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.textColor = isTitle ? (isHovered ? .linkColor : .labelColor) : .secondaryLabelColor
        label.toolTip = wraps ? nil : text
        self.isHovered = isHovered
    }

    // Clicks go to the table, which opens the note.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A scroll view that never scrolls: the table is as tall as its rows, and the note scrolls
/// when the pointer is over it.
final class PassThroughScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
