#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Tables, drawn as tables while the Markdown is hidden (see `MarkdownStyler.layOutTable`).
///
/// Typing in a cell edits its Markdown directly, as anywhere else. The pipes and padding
/// between cells are hidden, so the cursor steps over them, and Delete never takes them:
/// a table's shape only changes through Tab, Return and the commands here, each of which
/// writes the whole table out again, neatly, as one undoable change. A table typed in is
/// written out neatly too, once the cursor leaves it; that is undone along with the typing.
extension MarkdownTextView {
    /// Where a cell is: its row (0 is the header; the delimiter row isn't counted) and column.
    struct TableCell: Equatable {
        var row: Int
        var column: Int
    }

    /// The table drawn at `location` (or just after it), and its lines.
    func renderedTable(at location: Int) -> (token: MarkdownToken, lines: [MarkdownTable.Line])? {
        guard styler.theme.rendersTables, !styler.showsMarkdown,
              let token = tokens.first(where: { $0.kind == .table && location >= $0.range.location && location <= NSMaxRange($0.range) }),
              let lines = MarkdownTable.lines(in: string as NSString, range: token.range) else { return nil }
        return (token, lines)
    }

    /// The rows of a table's lines, without the delimiter row.
    func tableRows(_ lines: [MarkdownTable.Line]) -> [MarkdownTable.Line] {
        lines.filter { !$0.isDelimiter }
    }

    private func rows(_ lines: [MarkdownTable.Line]) -> [MarkdownTable.Line] { tableRows(lines) }

    /// The cell holding `location`, or the nearest one on its row when it's between cells.
    func tableCell(at location: Int, in lines: [MarkdownTable.Line]) -> TableCell? {
        let rows = rows(lines)
        guard let row = rows.firstIndex(where: { location >= $0.range.location && location <= NSMaxRange($0.range) }) else { return nil }
        let cells = rows[row].cells
        let column = cells.firstIndex { location >= $0.location && location <= NSMaxRange($0) }
            ?? cells.lastIndex { $0.location <= location } ?? 0
        return TableCell(row: row, column: column)
    }

    // MARK: Keeping the shape

    /// Whether Delete at `location` would take a table's pipe or join a line to it: at the
    /// start of a cell, it does nothing; at the start of the line after a table, it goes to the
    /// end of the table's last cell instead.
    func keepsTableShape(deletingBackwardFrom location: Int) -> Bool {
        if let (_, lines) = renderedTable(at: location),
           rows(lines).contains(where: { $0.cells.contains { $0.location == location } }) {
            return true
        }
        let text = string as NSString
        guard location > 0, location <= text.length, text.character(at: location - 1) == 10 else { return false }
        let previous = text.lineRange(for: NSRange(location: location - 1, length: 0))
        guard renderedTable(at: location) == nil, let (_, lines) = renderedTable(at: previous.location),
              let cell = rows(lines).last?.cells.last else { return false }
        setSelectionDirectly(NSRange(location: NSMaxRange(cell), length: 0))
        return true
    }

    /// Whether Forward Delete at `location`, the end of a cell, would take the pipe after it.
    func keepsTableShape(deletingForwardFrom location: Int) -> Bool {
        guard let (_, lines) = renderedTable(at: location) else { return false }
        return rows(lines).contains { $0.cells.contains { NSMaxRange($0) == location } }
    }

    /// Deletes a selection that reaches across a table's cells (or replaces it with `typed`)
    /// without taking the pipes: only the cells' text goes, and what's typed goes into the
    /// first cell. False if the selection isn't within one table, or is within one cell.
    func deleteInTable(_ selection: NSRange, inserting typed: String = "") -> Bool {
        guard selection.length > 0, !hasMarkedText(), let (token, lines) = renderedTable(at: selection.location),
              NSMaxRange(selection) <= NSMaxRange(token.range) else { return false }
        let cells = rows(lines).flatMap(\.cells)
        if cells.contains(where: { selection.location >= $0.location && NSMaxRange(selection) <= NSMaxRange($0) }) { return false }
        let text = string as NSString
        let typed = MarkdownTable.cellText(typed)
        var replacement = "", cursor: Int?
        var k = selection.location
        let end = NSMaxRange(selection)
        for cell in cells where NSMaxRange(cell) >= selection.location && cell.location <= end {
            let start = max(cell.location, selection.location)
            if start > k { replacement += text.substring(with: NSRange(location: k, length: start - k)) }
            if cursor == nil {
                replacement += typed
                cursor = selection.location + (replacement as NSString).length
            }
            k = max(k, min(NSMaxRange(cell), end))
        }
        if k < end { replacement += text.substring(with: NSRange(location: k, length: end - k)) }
        replace(selection, with: replacement, select: NSRange(location: cursor ?? selection.location, length: 0))
        return true
    }

