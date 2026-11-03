import AppKit
import Testing
@testable import EditorKit

/// An editor holding `markdown`, with the cursor at `|` or the selection between `‹` and `›`.
/// (Cells' own pipes are written `¦` here, so they can't be taken for the cursor.)
@MainActor
private func editor(_ marked: String, width: CGFloat = 760) -> MarkdownTextView {
    var text = marked
    var selection = NSRange(location: 0, length: 0)
    if let bar = text.range(of: "|") {
        selection.location = (String(text[..<bar.lowerBound]) as NSString).length
        text.removeSubrange(bar)
    } else if let open = text.range(of: "‹"), let close = text.range(of: "›") {
        let start = (String(text[..<open.lowerBound]) as NSString).length
        let end = (String(text[..<close.lowerBound]) as NSString).length - 1
        text.removeSubrange(close)
        text.removeSubrange(open)
        selection = NSRange(location: start, length: end - start)
    }
    let view = EditorTestSupport.makeEditor(text.replacingOccurrences(of: "¦", with: "|"), width: width, height: 500)
    view.window?.makeFirstResponder(view) // As in the app, where the note has the keyboard.
    view.setSelectionDirectly(selection)
    return view
}

/// The editor's text with the selection marked the same way.
@MainActor
private func marked(_ view: MarkdownTextView) -> String {
    let text = NSMutableString(string: view.string.replacingOccurrences(of: "|", with: "¦"))
    let selection = view.selectedRange()
    if selection.length == 0 {
        text.insert("|", at: selection.location)
    } else {
        text.insert("›", at: NSMaxRange(selection))
        text.insert("‹", at: selection.location)
    }
    return text as String
}

private let table = "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦"

/// What the keys go to: the table cell being typed in, or the note.
@MainActor
private func keys(_ view: MarkdownTextView) -> NSTextView {
    view.focusedTableCell ?? view
}

/// The first table's grid, brought up to date.
@MainActor
private func grid(_ view: MarkdownTextView) -> TableGridView {
    view.syncTableViews()
    return view.tableGrids[0]
}

/// Where a word in a cell is drawn, in its table's grid.
@MainActor
private func rect(of word: String, in cell: TableCellView) -> CGRect {
    let range = (cell.string as NSString).range(of: word)
    let layoutManager = cell.layoutManager!
    let box = layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: cell.textContainer!)
    return box.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY)
}

