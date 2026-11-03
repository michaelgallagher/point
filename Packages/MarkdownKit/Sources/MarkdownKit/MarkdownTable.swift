import Foundation

/// A GFM pipe table: the Markdown in each cell, and each column's alignment.
///
/// Cells hold their Markdown exactly as written (an escaped pipe stays `\|`), only trimmed of
/// the spaces around it, so writing a table back loses nothing but its old padding.
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    public var alignments: [Alignment]
    /// The header row first, then the body rows. Every row has a cell for every column.
    public private(set) var rows: [[String]]

    public var columnCount: Int { alignments.count }

    public init(alignments: [Alignment], rows: [[String]]) {
        // A row with more cells than the header widens the table rather than losing them.
        let count = max(alignments.count, rows.map(\.count).max() ?? 0, 1)
        self.alignments = alignments + Array(repeating: .none, count: count - alignments.count)
        self.rows = (rows.isEmpty ? [[]] : rows).map { $0 + Array(repeating: "", count: count - $0.count) }
    }

    /// A table of empty cells, with "Column 1", "Column 2" and so on as its header.
    public static func blank(columns: Int, bodyRows: Int) -> MarkdownTable {
        let header = (1...max(columns, 1)).map { "Column \($0)" }
        return MarkdownTable(alignments: Array(repeating: .none, count: header.count),
                             rows: [header] + Array(repeating: Array(repeating: "", count: header.count), count: bodyRows))
    }

    /// Reads a whole table (header, delimiter row and body rows), or nil if it isn't one.
    public init?(_ markdown: String) {
        let text = markdown as NSString
        guard let lines = Self.lines(in: text, range: NSRange(location: 0, length: text.length)) else { return nil }
        self.init(lines: lines, text: text)
    }

    /// The table that `lines` (from `lines(in:range:)`) lay out in `text`.
    public init(lines: [Line], text: NSString) {
        let delimiter = lines.first { $0.isDelimiter }
        let alignments = delimiter?.cells.map { Self.alignment(of: text.substring(with: $0)) } ?? []
        let rows = lines.filter { !$0.isDelimiter }.map { $0.cells.map(text.substring(with:)) }
        self.init(alignments: alignments, rows: rows)
    }

    // MARK: Writing

    /// The table written out neatly: each column padded to its widest cell, as the column is
    /// aligned, with a pipe at each end of every row.
    public func markdown(lineEnding: String = "\n") -> String {
        let widths = (0..<columnCount).map { column in
            max(3, rows.map { Self.width(of: $0[column]) }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            "| " + cells.joined(separator: " | ") + " |"
        }
        var lines = rows.map { row in
            line(row.enumerated().map { column, cell in Self.pad(cell, to: widths[column], alignment: alignments[column]) })
        }
        let delimiter = alignments.enumerated().map { column, alignment -> String in
            let width = widths[column]
            switch alignment {
            case .none: return String(repeating: "-", count: width)
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            }
        }
        lines.insert(line(delimiter), at: 1)
        return lines.joined(separator: lineEnding)
    }

    /// How wide a cell's Markdown is in a monospaced font, near enough: wide (East Asian)
    /// characters and emoji take two columns.
    static func width(of text: String) -> Int {
        text.reduce(0) { total, character in
            guard let scalar = character.unicodeScalars.first else { return total }
            let wide = character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || (0x1100...0x115F).contains(scalar.value) || (0x2E80...0xA4CF).contains(scalar.value)
                || (0xAC00...0xD7A3).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
                || (0xFE30...0xFE4F).contains(scalar.value) || (0xFF00...0xFF60).contains(scalar.value)
                || (0xFFE0...0xFFE6).contains(scalar.value)
            return total + (wide ? 2 : 1)
        }
    }

    private static func pad(_ cell: String, to width: Int, alignment: Alignment) -> String {
        let room = max(0, width - Self.width(of: cell))
        switch alignment {
        case .right: return String(repeating: " ", count: room) + cell
        case .center: return String(repeating: " ", count: room / 2) + cell + String(repeating: " ", count: room - room / 2)
        case .none, .left: return cell + String(repeating: " ", count: room)
        }
    }

    /// Text made safe to put in a cell: its pipes escaped, and line breaks made spaces, so it
    /// can't split the cell or end the row.
    public static func cellText(_ text: String) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            if character == "|", previous != "\\" {
                result += "\\|"
            } else if character.isNewline {
                result += " "
            } else {
                result.append(character)
            }
            previous = character
        }
        return result
    }

    // MARK: Changing the shape

    /// Adds an empty body row, so that it becomes row `index` (1 is the first body row).
    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 1), rows.count))
    }

    /// Removes a body row. The header row stays.
    public mutating func removeRow(at index: Int) {
        guard index >= 1, index < rows.count else { return }
        rows.remove(at: index)
    }

    /// Adds an empty column, so that it becomes column `index`.
    public mutating func insertColumn(at index: Int) {
        let index = min(max(index, 0), columnCount)
        alignments.insert(.none, at: index)
        for row in rows.indices { rows[row].insert("", at: index) }
    }

    /// Removes a column, unless it is the only one.
    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, index >= 0, index < columnCount else { return }
        alignments.remove(at: index)
        for row in rows.indices { rows[row].remove(at: index) }
    }

    public subscript(row: Int, column: Int) -> String {
        get { rows[row][column] }
        set { rows[row][column] = Self.cellText(newValue).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Reading the lines

    /// One line of a table, as it is in the note.
    public struct Line: Equatable, Sendable {
        /// The line, without its line break.
        public let range: NSRange
        /// Whether this is the row of dashes under the header.
        public let isDelimiter: Bool
        /// Each cell's Markdown, trimmed of the spaces around it. An empty cell is an empty
        /// range, where what's typed into it goes.
        public let cells: [NSRange]
        /// The pipes that divide the cells (escaped ones aren't), including any at the ends.
        public let pipes: [Int]
    }

    /// The lines of the table that `range` covers (as the parser found it), or nil if they
    /// aren't a well-formed table: the delimiter row must have one valid cell per header cell.
    public static func lines(in text: NSString, range: NSRange) -> [Line]? {
        var lines: [Line] = []
        var location = range.location
        while location < NSMaxRange(range) {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: start, length: min(contentsEnd, NSMaxRange(range)) - start)
            let (cells, pipes) = split(line.location..<NSMaxRange(line)) { text.character(at: $0) }
            lines.append(Line(range: line, isDelimiter: lines.count == 1,
                              cells: cells.map { NSRange(location: $0.lowerBound, length: $0.count) }, pipes: pipes))
            guard end > location else { break }
            location = end
        }
        guard lines.count >= 2, lines[0].cells.count == lines[1].cells.count,
              lines[1].cells.allSatisfy({ isDelimiterCell(text.substring(with: $0)) }) else { return nil }
        return lines
    }

    private static func isDelimiterCell(_ cell: String) -> Bool {
        var body = Substring(cell)
        if body.hasPrefix(":") { body = body.dropFirst() }
        if body.hasSuffix(":") { body = body.dropLast() }
        return !body.isEmpty && body.allSatisfy { $0 == "-" }
    }

    private static func alignment(of delimiter: String) -> Alignment {
        switch (delimiter.hasPrefix(":"), delimiter.count > 1 && delimiter.hasSuffix(":")) {
        case (true, true): .center
        case (true, false): .left
        case (false, true): .right
        case (false, false): .none
        }
    }

    /// Splits a row into its cells at its unescaped pipes, as GFM does before it reads any
    /// inline Markdown: a pipe in code or a link divides cells too, unless it is `\|`.
    /// Each cell is trimmed of spaces; an empty one is placed after the space following its
    /// pipe, if there is one, so text typed into it is padded.
    static func split(_ line: Range<Int>, _ character: (Int) -> UInt16) -> (cells: [Range<Int>], pipes: [Int]) {
        let pipe: UInt16 = 124, backslash: UInt16 = 92
        func isSpace(_ k: Int) -> Bool { character(k) == 32 || character(k) == 9 }
        var start = line.lowerBound, end = line.upperBound
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }

        var pipes: [Int] = []
        var k = start
        while k < end {
            if character(k) == backslash, k + 1 < end, character(k + 1) == pipe {
                k += 2
                continue
            }
            if character(k) == pipe { pipes.append(k) }
            k += 1
        }
        guard start < end else { return ([], []) }
        let leading = pipes.first == start
        let trailing = pipes.count > (leading ? 1 : 0) && pipes.last == end - 1
        let inner = pipes.dropFirst(leading ? 1 : 0).dropLast(trailing ? 1 : 0)
        var edges = [leading ? start + 1 : start]
        for p in inner { edges += [p, p + 1] }
        edges.append(trailing ? end - 1 : end)

        var cells: [Range<Int>] = []
        for i in stride(from: 0, to: edges.count, by: 2) {
            var a = edges[i], b = edges[i + 1]
            while a < b, isSpace(a) { a += 1 }
            while b > a, isSpace(b - 1) { b -= 1 }
            if a == b {
                a = edges[i] < edges[i + 1] ? edges[i] + 1 : edges[i]
                b = a
            }
            cells.append(a..<b)
        }
        return (cells, pipes)
    }
}
