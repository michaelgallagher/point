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

@MainActor
struct TableDisplayTests {
    @Test func pipesAndTheDelimiterRowAreHidden() {
        let view = editor("Before\n\n¦ Name ¦ Qty ¦\n¦ :--- ¦ --: ¦\n¦ Tea ¦ 2 ¦\n\nAfter")
        let text = view.string as NSString
        for k in 0..<text.length where text.character(at: k) == 124 || text.character(at: k) == 45 {
            #expect(view.isHidden(k), "character \(k) shows")
        }
        #expect(view.collapsedLine(containing: text.range(of: ":---").location) != nil)
    }

    @Test func cellsLineUpInColumns() {
        let view = editor("¦ Name ¦ Qty ¦ Note ¦\n¦ --- ¦ --: ¦ :-: ¦\n¦ Green tea ¦ 12 ¦ hot ¦\n¦ Milk ¦ 1234 ¦ a much longer note ¦")
        let layoutManager = view.layoutManager!, text = view.string as NSString
        func x(_ word: String) -> CGFloat { layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: text.range(of: word).location)).x }
        func right(_ word: String) -> CGFloat {
            let range = text.range(of: word)
            return layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: view.textContainer!).maxX
        }
        func centre(_ word: String) -> CGFloat {
            let range = text.range(of: word)
            return layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: view.textContainer!).midX
        }
        // Left-aligned (no alignment), right-aligned and centred.
        #expect(x("Name") == x("Green tea") && x("Green tea") == x("Milk"))
        #expect(abs(right("12") - right("1234")) < 1)
        #expect(abs(centre("hot") - centre("a much longer note")) < 1)
        #expect(x("Qty") > x("Green tea") + 60)
    }

    @Test func showingMarkdownShowsItAll() {
        let view = editor(table)
        view.showsMarkdown = true
        let text = view.string as NSString
        #expect((0..<text.length).allSatisfy { !view.isHidden($0) })
        #expect(view.renderedTable(at: 3) == nil)
    }

    @Test func aMalformedTableStaysMarkdown() {
        let view = editor("¦ a ¦ b ¦\n¦ - ¦\n¦ 1 ¦ 2 ¦")
        #expect(!view.isHidden(0))
    }
}

@MainActor
struct TableCursorTests {
    @Test func arrowsStepOverThePipes() {
        let view = editor("¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
        view.moveRight(nil)
        #expect(marked(view) == "¦ ab ¦ |cd ¦\n¦ - ¦ - ¦")
        view.moveLeft(nil)
        #expect(marked(view) == "¦ ab| ¦ cd ¦\n¦ - ¦ - ¦")
    }

    @Test func anEmptyCellHasAPlaceForTheCursor() {
        let view = editor("¦ a| ¦   ¦ b ¦\n¦ - ¦ - ¦ - ¦")
        view.moveRight(nil)
        #expect(marked(view) == "¦ a ¦ |  ¦ b ¦\n¦ - ¦ - ¦ - ¦")
        view.moveRight(nil)
        #expect(marked(view) == "¦ a ¦   ¦ |b ¦\n¦ - ¦ - ¦ - ¦")
    }

    @Test func pastTheLastCellIsTheNextLine() {
        let view = editor("¦ a ¦ b| ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
        view.moveRight(nil)
        #expect(marked(view) == "¦ a ¦ b ¦\n¦ - ¦ - ¦\n¦ |1 ¦ 2 ¦")
        view.moveLeft(nil)
        #expect(marked(view) == "¦ a ¦ b| ¦\n¦ - ¦ - ¦\n¦ 1 ¦ 2 ¦")
    }

    @Test func downStaysInTheColumn() {
        let view = editor("¦ alpha ¦ be|ta ¦\n¦ - ¦ - ¦\n¦ one ¦ two ¦")
        view.moveDown(nil)
        let location = view.selectedRange().location
        #expect(location > (view.string as NSString).range(of: "two").location - 1)
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

    @Test func aTypedPipeIsEscaped() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        view.insertText("|", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "| a\\| | b |\n| - | - |")
        // Still two cells.
        #expect(view.renderedTable(at: 0)?.lines[0].cells.count == 2)
    }

    @Test func pastedLinesBecomeOneLine() {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦")
        view.insertText("x\ny|z", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "| ax y\\|z | b |\n| - | - |")
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

    @Test func aTableOnlyMovedThroughIsLeftAlone() async {
        let view = editor("¦ a| ¦ b ¦\n¦ - ¦ - ¦\n\nAfter")
        view.moveRight(nil)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(view.string == "| a | b |\n| - | - |\n\nAfter")
    }
}