    // MARK: Moving between cells

    enum TableMove { case next, previous, down }

    /// Tab, Shift-Tab and Return in a table. Tab goes to the next cell, and from the last one
    /// adds a row; Shift-Tab goes back. Both select the cell's text, so typing replaces it.
    /// Return goes down a row, and from the last row adds one; on an empty last row, it removes
    /// the row and leaves the table. False if the cursor isn't in a table.
    func moveInTable(_ move: TableMove) -> Bool {
        let selection = selectedRange()
        guard !hasMultipleCursors, let (token, lines) = renderedTable(at: selection.location),
              NSMaxRange(selection) <= NSMaxRange(token.range),
              let cell = tableCell(at: selection.location, in: lines) else { return false }
        let rows = rows(lines)
        let text = string as NSString
        var table = MarkdownTable(lines: lines, text: text)
        func cellRange(_ target: TableCell) -> NSRange? {
            guard target.row < rows.count, target.column < rows[target.row].cells.count else { return nil }
            return rows[target.row].cells[target.column]
        }

        switch move {
        case .next, .previous:
            var target = cell
            if move == .next {
                target = cell.column + 1 < table.columnCount ? TableCell(row: cell.row, column: cell.column + 1)
                    : TableCell(row: cell.row + 1, column: 0)
            } else if cell.column > 0 {
                target.column -= 1
            } else if cell.row > 0 {
                target = TableCell(row: cell.row - 1, column: table.columnCount - 1)
            }
            if target.row == table.rows.count {
                table.insertRow(at: table.rows.count)
                return rewriteTable(token, as: table, selecting: target)
            }
            // A row short of cells has none to go to: written out, it has them all.
            guard let range = cellRange(target) else { return rewriteTable(token, as: table, selecting: target, selectingText: true) }
            setSelectionDirectly(range)
            return true

        case .down:
            if cell.row + 1 < table.rows.count {
                let target = TableCell(row: cell.row + 1, column: cell.column)
                guard let range = cellRange(target) else { return rewriteTable(token, as: table, selecting: target) }
                setSelectionDirectly(NSRange(location: NSMaxRange(range), length: 0))
                return true
            }
            if cell.row > 0, table.rows[cell.row].allSatisfy(\.isEmpty) {
                table.removeRow(at: cell.row)
                return leaveTable(token, as: table)
            }
            table.insertRow(at: table.rows.count)
            return rewriteTable(token, as: table, selecting: TableCell(row: cell.row + 1, column: cell.column))
        }
    }

    /// Writes a table out in place of `token`'s, neatly, as one undoable change, and puts the
    /// cursor at the end of a cell's text (or selects it).
    @discardableResult
    func rewriteTable(_ token: MarkdownToken, as table: MarkdownTable, selecting cell: TableCell?, selectingText: Bool = false) -> Bool {
        let text = string as NSString
        let old = text.substring(with: token.range)
        let new = table.markdown(lineEnding: old.contains("\r\n") ? "\r\n" : "\n")
        var selection = NSRange(location: token.range.location + (new as NSString).length, length: 0)
        if let cell, let lines = MarkdownTable.lines(in: new as NSString, range: NSRange(location: 0, length: (new as NSString).length)) {
            let rows = rows(lines)
            let row = min(cell.row, rows.count - 1), cells = rows[row].cells
            let range = cells[min(cell.column, cells.count - 1)]
            selection = selectingText ? NSRange(location: token.range.location + range.location, length: range.length)
                : NSRange(location: token.range.location + NSMaxRange(range), length: 0)
        }
        if new == old {
            setSelectionDirectly(selection)
            return true
        }
        isRewritingTable = true
        defer { isRewritingTable = false }
        return replace(token.range, with: new, select: selection)
    }