@MainActor
struct TableDisplayTests {
    @Test func aTableIsDrawnByAGridOverItsHiddenText() {
        let view = editor("Before\n\n¦ Name ¦ Qty ¦\n¦ :--- ¦ --: ¦\n¦ Tea ¦ 2 ¦\n\nAfter")
        let text = view.string as NSString, storage = view.textStorage!
        let table = NSRange(location: text.range(of: "| Name").location, length: text.range(of: "2 |").location + 3 - text.range(of: "| Name").location)
        for k in table.location..<NSMaxRange(table) {
            #expect(PointLayoutManager.hiddenRun(at: k, in: storage) != nil, "character \(k) shows")
        }
        let grid = grid(view)
        #expect(grid.cells.map(\.count) == [2, 2])
        #expect(grid.cells[1][0].string == "Tea")
        // The text after the table starts below the grid.
        let layoutManager = view.layoutManager!
        let after = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: text.range(of: "After").location), effectiveRange: nil)
        #expect(after.minY + view.textContainerOrigin.y >= grid.frame.maxY)
        view.load("Just text")
        view.syncTableViews()
        #expect(view.tableGrids.isEmpty)
    }

    @Test func theHeaderIsBold() {
        let view = editor(table)
        let font = grid(view).cells[0][0].textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func cellsLineUpInColumns() {
        let view = editor("¦ Name ¦ Qty ¦ Note ¦\n¦ --- ¦ --: ¦ :-: ¦\n¦ Green tea ¦ 12 ¦ hot ¦\n¦ Milk ¦ 1234 ¦ a much longer note ¦")
        let cells = grid(view).cells
        // Left-aligned (no alignment), right-aligned and centred.
        #expect(rect(of: "Name", in: cells[0][0]).minX == rect(of: "Green tea", in: cells[1][0]).minX)
        #expect(rect(of: "Green tea", in: cells[1][0]).minX == rect(of: "Milk", in: cells[2][0]).minX)
        #expect(abs(rect(of: "12", in: cells[1][1]).maxX - rect(of: "1234", in: cells[2][1]).maxX) < 1)
        #expect(abs(rect(of: "hot", in: cells[1][2]).midX - rect(of: "a much longer note", in: cells[2][2]).midX) < 1)
        #expect(rect(of: "Qty", in: cells[0][1]).minX > rect(of: "Green tea", in: cells[1][0]).maxX)
    }

    @Test func aLongCellWrapsInItsColumn() {
        let view = editor("¦ Item ¦ Note ¦\n¦ --- ¦ --- ¦\n¦ Tea ¦ one two three four five six seven eight nine ten eleven twelve ¦\n¦ Milk ¦ 2 ¦", width: 320)
        let grid = grid(view), cells = grid.cells
        // The note goes on down its column, beside the item, and the next row starts below it.
        #expect(rect(of: "twelve", in: cells[1][1]).minY > rect(of: "one", in: cells[1][1]).maxY)
        #expect(grid.frame.maxX < view.bounds.width)
        #expect(abs(rect(of: "Tea", in: cells[1][0]).minY - rect(of: "one", in: cells[1][1]).minY) < 1)
        #expect(rect(of: "Milk", in: cells[2][0]).minY > rect(of: "twelve", in: cells[1][1]).maxY)
    }

    @Test func typingDoesntMoveTheColumns() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1| ¦ 2 ¦")
        let edges = grid(view).decoration.columnEdges
        keys(view).insertText(" and a good deal more", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string.contains("| 1 and a good deal more |"))
        #expect(grid(view).decoration.columnEdges == edges)
        // Back in the note, the columns fit the text again.
        view.window?.makeFirstResponder(view)
        #expect(grid(view).decoration.columnEdges != edges)
    }

    @Test func showingMarkdownShowsItAll() {
        let view = editor(table)
        view.showsMarkdown = true
        let text = view.string as NSString
        #expect((0..<text.length).allSatisfy { !view.isHidden($0) })
        #expect(view.renderedTable(at: 3) == nil)
        view.syncTableViews()
        #expect(view.tableGrids.isEmpty)
    }

    @Test func aMalformedTableStaysMarkdown() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦\n¦ 1 ¦ 2 ¦")
        #expect(!view.isHidden(0))
        view.syncTableViews()
        #expect(view.tableGrids.isEmpty)
    }
}

