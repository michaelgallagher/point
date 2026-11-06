#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Tables' grids, laid over their hidden Markdown (see `TableGridView`).
///
/// The note's text is the only copy of a table. A cell shows its stretch of the note, and what's
/// typed in it is typed into the note there, as typing in the note would be; the cell is then
/// updated from the note. The note's selection follows the cell's cursor, so the table commands
/// (Tab, Return, the menu) work on the note as they always have, and the cursor arriving in a
/// table's hidden text (an arrow key, undo, Find) goes on into the cell it's in.
extension MarkdownTextView {
    // MARK: Keeping the grids in step

    /// Brings the grids up to date once the edit or layout under way is done.
    func scheduleTableSync() {
        guard !isTableSyncQueued else { return }
        isTableSyncQueued = true
        DispatchQueue.main.async { [weak self] in self?.syncTableViews() }
    }

    /// Puts a grid over each table drawn as one, where its hidden text is laid out, showing the
    /// note's text for each cell.
    func syncTableViews() {
        isTableSyncQueued = false
        guard let storage = textStorage, let layoutManager, let container = textContainer, !isSyncingTables else { return }
        isSyncingTables = true
        defer { isSyncingTables = false }
        let text = storage.string as NSString
        var count = 0
        for token in tokens where token.kind == .table && !styler.showsMarkdown && token.range.length > 0 && NSMaxRange(token.range) <= text.length {
            guard case .table(let decoration)? = storage.attribute(.pointBlock, at: token.range.location, effectiveRange: nil) as? BlockDecoration,
                  let lines = MarkdownTable.lines(in: text, range: token.range) else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: token.range.location)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let grid: TableGridView
            if count < tableGrids.count {
                grid = tableGrids[count]
            } else {
                grid = TableGridView(editor: self)
                addSubview(grid)
                tableGrids.append(grid)
            }
            count += 1
            let origin = textContainerOrigin
            let frame = CGRect(x: origin.x + container.lineFragmentPadding, y: origin.y + line.minY,
                               width: decoration.width, height: decoration.height)
            if grid.frame != frame { grid.frame = frame }
            let contents = tableRows(lines).map { row in
                row.cells.enumerated().map { column, cell in
                    (range: cell, text: styler.tableCellText(cell, in: storage, alignment: decoration.alignments[min(column, decoration.alignments.count - 1)]))
                }
            }
            grid.update(range: token.range, decoration: decoration, contents: contents, styler: styler, selection: selectedRange())
        }
        while tableGrids.count > count {
            let grid = tableGrids.removeLast()
            if let cell = window?.firstResponder as? TableCellView, cell.isDescendant(of: grid) { window?.makeFirstResponder(self) }
            grid.removeFromSuperview()
        }
        syncImageViews()
    }

    /// The grid of the table holding `location`, and the view for one of its cells.
    private func tableCellView(in tableStart: Int, _ cell: TableCell) -> TableCellView? {
        guard let grid = tableGrids.first(where: { $0.range.location == tableStart }), cell.row < grid.cells.count,
              cell.column < grid.cells[cell.row].count else { return nil }
        return grid.cells[cell.row][cell.column]
    }

    /// The cell views of the table the keyboard is in, if it's in one of this note's.
    var focusedTableCell: TableCellView? {
        guard let cell = window?.firstResponder as? TableCellView, cell.isDescendant(of: self) else { return nil }
        return cell
    }

    // MARK: The keyboard going in and out

    /// Once the selection has moved into a table's hidden text (and not from one of its cells),
    /// the keyboard goes to the cell it's in; once it's moved out, from a cell, it comes back.
    func followSelectionIntoTable() {
        guard !isMirroringCellSelection, !isSyncingTables, !hasMultipleCursors else { return }
        let selection = selectedRange()
        // A selection across cells stays in the note, to delete or copy them all.
        guard let (token, lines) = renderedTable(at: selection.location), selection.location >= token.range.location,
              NSMaxRange(selection) <= NSMaxRange(token.range), let found = tableCell(at: selection.location, in: lines),
              selection.length == 0 || NSLocationInRange(selection.location, tableRows(lines)[found.row].cells[found.column])
                && NSMaxRange(selection) <= NSMaxRange(tableRows(lines)[found.row].cells[found.column]) else {
            if focusedTableCell != nil { window?.makeFirstResponder(self) }
            return
        }
        // Not while the text is being changed, when it can't be laid out.
        guard textStorage?.editedMask.isEmpty != false else {
            DispatchQueue.main.async { [weak self] in self?.followSelectionIntoTable() }
            return
        }
        syncTableViews()
        var cell = found
        // Arriving by an arrow key: at the row it came to, in the column under the cursor.
        if let entry = tableEntry, let grid = tableGrids.first(where: { $0.range.location == token.range.location }), !grid.cells.isEmpty {
            cell.row = entry.fromAbove ? 0 : grid.cells.count - 1
            let edges = grid.decoration.columnEdges.dropLast()
            cell.column = min(edges.lastIndex { grid.frame.minX + $0 <= entry.x } ?? 0, grid.cells[cell.row].count - 1)
            tableEntry = nil
            guard let view = tableCellView(in: token.range.location, cell) else { return }
            view.setSelectedRange(NSRange(location: entry.fromAbove ? 0 : view.string.utf16.count, length: 0))
            if window?.firstResponder !== view { window?.makeFirstResponder(view) }
            return
        }
        guard let view = tableCellView(in: token.range.location, cell) else { return }
        let start = min(max(selection.location - view.range.location, 0), view.string.utf16.count)
        let end = min(max(NSMaxRange(selection) - view.range.location, start), view.string.utf16.count)
        view.setSelectedRange(NSRange(location: start, length: end - start))
        // The keyboard goes to the cell only from the note or another cell: not from the Find
        // bar, say, whose match is then shown selected in the cell.
        if window?.firstResponder === self || focusedTableCell != nil {
            if window?.firstResponder !== view { window?.makeFirstResponder(view) }
        } else {
            view.needsDisplay = true
        }
        view.scrollRangeToVisible(view.selectedRange())
    }

    public override func moveDown(_ sender: Any?) {
        enteringTable(fromAbove: true) { super.moveDown(sender) }
    }

    public override func moveUp(_ sender: Any?) {
        enteringTable(fromAbove: false) { super.moveUp(sender) }
    }

    /// Moves up or down; arriving in a table, the cursor goes to its first row (from above) or
    /// its last (from below), in the column under it, not wherever its hidden text lands.
    private func enteringTable(fromAbove: Bool, _ move: () -> Void) {
        let location = selectedRange().location
        guard let layoutManager, location <= (string as NSString).length, !tokens.allSatisfy({ $0.kind != .table }) else { return move() }
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        var x = textContainerOrigin.x
        if glyph < layoutManager.numberOfGlyphs {
            x += layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + layoutManager.location(forGlyphAt: glyph).x
        } else {
            x += layoutManager.extraLineFragmentRect.minX
        }
        tableEntry = (fromAbove, x)
        move()
        tableEntry = nil
    }

    /// Puts the cursor in a cell, `offset` into its text.
    func focus(_ cell: TableCellView, at offset: Int) {
        setSelectionDirectly(NSRange(location: cell.range.location + min(offset, cell.range.length), length: 0))
    }

    func cellDidTakeFocus(_ cell: TableCellView) {
        // The columns stay as wide as they are while the table's typed in.
        if let grid = cell.grid, styler.heldTableWidths?.table != grid.range.location {
            styler.heldTableWidths = (grid.range.location, grid.decoration.columnWidths)
        }
        cellSelectionChanged(cell)
    }

    /// The keyboard back in the note: the table it was in fits its columns to its text again.
    func leftTableCell() {
        guard styler.heldTableWidths != nil else { return }
        styler.heldTableWidths = nil
        restyleTables()
    }

    /// The note's selection follows the cell's.
    func cellSelectionChanged(_ cell: TableCellView) {
        guard !isSyncingTables else { return }
        let local = cell.selectedRange()
        let selection = NSRange(location: cell.range.location + local.location, length: local.length)
        // Setting it again as it is would end the undo step that typing builds up.
        guard selection != selectedRange() else { return }
        isMirroringCellSelection = true
        defer { isMirroringCellSelection = false }
        setSelectionDirectly(selection)
    }

    // MARK: Typing in a cell

    /// What's typed in a cell is typed into the note, at the same place. A pipe or line break
    /// typed or pasted is escaped, or made a space (see `insertText`), and then the cell takes
    /// the note's text instead of what was typed.
    func cellWillChange(_ cell: TableCellView, replacing range: NSRange, with string: String?) -> Bool {
        guard let string else { return true } // Only how it looks.
        let target = NSRange(location: cell.range.location + range.location, length: range.length)
        // Into a style held at the cursor: the cell shows the note's text once it has the markers.
        if typeForStyles(string, at: target) {
            syncTableViews()
            followSelectionIntoTable()
            // Just after what's typed, inside the markers, which the cell's cursor would otherwise step over.
            if let cell = focusedTableCell { cell.placeCursor(at: selectedRange().location - cell.range.location) }
            return false
        }
        do {
            isMirroringCellSelection = true
            defer { isMirroringCellSelection = false }
            insertText(string, replacementRange: target)
        }
        guard MarkdownTable.cellText(string) == string else {
            syncTableViews()
            followSelectionIntoTable()
            return false
        }
        return true
    }

    func cellDidChange(_ cell: TableCellView) {
        syncTableViews()
    }

    /// Tab, Shift-Tab and Return in a cell, as in the note's table.
    func cellCommand(_ cell: TableCellView, _ move: TableMove) {
        cellSelectionChanged(cell)
        if !moveInTable(move) { NSSound.beep() }
    }

    enum CellExit { case up, down, left, right }

    /// Puts the cursor at the start of the line after a table, adding the line if the table
    /// ends the note, so there's always somewhere to type below it.
    func moveBelowTable(_ table: NSRange) {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: NSMaxRange(table), length: 0))
        if NSMaxRange(line) > NSMaxRange(table) {
            setSelectedRange(NSRange(location: NSMaxRange(line), length: 0))
        } else {
            let ending = text.substring(with: table).contains("\r\n") ? "\r\n" : "\n"
            replace(NSRange(location: NSMaxRange(table), length: 0), with: ending)
        }
        window?.makeFirstResponder(self)
    }

    /// Puts the cursor at the end of the line before a table, adding the line if the table
    /// starts the note (after any properties).
    func moveAboveTable(_ table: NSRange) {
        if table.location > bodyStart {
            setSelectedRange(NSRange(location: table.location - 1, length: 0))
        } else {
            let ending = (string as NSString).substring(with: table).contains("\r\n") ? "\r\n" : "\n"
            replace(NSRange(location: table.location, length: 0), with: ending, select: NSRange(location: table.location, length: 0))
        }
        window?.makeFirstResponder(self)
    }

    /// A click below a table that ends the note goes on the line after it (added if need be),
    /// not into the table's last cell, where its hidden text ends.
    func clickBelowTable(at point: NSPoint) -> Bool {
        let length = (string as NSString).length
        guard let grid = tableGrids.first(where: { NSMaxRange($0.range) == length }), point.y > grid.frame.maxY else { return false }
        moveBelowTable(grid.range)
        return true
    }

    /// An arrow key at a cell's edge: on to the cell beside it, or out of the table.
    func moveOutOfCell(_ cell: TableCellView, _ direction: CellExit) {
        guard let grid = cell.grid else { return }
        let rows = grid.cells
        let text = string as NSString
        /// Just before the table (the end of the line above), or just after (the start of the
        /// line below).
        func leave(below: Bool) {
            below ? moveBelowTable(grid.range) : moveAboveTable(grid.range)
        }
        func go(_ row: Int, _ column: Int, atEnd: Bool) {
            guard row >= 0, row < rows.count, !rows[row].isEmpty else { return leave(below: row >= rows.count) }
            let target = rows[row][min(column, rows[row].count - 1)]
            focus(target, at: atEnd ? target.range.length : 0)
        }
        switch direction {
        case .up: go(cell.row - 1, cell.column, atEnd: true)
        case .down: go(cell.row + 1, cell.column, atEnd: false)
        case .left:
            if cell.column > 0 { go(cell.row, cell.column - 1, atEnd: true) }
            else { go(cell.row - 1, Int.max, atEnd: true) }
        case .right:
            if cell.column + 1 < rows[cell.row].count { go(cell.row, cell.column + 1, atEnd: false) }
            else { go(cell.row + 1, 0, atEnd: false) }
        }
    }
}
#endif
