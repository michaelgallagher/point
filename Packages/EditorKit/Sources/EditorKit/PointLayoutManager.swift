#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MarkdownKit

/// Lays out note text with Markdown markers hidden, and draws what replaces them:
/// bullets, checkboxes, quote bars, callout and code backgrounds, and rules.
final class PointLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var theme = EditorTheme()

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // MARK: Hiding markers

    /// Hidden characters become zero-width control glyphs: still in the text, never drawn,
    /// and (unlike null glyphs) still placed on their own line, so cursor movement and
    /// hit-testing stay on the right line.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: PlatformFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var modified: [NSLayoutManager.GlyphProperty]?
        var hiddenRun = NSRange(location: NSNotFound, length: 0)
        for i in 0..<glyphRange.length {
            let index = characterIndexes[i]
            if !NSLocationInRange(index, hiddenRun) {
                var effective = NSRange()
                let hidden = storage.attribute(.pointHidden, at: index, effectiveRange: &effective) != nil
                hiddenRun = hidden ? effective : NSRange(location: NSNotFound, length: 0)
                if !hidden { continue }
            }
            if modified == nil {
                modified = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            }
            modified![i] = .controlCharacter
        }
        guard let modified else { return 0 }
        modified.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        if layoutManager.textStorage?.attribute(.pointHidden, at: charIndex, effectiveRange: nil) != nil {
            return .zeroAdvancement
        }
        return action
    }

    /// Adds the theme's extra line height half above and half below the text, so
    /// selections and backgrounds sit evenly around it.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characters.location < storage.length else { return false }
        if let style = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle,
           style.maximumLineHeight > 0 {
            return false // A collapsed line, such as a code fence, keeps its sliver of height.
        }
        let multiple = storage.attribute(.pointLineHeight, at: characters.location, effectiveRange: nil) as? CGFloat
            ?? theme.lineHeightMultiple
        var tallest: CGFloat = 0
        storage.enumerateAttribute(.font, in: characters) { value, _, _ in
            if let font = value as? PlatformFont { tallest = max(tallest, font.ascender - font.descender) }
        }
        let extra = (tallest * (multiple - 1)).rounded()
        guard extra > 0 else { return false }
        lineFragmentRect.pointee.size.height += extra
        lineFragmentUsedRect.pointee.size.height += extra
        baselineOffset.pointee += extra / 2
        return true
    }

    // MARK: Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let everything = NSRange(location: 0, length: storage.length)

        var drawnBlocks = Set<Int>()
        storage.enumerateAttribute(.pointBlock, in: characters) { value, range, _ in
            guard let block = value as? BlockDecoration else { return }
            var full = NSRange()
            _ = storage.attribute(.pointBlock, at: range.location, longestEffectiveRange: &full, in: everything)
            guard drawnBlocks.insert(full.location).inserted else { return }
            draw(block, rect: rect(forCharacters: full, in: container, origin: origin), range: full, storage: storage)
        }

        storage.enumerateAttribute(.pointListHighlight, in: characters) { value, range, _ in
            guard let color = value as? PlatformColor else { return }
            // Item by item: two in a row with the same colour are still two.
            let text = storage.string as NSString
            var location = range.location
            while location < NSMaxRange(range) {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                drawListHighlight(color, for: NSIntersectionRange(line, range), storage: storage, container: container, origin: origin)
                location = NSMaxRange(line)
            }
        }

        drawListGuides(in: characters, storage: storage, container: container, origin: origin)

        storage.enumerateAttribute(.pointListMarker, in: characters) { value, range, _ in
            guard let decoration = value as? ListMarkerDecoration else { return }
            draw(decoration, at: range.location, storage: storage, container: container, origin: origin)
        }

        storage.enumerateAttribute(.pointRoundedBackground, in: characters) { value, range, _ in
            guard let color = value as? PlatformColor else { return }
            drawRoundedBackground(color, for: range, storage: storage, container: container, origin: origin)
        }

        storage.enumerateAttribute(.pointTag, in: characters) { value, range, _ in
            guard value != nil else { return }
            drawTagPill(for: range, storage: storage, container: container, origin: origin)
        }

        storage.enumerateAttribute(.pointWebLink, in: characters) { value, range, _ in
            guard value != nil else { return }
            drawWebLinkSymbol(after: range.location, storage: storage, container: container, origin: origin)
        }

        storage.enumerateAttribute(.pointRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let line = lineRect(containing: range.location, storage: storage)
            let padding = container.lineFragmentPadding
            let y = (origin.y + line.midY).rounded() + 0.5
            PlatformColor.separatorColor.setStroke()
            let path = PlatformBezierPath()
            path.move(to: CGPoint(x: origin.x + line.minX + padding, y: y))
            path.line(to: CGPoint(x: origin.x + line.maxX - padding, y: y))
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// A highlighted list item's background: its colour, faint, from just before its marker to
    /// the end of the text column, on each line the item takes.
    private func drawListHighlight(_ color: PlatformColor, for range: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        let start = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location
        guard let decoration = storage.attribute(.pointListMarker, at: start, effectiveRange: nil) as? ListMarkerDecoration else { return }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        var bounds = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, _, _ in bounds = bounds.union(line) }
        guard !bounds.isNull else { return }
        let left = container.lineFragmentPadding + theme.indentPerLevel * CGFloat(decoration.level) - 4
        let rect = CGRect(x: origin.x + left, y: origin.y + bounds.minY,
                          width: bounds.maxX - container.lineFragmentPadding - left + 4, height: bounds.height)
        color.withAlphaComponent(0.14).setFill()
        PlatformBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    /// A highlight's or inline code's background: around the text's own height, not the whole
    /// line, with slightly rounded corners, on each line it covers.
    private func drawRoundedBackground(_ color: PlatformColor, for range: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        color.setFill()
        enumerateLineFragments(forGlyphRange: glyphs) { [self] line, _, _, lineGlyphs, _ in
            let part = NSIntersectionRange(glyphs, lineGlyphs)
            guard part.length > 0 else { return }
            let bounds = boundingRect(forGlyphRange: part, in: container)
            guard bounds.width > 0.5 else { return }
            let character = characterIndexForGlyph(at: part.location)
            let font = storage.attribute(.font, at: min(character, storage.length - 1), effectiveRange: nil) as? PlatformFont ?? theme.body
            let baseline = origin.y + line.minY + location(forGlyphAt: part.location).y
            let rect = CGRect(x: origin.x + bounds.minX - 2, y: baseline - font.ascender - 1,
                              width: bounds.width + 4, height: (font.ascender - font.descender + 2).rounded())
            PlatformBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }

    /// A tag's background: fully rounded, in the system highlight colour.
    private func drawTagPill(for range: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? theme.body
        // A tag has no spaces, so it never wraps: one line, one pill.
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let bounds = boundingRect(forGlyphRange: glyphs, in: container)
        let baseline = origin.y + line.minY + location(forGlyphAt: glyphs.location).y
        let height = (font.ascender - font.descender + 4).rounded()
        // The glyphs' bounds include the space added after the tag's last letter; leave it out.
        let trailing = storage.attribute(.kern, at: NSMaxRange(range) - 1, effectiveRange: nil) as? CGFloat ?? 0
        // 6 points either side of the text, and 2 above and below.
        let rect = CGRect(x: origin.x + bounds.minX - 6, y: baseline - font.ascender - 2, width: bounds.width - trailing + 12, height: height)
        // The highlight colour, a quarter of the way towards the page colour, so pills stay light.
        let fill = PlatformColor.selectedTextBackgroundColor.blended(withFraction: 0.25, of: .textBackgroundColor) ?? .selectedTextBackgroundColor
        fill.setFill()
        PlatformBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
    }

    /// The `arrow.up.right.circle` symbol in the space made after a web link's last letter.
    private func drawWebLinkSymbol(after index: Int, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        let glyph = glyphIndexForCharacter(at: index)
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont ?? theme.body
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let letter = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        // The symbol sits at the end of the letter's advance, which includes the added space.
        var end = letter.maxX
        if glyph + 1 < numberOfGlyphs, lineFragmentRect(forGlyphAt: glyph + 1, effectiveRange: nil).minY == line.minY {
            end = line.minX + location(forGlyphAt: glyph + 1).x
        }
        let size = theme.webLinkSymbolSize(for: font)
        let baseline = origin.y + line.minY + location(forGlyphAt: glyph).y
        let rect = CGRect(x: origin.x + end - size - 1, y: baseline - font.capHeight / 2 - size / 2, width: size, height: size)
        symbolImage("arrow.up.right.circle", pointSize: size, colors: [.linkColor], description: "Web link")?.drawFlipped(in: rect)
    }

    /// The line fragment holding the character at `index`.
    ///
    /// Measured from the line's first visible glyph (or its line break), because hidden
    /// glyphs at the start of a line are reported as part of the line before.
    func lineRect(containing index: Int, storage: NSTextStorage) -> CGRect {
        guard storage.length > 0 else { return extraLineFragmentRect }
        let text = storage.string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(index, text.length), length: 0))
        var k = start
        while k < contentsEnd, storage.attribute(.pointHidden, at: k, effectiveRange: nil) != nil { k += 1 }
        if k >= text.length {
            // A fully hidden last line with no line break: fall back to its first glyph.
            k = min(start, text.length - 1)
        }
        return lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: k), effectiveRange: nil)
    }

    /// The first visible character on the line holding `index`, or nil if the line is all hidden.
    func firstVisibleCharacter(onLineOf index: Int, storage: NSTextStorage) -> Int? {
        let text = storage.string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(index, text.length), length: 0))
        var k = start
        while k < contentsEnd, storage.attribute(.pointHidden, at: k, effectiveRange: nil) != nil { k += 1 }
        return k < contentsEnd ? k : nil
    }

    /// The full-width rectangle covering the lines of a character range.
    private func rect(forCharacters range: NSRange, in container: NSTextContainer, origin: CGPoint) -> CGRect {
        guard range.length > 0, let storage = textStorage else { return .zero }
        let first = lineRect(containing: range.location, storage: storage)
        let last = lineRect(containing: NSMaxRange(range) - 1, storage: storage)
        let padding = container.lineFragmentPadding
        return CGRect(
            x: origin.x + first.minX + padding,
            y: origin.y + first.minY,
            width: first.width - padding * 2,
            height: last.maxY - first.minY - theme.paragraphSpacing
        )
    }

    private func draw(_ block: BlockDecoration, rect: CGRect, range: NSRange, storage: NSTextStorage) {
        guard rect.height > 0 else { return }
        switch block {
        case .quote:
            PlatformColor.labelColor.setFill() // Black, or white in dark mode.
            PlatformBezierPath(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()
        case .callout(let type):
            let color = theme.calloutColor(type)
            color.withAlphaComponent(0.1).setFill()
            PlatformBezierPath(roundedRect: rect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6).fill()
            color.setFill()
            PlatformBezierPath(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: 3, height: rect.height - 4), xRadius: 1.5, yRadius: 1.5).fill()
            // With no title of its own, a callout is titled by its type, as in Obsidian.
            if firstVisibleCharacter(onLineOf: range.location, storage: storage) == nil {
                let font = PlatformFont.systemFont(ofSize: theme.bodySize, weight: .bold)
                let label = type.prefix(1).uppercased() + type.dropFirst()
                let baseline = rect.minY + location(forGlyphAt: glyphIndexForCharacter(at: range.location)).y
                (label as NSString).draw(at: CGPoint(x: rect.minX + 16, y: baseline - font.ascender),
                                         withAttributes: [.font: font, .foregroundColor: color])
            }
        case .code:
            PlatformColor.textColor.withAlphaComponent(0.05).setFill()
            PlatformBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func draw(_ decoration: ListMarkerDecoration, at index: Int, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        let line = lineRect(containing: index, storage: storage)
        let font = textFont(near: index, storage: storage)
        let baseline: CGFloat
        if let visible = firstVisibleCharacter(onLineOf: index, storage: storage) {
            baseline = origin.y + line.minY + location(forGlyphAt: glyphIndexForCharacter(at: visible)).y
        } else {
            // An empty item: its hidden marker glyphs still sit on the baseline.
            baseline = origin.y + line.minY + location(forGlyphAt: glyphIndexForCharacter(at: index)).y
        }
        let x = origin.x + container.lineFragmentPadding + theme.indentPerLevel * CGFloat(decoration.level)

        switch decoration.marker {
        case .bullet:
            // A highlighted item's bullet is in its colour.
            let highlight = storage.attribute(.pointListHighlight, at: index, effectiveRange: nil) as? PlatformColor
            (highlight ?? PlatformColor.textColor).setFill()
            PlatformBezierPath(ovalIn: bulletRect(x: x, baseline: baseline, font: font)).fill()
        case .ordered(let number):
            let label = "\(number)." as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PlatformColor.secondaryLabelColor]
            let width = label.size(withAttributes: attributes).width
            label.draw(at: CGPoint(x: x + theme.markerWidth - 6 - width, y: baseline - font.ascender), withAttributes: attributes)
        case .task(let done):
            let rect = checkboxRect(x: x, baseline: baseline, font: font)
            let color: PlatformColor = done ? .controlAccentColor : .tertiaryLabelColor
            let name = done ? "checkmark.circle.fill" : "circle"
            symbolImage(name, pointSize: rect.height, colors: [done ? .white : color, color], description: done ? "Done" : "To do")?
                .drawFlipped(in: rect)
        }
    }

    // MARK: List guides

    /// A thin vertical line under each list item that has items nested beneath it, centred
    /// on its marker, so a sub-list reads as belonging to the item above it. It starts the
    /// same distance below the item's marker as it stops above the next marker down (the
    /// next item after the nested ones, or where one would be when the list ends there).
    private func drawListGuides(in visible: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: CGPoint) {
        // Every item in the note, as a nested item can start above what's being drawn.
        var items: [(index: Int, decoration: ListMarkerDecoration)] = []
        storage.enumerateAttribute(.pointListMarker, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let decoration = value as? ListMarkerDecoration { items.append((range.location, decoration)) }
        }
        guard items.count > 1 else { return }
        let text = storage.string as NSString
        let gap: CGFloat = 4
        PlatformColor.separatorColor.setFill()
        for (i, item) in items.enumerated() {
            // The items after it nested deeper, up to the next at its level or above, or a
            // paragraph that ends the list.
            var last: Int?
            var j = i + 1
            while j < items.count, items[j].decoration.level > item.decoration.level,
                  Self.onlyContinues(text, from: items[j - 1].index, to: items[j].index) {
                last = j
                j += 1
            }
            guard let last else { continue }
            let lastLine = text.lineRange(for: NSRange(location: items[last].index, length: 0))
            let span = NSRange(location: item.index, length: NSMaxRange(lastLine) - item.index)
            guard NSIntersectionRange(span, visible).length > 0 || NSLocationInRange(visible.location, span) else { continue }

            let marker = markerRect(for: item, storage: storage, container: container, origin: origin)
            let top = marker.maxY + gap
            let bottom: CGFloat
            if j < items.count, items[j].decoration.level <= item.decoration.level,
               Self.onlyContinues(text, from: items[last].index, to: items[j].index) {
                // The next item, at this item's level: stop as far above its marker.
                bottom = markerRect(for: items[j], storage: storage, container: container, origin: origin).minY - gap
            } else {
                // The list ends: stop where this item's marker would be on the line after.
                let lastRect = lineRect(containing: max(NSMaxRange(lastLine) - 1, items[last].index), storage: storage)
                let itemLine = lineRect(containing: item.index, storage: storage)
                bottom = origin.y + lastRect.maxY + (marker.minY - (origin.y + itemLine.minY)) - gap
            }
            guard bottom > top else { continue }
            let width: CGFloat = 1
            PlatformBezierPath(rect: CGRect(x: (marker.midX - width / 2).rounded(), y: top.rounded(), width: width, height: (bottom - top).rounded())).fill()
        }
    }

    /// Where an item's marker is drawn, in the view.
    private func markerRect(for item: (index: Int, decoration: ListMarkerDecoration), storage: NSTextStorage,
                            container: NSTextContainer, origin: CGPoint) -> CGRect {
        let line = lineRect(containing: item.index, storage: storage)
        let font = textFont(near: item.index, storage: storage)
        let first = firstVisibleCharacter(onLineOf: item.index, storage: storage) ?? item.index
        let baseline = origin.y + line.minY + location(forGlyphAt: glyphIndexForCharacter(at: first)).y
        let x = origin.x + container.lineFragmentPadding + theme.indentPerLevel * CGFloat(item.decoration.level)
        return markerRect(item.decoration.marker, x: x, baseline: baseline, font: font)
    }

    /// Whether only an item's own continuation lies between two items' lines: blank lines,
    /// or lines indented under the item, not a paragraph that ends the list.
    private static func onlyContinues(_ text: NSString, from previous: Int, to next: Int) -> Bool {
        let previousLine = text.lineRange(for: NSRange(location: previous, length: 0))
        let nextLine = text.lineRange(for: NSRange(location: next, length: 0))
        var position = NSMaxRange(previousLine)
        while position < nextLine.location {
            let line = text.lineRange(for: NSRange(location: position, length: 0))
            let content = text.substring(with: line)
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !(content.hasPrefix(" ") || content.hasPrefix("\t")) { return false }
            position = NSMaxRange(line)
        }
        return true
    }

    func checkboxRect(x: CGFloat, baseline: CGFloat, font: PlatformFont) -> CGRect {
        let size = (font.pointSize * 1.05).rounded()
        return CGRect(x: x + theme.markerAxis - size / 2, y: baseline - font.capHeight / 2 - size / 2, width: size, height: size)
    }

    /// A bullet's dot: centred on the same axis as a checkbox, at the middle of the x-height.
    func bulletRect(x: CGFloat, baseline: CGFloat, font: PlatformFont) -> CGRect {
        let size: CGFloat = 5
        return CGRect(x: x + theme.markerAxis - size / 2, y: baseline - font.xHeight / 2 - size / 2, width: size, height: size)
    }

    /// Where a list item's marker is drawn, for its line's baseline and font.
    private func markerRect(_ marker: ListMarker, x: CGFloat, baseline: CGFloat, font: PlatformFont) -> CGRect {
        switch marker {
        case .bullet: return bulletRect(x: x, baseline: baseline, font: font)
        case .task: return checkboxRect(x: x, baseline: baseline, font: font)
        case .ordered(let number):
            // The number, right-aligned before the text, from its cap height to the baseline.
            let width = ("\(number)." as NSString).size(withAttributes: [.font: font]).width
            return CGRect(x: x + theme.markerWidth - 6 - width, y: baseline - font.capHeight, width: width, height: font.capHeight)
        }
    }

    /// The font of the first visible character on a line, for sizing its marker.
    func textFont(near index: Int, storage: NSTextStorage) -> PlatformFont {
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var k = index
        while k < NSMaxRange(line), storage.attribute(.pointHidden, at: k, effectiveRange: nil) != nil { k += 1 }
        let at = min(k, max(storage.length - 1, 0))
        return storage.length > 0 ? (storage.attribute(.font, at: at, effectiveRange: nil) as? PlatformFont ?? theme.body) : theme.body
    }
}
