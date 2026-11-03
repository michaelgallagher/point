#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MarkdownKit

/// Applies display attributes for parsed Markdown to a text storage.
///
/// It only ever changes attributes, never characters, so the text stays exactly
/// what is on disk.
struct MarkdownStyler {
    var theme = EditorTheme()
    /// Shows the raw Markdown, every marker visible, in a monospaced font.
    var showsMarkdown = false
    /// Whether a wikilink's target is a note that exists. Links to notes that don't exist
    /// yet are fainter. Without it, every link looks as if its note exists.
    var wikiLinkExists: ((String) -> Bool)?
    /// Characters that highlight a list item when they start it, with their colours.
    var listHighlights: [Character: PlatformColor] = [:]

    /// The highlight character starting a list item's text, with its space, and its colour.
    func listHighlight(after marker: NSRange, in item: NSRange, text: NSString) -> (NSRange, PlatformColor)? {
        let start = NSMaxRange(marker)
        guard !showsMarkdown, start + 1 <= NSMaxRange(item), start < text.length,
              let scalar = UnicodeScalar(text.character(at: start)),
              let color = listHighlights[Character(scalar)] else { return nil }
        // Followed by a space, or alone on the line.
        let next = start + 1
        let ends = next >= NSMaxRange(item) || text.character(at: next) == 10
        guard ends || text.character(at: next) == 32 else { return nil }
        return (NSRange(location: start, length: ends ? 1 : 2), color)
    }

