import Foundation

/// Finds the Markdown structure in a note.
///
/// The parser never changes text. It only reports where things are, so the editor can
/// style the exact characters on disk and saving stays byte-for-byte lossless. It covers
/// CommonMark and GFM as Obsidian writes them, plus Obsidian's own syntax: wikilinks,
/// embeds, tags, callouts, highlights and frontmatter. It is deliberately forgiving:
/// anything it doesn't recognise is plain text.
public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownToken] {
        var parser = Parser(Array(text.utf16))
        parser.parseBlocks()
        return parser.tokens.sorted {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location
                : $0.range.length > $1.range.length
        }
    }
}

// MARK: - Characters

private func u(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }

private let newline = u("\n"), carriageReturn = u("\r"), space = u(" "), tab = u("\t")
private let hash = u("#"), greaterThan = u(">"), backtick = u("`"), tilde = u("~")
private let star = u("*"), underscore = u("_"), dash = u("-"), plus = u("+"), equals = u("=")
private let openBracket = u("["), closeBracket = u("]"), openParen = u("("), closeParen = u(")")
private let bang = u("!"), pipe = u("|"), caret = u("^"), backslash = u("\\"), colon = u(":")
private let dot = u("."), byteOrderMark: UInt16 = 0xFEFF

private func isSpace(_ c: UInt16) -> Bool { c == space || c == tab }
private func isWhitespace(_ c: UInt16) -> Bool { c == space || c == tab || c == newline || c == carriageReturn || c == 0xA0 }
private func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }

private func isASCIIPunctuation(_ c: UInt16) -> Bool {
    (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)
}

private func isPunctuation(_ c: UInt16) -> Bool {
    if c < 128 { return isASCIIPunctuation(c) }
    guard let scalar = Unicode.Scalar(c) else { return false }
    return CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
}

