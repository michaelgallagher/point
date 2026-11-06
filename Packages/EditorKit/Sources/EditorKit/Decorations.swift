#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
    /// A background colour (an `PlatformColor`) drawn with rounded corners behind the text, line by
    /// line: highlights and inline code.
    static let pointRoundedBackground = NSAttributedString.Key("point.roundedBackground")
    /// A list item highlighted by the character at its start (`- ! Important`): its colour,
    /// an `PlatformColor`, drawn behind the line and used for its bullet.
    static let pointListHighlight = NSAttributedString.Key("point.listHighlight")
    /// A line-height multiple (CGFloat) overriding the theme's, for example in code blocks.
    static let pointLineHeight = NSAttributedString.Key("point.lineHeight")
    /// An embedded image (an `ImageDecoration`), drawn by a view in the room made above its line.
    static let pointImage = NSAttributedString.Key("point.image")
}

/// An image embed alone on its line, drawn above it: its Markdown stays, small, as a caption.
struct ImageDecoration: Hashable {
    let url: URL
    /// The size it's shown at.
    let size: CGSize
    /// The room above the line that was there before the image's: the image is drawn below it.
    let spaceAbove: CGFloat
    /// How far in from the line's start it's drawn: images side by side follow each other.
    var x: CGFloat = 0
}

enum BlockDecoration: Hashable {
    case quote
    case callout(type: String)
    case code
    case table(TableDecoration)
}

/// Where a table's grid is laid out, from the left edge of the text and the top of the table.
/// Its Markdown is hidden; a `TableGridView` draws it from this.
struct TableDecoration: Hashable {
    /// Each column's edges, starting at 0, with the cell padding between them and the text.
    let columnEdges: [CGFloat]
    /// How wide each column's text is.
    let columnWidths: [CGFloat]
    /// Each row's height, the header first (the delimiter row isn't counted), with its padding.
    let rowHeights: [CGFloat]
    let alignments: [MarkdownTable.Alignment]

    var width: CGFloat { columnEdges.last ?? 0 }
    var height: CGFloat { rowHeights.reduce(0, +) }
    /// Where each row's top is.
    var rowTops: [CGFloat] { rowHeights.indices.map { rowHeights[..<$0].reduce(0, +) } }
}

struct ListMarkerDecoration: Hashable {
    let marker: ListMarker
    let level: Int
}

/// Sizes and colours for the editor. Apple Notes is the reference for the feel.
struct EditorTheme {
    /// Whether a tag's pill stays inside the text's left edge: on the phone the text is the page's
    /// margin, shared with the note's title.
    var keepsTagsInsideMargin = false
    /// How far a tag's pill reaches past its text at each side, which is the room made for it.
    var tagSpace: CGFloat = 6
    /// How far a tag's pill reaches above and below its text.
    var tagRise: CGFloat = 2
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

    /// Whether tables are drawn as tables, with their pipes hidden, rather than as monospaced
    /// Markdown. Only the Mac's editor moves the cursor between cells as they need.
    var rendersTables = false
    /// Whether images embedded alone on a line are shown, above it. Only the Mac's editor puts
    /// views over the text to draw them.
    var rendersImages = false
    /// The tallest an image is shown, so a tall screenshot doesn't fill the window.
    var imageMaxHeight: CGFloat = 520
    /// The room between an image and its caption.
    var imageGap: CGFloat = 4
    /// How wide the text is, which a table's columns are narrowed to fit.
    var textWidth: CGFloat = 720
    /// The room between a cell's text and its column's edges.
    var tableCellPadding: CGFloat = 8
    /// The room above and below a cell's text.
    var tableRowPadding: CGFloat = 5

    /// The size of the arrow symbol after web links, and the space made for it.
    func webLinkSymbolSize(for font: PlatformFont) -> CGFloat { (font.pointSize * 0.8).rounded() }
    func webLinkSpace(for font: PlatformFont) -> CGFloat { webLinkSymbolSize(for: font) + 4 }

    var body: PlatformFont { .systemFont(ofSize: bodySize) }
    var mono: PlatformFont { .monospacedSystemFont(ofSize: bodySize - 2, weight: .regular) }

    /// A heading's font, from the typography: its size relative to the body, its weight,
    /// and italic or not.
    func headingFont(level: Int) -> PlatformFont {
        let style = typography.heading(level)
        let size = (bodySize * CGFloat(style.size)).rounded()
        let weight: PlatformFont.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        let font = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard style.italic else { return font }
        return font.adding(PlatformTraits.italic)
    }

    func calloutColor(_ type: String) -> PlatformColor {
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