    var baseParagraphStyle: NSParagraphStyle {
        // Line height is added by the layout manager, centred on the text, not here:
        // the paragraph style would put all the extra space above the text.
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.paragraphSpacing
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.body, .foregroundColor: PlatformColor.textColor, .paragraphStyle: baseParagraphStyle]
    }

    /// Restyles `range`, widened to whole tokens, and returns the range actually restyled.
    @discardableResult
    func style(_ storage: NSTextStorage, range: NSRange, tokens: [MarkdownToken]) -> NSRange {
        let text = storage.string as NSString
        var range = text.paragraphRange(for: range)
        // Widen to every token that touches the range, until nothing more is added.
        while true {
            var widened = range
            for token in tokens where intersects(token.range, widened) {
                widened = NSUnionRange(widened, token.range)
            }
            widened = text.paragraphRange(for: widened)
            if widened == range { break }
            range = widened
        }

        // Fonts set here have no emoji: the system's fallback (Apple Color Emoji) has to be put
        // back. Restyling after an edit comes after the text storage has done that itself.
        defer { storage.fixAttributes(in: range) }
        if showsMarkdown {
            storage.setAttributes([.font: theme.mono, .foregroundColor: PlatformColor.textColor,
                                   .paragraphStyle: baseParagraphStyle], range: range)
            return range
        }
        storage.setAttributes(baseAttributes, range: range)
        for token in tokens where intersects(token.range, range) {
            apply(token, to: storage, text: text)
        }
        // Tables last, once the formatting in their cells (which sets how wide they are) is on.
        for token in tokens where token.kind == .table && intersects(token.range, range) {
            layOutTable(token.range, storage: storage, text: text)
        }
        return range
    }

    private func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location <= NSMaxRange(b) && b.location <= NSMaxRange(a)
    }

    private func apply(_ token: MarkdownToken, to storage: NSTextStorage, text: NSString) {
        let range = token.range
        switch token.kind {
        case .frontmatter:
            // Hidden: the app shows properties in a strip above the text instead.
            var location = range.location
            while location < NSMaxRange(range) {
                var start = 0, end = 0, contentsEnd = 0
                text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
                collapseLine(NSRange(location: start, length: contentsEnd - start), storage: storage, text: text, height: 0.1)
                location = end
            }
            return

        case .heading(let level):
            let font = theme.headingFont(level: level)
            storage.addAttributes([.font: font, .paragraphStyle: paragraphStyle { _ in }], range: range)

        case .blockquote, .callout:
            let style = paragraphStyle {
                $0.firstLineHeadIndent = 16
                $0.headIndent = 16
            }
            var block = BlockDecoration.quote
            if case .callout(let type) = token.kind {
                block = .callout(type: type)
                // The title line, after `[!type]`, is bold.
                if token.syntax.count > 1 {
                    let titleStart = NSMaxRange(token.syntax[1])
                    let lineEnd = NSMaxRange(text.lineRange(for: NSRange(location: titleStart, length: 0)))
                    let titleRange = NSRange(location: titleStart, length: max(0, min(lineEnd, NSMaxRange(range)) - titleStart))
                    addTrait(PlatformTraits.bold, in: titleRange, storage: storage)
                }
            }
            storage.addAttributes([.paragraphStyle: style, .pointBlock: block], range: range)

        case .listItem(let marker, let indent):
            let level = Int((Double(indent) / 4).rounded(.up))
            let start = theme.indentPerLevel * CGFloat(level) + theme.markerWidth(for: marker)
            let style = paragraphStyle {
                $0.firstLineHeadIndent = start
                $0.headIndent = start
            }
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            if let markerRange = token.syntax.first {
                // Hide the indent and the marker; the layout manager draws the marker instead.
                let hidden = NSRange(location: range.location, length: NSMaxRange(markerRange) - range.location)
                storage.addAttribute(.pointHidden, value: true, range: hidden)
                storage.addAttribute(.pointListMarker, value: ListMarkerDecoration(marker: marker, level: level),
                                     range: NSRange(location: range.location, length: 1))
                if case .task(done: true) = marker {
                    let content = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(range) - NSMaxRange(markerRange))
                    storage.addAttribute(.foregroundColor, value: PlatformColor.secondaryLabelColor, range: content)
                }
                // `- ! text`: the character and its space are hidden, and the line coloured.
                if let (character, color) = listHighlight(after: markerRange, in: range, text: text) {
                    storage.addAttribute(.pointHidden, value: true, range: character)
                    storage.addAttribute(.pointListHighlight, value: color, range: range)
                }
            }
            return

        case .codeBlock:
            let style = paragraphStyle {
                $0.firstLineHeadIndent = 12
                $0.headIndent = 12
                $0.tailIndent = -12
                $0.paragraphSpacing = 0
            }
            storage.addAttributes([.font: theme.mono, .paragraphStyle: style, .pointBlock: BlockDecoration.code,
                                   .pointLineHeight: CGFloat(1.15)], range: range)
            for fence in token.syntax {
                collapseLine(fence, storage: storage, text: text)
            }
            return

        case .thematicBreak:
            storage.addAttribute(.pointRule, value: true, range: range)

        case .table:
            // Drawn as a table once its cells are styled (see `layOutTable`), if it is a
            // well-formed one; otherwise left as Markdown.
            if !theme.rendersTables || MarkdownTable.lines(in: text, range: range) == nil {
                storage.addAttribute(.font, value: theme.mono, range: range)
            }

        case .footnoteDefinition:
            storage.addAttributes([
                .font: PlatformFont.systemFont(ofSize: theme.bodySize - 2),
                .foregroundColor: PlatformColor.secondaryLabelColor,
            ], range: range)

        case .strong:
            addTrait(PlatformTraits.bold, in: range, storage: storage)
        case .emphasis:
            addTrait(PlatformTraits.italic, in: range, storage: storage)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            // Drawn by the layout manager, with rounded corners.
            storage.addAttribute(.pointRoundedBackground, value: PlatformColor.systemYellow.withAlphaComponent(0.35), range: range)
        case .code:
            let size = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? theme.bodySize
            storage.addAttributes([
                .font: PlatformFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular),
                .pointRoundedBackground: PlatformColor.textColor.withAlphaComponent(0.07),
            ], range: range)
        case .link(let destination), .image(let destination):
            storage.addAttributes(pointing([.foregroundColor: PlatformColor.linkColor]), range: range)
            if Self.isWebAddress(destination), let close = token.syntax.last, close.location > range.location {
                markWebLink(at: close.location - 1, storage: storage) // The last letter of the link text.
            }
        case .url:
            storage.addAttributes(pointing([.foregroundColor: PlatformColor.linkColor]), range: range)
            markWebLink(at: NSMaxRange(range) - 1, storage: storage)
        case .wikiLink(let target), .embed(let target):
            let exists = wikiLinkExists?(target) ?? true
            let color = exists ? PlatformColor.linkColor : PlatformColor.linkColor.withAlphaComponent(0.5)
            storage.addAttributes(pointing([.foregroundColor: color]), range: range)
        case .tag:
            // Drawn as a pill by the layout manager, with a little room on each side for it.
            storage.addAttributes(pointing([.pointTag: true]), range: range)
            if range.location > 0, text.character(at: range.location - 1) != 10 {
                storage.addAttribute(.kern, value: theme.tagSpace, range: NSRange(location: range.location - 1, length: 1))
            } else if theme.keepsTagsInsideMargin {
                let style = paragraphStyle { $0.firstLineHeadIndent = theme.tagSpace }
                storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: NSRange(location: range.location, length: 0)))
            }
            storage.addAttribute(.kern, value: theme.tagSpace, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        case .footnoteReference:
            storage.addAttributes([
                .font: PlatformFont.systemFont(ofSize: theme.bodySize * 0.75),
                .baselineOffset: theme.bodySize * 0.35,
                .foregroundColor: PlatformColor.linkColor,
            ], range: range)
        case .escape:
            break
        }

        for marker in token.syntax {
            storage.addAttribute(.pointHidden, value: true, range: marker)
        }
    }

    static func isWebAddress(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// Makes room after a link's last letter for the arrow symbol, which the layout manager draws.
    private func markWebLink(at index: Int, storage: NSTextStorage) {
        guard index >= 0, index < storage.length else { return }
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont ?? theme.body
        storage.addAttributes([.pointWebLink: true, .kern: theme.webLinkSpace(for: font)], range: NSRange(location: index, length: 1))
    }

    private func paragraphStyle(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = baseParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        configure(style)
        return style
    }

    // MARK: Tables

    /// Lays a table out in columns. The pipes and the padding around each cell's text are
    /// hidden, and each pipe between cells becomes a space reaching to where the next cell's
    /// text starts, so the text lines up in columns (aligned as the delimiter row says) without
    /// a character changing. The delimiter row is squeezed to a sliver, like a code fence, and
    /// the layout manager draws the lines between the cells. A cell too wide for its column is
    /// cut off at the column's edge: rows never wrap.
    func layOutTable(_ range: NSRange, storage: NSTextStorage, text: NSString) {
        guard theme.rendersTables, let lines = MarkdownTable.lines(in: text, range: range) else { return }
        let rows = lines.filter { !$0.isDelimiter }
        let alignments = MarkdownTable(lines: lines, text: text).alignments
        let columns = alignments.count
        let padding = theme.tableCellPadding

        let style = paragraphStyle {
            $0.firstLineHeadIndent = padding
            $0.headIndent = padding
            $0.paragraphSpacingBefore = theme.tableRowPadding
            $0.paragraphSpacing = theme.tableRowPadding
            $0.lineBreakMode = .byClipping
        }
        for row in rows {
            storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: row.range))
        }
        if let delimiter = lines.first(where: \.isDelimiter) {
            collapseLine(delimiter.range, storage: storage, text: text, height: 1)
        }
        for cell in rows[0].cells {
            addTrait(PlatformTraits.bold, in: cell, storage: storage)
        }
        // `\|` is a pipe in a cell, even in code, where other escapes show.
        for row in rows {
            for cell in row.cells where cell.length > 1 {
                for k in cell.location..<(NSMaxRange(cell) - 1) where text.character(at: k) == 92 && text.character(at: k + 1) == 124 {
                    storage.addAttribute(.pointHidden, value: true, range: NSRange(location: k, length: 1))
                }
            }
        }
        // Fonts with the emoji fallback put back, so cells measure as they're drawn.
        storage.fixAttributes(in: range)

        // Each cell's width, and each column's: as wide as its widest cell, unless the table
        // is wider than the text, when the widest columns give up room until it fits.
        let widths = rows.map { row in row.cells.map { visibleWidth(of: $0, in: storage) } }
        var natural = (0..<columns).map { column in
            max(theme.bodySize * 2, widths.compactMap { column < $0.count ? $0[column] : nil }.max() ?? 0)
        }
        let room = theme.textWidth - padding * 2 * CGFloat(columns)
        if natural.reduce(0, +) > room {
            // Columns narrower than an equal share keep their width; the rest share what's left.
            var left = max(room, theme.bodySize * 2 * CGFloat(columns))
            var open = Set(natural.indices)
            while !open.isEmpty {
                let share = left / CGFloat(open.count)
                let narrow = open.filter { natural[$0] <= share }
                guard !narrow.isEmpty else {
                    for column in open { natural[column] = share.rounded(.down) }
                    break
                }
                for column in narrow {
                    left -= natural[column]
                    open.remove(column)
                }
            }
        }
        var edges: [CGFloat] = [0]
        for width in natural { edges.append((edges.last! + width + padding * 2).rounded()) }
        storage.addAttribute(.pointBlock, value: BlockDecoration.table(TableDecoration(columnEdges: edges)), range: range)

        for (r, row) in rows.enumerated() {
            let lineEnd = NSMaxRange(row.range)
            // The hidden stretches: before the first cell, between cells, and after the last.
            var starts = [row.range.location] + row.cells.map(\.upperBound)
            var ends = row.cells.map(\.location) + [lineEnd]
            if row.cells.isEmpty { starts = [row.range.location]; ends = [lineEnd] }
            for (start, end) in zip(starts, ends) where end > start {
                storage.addAttribute(.pointHidden, value: TableBoundary(location: start), range: NSRange(location: start, length: end - start))
            }
            for (column, cell) in row.cells.enumerated() where column < columns {
                let width = natural[column]
                let measured = widths[r][column]
                let spare = max(0, width - measured)
                let offset: CGFloat = switch alignments[column] {
                case .center: (spare / 2).rounded()
                case .right: spare
                case .none, .left: 0
                }
                // The pipe before this cell reaches to its text. (The first cell's has no pipe
                // before it when the row doesn't start with one, and so is left-aligned.)
                let before = column == 0 ? row.range.location : row.cells[column - 1].upperBound
                if let pipe = row.pipes.first(where: { $0 >= before && $0 < cell.location }) {
                    storage.addAttribute(.pointTableGap, value: TableGap(x: edges[column] + padding + offset), range: NSRange(location: pipe, length: 1))
                }
                // Too wide: pulled back, after its last letter, to the column's edge, and cut off there.
                if measured > width, let last = lastVisibleCharacter(in: cell, storage: storage) {
                    let kern = storage.attribute(.kern, at: last, effectiveRange: nil) as? CGFloat ?? 0
                    storage.addAttribute(.kern, value: kern - (measured - width), range: NSRange(location: last, length: 1))
                    storage.addAttribute(.pointTableClip, value: edges[column + 1] - padding / 2, range: cell)
                    storage.removeAttribute(.pointWebLink, range: cell) // Its arrow would be over the text.
                }
            }
        }
    }

    /// How wide a stretch of text is, leaving out what's hidden.
    private func visibleWidth(of range: NSRange, in storage: NSTextStorage) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let visible = NSMutableAttributedString()
        storage.enumerateAttribute(.pointHidden, in: range) { value, part, _ in
            if value == nil { visible.append(storage.attributedSubstring(from: part)) }
        }
        return visible.size().width.rounded(.up)
    }

    private func lastVisibleCharacter(in range: NSRange, storage: NSTextStorage) -> Int? {
        var k = NSMaxRange(range) - 1
        while k >= range.location, storage.attribute(.pointHidden, at: k, effectiveRange: nil) != nil { k -= 1 }
        return k >= range.location ? k : nil
    }

    /// Hides a whole line under a fold, as frontmatter is hidden.
    func hideLine(_ line: NSRange, storage: NSTextStorage, text: NSString) {
        collapseLine(line, storage: storage, text: text, height: 0.1)
        // Nothing drawn for it either: no bullet, checkbox, tag pill or block background.
        let full = text.lineRange(for: line)
        for key: NSAttributedString.Key in [.pointListMarker, .pointTag, .pointWebLink, .pointRule, .pointBlock, .pointTableGap, .pointTableClip] {
            storage.removeAttribute(key, range: full)
        }
    }

    /// Hides a whole line, such as a code fence, leaving only a sliver of space.
    private func collapseLine(_ line: NSRange, storage: NSTextStorage, text: NSString, height: CGFloat = 6) {
        let full = text.lineRange(for: line) // Includes the line break, which sets the line's height.
        let style = paragraphStyle {
            $0.minimumLineHeight = height
            $0.maximumLineHeight = height
            $0.lineHeightMultiple = 1
            $0.paragraphSpacing = 0
            $0.paragraphSpacingBefore = 0
        }
        storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 1), .paragraphStyle: style, .pointCollapsed: true], range: full)
        storage.addAttribute(.pointHidden, value: true, range: line)
    }

    private func addTrait(_ trait: PlatformFontTraits, in range: NSRange, storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? PlatformFont ?? theme.body
            storage.addAttribute(.font, value: font.adding(trait), range: subrange)
        }
    }
}
