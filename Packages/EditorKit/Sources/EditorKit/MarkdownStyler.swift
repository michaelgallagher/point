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
    /// Column widths kept while a table's cells are typed in, so its columns don't move with
    /// each keystroke: the table's start, and each column's width.
    var heldTableWidths: (table: Int, widths: [CGFloat])?
    /// Measures table cells as their grid lays them out.
    let tableMeasurer = TableCellMeasurer()
    /// Whether a wikilink's target is a note that exists. Links to notes that don't exist
    /// yet are fainter. Without it, every link looks as if its note exists.
    var wikiLinkExists: ((String) -> Bool)?
    /// Where the image an embed names is (`a.png`, or a path), if it's in the vault. Without
    /// it, no images are shown.
    var imageURL: ((String) -> URL?)?
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
        // Images last too, once their lines' own room above is set.
        if theme.rendersImages, imageURL != nil {
            // By line: images side by side share one.
            var lines: [Int: [MarkdownToken]] = [:]
            for token in tokens where intersects(token.range, range) && Self.imageEmbed(token, in: text) != nil {
                lines[text.lineRange(for: NSRange(location: token.range.location, length: 0)).location, default: []].append(token)
            }
            for (_, images) in lines { layOutImages(images.sorted { $0.range.location < $1.range.location }, storage: storage, text: text) }
        }
        return range
    }

    // MARK: Images

    /// An image embed's target (`a.png`, a path or a web address) and the width it asks for:
    /// `![[a.png|300]]` or `![alt|300](a.png)`. Nil for anything else.
    static func imageEmbed(_ token: MarkdownToken, in text: NSString) -> (target: String, width: CGFloat?)? {
        let range = token.range
        guard NSMaxRange(range) <= text.length else { return nil }
        switch token.kind {
        case .embed:
            guard range.length > 5 else { return nil }
            let inside = text.substring(with: NSRange(location: range.location + 3, length: range.length - 5))
            let parts = inside.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let target = parts[0].trimmingCharacters(in: .whitespaces)
            guard isImageName(target) else { return nil }
            return (target, parts.count > 1 ? width(parts[1]) : nil)
        case .image(let source):
            let whole = text.substring(with: range)
            var width: CGFloat?
            if let close = whole.range(of: "]("), let bar = whole[..<close.lowerBound].lastIndex(of: "|") {
                width = Self.width(String(whole[whole.index(after: bar)..<close.lowerBound]))
            }
            return (source.trimmingCharacters(in: .whitespaces), width)
        default:
            return nil
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "svg"]

    static func isImageName(_ name: String) -> Bool {
        imageExtensions.contains(((name as NSString).lastPathComponent as NSString).pathExtension.lowercased())
    }

    /// `300` or `300x200`: the width.
    private static func width(_ size: String) -> CGFloat? {
        let first = size.trimmingCharacters(in: .whitespaces).split(separator: "x", maxSplits: 1).first.map(String.init) ?? ""
        guard let value = Int(first), value > 0 else { return nil }
        return CGFloat(value)
    }

    /// Makes room above a line of nothing but image embeds (in a quote or list item too) for
    /// the images, drawn there by views (see `ImageEmbedView`), side by side at one height, and
    /// shows the embeds' Markdown small and quiet, as captions. Nothing changes for a line with
    /// text on it, or with an image that can't be shown (not in the vault, or not loaded yet).
    private func layOutImages(_ tokens: [MarkdownToken], storage: NSTextStorage, text: NSString) {
        guard let first = tokens.first else { return }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: first.range)
        guard storage.attribute(.pointCollapsed, at: first.range.location, effectiveRange: nil) == nil else { return }
        // Nothing else to read on the line: what isn't an image is space or hidden (`> `, `- `).
        for k in start..<contentsEnd where !tokens.contains(where: { NSLocationInRange(k, $0.range) }) {
            let c = text.character(at: k)
            if c == 32 || c == 9 || storage.attribute(.pointHidden, at: k, effectiveRange: nil) != nil { continue }
            return
        }
        var images: [(token: MarkdownToken, url: URL, size: CGSize)] = []
        for token in tokens {
            guard let embed = Self.imageEmbed(token, in: text), let url = imageURL?(embed.target),
                  let natural = EditorImages.shared.size(of: url), natural.width > 0, natural.height > 0 else { return }
            // As wide as asked, keeping its shape.
            let width = embed.width ?? natural.width
            images.append((token, url, CGSize(width: width, height: width * natural.height / natural.width)))
        }
        let existing = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle ?? baseParagraphStyle
        let gap = theme.imageGap * 3
        let room = max(theme.textWidth - existing.firstLineHeadIndent, 40) - gap * CGFloat(images.count - 1)
        // One height for them all: no taller than any is, or than the most an image is shown,
        // and low enough that they fit across the text.
        let aspects = images.map { $0.size.width / $0.size.height }
        let height = min(theme.imageMaxHeight, images.map(\.size.height).min()!, room / aspects.reduce(0, +)).rounded(.down)
        guard height >= 1 else { return }
        let style = existing.mutableCopy() as! NSMutableParagraphStyle
        let above = existing.paragraphSpacingBefore
        style.paragraphSpacingBefore = above + height + theme.imageGap
        storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: end - start))
        var x: CGFloat = 0
        for (index, image) in images.enumerated() {
            let size = CGSize(width: (height * aspects[index]).rounded(), height: height)
            let range = image.token.range
            storage.addAttributes([
                .pointImage: ImageDecoration(url: image.url, size: size, spaceAbove: above, x: x),
                .font: PlatformFont.systemFont(ofSize: (theme.bodySize * 0.75).rounded()),
                .foregroundColor: PlatformColor.secondaryLabelColor,
            ], range: range)
            storage.removeAttribute(.pointWebLink, range: range)
            storage.removeAttribute(.kern, range: range)
            x += size.width + gap
            // The caption is the file's name, never a width (`|300`), which isn't a label.
            if case .embed = image.token.kind {
                let inside = NSRange(location: range.location + 3, length: range.length - 5)
                let bar = (text.substring(with: inside) as NSString).range(of: "|")
                storage.addAttribute(.pointHidden, value: true, range: range)
                storage.removeAttribute(.pointHidden, range: NSRange(location: inside.location, length: bar.location == NSNotFound ? inside.length : bar.location))
            }
            // Captions side by side are kept apart.
            if index < images.count - 1 {
                var last = NSMaxRange(range) - 1
                while last > range.location, storage.attribute(.pointHidden, at: last, effectiveRange: nil) != nil { last -= 1 }
                storage.addAttribute(.kern, value: 12, range: NSRange(location: last, length: 1))
            }
        }
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
            let image = Self.imageEmbed(token, in: text)
            let exists = image.map { imageURL?($0.target) != nil || imageURL == nil } ?? wikiLinkExists?(target) ?? true
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

    /// Lays a table out as a grid, drawn by a view over it (see `TableGridView`), without a
    /// character changing. Its Markdown is hidden, and its first line is made as tall as the
    /// grid, its others a sliver, so the text after it starts below the grid. Each cell's text
    /// keeps its formatting here, for the grid to show; the grid's geometry (`TableDecoration`)
    /// is worked out here too, measuring each cell as the grid lays it out.
    func layOutTable(_ range: NSRange, storage: NSTextStorage, text: NSString) {
        guard theme.rendersTables, let lines = MarkdownTable.lines(in: text, range: range) else { return }
        let rows = lines.filter { !$0.isDelimiter }
        let table = MarkdownTable(lines: lines, text: text)
        let alignments = table.alignments
        let columns = alignments.count
        let padding = theme.tableCellPadding

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

        let widths = columnWidths(table, rows: rows, range: range, storage: storage)
        var edges: [CGFloat] = [0]
        for width in widths { edges.append((edges.last! + width + padding * 2).rounded()) }
        // Each row as tall as its tallest cell, wrapped in its column.
        let heights = rows.enumerated().map { r, row in
            let tallest = (0..<columns).map { column -> CGFloat in
                let cell = column < row.cells.count ? tableCellText(row.cells[column], in: storage, alignment: alignments[column])
                    : NSAttributedString()
                return tableMeasurer.height(of: cell, width: widths[column], theme: theme,
                                            emptyAttributes: emptyCellAttributes(header: r == 0))
            }.max() ?? 0
            return tallest + theme.tableRowPadding * 2
        }
        let decoration = TableDecoration(columnEdges: edges, columnWidths: widths, rowHeights: heights, alignments: alignments)
        storage.addAttribute(.pointBlock, value: BlockDecoration.table(decoration), range: range)

        // The first line holds the grid's height; the rest, the delimiter row's too, are slivers.
        var location = range.location
        var first = true
        while location < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let last = NSMaxRange(line) >= NSMaxRange(range)
            let height = first ? heights.reduce(0, +) : 0.1
            let style = paragraphStyle {
                $0.minimumLineHeight = height
                $0.maximumLineHeight = height
                $0.lineHeightMultiple = 1
                $0.paragraphSpacingBefore = 0
                if !last { $0.paragraphSpacing = 0 }
            }
            storage.addAttribute(.paragraphStyle, value: style, range: line)
            first = false
            guard NSMaxRange(line) > location else { break }
            location = NSMaxRange(line)
        }
    }

    /// How wide each column's text is: as wide as its widest cell, unless the table is wider
    /// than the text, when the widest columns give up room until it fits. While the table is
    /// typed in, they stay as they were.
    private func columnWidths(_ table: MarkdownTable, rows: [MarkdownTable.Line], range: NSRange, storage: NSTextStorage) -> [CGFloat] {
        let columns = table.columnCount
        let narrowest = theme.bodySize * 2
        let room = theme.textWidth - theme.tableCellPadding * 2 * CGFloat(columns)
        if let held = heldTableWidths, held.table == range.location, held.widths.count == columns {
            return held.widths
        }
        let measured = rows.map { row in row.cells.map { visibleWidth(of: $0, in: storage) } }
        var widths = (0..<columns).map { column in
            max(narrowest, measured.compactMap { column < $0.count ? $0[column] : nil }.max() ?? 0)
        }
        guard widths.reduce(0, +) > room else { return widths }
        // Columns narrower than an equal share keep their width; the rest share what's left.
        var left = max(room, narrowest * CGFloat(columns))
        var open = Set(widths.indices)
        while !open.isEmpty {
            let share = left / CGFloat(open.count)
            let narrow = open.filter { widths[$0] <= share }
            guard !narrow.isEmpty else {
                for column in open { widths[column] = share.rounded(.down) }
                break
            }
            for column in narrow {
                left -= widths[column]
                open.remove(column)
            }
        }
        return widths
    }

    /// A table cell's text as its grid shows it: as styled in the note, aligned as its column is.
    func tableCellText(_ range: NSRange, in storage: NSAttributedString, alignment: MarkdownTable.Alignment) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let all = NSRange(location: 0, length: text.length)
        text.removeAttribute(.pointBlock, range: all)
        text.addAttribute(.paragraphStyle, value: tableCellParagraphStyle(alignment), range: all)
        return text
    }

    func tableCellParagraphStyle(_ alignment: MarkdownTable.Alignment) -> NSParagraphStyle {
        paragraphStyle {
            $0.paragraphSpacing = 0
            $0.alignment = switch alignment {
            case .center: .center
            case .right: .right
            case .none, .left: .natural
            }
        }
    }

    /// What an empty cell is measured with, and what's typed into one starts with.
    func emptyCellAttributes(header: Bool) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        if header { attributes[.font] = theme.body.adding(PlatformTraits.bold) }
        return attributes
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

    /// Hides a whole line under a fold, as frontmatter is hidden.
    func hideLine(_ line: NSRange, storage: NSTextStorage, text: NSString) {
        collapseLine(line, storage: storage, text: text, height: 0.1)
        // Nothing drawn for it either: no bullet, checkbox, tag pill or block background.
        let full = text.lineRange(for: line)
        for key: NSAttributedString.Key in [.pointListMarker, .pointTag, .pointWebLink, .pointRule, .pointBlock, .pointImage] {
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
