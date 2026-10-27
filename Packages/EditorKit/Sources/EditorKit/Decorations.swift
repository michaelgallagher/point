#if canImport(AppKit)
import AppKit
import MarkdownKit

extension NSAttributedString.Key {
    /// Marker characters (`**`, `[[`, `# `) that are in the file but not shown.
    static let pointHidden = NSAttributedString.Key("point.hidden")
    /// A line squeezed to a sliver, such as a code fence or frontmatter. The cursor skips it.
    static let pointCollapsed = NSAttributedString.Key("point.collapsed")
    /// A block drawn behind its text: a quote bar, callout or code background.
    static let pointBlock = NSAttributedString.Key("point.block")
    /// A list marker drawn in place of the hidden `- `, `1. ` or `- [ ] `.
    static let pointListMarker = NSAttributedString.Key("point.listMarker")
    /// A horizontal rule drawn in place of the hidden `---`.
    static let pointRule = NSAttributedString.Key("point.rule")
    /// A `#tag`, drawn as a pill.
    static let pointTag = NSAttributedString.Key("point.tag")
    /// The last letter of a link to a website, followed by the arrow symbol drawn after it.
    static let pointWebLink = NSAttributedString.Key("point.webLink")
    /// A background colour (an `NSColor`) drawn with rounded corners behind the text, line by
    /// line: highlights and inline code.
    static let pointRoundedBackground = NSAttributedString.Key("point.roundedBackground")
    /// A list item highlighted by the character at its start (`- ! Important`): its colour,
    /// an `NSColor`, drawn behind the line and used for its bullet.
    static let pointListHighlight = NSAttributedString.Key("point.listHighlight")
    /// A line-height multiple (CGFloat) overriding the theme's, for example in code blocks.
    static let pointLineHeight = NSAttributedString.Key("point.lineHeight")
}

enum BlockDecoration: Hashable {
    case quote
    case callout(type: String)
    case code
}

struct ListMarkerDecoration: Hashable {
    let marker: ListMarker
    let level: Int
}

/// Sizes and colours for the editor. Apple Notes is the reference for the feel.
struct EditorTheme {
    /// The chosen sizes and styles.
    var typography = Typography()
    /// ⌘+ and ⌘−: how much bigger or smaller than chosen everything is.
    var scale: CGFloat = 1
    var bodySize: CGFloat { (CGFloat(typography.bodySize) * scale).rounded() }
    /// Extra line height, split evenly above and below the text by the layout manager.
    var lineHeightMultiple: CGFloat { CGFloat(typography.lineHeight) }
    var paragraphSpacing: CGFloat = 0
    var indentPerLevel: CGFloat = 22
    var markerWidth: CGFloat = 22
    /// Where bullets and checkboxes are centred across their marker column, from its start, so
    /// they line up with each other, and with the guide under an item with nested items.
    var markerAxis: CGFloat { markerWidth / 2 - 3 }
    /// A bullet is smaller than a checkbox, so its text starts closer: the same gap after the
    /// dot as after a checkbox.
    var bulletWidth: CGFloat = 17
    func markerWidth(for marker: ListMarker) -> CGFloat {
        if case .bullet = marker { return bulletWidth }
        return markerWidth
    }
    var maxTextWidth: CGFloat = 720

    /// The size of the arrow symbol after web links, and the space made for it.
    func webLinkSymbolSize(for font: NSFont) -> CGFloat { (font.pointSize * 0.8).rounded() }
    func webLinkSpace(for font: NSFont) -> CGFloat { webLinkSymbolSize(for: font) + 4 }

    var body: NSFont { .systemFont(ofSize: bodySize) }
    var mono: NSFont { .monospacedSystemFont(ofSize: bodySize - 2, weight: .regular) }

    /// A heading's font, from the typography: its size relative to the body, its weight,
    /// and italic or not.
    func headingFont(level: Int) -> NSFont {
        let style = typography.heading(level)
        let size = (bodySize * CGFloat(style.size)).rounded()
        let weight: NSFont.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard style.italic else { return font }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? font
    }

    func calloutColor(_ type: String) -> NSColor {
        switch type {
        case "warning", "caution", "attention": .systemOrange
        case "danger", "error", "bug", "failure", "fail", "missing": .systemRed
        case "tip", "hint", "important", "success", "check", "done": .systemGreen
        case "question", "help", "faq": .systemYellow
        case "example": .systemPurple
        case "quote", "cite": .systemGray
        default: .systemBlue
        }
    }
}
#endif
