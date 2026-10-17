#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Lays out note text with Markdown markers hidden, and draws what replaces them:
/// bullets, checkboxes, quote bars, callout and code backgrounds, and rules.
final class ImprintLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
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

    /// Hidden characters become null glyphs: still in the text, but with no width and never drawn.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var modified: [NSLayoutManager.GlyphProperty]?
        var hiddenRun = NSRange(location: NSNotFound, length: 0)
        for i in 0..<glyphRange.length {
            let index = characterIndexes[i]
            if !NSLocationInRange(index, hiddenRun) {
                var effective = NSRange()
                let hidden = storage.attribute(.imprintHidden, at: index, effectiveRange: &effective) != nil
                hiddenRun = hidden ? effective : NSRange(location: NSNotFound, length: 0)
                if !hidden { continue }
            }
            if modified == nil {
                modified = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            }
            modified![i] = .null
        }
        guard let modified else { return 0 }
        modified.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    // MARK: Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let everything = NSRange(location: 0, length: storage.length)

        var drawnBlocks = Set<Int>()
        storage.enumerateAttribute(.imprintBlock, in: characters) { value, range, _ in
            guard let block = value as? BlockDecoration else { return }
            var full = NSRange()
            _ = storage.attribute(.imprintBlock, at: range.location, longestEffectiveRange: &full, in: everything)
            guard drawnBlocks.insert(full.location).inserted else { return }
            draw(block, rect: rect(forCharacters: full, in: container, origin: origin), range: full, storage: storage)
        }

        storage.enumerateAttribute(.imprintListMarker, in: characters) { value, range, _ in
            guard let decoration = value as? ListMarkerDecoration else { return }
            draw(decoration, at: range.location, storage: storage, container: container, origin: origin)
        }

        storage.enumerateAttribute(.imprintRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let line = lineRect(containing: range.location, storage: storage)
            let padding = container.lineFragmentPadding
            let y = (origin.y + line.midY).rounded() + 0.5
            NSColor.separatorColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x + line.minX + padding, y: y))
            path.line(to: NSPoint(x: origin.x + line.maxX - padding, y: y))
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// The line fragment holding the character at `index`.
    ///
    /// Measured from the line's first visible glyph (or its line break), because hidden
    /// glyphs at the start of a line are reported as part of the line before.
    func lineRect(containing index: Int, storage: NSTextStorage) -> NSRect {
        guard storage.length > 0 else { return extraLineFragmentRect }
        let text = storage.string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(index, text.length), length: 0))
        var k = start
        while k < contentsEnd, storage.attribute(.imprintHidden, at: k, effectiveRange: nil) != nil { k += 1 }
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
        while k < contentsEnd, storage.attribute(.imprintHidden, at: k, effectiveRange: nil) != nil { k += 1 }
        return k < contentsEnd ? k : nil
    }

    /// The full-width rectangle covering the lines of a character range.
    private func rect(forCharacters range: NSRange, in container: NSTextContainer, origin: NSPoint) -> NSRect {
        guard range.length > 0, let storage = textStorage else { return .zero }
        let first = lineRect(containing: range.location, storage: storage)
        let last = lineRect(containing: NSMaxRange(range) - 1, storage: storage)
        let padding = container.lineFragmentPadding
        return NSRect(
            x: origin.x + first.minX + padding,
            y: origin.y + first.minY,
            width: first.width - padding * 2,
            height: last.maxY - first.minY - theme.paragraphSpacing
        )
    }

    private func draw(_ block: BlockDecoration, rect: NSRect, range: NSRange, storage: NSTextStorage) {
        guard rect.height > 0 else { return }
        switch block {
        case .quote:
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 2, y: rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()
        case .callout(let type):
            let color = theme.calloutColor(type)
            color.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6).fill()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 2, y: rect.minY + 2, width: 3, height: rect.height - 4), xRadius: 1.5, yRadius: 1.5).fill()
            // With no title of its own, a callout is titled by its type, as in Obsidian.
            if firstVisibleCharacter(onLineOf: range.location, storage: storage) == nil {
                let line = lineRect(containing: range.location, storage: storage)
                let font = NSFont.systemFont(ofSize: theme.bodySize, weight: .bold)
                let label = type.prefix(1).uppercased() + type.dropFirst()
                let baseline = line.minY + (line.height - theme.paragraphSpacing + font.ascender - font.descender) / 2 - font.descender
                (label as NSString).draw(at: NSPoint(x: rect.minX + 16, y: rect.minY + (baseline - font.ascender - line.minY)),
                                         withAttributes: [.font: font, .foregroundColor: color])
            }
        case .code:
            NSColor.textColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func draw(_ decoration: ListMarkerDecoration, at index: Int, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        let line = lineRect(containing: index, storage: storage)
        let font = textFont(near: index, storage: storage)
        let baseline: CGFloat
        if let visible = firstVisibleCharacter(onLineOf: index, storage: storage) {
            baseline = origin.y + line.minY + location(forGlyphAt: glyphIndexForCharacter(at: visible)).y
        } else {
            // An empty item: centre the marker in its line.
            baseline = origin.y + line.minY + (line.height - theme.paragraphSpacing + font.ascender - font.descender) / 2 - font.descender + font.descender
        }
        let x = origin.x + container.lineFragmentPadding + theme.indentPerLevel * CGFloat(decoration.level)

        switch decoration.marker {
        case .bullet:
            let size: CGFloat = 5
            let center = NSPoint(x: x + theme.markerWidth / 2 - 3, y: baseline - font.xHeight / 2)
            NSColor.textColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)).fill()
        case .ordered(let number):
            let label = "\(number)." as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            let width = label.size(withAttributes: attributes).width
            label.draw(at: NSPoint(x: x + theme.markerWidth - 6 - width, y: baseline - font.ascender), withAttributes: attributes)
        case .task(let done):
            let rect = checkboxRect(x: x, baseline: baseline, font: font)
            let color: NSColor = done ? .controlAccentColor : .tertiaryLabelColor
            let name = done ? "checkmark.circle.fill" : "circle"
            let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [done ? .white : color, color]))
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: done ? "Done" : "To do")?
                .withSymbolConfiguration(configuration) {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }

    func checkboxRect(x: CGFloat, baseline: CGFloat, font: NSFont) -> NSRect {
        let size = (font.pointSize * 1.05).rounded()
        return NSRect(x: x + theme.markerWidth / 2 - size / 2 - 3, y: baseline - font.capHeight / 2 - size / 2, width: size, height: size)
    }

    /// The font of the first visible character on a line, for sizing its marker.
    func textFont(near index: Int, storage: NSTextStorage) -> NSFont {
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var k = index
        while k < NSMaxRange(line), storage.attribute(.imprintHidden, at: k, effectiveRange: nil) != nil { k += 1 }
        let at = min(k, max(storage.length - 1, 0))
        return storage.length > 0 ? (storage.attribute(.font, at: at, effectiveRange: nil) as? NSFont ?? theme.body) : theme.body
    }
}
#endif