@MainActor
struct TableCursorTests {
    @Test func theKeysGoToTheCellTheCursorIsIn() {
        let view = editor("¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
        let cell = try! #require(view.focusedTableCell)
        #expect(cell.string == "ab" && cell.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func arrowsStepOverThePipes() {
        let view = editor("¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
        keys(view).moveRight(nil)
        #expect(marked(view) == "¦ ab ¦ |cd ¦\n¦ - ¦ - ¦")
        keys(view).moveLeft(nil)
        #expect(marked(view) == "¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
    }

    @Test func anEmptyCellHasAPlaceForTheCursor() {
        let view = editor("¦ a| ¦   ¦ b ¦\n¦ - ¦ - ¦ - ¦")
        keys(view).moveRight(nil)
        #expect(marked(view) == "¦ a ¦ |  ¦ b ¦\n¦ - ¦ - ¦ - ¦")
        keys(view).moveRight(nil)
        #expect(marked(view) == "¦ a ¦   ¦ |b ¦\n¦ - ¦ - ¦ - ¦")
    }

    @Test func pastTheLastCellIsTheNextLine() {
        let view = editor("¦ a ¦ b| ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        keys(view).moveRight(nil)
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ |1 ¦ 2 ¦")
        keys(view).moveLeft(nil)
        #expect(marked(view) == "¦ a ¦ b| ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
    }

    @Test func downStaysInTheColumn() {
        let view = editor("¦ alpha ¦ be|ta ¦\n¦ - ¦ - ¦\n¦ one ¦ two ¦")
        keys(view).moveDown(nil)
        #expect(marked(view) == "¦ alpha ¦ beta ¦\n¦ - ¦ - ¦\n¦ one ¦ |two ¦")
    }

    @Test func upAndDownGoInAndOutOfTheTable() {
        let view = editor("Before|\n¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦\nAfter")
        view.moveDown(nil)
        #expect(view.focusedTableCell != nil)
        keys(view).moveUp(nil)
        #expect(view.focusedTableCell == nil)
        #expect(marked(view).hasPrefix("Before|"))
        view.setSelectionDirectly((view.string as NSString).range(of: "2"))
        keys(view).moveDown(nil)
        keys(view).moveDown(nil)
        #expect(view.focusedTableCell == nil)
        #expect(marked(view).hasSuffix("|After"))
    }

    @Test func belowATableThatEndsTheNoteIsANewLine() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2| ¦")
        keys(view).moveDown(nil)
        #expect(view.focusedTableCell == nil)
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦\n|")
    }

    @Test func typingAfterATablesLastPipeGoesBelowIt() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦|")
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\nx|")
        let middle = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦|\nafter")
        middle.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(middle) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\nx|after")
    }

    @Test func aboveATableThatStartsTheNoteIsANewLine() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        keys(view).moveUp(nil)
        #expect(view.focusedTableCell == nil)
        #expect(marked(view) == "|\n¦ a ¦ b ¦\n¦ - ¦ - ¦")
    }

    @Test func clickingBelowATableThatEndsTheNoteGoesBelowIt() {
        let view = editor("Before|\n\n¦ a ¦ b ¦\n¦ - ¦ - ¦")
        let grid = grid(view)
        #expect(view.clickBelowTable(at: NSPoint(x: grid.frame.midX, y: grid.frame.maxY + 30)))
        #expect(marked(view) == "Before\n\n¦ a ¦ b ¦\n¦ - ¦ - ¦\n|")
        #expect(!view.clickBelowTable(at: NSPoint(x: grid.frame.midX, y: grid.frame.maxY + 30)))
    }

    @Test func theLineAfterATableAtTheEndOfTheNoteIsFullHeight() {
        let view = editor("Before|\n\n¦ a ¦ b ¦\n¦ - ¦ - ¦\n")
        let grid = grid(view)
        let below = NSPoint(x: grid.frame.midX, y: grid.frame.maxY + 10)
        #expect(!view.clickBelowTable(at: below))
        #expect(view.characterIndexForInsertion(at: below) == (view.string as NSString).length)
        // The empty last line is as tall as a line of text, so the cursor can be seen there.
        #expect(view.layoutManager!.extraLineFragmentRect.height > 10)
    }

    @Test func theCursorStepsOverHiddenMarkersInACell() throws {
        let view = editor("¦ |**bold** ¦ b ¦\n¦ - ¦ - ¦")
        let cell = try #require(view.focusedTableCell)
        #expect(cell.selectedRange().location == 2) // After the hidden `**`.
        cell.moveRight(nil)
        #expect(cell.selectedRange().location == 3)
        cell.moveLeft(nil)
        #expect(cell.selectedRange().location == 0)
        // With only hidden markers before it, it's at the start: left leaves the table.
        cell.moveLeft(nil)
        #expect(view.focusedTableCell == nil)
    }