/// Letters and digits in any script, plus `_`, `-` and `/`, as Obsidian allows in tags.
private func isTagCharacter(_ c: UInt16) -> Bool {
    if c == underscore || c == dash || c == u("/") { return true }
    if c < 128 { return isDigit(c) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
    guard let scalar = Unicode.Scalar(c) else { return false }
    return CharacterSet.alphanumerics.contains(scalar)
}

// MARK: - Parser

private struct Parser {
    let s: [UInt16]
    /// Each line's content, without its line terminator.
    var lines: [Range<Int>] = []
    var tokens: [MarkdownToken] = []

    init(_ s: [UInt16]) {
        self.s = s
        var start = 0
        for i in s.indices where s[i] == newline {
            lines.append(start..<(i > start && s[i - 1] == carriageReturn ? i - 1 : i))
            start = i + 1
        }
        lines.append(start..<s.count)
    }

    mutating func add(_ kind: MarkdownToken.Kind, _ range: Range<Int>, syntax: [Range<Int>] = []) {
        tokens.append(MarkdownToken(
            kind: kind,
            range: NSRange(location: range.lowerBound, length: range.count),
            syntax: syntax.map { NSRange(location: $0.lowerBound, length: $0.count) }
        ))
    }

    func string(_ r: Range<Int>) -> String {
        String(decoding: s[r], as: UTF16.self)
    }

    /// The line with leading and trailing spaces and tabs removed.
    func trimmed(_ line: Range<Int>) -> Range<Int> {
        var a = line.lowerBound, b = line.upperBound
        while a < b, isSpace(s[a]) { a += 1 }
        while b > a, isSpace(s[b - 1]) { b -= 1 }
        return a..<b
    }

    func isBlank(_ line: Range<Int>) -> Bool { trimmed(line).isEmpty }

    func matches(_ r: Range<Int>, _ text: String) -> Bool {
        Array(text.utf16) == Array(s[r])
    }

    // MARK: Blocks

    mutating func parseBlocks() {
        var i = 0
        if let end = frontmatterEnd() {
            let range = lines[0].lowerBound..<lines[end].upperBound
            add(.frontmatter, range, syntax: [range])
            i = end + 1
        }
        while i < lines.count {
            let line = lines[i]
            if let fence = fenceOpening(line) {
                i = parseFence(from: i, fence)
            } else if isThematicBreak(line) {
                add(.thematicBreak, line, syntax: [line])
                i += 1
            } else if parseHeading(line) {
                i += 1
            } else if quoteMarkerEnd(line) != nil {
                i = parseQuote(from: i)
            } else if parseListItem(line) {
                i += 1
            } else if isTableStart(i) {
                i = parseTable(from: i)
            } else {
                if let markerEnd = footnoteDefinitionMarkerEnd(line) {
                    add(.footnoteDefinition, line)
                    inline(markerEnd..<line.upperBound)
                } else {
                    inline(line)
                }
                i += 1
            }
        }
    }

    /// The index of the line closing frontmatter that opens the file, if there is any.
    func frontmatterEnd() -> Int? {
        var first = trimmed(lines[0])
        if first.lowerBound < first.upperBound, s[first.lowerBound] == byteOrderMark {
            first = (first.lowerBound + 1)..<first.upperBound
        }
        guard matches(first, "---") else { return nil }
        for j in lines.indices.dropFirst() {
            let line = trimmed(lines[j])
            if matches(line, "---") || matches(line, "...") { return j }
        }
        return nil
    }

    // Fenced code

    struct Fence { let character: UInt16; let length: Int; let language: String }

    func fenceOpening(_ line: Range<Int>) -> Fence? {
        let t = trimmed(line)
        guard let c = t.first.map({ s[$0] }), c == backtick || c == tilde else { return nil }
        var n = 0
        while t.lowerBound + n < t.upperBound, s[t.lowerBound + n] == c { n += 1 }
        guard n >= 3 else { return nil }
        let info = trimmed((t.lowerBound + n)..<t.upperBound)
        if c == backtick, s[info].contains(backtick) { return nil }
        let language = string(info).split(separator: " ").first.map(String.init) ?? ""
        return Fence(character: c, length: n, language: language)
    }

    mutating func parseFence(from i: Int, _ fence: Fence) -> Int {
        var j = i + 1
        while j < lines.count {
            let t = trimmed(lines[j])
            if t.count >= fence.length, s[t].allSatisfy({ $0 == fence.character }) {
                add(.codeBlock(language: fence.language), lines[i].lowerBound..<lines[j].upperBound, syntax: [lines[i], lines[j]])
                return j + 1
            }
            j += 1
        }
        // Unclosed: the block runs to the end of the note, as in Obsidian.
        add(.codeBlock(language: fence.language), lines[i].lowerBound..<lines[lines.count - 1].upperBound, syntax: [lines[i]])
        return lines.count
    }

    func isThematicBreak(_ line: Range<Int>) -> Bool {
        let t = trimmed(line)
        guard let c = t.first.map({ s[$0] }), c == dash || c == star || c == underscore else { return false }
        var count = 0
        for k in t {
            if s[k] == c { count += 1 } else if !isSpace(s[k]) { return false }
        }
        return count >= 3
    }

    mutating func parseHeading(_ line: Range<Int>) -> Bool {
        var k = line.lowerBound
        while k < line.upperBound, s[k] == hash { k += 1 }
        let level = k - line.lowerBound
        guard (1...6).contains(level), k == line.upperBound || isSpace(s[k]) else { return false }
        while k < line.upperBound, isSpace(s[k]) { k += 1 }
        add(.heading(level: level), line, syntax: [line.lowerBound..<k])
        inline(k..<line.upperBound)
        return true
    }

    // Quotes and callouts

    /// Where the `>` markers (and one following space) end, if the line is quoted.
    func quoteMarkerEnd(_ line: Range<Int>) -> Int? {
        var k = line.lowerBound
        while k < line.upperBound, k - line.lowerBound < 3, s[k] == space { k += 1 }
        guard k < line.upperBound, s[k] == greaterThan else { return nil }
        while k < line.upperBound, s[k] == greaterThan {
            k += 1
            if k < line.upperBound, isSpace(s[k]) { k += 1 }
        }
        return k
    }

    mutating func parseQuote(from i: Int) -> Int {
        var j = i
        var syntax: [Range<Int>] = []
        var calloutType: String?
        while j < lines.count, let markerEnd = quoteMarkerEnd(lines[j]) {
            let line = lines[j]
            syntax.append(line.lowerBound..<markerEnd)
            var contentStart = markerEnd
            if j == i, let (type, end) = calloutMarker(markerEnd..<line.upperBound) {
                calloutType = type
                syntax.append(markerEnd..<end)
                contentStart = end
            }
            inline(contentStart..<line.upperBound)
            j += 1
        }
        let range = lines[i].lowerBound..<lines[j - 1].upperBound
        add(calloutType.map { .callout(type: $0) } ?? .blockquote, range, syntax: syntax)
        return j
    }

    /// `[!note]`, optionally followed by `+` or `-` (foldable) and a space.
    func calloutMarker(_ r: Range<Int>) -> (String, Int)? {
        guard r.count > 3, s[r.lowerBound] == openBracket, s[r.lowerBound + 1] == bang else { return nil }
        var k = r.lowerBound + 2
        while k < r.upperBound, s[k] != closeBracket, !isSpace(s[k]) { k += 1 }
        guard k < r.upperBound, s[k] == closeBracket, k > r.lowerBound + 2 else { return nil }
        let type = string((r.lowerBound + 2)..<k).lowercased()
        k += 1
        if k < r.upperBound, s[k] == plus || s[k] == dash { k += 1 }
        if k < r.upperBound, isSpace(s[k]) { k += 1 }
        return (type, k)
    }

    // Lists

    mutating func parseListItem(_ line: Range<Int>) -> Bool {
        var k = line.lowerBound
        var indent = 0
        while k < line.upperBound, isSpace(s[k]) {
            indent += s[k] == tab ? 4 : 1
            k += 1
        }
        let markerStart = k
        var marker: ListMarker
        if k < line.upperBound, s[k] == dash || s[k] == star || s[k] == plus {
            marker = .bullet
            k += 1
        } else {
            while k < line.upperBound, isDigit(s[k]), k - markerStart < 9 { k += 1 }
            guard k > markerStart, k < line.upperBound, s[k] == dot || s[k] == closeParen else { return false }
            marker = .ordered(Int(string(markerStart..<k)) ?? 1)
            k += 1
        }
        // The marker must be followed by a space, or end the line (an empty item).
        if k < line.upperBound {
            guard isSpace(s[k]) else { return false }
            k += 1
        }
        if case .bullet = marker, k + 3 <= line.upperBound, s[k] == openBracket, s[k + 2] == closeBracket,
           [space, u("x"), u("X")].contains(s[k + 1]),
           k + 3 == line.upperBound || isSpace(s[k + 3]) {
            marker = .task(done: s[k + 1] != space)
            k = min(k + 4, line.upperBound)
        }
        add(.listItem(marker, indent: indent), line, syntax: [markerStart..<k])
        inline(k..<line.upperBound)
        return true
    }

    // Tables

    func isTableStart(_ i: Int) -> Bool {
        guard i + 1 < lines.count, s[lines[i]].contains(pipe) else { return false }
        let separator = trimmed(lines[i + 1])
        guard !separator.isEmpty, s[separator].contains(dash) else { return false }
        return s[separator].allSatisfy { $0 == pipe || $0 == colon || $0 == dash || isSpace($0) }
            && s[separator].contains(pipe)
    }

    mutating func parseTable(from i: Int) -> Int {
        var j = i + 2
        while j < lines.count, !isBlank(lines[j]), s[lines[j]].contains(pipe) { j += 1 }
        add(.table, lines[i].lowerBound..<lines[j - 1].upperBound)
        for row in i..<j where row != i + 1 { inline(lines[row]) }
        return j
    }

    func footnoteDefinitionMarkerEnd(_ line: Range<Int>) -> Int? {
        let a = line.lowerBound
        guard line.count > 4, s[a] == openBracket, s[a + 1] == caret else { return nil }
        var k = a + 2
        while k < line.upperBound, s[k] != closeBracket, !isSpace(s[k]) { k += 1 }
        guard k > a + 2, k + 1 < line.upperBound, s[k] == closeBracket, s[k + 1] == colon else { return nil }
        return k + 2
    }

    // MARK: Inline

    /// A run of `*`, `_`, `~` or `=` that may open or close emphasis.
    struct DelimiterRun {
        let character: UInt16
        /// The characters not yet used. Openers are used from the right, closers from the left.
        var start: Int
        var end: Int
        let canOpen: Bool
        let canClose: Bool
        var count: Int { end - start }
    }

    mutating func inline(_ r: Range<Int>) {
        var runs: [DelimiterRun] = []
        // A Markdown link's destination, to jump over once its text has been scanned.
        var skip: (from: Int, to: Int)?
        var i = r.lowerBound
        let end = r.upperBound

        func at(_ k: Int) -> UInt16? { k >= r.lowerBound && k < end ? s[k] : nil }

        while i < end {
            if let pending = skip, i >= pending.from {
                i = pending.to
                skip = nil
                continue
            }
            let c = s[i]

            if c == backslash, let next = at(i + 1), isASCIIPunctuation(next) {
                add(.escape, i..<(i + 2), syntax: [i..<(i + 1)])
                i += 2
            } else if c == backtick {
                var n = 1
                while at(i + n) == backtick { n += 1 }
                if let close = closingBacktickRun(length: n, from: i + n, end: end) {
                    add(.code, i..<(close + n), syntax: [i..<(i + n), close..<(close + n)])
                    i = close + n
                } else {
                    i += n
                }
            } else if c == bang, at(i + 1) == openBracket, at(i + 2) == openBracket,
                      let next = wikiLink(at: i + 1, end: end, embed: true) {
                i = next
            } else if c == openBracket, at(i + 1) == openBracket, let next = wikiLink(at: i, end: end, embed: false) {
                i = next
            } else if c == openBracket, at(i + 1) == caret, let close = footnoteReferenceEnd(at: i, end: end) {
                add(.footnoteReference, i..<close)
                i = close
            } else if c == openBracket || (c == bang && at(i + 1) == openBracket),
                      let link = markdownLink(at: c == bang ? i + 1 : i, end: end) {
                let start = i
                let destination = string(link.destination)
                add(c == bang ? .image(source: destination) : .link(destination: destination),
                    start..<link.end,
                    syntax: [start..<(link.textStart), link.textEnd..<link.end])
                // Scan the link text for emphasis, then jump over the destination.
                skip = (link.textEnd, link.end)
                i = link.textStart
            } else if c == hash, i == r.lowerBound || isWhitespace(s[i - 1]), let tagEnd = tagEnd(from: i + 1, end: end) {
                add(.tag(string((i + 1)..<tagEnd)), i..<tagEnd)
                i = tagEnd
            } else if c == u("h"), i == r.lowerBound || isWhitespace(s[i - 1]) || s[i - 1] == openParen || s[i - 1] == u("<"),
                      let urlEnd = urlEnd(from: i, end: end) {
                add(.url, i..<urlEnd)
                i = urlEnd
            } else if c == star || c == underscore || c == tilde || c == equals {
                var j = i
                while j < end, s[j] == c { j += 1 }
                if c == star || c == underscore || j - i >= 2 {
                    runs.append(delimiterRun(i..<j, in: r))
                }
                i = j
            } else {
                i += 1
            }
        }
        resolveEmphasis(&runs)
    }

    func closingBacktickRun(length: Int, from start: Int, end: Int) -> Int? {
        var k = start
        while k < end {
            guard s[k] == backtick else { k += 1; continue }
            var n = 0
            while k + n < end, s[k + n] == backtick { n += 1 }
            if n == length { return k }
            k += n
        }
        return nil
    }

    /// Parses `[[Target]]`, `[[Target|alias]]` or (for embeds) `![[Target]]` starting at the
    /// first `[`, and returns the index after it.
    mutating func wikiLink(at open: Int, end: Int, embed: Bool) -> Int? {
        var close = open + 2
        while close + 1 < end, !(s[close] == closeBracket && s[close + 1] == closeBracket) {
            if s[close] == openBracket, s[close + 1] == openBracket { return nil }
            close += 1
        }
        guard close + 1 < end, close > open + 2 else { return nil }
        let inner = (open + 2)..<close
        let pipeIndex = inner.first { s[$0] == pipe && ($0 == inner.lowerBound || s[$0 - 1] != backslash) }
        var targetEnd = pipeIndex ?? close
        if targetEnd > inner.lowerBound, s[targetEnd - 1] == backslash { targetEnd -= 1 } // `\|` in tables
        let target = string(inner.lowerBound..<targetEnd)
        let start = embed ? open - 1 : open
        var syntax = [start..<(open + 2)]
        if let pipeIndex { syntax.append((open + 2)..<(pipeIndex + 1)) }
        syntax.append(close..<(close + 2))
        add(embed ? .embed(target: target) : .wikiLink(target: target), start..<(close + 2), syntax: syntax)
        return close + 2
    }

    func footnoteReferenceEnd(at open: Int, end: Int) -> Int? {
        var k = open + 2
        while k < end, s[k] != closeBracket, !isSpace(s[k]) { k += 1 }
        guard k < end, k > open + 2, s[k] == closeBracket else { return nil }
        return k + 1
    }

    struct MarkdownLink { let textStart: Int; let textEnd: Int; let destination: Range<Int>; let end: Int }

    /// Parses `[text](destination)` starting at `[`. `textEnd` is the index of `]`.
    func markdownLink(at open: Int, end: Int) -> MarkdownLink? {
        var depth = 0
        var k = open
        while k < end {
            if s[k] == backslash { k += 2; continue }
            if s[k] == openBracket { depth += 1 }
            if s[k] == closeBracket { depth -= 1; if depth == 0 { break } }
            k += 1
        }
        guard k + 1 < end, s[k] == closeBracket, s[k + 1] == openParen else { return nil }
        let textEnd = k
        var parens = 0
        k += 1
        while k < end {
            if s[k] == backslash { k += 2; continue }
            if s[k] == openParen { parens += 1 }
            if s[k] == closeParen { parens -= 1; if parens == 0 { break } }
            k += 1
        }
        guard k < end, s[k] == closeParen else { return nil }
        var destination = trimmed((textEnd + 2)..<k)
        if destination.first.map({ s[$0] }) == u("<"),
           let close = destination.first(where: { s[$0] == greaterThan }) {
            destination = (destination.lowerBound + 1)..<close // `<my file.md>` may contain spaces.
        } else if let space = destination.first(where: { isSpace(s[$0]) }) {
            destination = destination.lowerBound..<space // Drop a "title".
        }
        return MarkdownLink(textStart: open + 1, textEnd: textEnd, destination: destination, end: k + 1)
    }

    /// A tag needs at least one character that isn't a digit, as in Obsidian.
    func tagEnd(from start: Int, end: Int) -> Int? {
        var k = start
        var hasNonDigit = false
        while k < end, isTagCharacter(s[k]) {
            if !isDigit(s[k]) { hasNonDigit = true }
            k += 1
        }
        return k > start && hasNonDigit ? k : nil
    }

    func urlEnd(from start: Int, end: Int) -> Int? {
        let scheme: Int
        if start + 8 <= end, matches(start..<(start + 8), "https://") { scheme = 8 }
        else if start + 7 <= end, matches(start..<(start + 7), "http://") { scheme = 7 }
        else { return nil }
        var k = start + scheme
        var parens = 0
        while k < end, !isWhitespace(s[k]), s[k] != u("<"), s[k] != greaterThan {
            if s[k] == openParen { parens += 1 }
            if s[k] == closeParen {
                if parens == 0 { break }
                parens -= 1
            }
            k += 1
        }
        while k > start + scheme, [dot, u(","), u(";"), colon, bang, u("?"), u("'"), u("\""), u("*"), underscore].contains(s[k - 1]) {
            k -= 1
        }
        return k > start + scheme ? k : nil
    }

    // Emphasis

    func delimiterRun(_ run: Range<Int>, in r: Range<Int>) -> DelimiterRun {
        let before = run.lowerBound > r.lowerBound ? s[run.lowerBound - 1] : space
        let after = run.upperBound < r.upperBound ? s[run.upperBound] : space
        let leftFlanking = !isWhitespace(after) && (!isPunctuation(after) || isWhitespace(before) || isPunctuation(before))
        let rightFlanking = !isWhitespace(before) && (!isPunctuation(before) || isWhitespace(after) || isPunctuation(after))
        let c = s[run.lowerBound]
        let canOpen = c == underscore ? leftFlanking && (!rightFlanking || isPunctuation(before)) : leftFlanking
        let canClose = c == underscore ? rightFlanking && (!leftFlanking || isPunctuation(after)) : rightFlanking
        return DelimiterRun(character: c, start: run.lowerBound, end: run.upperBound, canOpen: canOpen, canClose: canClose)
    }

    mutating func resolveEmphasis(_ runs: inout [DelimiterRun]) {
        for closer in runs.indices where runs[closer].canClose {
            while runs[closer].count > 0 {
                let c = runs[closer].character
                guard let opener = runs[..<closer].lastIndex(where: { $0.character == c && $0.canOpen && $0.count > 0 }) else { break }
                let available = min(runs[opener].count, runs[closer].count)
                let use: Int
                if c == star || c == underscore {
                    use = available >= 2 ? 2 : 1
                } else {
                    guard available >= 2 else { break }
                    use = 2
                }
                let openMarker = (runs[opener].end - use)..<runs[opener].end
                let closeMarker = runs[closer].start..<(runs[closer].start + use)
                runs[opener].end -= use
                runs[closer].start += use
                let kind: MarkdownToken.Kind = switch c {
                case tilde: .strikethrough
                case equals: .highlight
                default: use == 2 ? .strong : .emphasis
                }
                add(kind, openMarker.lowerBound..<closeMarker.upperBound, syntax: [openMarker, closeMarker])
                // Delimiters between a matched pair can no longer match, as in CommonMark.
                for k in (opener + 1)..<closer { runs[k].start = runs[k].end }
            }
        }
    }
}
