import Foundation
import Testing
@testable import MarkdownKit

/// The cells of each line, as strings.
private func cells(_ markdown: String) -> [[String]]? {
    let text = markdown as NSString
    return MarkdownTable.lines(in: text, range: NSRange(location: 0, length: text.length))?
        .map { $0.cells.map(text.substring(with:)) }
}

struct TableReadingTests {
    @Test func readsCellsAndAlignments() throws {
        let table = try #require(MarkdownTable("| Name | Qty | Note |\n| :--- | ---: | :-: |\n| Tea | 2 | hot |"))
        #expect(table.alignments == [.left, .right, .center])
        #expect(table.rows == [["Name", "Qty", "Note"], ["Tea", "2", "hot"]])
    }

    @Test func pipesAtTheEndsAreOptional() {
        #expect(cells("a | b\n--- | ---\n1 | 2") == [["a", "b"], ["---", "---"], ["1", "2"]])
        #expect(cells("| a | b\n|---|---\n| 1 | 2") == [["a", "b"], ["---", "---"], ["1", "2"]])
    }

    @Test func escapedPipesStayInTheirCell() {
        #expect(cells("| a \\| b | c |\n| - | - |\n| `x \\| y` | [[Note\\|alias]] |")
            == [["a \\| b", "c"], ["-", "-"], ["`x \\| y`", "[[Note\\|alias]]"]])
    }

    @Test func aPipeInCodeStillDividesCells() {
        // As GFM reads it: cells are split before code spans are found.
        #expect(cells("| `a|b` |\n| --- | --- |") == [["`a", "b`"], ["---", "---"]])
    }

    @Test func emptyCellsAreAfterTheirSpace() {
        let text = "|   | b ||\n| - | - | - |" as NSString
        let lines = MarkdownTable.lines(in: text, range: NSRange(location: 0, length: text.length))!
        #expect(lines[0].cells.map(\.location) == [2, 6, 9])
        #expect(lines[0].cells.map(\.length) == [0, 1, 0])
        #expect(lines[0].pipes == [0, 4, 8, 9])
        #expect(lines[1].isDelimiter)
    }

    @Test func notATableWithoutAMatchingDelimiterRow() {
        #expect(MarkdownTable("| a | b |\n| --- |\n| 1 | 2 |") == nil)
        #expect(MarkdownTable("| a | b |\n| --- | x |") == nil)
        #expect(MarkdownTable("| a |") == nil)
    }

    @Test func aLongRowWidensTheTableRatherThanLosingCells() throws {
        let table = try #require(MarkdownTable("| a |\n| - |\n| 1 | 2 |\n| 3 |"))
        #expect(table.rows == [["a", ""], ["1", "2"], ["3", ""]])
        #expect(table.alignments == [.none, .none])
    }

    @Test func crlfLineEndsAreLeftOutOfCells() {
        #expect(cells("| a | b |\r\n| - | - |\r\n| 1 | 2 |") == [["a", "b"], ["-", "-"], ["1", "2"]])
    }
}

