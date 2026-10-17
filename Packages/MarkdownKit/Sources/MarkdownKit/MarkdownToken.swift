import Foundation

/// One piece of Markdown structure found in a note: a heading, a bold span, a link.
///
/// Ranges are UTF-16 offsets into the note's text, the units `NSString` and
/// `NSTextStorage` use, so the editor can apply them directly.
public struct MarkdownToken: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        // Blocks
        case frontmatter
        case heading(level: Int)
        case blockquote
        case callout(type: String)
        /// `indent` is the leading whitespace in columns, with a tab counting as 4.
        case listItem(ListMarker, indent: Int)
        case codeBlock(language: String)
        case thematicBreak
        case table
        case footnoteDefinition

        // Inline
        case strong
        case emphasis
        case strikethrough
        case highlight
        case code
        case link(destination: String)
        case image(source: String)
        case wikiLink(target: String)
        case embed(target: String)
        case tag(String)
        case url
        case footnoteReference
        /// A backslash escape such as `\*`. The backslash is syntax; the character is text.
        case escape
    }

    public let kind: Kind
    /// The whole construct, markers included.
    public let range: NSRange
    /// The marker characters within `range` (such as `**` or `[[`), which the editor hides.
    /// For a list item, the first range is the marker itself, such as `- ` or `- [ ] `.
    public let syntax: [NSRange]

    public init(kind: Kind, range: NSRange, syntax: [NSRange]) {
        self.kind = kind
        self.range = range
        self.syntax = syntax
    }
}

public enum ListMarker: Hashable, Sendable {
    case bullet
    case ordered(Int)
    case task(done: Bool)
}
