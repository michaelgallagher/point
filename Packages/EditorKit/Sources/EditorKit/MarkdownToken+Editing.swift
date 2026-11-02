import Foundation
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

    var isLink: Bool {
        switch kind {
        case .link, .wikiLink, .url, .image, .embed: true
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

extension Array where Element == MarkdownToken {
    /// `range` widened to take in every link it touches. Styling has to go around a link:
    /// inside, `[[**Name**]]` is a link to a note called "**Name**".
    func wideningToLinks(_ range: NSRange) -> NSRange {
        var result = range
        for token in self where token.isLink {
            let touches = range.length == 0
                ? token.range.location < range.location && range.location < NSMaxRange(token.range)
                : NSIntersectionRange(token.range, range).length > 0
            if touches { result = NSUnionRange(result, token.range) }
        }
        return result
    }
}
