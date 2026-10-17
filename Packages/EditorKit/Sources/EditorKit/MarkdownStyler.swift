#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Applies display attributes for parsed Markdown to a text storage.
///
/// It only ever changes attributes, never characters, so the text stays exactly
/// what is on disk.
struct MarkdownStyler {
    var theme = EditorTheme()

    var baseParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.paragraphSpacing = theme.paragraphSpacing
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.body, .foregroundColor: NSColor.textColor, .paragraphStyle: baseParagraphStyle]
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

        storage.setAttributes(baseAttributes, range: range)
        for token in tokens where intersects(token.range, range) {
            apply(token, to: storage, text: text)
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
            // Shown small and quiet for now. M2 replaces it with the collapsed properties strip.
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: theme.bodySize - 3, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ], range: range)
            return

        case .heading(let level):
            let font = theme.headingFont(level: level)
            let style = paragraphStyle { $0.paragraphSpacingBefore = font.pointSize * 0.5 }
            storage.addAttributes([.font: font, .paragraphStyle: style], range: range)

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
                    addTrait(.bold, in: titleRange, storage: storage)
                }
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
            storage.addAttributes([.paragraphStyle: style, .imprintBlock: block], range: range)

        case .listItem(let marker, let indent):
            let level = Int((Double(indent) / 4).rounded(.up))
            let start = theme.indentPerLevel * CGFloat(level) + theme.markerWidth
            let style = paragraphStyle {
                $0.firstLineHeadIndent = start
                $0.headIndent = start
            }
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            if let markerRange = token.syntax.first {
                // Hide the indent and the marker; the layout manager draws the marker instead.
                let hidden = NSRange(location: range.location, length: NSMaxRange(markerRange) - range.location)
                storage.addAttribute(.imprintHidden, value: true, range: hidden)
                storage.addAttribute(.imprintListMarker, value: ListMarkerDecoration(marker: marker, level: level),
                                     range: NSRange(location: range.location, length: 1))
                if case .task(done: true) = marker {
                    let content = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(range) - NSMaxRange(markerRange))
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: content)
                }
            }
            return

        case .codeBlock:
            let style = paragraphStyle {
                $0.firstLineHeadIndent = 12
                $0.headIndent = 12
                $0.tailIndent = -12
                $0.lineHeightMultiple = 1.1
                $0.paragraphSpacing = 0
            }
            storage.addAttributes([.font: theme.mono, .paragraphStyle: style, .imprintBlock: BlockDecoration.code], range: range)
            for fence in token.syntax {
                collapseLine(fence, storage: storage, text: text)
            }
            return

        case .thematicBreak:
            storage.addAttribute(.imprintRule, value: true, range: range)

        case .table:
            storage.addAttribute(.font, value: theme.mono, range: range)

        case .footnoteDefinition:
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: theme.bodySize - 2),
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)

        case .strong:
            addTrait(.bold, in: range, storage: storage)
        case .emphasis:
            addTrait(.italic, in: range, storage: storage)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
        case .code:
            let size = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? theme.bodySize
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular),
                .backgroundColor: NSColor.textColor.withAlphaComponent(0.07),
            ], range: range)
        case .link, .image, .wikiLink, .embed, .url:
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        case .tag:
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
        case .footnoteReference:
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: theme.bodySize * 0.75),
                .baselineOffset: theme.bodySize * 0.35,
                .foregroundColor: NSColor.linkColor,
            ], range: range)
        case .escape:
            break
        }

        for marker in token.syntax {
            storage.addAttribute(.imprintHidden, value: true, range: marker)
        }
    }

    private func paragraphStyle(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = baseParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        configure(style)
        return style
    }

    /// Hides a whole line, such as a code fence, leaving only a sliver of space.
    private func collapseLine(_ line: NSRange, storage: NSTextStorage, text: NSString) {
        let full = text.lineRange(for: line) // Includes the line break, which sets the line's height.
        let style = paragraphStyle {
            $0.minimumLineHeight = 6
            $0.maximumLineHeight = 6
            $0.lineHeightMultiple = 1
            $0.paragraphSpacing = 0
            $0.paragraphSpacingBefore = 0
        }
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: style], range: full)
        storage.addAttribute(.imprintHidden, value: true, range: line)
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, in range: NSRange, storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? theme.body
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            let converted = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            storage.addAttribute(.font, value: converted, range: subrange)
        }
    }
}
#endif