    /// Writes a table out and puts the cursor on an empty line below it.
    private func leaveTable(_ token: MarkdownToken, as table: MarkdownTable) -> Bool {
        let text = string as NSString
        let old = text.substring(with: token.range)
        let ending = old.contains("\r\n") ? "\r\n" : "\n"
        var new = table.markdown(lineEnding: ending)
        let after = NSMaxRange(token.range)
        let next = text.lineRange(for: NSRange(location: after, length: 0))
        var cursor: Int
        if after >= text.length {
            new += ending
            cursor = token.range.location + (new as NSString).length
        } else {
            let following = NSMaxRange(next) < text.length ? text.lineRange(for: NSRange(location: NSMaxRange(next), length: 0)) : nil
            if let following, text.substring(with: following).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Already a blank line below: onto it.
                cursor = token.range.location + (new as NSString).length + (NSMaxRange(next) - after)
            } else {
                new += ending
                cursor = token.range.location + (new as NSString).length
            }
        }
        isRewritingTable = true
        defer { isRewritingTable = false }
        return replace(token.range, with: new, select: NSRange(location: cursor, length: 0))
    }

    // MARK: Writing a table out neatly once it's left

    /// Notes the table an edit was made in (`location` is where), to write it out neatly once
    /// the cursor leaves it.
    func noteTableEdit(at location: Int) {
        guard !isRewritingTable, undoManager?.isUndoing != true, undoManager?.isRedoing != true,
              let (token, _) = renderedTable(at: location) else { return }
        editedTableStart = token.range.location
    }

    /// Once the cursor has left a table typed in, writes the table out neatly (soon after, not
    /// in the middle of the selection changing).
    func neatenTableIfLeft() {
        guard let start = editedTableStart, !isRewritingTable else { return }
        let location = selectedRange().location
        if let (token, _) = renderedTable(at: location), token.range.location == start { return }
        editedTableStart = nil
        DispatchQueue.main.async { [weak self] in self?.neatenTable(startingAt: start) }
    }

    private func neatenTable(startingAt start: Int) {
        guard let (token, lines) = renderedTable(at: start), token.range.location == start else { return }
        let selection = selectedRange()
        guard !NSLocationInRange(selection.location, token.range), selection.location != NSMaxRange(token.range) else { return }
        let text = string as NSString
        let old = text.substring(with: token.range)
        let new = MarkdownTable(lines: lines, text: text).markdown(lineEnding: old.contains("\r\n") ? "\r\n" : "\n")
        guard new != old else { return }
        isRewritingTable = true
        defer { isRewritingTable = false }
        applyEdit(replacing: token.range, with: new)
        undoManager?.setActionName(Self.tidyTableActionName)
    }

    // MARK: Undo

    /// The name of the undo step that writes a table out neatly once it's left. It changes
    /// nothing that shows, so it is undone and redone with the step before it.
    static let tidyTableActionName = "Tidy Table"

    /// Undo, taking back the edit before a table's tidying with it, so a step that changes
    /// nothing visible is never undone on its own.
    @objc func undo(_ sender: Any?) {
        guard let undoManager, undoManager.canUndo else { return NSSound.beep() }
        let tidied = undoManager.undoActionName == Self.tidyTableActionName
        undoManager.undo()
        if tidied, undoManager.canUndo { undoManager.undo() }
    }

    /// Redo, putting a table's tidying back with the edit before it.
    @objc func redo(_ sender: Any?) {
        guard let undoManager, undoManager.canRedo else { return NSSound.beep() }
        undoManager.redo()
        if undoManager.redoActionName == Self.tidyTableActionName { undoManager.redo() }
    }

    // MARK: Commands

    /// Puts in a table of three columns and two rows, on lines of its own, with its first
    /// header cell selected to type over.
    @objc public func insertTable(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        guard renderedTable(at: selection.location) == nil else { return NSSound.beep() }
        let table = MarkdownTable.blank(columns: 3, bodyRows: 2).markdown()
        func isBlank(_ range: NSRange) -> Bool {
            text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: NSMaxRange(selection), length: 0))
        let line = NSRange(location: start, length: contentsEnd - start)
        // A blank line before and after, so it isn't read as part of a paragraph beside it.
        let hasNext = end < text.length
        let nextIsBlank = hasNext && isBlank(text.lineRange(for: NSRange(location: end, length: 0)))
        let target: NSRange, prefix: String
        if isBlank(line) {
            target = line
            let previousIsBlank = start == 0 || isBlank(text.lineRange(for: NSRange(location: start - 1, length: 0)))
            prefix = previousIsBlank ? "" : "\n"
        } else {
            target = NSRange(location: contentsEnd, length: 0)
            prefix = "\n\n"
        }
        let suffix = hasNext && !nextIsBlank ? "\n" : ""
        // "Column 1", after the first `| `.
        let header = NSRange(location: target.location + (prefix as NSString).length + 2, length: 8)
        replace(target, with: prefix + table + suffix, select: header)
    }

    /// The table cell a command applies to: the one right-clicked, or the cursor's.
    private func commandTarget(_ sender: Any?) -> (token: MarkdownToken, lines: [MarkdownTable.Line], cell: TableCell)? {
        let location = (sender as? NSMenuItem)?.representedObject as? Int ?? selectedRange().location
        guard let (token, lines) = renderedTable(at: location), let cell = tableCell(at: location, in: lines) else { return nil }
        return (token, lines, cell)
    }

    /// Changes a table's shape, then puts the cursor in the cell that `change` returns.
    private func reshapeTable(_ sender: Any?, _ change: (inout MarkdownTable, TableCell) -> TableCell?) {
        guard let (token, lines, cell) = commandTarget(sender) else { return NSSound.beep() }
        var table = MarkdownTable(lines: lines, text: string as NSString)
        let before = table
        guard let target = change(&table, cell), table != before else { return NSSound.beep() }
        rewriteTable(token, as: table, selecting: target)
    }

    @objc public func insertTableRowAbove(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            guard cell.row > 0 else { return nil } // Nothing goes above the header.
            table.insertRow(at: cell.row)
            return cell
        }
    }

    @objc public func insertTableRowBelow(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            table.insertRow(at: cell.row + 1)
            return TableCell(row: cell.row + 1, column: cell.column)
        }
    }

    @objc public func insertTableColumnLeft(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            table.insertColumn(at: cell.column)
            return cell
        }
    }

    @objc public func insertTableColumnRight(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            table.insertColumn(at: cell.column + 1)
            return TableCell(row: cell.row, column: cell.column + 1)
        }
    }

    @objc public func deleteTableRow(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            table.removeRow(at: cell.row)
            return TableCell(row: min(cell.row, table.rows.count - 1), column: cell.column)
        }
    }

    @objc public func deleteTableColumn(_ sender: Any?) {
        reshapeTable(sender) { table, cell in
            table.removeColumn(at: cell.column)
            return TableCell(row: cell.row, column: min(cell.column, table.columnCount - 1))
        }
    }

    @objc public func alignTableColumnLeft(_ sender: Any?) { alignColumn(.left, sender) }
    @objc public func alignTableColumnCentre(_ sender: Any?) { alignColumn(.center, sender) }
    @objc public func alignTableColumnRight(_ sender: Any?) { alignColumn(.right, sender) }

    private func alignColumn(_ alignment: MarkdownTable.Alignment, _ sender: Any?) {
        reshapeTable(sender) { table, cell in
            // Choosing the alignment it has already takes it off.
            table.alignments[cell.column] = table.alignments[cell.column] == alignment ? .none : alignment
            return cell
        }
    }

    /// Removes the whole table, and the line break after it.
    @objc public func deleteTable(_ sender: Any?) {
        guard let (token, _, _) = commandTarget(sender) else { return NSSound.beep() }
        let text = string as NSString
        var range = token.range
        let after = NSMaxRange(text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0)))
        range.length = after - range.location
        replace(range, with: "", select: NSRange(location: range.location, length: 0))
    }

    /// Right-clicking a table offers to change its shape, before the usual items.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard let menu, let layoutManager, let textContainer else { return menu }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let location = layoutManager.characterIndexForPoint(NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: textContainer)
        return tableMenu(at: location, adding: menu)
    }

    /// The commands for the table cell at `location`, put before `menu`'s items (from a cell's
    /// own menu, or the note's).
    func tableMenu(at location: Int, adding menu: NSMenu) -> NSMenu {
        guard let (_, lines) = renderedTable(at: location), let cell = tableCell(at: location, in: lines) else { return menu }
        let table = MarkdownTable(lines: lines, text: string as NSString)
        let alignment = table.alignments[min(cell.column, table.columnCount - 1)]

        func item(_ title: String, _ action: Selector, enabled: Bool = true, on: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = location
            item.state = on ? .on : .off
            return item
        }
        let align = NSMenuItem(title: "Align Column", action: nil, keyEquivalent: "")
        align.submenu = NSMenu()
        align.submenu?.items = [
            item("Left", #selector(alignTableColumnLeft(_:)), on: alignment == .left),
            item("Centre", #selector(alignTableColumnCentre(_:)), on: alignment == .center),
            item("Right", #selector(alignTableColumnRight(_:)), on: alignment == .right),
        ]
        let items = [
            item("Insert Row Above", #selector(insertTableRowAbove(_:)), enabled: cell.row > 0),
            item("Insert Row Below", #selector(insertTableRowBelow(_:))),
            item("Insert Column Left", #selector(insertTableColumnLeft(_:))),
            item("Insert Column Right", #selector(insertTableColumnRight(_:))),
            .separator(),
            item("Delete Row", #selector(deleteTableRow(_:)), enabled: cell.row > 0),
            item("Delete Column", #selector(deleteTableColumn(_:)), enabled: table.columnCount > 1),
            item("Delete Table", #selector(deleteTable(_:))),
            .separator(),
            align,
            .separator(),
        ]
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }
}
#endif
