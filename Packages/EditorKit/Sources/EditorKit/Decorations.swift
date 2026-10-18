#if canImport(AppKit)
import AppKit
import MarkdownKit

extension NSAttributedString.Key {
    /// Marker characters (`**`, `[[`, `# `) that are in the file but not shown.
    static let imprintHidden = NSAttributedString.Key("imprint.hidden")
    /// A line squeezed to a sliver, such as a code fence or frontmatter. The cursor skips it.
    static let imprintCollapsed = NSAttributedString.Key("imprint.collapsed")
    /// A block drawn behind its text: a quote bar, callout or code background.
    static let imprintBlock = NSAttributedString.Key("imprint.block")
    /// A list marker drawn in place of the hidden `- `, `1. ` or `- [ ] `.
    static let imprintListMarker = NSAttributedString.Key("imprint.listMarker")
    /// A horizontal rule drawn in place of the hidden `---`.
    static let imprintRule = NSAttributedString.Key("imprint.rule")
    /// A `#tag`, drawn as a pill.
    static let imprintTag = NSAttributedString.Key("imprint.tag")
    /// The last letter of a link to a website, followed by the arrow symbol drawn after it.
    static let imprintWebLink = NSAttributedString.Key("imprint.webLink")
    /// A line-height multiple (CGFloat) overriding the theme's, for example in code blocks.
    static let imprintLineHeight = NSAttributedString.Key("imprint.lineHeight")
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
    var bodySize: CGFloat = 15
    /// Extra line height, split evenly above and below the text by the layout manager.
    var lineHeightMultiple: CGFloat = 1.3
    var paragraphSpacing: CGFloat = 0
    var indentPerLevel: CGFloat = 22
    var markerWidth: CGFloat = 22
    var maxTextWidth: CGFloat = 720

    /// The size of the arrow symbol after web links, and the space made for it.
    func webLinkSymbolSize(for font: NSFont) -> CGFloat { (font.pointSize * 0.8).rounded() }
    func webLinkSpace(for font: NSFont) -> CGFloat { webLinkSymbolSize(for: font) + 4 }

    var body: NSFont { .systemFont(ofSize: bodySize) }
    var mono: NSFont { .monospacedSystemFont(ofSize: bodySize - 2, weight: .regular) }

    /// H1 26pt bold, H2 18pt semibold, H3 body-size bold, H4 to H6 body-size italic.
    func headingFont(level: Int) -> NSFont {
        switch level {
        // Sizes are for 15pt body text and scale with it (⌘+ / ⌘−).
        case 1: return .systemFont(ofSize: (26 * bodySize / 15).rounded(), weight: .bold)
        case 2: return .systemFont(ofSize: (18 * bodySize / 15).rounded(), weight: .semibold)
        case 3: return .systemFont(ofSize: bodySize, weight: .bold)
        default:
            let regular = NSFont.systemFont(ofSize: bodySize)
            return NSFont(descriptor: regular.fontDescriptor.withSymbolicTraits(.italic), size: bodySize) ?? regular
        }
    }

    /// Space above a heading: H1 and H2 stand apart, smaller headings sit like body text.
    func spaceBeforeHeading(level: Int) -> CGFloat {
        level <= 2 ? headingFont(level: level).pointSize * 0.5 : 0
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
