#if canImport(AppKit)
import AppKit
import MarkdownKit

/// The table under the pointer, and which of its controls the pointer is on.
struct TableHover: Equatable {
    /// Where the table's text starts.
    var table: Int
    /// The row (0 is the header) and column the pointer is level with.
    var row: Int?
    var column: Int?
}

/// A row or column being dragged to a new place.
enum TableDrag: Equatable {
    /// `to` is the gap it would go into: before that row, or after the last.
    case row(from: Int, to: Int)
    /// `to` is the gap it would go into: before that column, or after the last.
    case column(from: Int, to: Int)
}

/// Where a table's controls are, in the view: a strip below it and one beside it that add a
/// row or column, and a grip beside each row and above each column to drag it by.
struct TableControlLayout {
    let range: NSRange
    let bounds: CGRect
    /// The header row first.
    let rows: [CGRect]
    /// Each column's edges, left to right, in the view.
    let edges: [CGFloat]

    var columnCount: Int { edges.count - 1 }
    /// Where the pointer shows the controls: the table, and enough around it to reach them.
    var zone: CGRect { CGRect(x: bounds.minX - 26, y: bounds.minY - 18, width: bounds.width + 50, height: bounds.height + 40) }
    var addRow: CGRect { CGRect(x: bounds.minX, y: bounds.maxY + 5, width: bounds.width, height: 14) }
    var addColumn: CGRect { CGRect(x: bounds.maxX + 5, y: bounds.minY, width: 14, height: bounds.height) }

    /// Where a click takes hold of a row's grip: a little more than it.
    func rowGripTarget(_ row: Int) -> CGRect { rowGrip(row).insetBy(dx: -5, dy: -4) }
    func columnGripTarget(_ column: Int) -> CGRect { columnGrip(column).insetBy(dx: -4, dy: -5) }

    func rowGrip(_ row: Int) -> CGRect {
        CGRect(x: bounds.minX - 20, y: rows[row].midY - 10, width: 14, height: 20)
    }

    func columnGrip(_ column: Int) -> CGRect {
        CGRect(x: (edges[column] + edges[column + 1]) / 2 - 10, y: bounds.minY - 16, width: 20, height: 12)
    }

    /// The row the pointer is level with, if it's level with the table.
    func row(at point: CGPoint) -> Int? {
        rows.firstIndex { point.y >= $0.minY && point.y < $0.maxY }
    }

    /// The column the pointer is above or below, if any.
    func column(at point: CGPoint) -> Int? {
        (0..<columnCount).first { point.x >= edges[$0] && point.x < edges[$0 + 1] }
    }

}

extension MarkdownTextView {
    /// The controls of the table with a character in it, if it's drawn as a table.
    func tableControls(at location: Int) -> TableControlLayout? {
        tableGrids.first { location >= $0.range.location && location <= NSMaxRange($0.range) }.map(tableControls(of:))
    }

    private func tableControls(of grid: TableGridView) -> TableControlLayout {
        let bounds = grid.frame, decoration = grid.decoration
        return TableControlLayout(
            range: grid.range, bounds: bounds,
            rows: zip(decoration.rowTops, decoration.rowHeights).map { CGRect(x: bounds.minX, y: bounds.minY + $0, width: bounds.width, height: $1) },
            edges: decoration.columnEdges.map { bounds.minX + $0 })
    }

    /// The controls of the table near a point in the view, if there is one.
    private func tableControls(near point: NSPoint) -> TableControlLayout? {
        tableGrids.lazy.map(tableControls(of:)).first { $0.zone.contains(point) }
    }

    // MARK: Hovering

    /// Follows the pointer, to show the controls of the table it's over, and the pointer for
    /// what it's on.
    func updateTableHover(at point: NSPoint?) {
        var hover: TableHover?
        var controls: TableControlLayout?
        if let point, let found = tableControls(near: point) {
            controls = found
            hover = TableHover(table: found.range.location, row: found.row(at: point), column: found.column(at: point))
            if (hover?.row).map({ $0 > 0 && found.rowGripTarget($0).contains(point) }) == true
                        || (hover?.column).map({ found.columnGripTarget($0).contains(point) }) == true {
                NSCursor.openHand.set()
            } else if found.addRow.contains(point) || found.addColumn.contains(point) {
                NSCursor.arrow.set()
            }
        }
        guard hover != tableHover else { return }
        let old = tableHover.flatMap { tableControls(at: $0.table) }
        tableHover = hover
        for changed in [old, controls].compactMap({ $0 }) {
            setNeedsDisplay(changed.zone.insetBy(dx: -2, dy: -2))
        }
    }