struct TableWritingTests {
    @Test func padsEachColumnToItsWidestCell() throws {
        let table = try #require(MarkdownTable("|Name|Qty|\n|:-|-:|\n|Green tea|12|\n|Milk||"))
        #expect(table.markdown() == """
        | Name      | Qty |
        | :-------- | --: |
        | Green tea |  12 |
        | Milk      |     |
        """)
    }

    @Test func centredColumnsAreCentred() throws {
        let table = try #require(MarkdownTable("| Title |\n| :---: |\n| a |"))
        #expect(table.markdown() == "| Title |\n| :---: |\n|   a   |")
    }

    @Test func wideCharactersCountDouble() throws {
        let table = try #require(MarkdownTable("| 日本 | a |\n| - | - |\n| x | b |"))
        #expect(table.markdown() == "| 日本 | a   |\n| ---- | --- |\n| x    | b   |")
    }

    @Test func usesTheLineEndingGiven() throws {
        let table = try #require(MarkdownTable("| a |\n| - |"))
        #expect(table.markdown(lineEnding: "\r\n") == "| a   |\r\n| --- |")
    }

    /// Whatever the cells hold, writing a table and reading it back gives the same table.
    @Test(arguments: [
        "| a \\| b | **bold** |\n| --- | --- |\n| [link](https://example.com/a_b) | `code` |",
        "| [[Note\\|alias]] | ==mark== |\n| :-: | --: |\n| ~~gone~~ | #tag |",
        "| x |\n|---|\n| \\\\ |\n| ends with \\| |",
        "a | b\n- | -\n|",
        "| 😀 | é |\n| - | - |\n| 漢字 | ![](image.png) |",
    ])
    func roundTripsWithoutLoss(_ markdown: String) throws {
        let table = try #require(MarkdownTable(markdown))
        let written = table.markdown()
        #expect(MarkdownTable(written) == table)
        // And writing it again changes nothing.
        #expect(MarkdownTable(written)?.markdown() == written)
    }

    @Test func aWideTableIsntPadded() throws {
        let long = String(repeating: "word ", count: 16).trimmingCharacters(in: .whitespaces)
        let table = try #require(MarkdownTable("| a | b |\n| - | :-: |\n| \(long) | c |"))
        #expect(table.markdown() == "| a | b |\n| --- | :-: |\n| \(long) | c |")
        #expect(MarkdownTable(table.markdown()) == table)
    }

    @Test func longDashesAreWrittenNeatly() throws {
        // Dashes don't set widths: the table is written out padded to its cells, as any other.
        let table = try #require(MarkdownTable("| a | b |\n| ---------- | ------------------------------ |\n| 1 | 2 |"))
        #expect(table.markdown() == "| a   | b   |\n| --- | --- |\n| 1   | 2   |")
    }

    @Test func cellTextIsEscaped() {
        #expect(MarkdownTable.cellText("a|b\nc \\| d") == "a\\|b c \\| d")
    }
}

struct TableShapeTests {
    @Test func addsAndRemovesRowsAndColumns() throws {
        var table = try #require(MarkdownTable("| a | b |\n| :- | -: |\n| 1 | 2 |"))
        table.insertRow(at: 1)
        #expect(table.rows == [["a", "b"], ["", ""], ["1", "2"]])
        table.insertColumn(at: 1)
        #expect(table.rows == [["a", "", "b"], ["", "", ""], ["1", "", "2"]])
        #expect(table.alignments == [.left, .none, .right])
        table.removeColumn(at: 0)
        #expect(table.rows == [["", "b"], ["", ""], ["", "2"]])
        table.removeRow(at: 1)
        #expect(table.rows == [["", "b"], ["", "2"]])
    }

    @Test func movesRowsAndColumns() throws {
        var table = try #require(MarkdownTable("| a | b | c |\n| :- | - | -: |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |"))
        table.moveRow(from: 2, to: 1)
        #expect(table.rows == [["a", "b", "c"], ["4", "5", "6"], ["1", "2", "3"]])
        table.moveRow(from: 1, to: 0)
        #expect(table.rows[0] == ["a", "b", "c"])
        table.moveColumn(from: 0, to: 2)
        #expect(table.rows == [["b", "c", "a"], ["5", "6", "4"], ["2", "3", "1"]])
        #expect(table.alignments == [.none, .right, .left])
    }

    @Test func theHeaderRowAndLastColumnStay() throws {
        var table = try #require(MarkdownTable("| a |\n| - |"))
        table.removeRow(at: 0)
        table.removeColumn(at: 0)
        #expect(table.rows == [["a"]])
        table.insertRow(at: 0)
        #expect(table.rows == [["a"], [""]])
    }

    @Test func aBlankTable() {
        #expect(MarkdownTable.blank(columns: 2, bodyRows: 1).markdown() == """
        | Column 1 | Column 2 |
        | -------- | -------- |
        |          |          |
        """)
    }
}
