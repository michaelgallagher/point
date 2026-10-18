#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Applies display attributes for parsed Markdown to a text storage.
///
/// It only ever changes attributes, never characters, so the text stays exactly
/// what is on disk.
struct MarkdownStyler {
    var theme = EditorTheme()
    /// Shows the raw Markdown, every marker visible, in a monospaced font.
    var showsMarkdown = false

    var baseParagraphStyle: NSParagraphStyle {
        // Line height is added by the layout manager, centred on the text, not here:
        // the paragraph style would put all the extra space above the text.
        let style = NSMutableParagraphStyle()
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

        if showsMarkdown {
            storage.setAttributes([.font: theme.mono, .foregroundColor: NSColor.textColor,
                                   .paragraphStyle: baseParagraphStyle], range: range)
            return range
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
            let style = paragraphStyle { $0.paragraphSpacingBefore = theme.spaceBeforeHeading(level: level) }
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
                $0.paragraphSpacing = 0
            }
            storage.addAttributes([.font: theme.mono, .paragraphStyle: style, .imprintBlock: BlockDecoration.code,
                                   .imprintLineHeight: CGFloat(1.15)], range: range)
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
        case .link(let destination), .image(let destination):
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand], range: range)
            if Self.isWebAddress(destination), let close = token.syntax.last, close.location > range.location {
                markWebLink(at: close.location - 1, storage: storage) // The last letter of the link text.
            }
        case .url:
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand], range: range)
            markWebLink(at: NSMaxRange(range) - 1, storage: storage)
        case .wikiLink, .embed:
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand], range: range)
        case .tag:
            // Drawn as a pill by the layout manager, with a little room on each side for it.
            storage.addAttributes([.imprintTag: true, .cursor: NSCursor.pointingHand], range: range)
            if range.location > 0, text.character(at: range.location - 1) != 10 {
                storage.addAttribute(.kern, value: CGFloat(3), range: NSRange(location: range.location - 1, length: 1))
            }
            storage.addAttribute(.kern, value: CGFloat(3), range: NSRange(location: NSMaxRange(range) - 1, length: 1))
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

    static func isWebAddress(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    /// Makes room after a link's last letter for the arrow symbol, which the layout manager draws.
    private func markWebLink(at index: Int, storage: NSTextStorage) {
        guard index >= 0, index < storage.length else { return }
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? theme.body
        storage.addAttributes([.imprintWebLink: true, .kern: theme.webLinkSpace(for: font)], range: NSRange(location: index, length: 1))
    }

    private func paragraphStyle(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = baseParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        configure(style)
        return style
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
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: style, .imprintCollapsed: true], range: full)
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