    @Test func aMatchFoundInACellDoesntTakeTheKeyboard() {
        let view = editor("Before|\n\n¦ a ¦ needle ¦\n¦ - ¦ - ¦")
        view.window?.makeFirstResponder(nil)
        view.setSelectedRange((view.string as NSString).range(of: "needle"))
        #expect(view.focusedTableCell == nil)
        #expect(grid(view).cells[0][1].selectedRange() == NSRange(location: 0, length: 6))
    }

    @Test func undoPutsTheCellBack() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1| ¦ 2 ¦")
        keys(view).insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(grid(view).cells[1][0].string == "1x")
        view.undoManager?.undo()
        #expect(view.string == "| a | b |\n| - | - |\n| 1 | 2 |")
        #expect(grid(view).cells[1][0].string == "1")
    }
}

@MainActor
struct TableEditingTests {
    @Test func deleteAtTheStartOfACellLeavesThePipe() {
        let view = editor("¦ a ¦ |b ¦\n¦ - ¦ - ¦")
        view.deleteBackward(nil)
        #expect(marked(view) == "¦ a ¦ |b ¦\n¦ - ¦ - ¦")
        let first = editor("¦ |a ¦ b ¦\n¦ - ¦ - ¦")
        first.deleteBackward(nil)
        #expect(marked(first) == "¦ |a ¦ b ¦\n¦ - ¦ - ¦")
    }

    @Test func forwardDeleteAtTheEndOfACellLeavesThePipe() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        view.deleteForward(nil)
        #expect(view.string == "| a | b |\n| - | - |")
    }

    @Test func deleteInACellDeletesText() {
        let view = editor("¦ ab| ¦ c ¦\n¦ - ¦ - ¦")
        view.deleteBackward(nil)
        #expect(marked(view) == "¦ a| ¦ c ¦\n¦ - ¦ - ¦")
    }

    @Test func deleteAfterATableDoesntJoinTheLineToIt() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦\n|more")
        view.deleteBackward(nil)
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2| ¦\nmore")
    }

    @Test func deletingAcrossCellsKeepsThePipes() {
        let view = editor("¦ a‹b ¦ cd ¦ e›f ¦\n¦ - ¦ - ¦ - ¦")
        view.deleteBackward(nil)
        #expect(marked(view) == "¦ a| ¦  ¦ f ¦\n¦ - ¦ - ¦ - ¦")
    }

    @Test func typingOverCellsGoesInTheFirst() {
        let view = editor("¦ a‹b ¦ c›d ¦\n¦ - ¦ - ¦")
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(view) == "¦ ax| ¦ d ¦\n¦ - ¦ - ¦")
    }

    @Test func aSpaceStaysInTheCell() {
        let view = editor("¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
        keys(view).insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(view) == "¦ ab | ¦ cd ¦\n¦ - ¦ - ¦")
        keys(view).insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(view) == "¦ ab x| ¦ cd ¦\n¦ - ¦ - ¦")
        #expect(view.focusedTableCell?.string == "ab x")
    }

    @Test func aSpaceInAnEmptyCellStaysThere() {
        let view = editor("¦ a ¦ | ¦\n¦ - ¦ - ¦")
        keys(view).insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(marked(view) == "¦ a ¦  | ¦\n¦ - ¦ - ¦")
    }

    @Test func aTypedPipeIsEscaped() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        keys(view).insertText("|", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "| a\\| | b |\n| - | - |")
        #expect(view.focusedTableCell?.string == "a\\|")
        #expect(view.focusedTableCell?.selectedRange() == NSRange(location: 3, length: 0))
        // Still two cells.
        #expect(view.renderedTable(at: 0)?.lines[0].cells.count == 2)
    }

    @Test func pastedLinesBecomeOneLine() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        view.insertText("x\ny|z", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "| ax y\\|z | b |\n| - | - |")
    }

    @Test func aHeldStyleInAnEmptyCell() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ | ¦ y ¦")
        view.toggleBold(nil)
        #expect(view.string == "| a | b |\n| - | - |\n|  | y |")
        let cell = try! #require(view.focusedTableCell)
        cell.insertText("t", replacementRange: cell.selectedRange())
        let now = try! #require(view.focusedTableCell)
        now.insertText("o", replacementRange: now.selectedRange())
        #expect(view.string == "| a | b |\n| - | - |\n| **to** | y |")
    }

    @Test func boldInACell() {
        let view = editor("¦ ‹word› ¦ b ¦\n¦ - ¦ - ¦")
        view.toggleBold(nil)
        #expect(view.string == "| **word** | b |\n| - | - |")
    }
}

