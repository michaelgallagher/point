#if canImport(AppKit)
import AppKit
import MarkdownKit

extension NSAttributedString.Key {
    /// Marker characters (`**`, `[[`, `# `) that are in the file but not shown.
    static let imprintHidden = NSAttributedString.Key("imprint.hidden")
    /// A block drawn behind its text: a quote bar, callout or code background.
    static let imprintBlock = NSAttributedString.Key("imprint.block")
    /// A list marker drawn in place of the hidden `- `, `1. ` or `- [ ] `.
    static let imprintListMarker = NSAttributedString.Key("imprint.listMarker")
    /// A horizontal rule drawn in place of the hidden `---`.
    static let imprintRule = NSAttributedString.Key("imprint.rule")
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
    var lineHeightMultiple: CGFloat = 1.2
    var paragraphSpacing: CGFloat = 4
    var indentPerLevel: CGFloat = 22
    var markerWidth: CGFloat = 22
    var maxTextWidth: CGFloat = 720

    var body: NSFont { .systemFont(ofSize: bodySize) }
    var mono: NSFont { .monospacedSystemFont(ofSize: bodySize - 2, weight: .regular) }

    func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [26, 21, 18, 16, bodySize, bodySize]
        return .systemFont(ofSize: sizes[min(max(level, 1), 6) - 1], weight: level <= 2 ? .bold : .semibold)
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
