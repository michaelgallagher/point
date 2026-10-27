import MarkdownKit

/// What the editors (Mac and iPhone) need to know about a token when restyling.
extension MarkdownToken {
    var isBlock: Bool {
        switch kind {
        case .frontmatter, .heading, .blockquote, .callout, .listItem, .codeBlock, .thematicBreak, .table, .footnoteDefinition:
            true
        default:
            false
        }
    }

    var isMultiLineBlock: Bool {
        switch kind {
        case .frontmatter, .blockquote, .callout, .codeBlock, .table: true
        default: false
        }
    }

    /// Code blocks and frontmatter change how everything after them is read.
    var changesFollowingText: Bool {
        switch kind {
        case .frontmatter, .codeBlock: true
        default: false
        }
    }
}