@MainActor
struct TableNavigationTests {
    @Test func tabSelectsTheNextCell() {
        let view = editor("¦ a| ¦ bc ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        view.insertTab(nil)
        #expect(marked(view) == "¦ a ¦ ‹bc› ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        view.insertTab(nil)
        #expect(marked(view) == "¦ a ¦ bc ¦\n¦ - ¦ - ¦\n¦ ‹1› ¦ 2 ¦")
        view.insertBacktab(nil)
        #expect(marked(view) == "¦ a ¦ ‹bc› ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
    }

    @Test func tabFromTheLastCellAddsARow() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2| ¦\n\nAfter")
        view.insertTab(nil)
        #expect(marked(view) == "¦ a   ¦ b   ¦\n¦ --- ¦ --- ¦\n¦ 1   ¦ 2   ¦\n¦ |    ¦     ¦\n\nAfter")
        view.undoManager?.undo()
        #expect(view.string == "| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter")
    }

    @Test func returnGoesDownAndAddsARow() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        view.insertNewline(nil)
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1| ¦ 2 ¦")
        view.insertNewline(nil)
        #expect(marked(view) == "¦ a   ¦ b   ¦\n¦ --- ¦ --- ¦\n¦ 1   ¦ 2   ¦\n¦ |    ¦     ¦")
    }

    @Test func returnOnAnEmptyLastRowLeavesTheTable() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ | ¦ ¦\nnext")
        view.insertNewline(nil)
        #expect(marked(view) == "¦ a   ¦ b   ¦\n¦ --- ¦ --- ¦\n|\nnext")
    }

    @Test func returnOnAnEmptyLastRowAtTheEnd() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ | ¦ ¦")
        view.insertNewline(nil)
        #expect(marked(view) == "¦ a   ¦ b   ¦\n¦ --- ¦ --- ¦\n|")
    }
}

@MainActor
struct TableCommandTests {
    @Test func rowsAndColumns() {
        let view = editor("¦ a ¦ b ¦\n¦ :- ¦ -: ¦\n¦ 1| ¦ 2 ¦")
        view.insertTableRowAbove(nil)
        #expect(view.string == "| a   |   b |\n| :-- | --: |\n|     |     |\n| 1   |   2 |")
        view.deleteTableRow(nil)
        #expect(view.string == "| a   |   b |\n| :-- | --: |\n| 1   |   2 |")
        view.insertTableColumnRight(nil)
        #expect(view.string == "| a   |     |   b |\n| :-- | --- | --: |\n| 1   |     |   2 |")
        view.deleteTableColumn(nil)
        #expect(view.string == "| a   |   b |\n| :-- | --: |\n| 1   |   2 |")
        view.alignTableColumnCentre(nil)
        #expect(view.string.hasPrefix("| a   |  b  |\n| :-- | :-: |"))
    }