    // MARK: Drawing

    func drawTableControls(in dirtyRect: NSRect) {
        guard let hover = tableHover, let controls = tableControls(at: hover.table), controls.zone.intersects(dirtyRect) else { return }
        let pointer = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }

        for strip in [controls.addRow, controls.addColumn] {
            let over = pointer.map(strip.contains) ?? false
            NSColor.textColor.withAlphaComponent(over ? 0.09 : 0.04).setFill()
            NSBezierPath(roundedRect: strip, xRadius: 4, yRadius: 4).fill()
            drawSymbol("plus", in: CGRect(x: strip.midX - 5, y: strip.midY - 5, width: 10, height: 10))
        }
        if tableDrag == nil {
            if let row = hover.row, row > 0 { drawGrip(controls.rowGrip(row), vertical: true, pointer: pointer) }
            if let column = hover.column { drawGrip(controls.columnGrip(column), vertical: false, pointer: pointer) }
        }

        NSColor.controlAccentColor.set()
        switch tableDrag {
        case .row(let from, let to):
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            var dragged = controls.rows[from]
            dragged.size.height = (from + 1 < controls.rows.count ? controls.rows[from + 1].minY : controls.bounds.maxY) - dragged.minY
            dragged.fill(using: .sourceOver)
            let y = to < controls.rows.count ? controls.rows[to].minY : controls.bounds.maxY
            NSColor.controlAccentColor.setFill()
            NSRect(x: controls.bounds.minX, y: y - 1, width: controls.bounds.width, height: 2).fill()
        case .column(let from, let to):
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSRect(x: controls.edges[from], y: controls.bounds.minY, width: controls.edges[from + 1] - controls.edges[from],
                   height: controls.bounds.height).fill(using: .sourceOver)
            NSColor.controlAccentColor.setFill()
            NSRect(x: controls.edges[to] - 1, y: controls.bounds.minY, width: 2, height: controls.bounds.height).fill()
        case nil:
            break
        }
    }

    /// Six dots, in two lines, to drag a row or column by.
    private func drawGrip(_ rect: CGRect, vertical: Bool, pointer: NSPoint?) {
        if pointer.map(rect.contains) ?? false {
            NSColor.textColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
        NSColor.secondaryLabelColor.setFill()
        for a in 0..<3 {
            for b in 0..<2 {
                let along = CGFloat(a - 1) * 4.5, across = (CGFloat(b) - 0.5) * 4.5
                let centre = vertical ? CGPoint(x: rect.midX + across, y: rect.midY + along) : CGPoint(x: rect.midX + along, y: rect.midY + across)
                NSBezierPath(ovalIn: CGRect(x: centre.x - 1.25, y: centre.y - 1.25, width: 2.5, height: 2.5)).fill()
            }
        }
    }

    private func drawSymbol(_ name: String, in rect: CGRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: Clicking and dragging

    /// Handles a click on a table's controls, and any drag that follows. False if the click
    /// wasn't on one.
    func tableControlsMouseDown(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        // As it is under the pointer now, whatever the last mouse move found.
        updateTableHover(at: point)
        guard let hover = tableHover, let controls = tableControls(at: hover.table), controls.zone.contains(point) else { return false }
        let start = controls.range.location

        if controls.addRow.contains(point) {
            changeTable(at: start) { table in
                table.insertRow(at: table.rows.count)
                return TableCell(row: table.rows.count - 1, column: 0)
            }
            return true
        }
        if controls.addColumn.contains(point) {
            changeTable(at: start) { table in
                table.insertColumn(at: table.columnCount)
                return TableCell(row: 0, column: table.columnCount - 1)
            }
            return true
        }
        if let row = hover.row, row > 0, controls.rowGripTarget(row).contains(point) {
            var dragged = controls.rows[row]
            dragged.size.height = (row + 1 < controls.rows.count ? controls.rows[row + 1].minY : controls.bounds.maxY) - dragged.minY
            let drag = trackTableDrag(from: event, lifting: dragged, along: .vertical) { point in
                let gap = 1 + controls.rows.dropFirst().filter { $0.midY < point.y }.count
                return .row(from: row, to: gap)
            }
            if case .row(let from, let gap)? = drag {
                let to = gap > from ? gap - 1 : gap
                changeTable(at: start) { table in
                    table.moveRow(from: from, to: to)
                    return TableCell(row: to, column: 0)
                }
            }
            return true
        }
        if let column = hover.column, controls.columnGripTarget(column).contains(point) {
            let dragged = CGRect(x: controls.edges[column], y: controls.bounds.minY,
                                 width: controls.edges[column + 1] - controls.edges[column], height: controls.bounds.height)
            let drag = trackTableDrag(from: event, lifting: dragged, along: .horizontal) { point in
                let gap = (0..<controls.columnCount).filter { (controls.edges[$0] + controls.edges[$0 + 1]) / 2 < point.x }.count
                return .column(from: column, to: gap)
            }
            if case .column(let from, let gap)? = drag {
                let to = gap > from ? gap - 1 : gap
                changeTable(at: start) { table in
                    table.moveColumn(from: from, to: to)
                    return TableCell(row: 0, column: to)
                }
            }
            return true
        }
        return false
    }

    /// Does `change` to a table without the note scrolling: nothing above the table moves, but
    /// the note's height is worked out again, and could take the scroll position with it.
    private func keepingScrollPosition(_ change: () -> Void) {
        let clip = enclosingScrollView?.contentView
        let origin = clip?.bounds.origin
        change()
        guard let clip, let origin, let layoutManager, let container = textContainer else { return }
        layoutManager.ensureLayout(forBoundingRect: CGRect(x: 0, y: 0, width: container.size.width, height: origin.y + clip.bounds.height * 2), in: container)
        sizeToFit()
        let bounds = clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size))
        if bounds.origin != clip.bounds.origin {
            clip.scroll(to: bounds.origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// Follows a drag until the button is let go, showing where it's got to: a row or column
    /// being moved (`lifting`) follows the pointer along its axis. The drag's last state, or nil
    /// if the pointer hardly moved (a click).
    private func trackTableDrag(from event: NSEvent, lifting lifted: CGRect? = nil, along axis: NSLayoutConstraint.Orientation = .vertical,
                                _ state: (NSPoint) -> TableDrag) -> TableDrag? {
        let start = convert(event.locationInWindow, from: nil)
        var moved = false
        var last: TableDrag?
        var image: NSImage?
        let zone = tableHover.flatMap { tableControls(at: $0.table) }?.zone ?? bounds
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if !moved, hypot(point.x - start.x, point.y - start.y) > 3 {
                moved = true
                if let lifted { image = snapshot(of: lifted) }
            }
            guard moved else { return }
            if lifted != nil { NSCursor.closedHand.set() }
            last = state(point)
            tableDrag = last
            if let lifted, let image {
                let frame = axis == .vertical ? lifted.offsetBy(dx: 0, dy: point.y - start.y) : lifted.offsetBy(dx: point.x - start.x, dy: 0)
                if tableDragGhost == nil {
                    let ghost = TableDragGhostView(image: image)
                    addSubview(ghost)
                    tableDragGhost = ghost
                }
                tableDragGhost?.frame = frame.insetBy(dx: -TableDragGhostView.margin, dy: -TableDragGhostView.margin)
            }
            setNeedsDisplay(zone.insetBy(dx: -40, dy: -40))
        }
        tableDragGhost?.removeFromSuperview()
        tableDragGhost = nil
        tableDrag = nil
        setNeedsDisplay(zone.insetBy(dx: -40, dy: -40))
        return moved ? last : nil
    }

    /// What's drawn in a part of the view, to drag about.
    private func snapshot(of rect: CGRect) -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// Changes the table that starts at `location`, then puts the cursor in the cell `change`
    /// returns, or, if none, leaves it where it was.
    private func changeTable(at location: Int, _ change: (inout MarkdownTable) -> TableCell?) {
        guard let (token, lines) = renderedTable(at: location) else { return }
        var table = MarkdownTable(lines: lines, text: string as NSString)
        let before = table
        let cell = change(&table)
        guard table != before else { return }
        let selection = selectedRange()
        let inside = selection.location >= token.range.location && NSMaxRange(selection) <= NSMaxRange(token.range)
        let length = (string as NSString).length
        keepingScrollPosition {
            rewriteTable(token, as: table, selecting: cell ?? (inside ? tableCell(at: selection.location, in: lines) : nil))
            if cell == nil, !inside {
                // Text after the table moved with it.
                let shift = selection.location >= NSMaxRange(token.range) ? (string as NSString).length - length : 0
                setSelectionDirectly(NSRange(location: selection.location + shift, length: selection.length))
            }
        }
    }
}
#endif