    @Test func theHeaderRowCantBeDeleted() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        view.deleteTableRow(nil)
        #expect(view.string == "| a | b |\n| - | - |")
    }

    @Test func deleteTableTakesItsLine() {
        let view = editor("Before\n\n¦ a| ¦ b ¦\n¦ - ¦ - ¦\nAfter")
        view.deleteTable(nil)
        #expect(view.string == "Before\n\nAfter")
    }

    @Test func insertTableOnABlankLine() {
        let view = editor("Before\n|\nAfter")
        view.insertTable(nil)
        #expect(marked(view) == "Before\n\n¦ ‹Column 1› ¦ Column 2 ¦ Column 3 ¦\n¦ -------- ¦ -------- ¦ -------- ¦\n¦          ¦          ¦          ¦\n¦          ¦          ¦          ¦\n\nAfter")
    }

    @Test func insertTableAfterText() {
        let view = editor("Some te|xt")
        view.insertTable(nil)
        #expect(view.string.hasPrefix("Some text\n\n| Column 1 |"))
        #expect(view.renderedTable(at: view.selectedRange().location) != nil)
    }
}

@MainActor
struct TableNeateningTests {
    @Test func aTableTypedInIsWrittenNeatlyOnceLeft() async {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦\n\nAfter")
        view.insertText("bc", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "| abc | b |\n| - | - |\n\nAfter")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(marked(view) == "¦ abc ¦ b   ¦\n¦ --- ¦ --- ¦\n\nAfter|")
    }

    @Test func undoTakesBackTheTypingAndTheTidyingTogether() async {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦\n\nAfter")
        let window = view.window // Kept through the wait: the undo manager is the window's.
        view.insertText("bc", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(window != nil)
        #expect(view.string == "| abc | b   |\n| --- | --- |\n\nAfter")
        #expect(view.undoManager?.undoActionName == MarkdownTextView.tidyTableActionName)
        view.undo(nil)
        #expect(view.string == "| a | b |\n| - | - |\n\nAfter")
        view.redo(nil)
        #expect(view.string == "| abc | b   |\n| --- | --- |\n\nAfter")
        #expect(view.undoManager?.canRedo == false)
    }

    @Test func aTableOnlyMovedThroughIsLeftAlone() async {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦\n\nAfter")
        view.moveRight(nil)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(view.string == "| a | b |\n| - | - |\n\nAfter")
    }
}


@MainActor
struct TableControlsTests {
    /// Clicks a point in the view, after moving the pointer there.
    private func click(_ view: MarkdownTextView, at point: NSPoint, count: Int = 1) -> Bool {
        view.updateTableHover(at: point)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        return view.tableControlsMouseDown(event)
    }

    @Test func thePlusBelowAddsARow() throws {
        let view = editor("Before\n\n¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦\n\nAfter")
        let controls = try #require(view.tableControls(at: 10))
        #expect(click(view, at: NSPoint(x: controls.addRow.midX, y: controls.addRow.midY)))
        #expect(marked(view) == "Before\n\n¦ a   ¦ b   ¦\n¦ --- ¦ --- ¦\n¦ 1   ¦ 2   ¦\n¦ |    ¦     ¦\n\nAfter")
    }

    @Test func thePlusBesideAddsAColumn() throws {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        let controls = try #require(view.tableControls(at: 0))
        #expect(click(view, at: NSPoint(x: controls.addColumn.midX, y: controls.addColumn.midY)))
        #expect(view.string == "| a   | b   |     |\n| --- | --- | --- |\n| 1   | 2   |     |")
    }

    @Test func longDashesDontWidenTheColumns() throws {
        let long = editor("¦ a ¦ b ¦\n¦ ---------- ¦ -------------------- ¦\n¦ 1 ¦ 2 ¦")
        let short = editor("¦ a ¦ b ¦\n¦ --- ¦ --- ¦\n¦ 1 ¦ 2 ¦")
        #expect(try #require(long.tableControls(at: 0)).edges == (try #require(short.tableControls(at: 0))).edges)
    }

    @Test func clicksElsewhereAreLeftToTheText() throws {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        let controls = try #require(view.tableControls(at: 0))
        #expect(!click(view, at: NSPoint(x: (controls.edges[0] + controls.edges[1]) / 2, y: controls.rows[1].midY)))
    }
}



