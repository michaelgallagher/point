import Foundation
import MarkdownKit

public enum NoteTags {
    /// A note's tags, from its frontmatter and its inline `#tags`, in order of first
    /// appearance, each once (ignoring case), without `#`.
    public static func tags(in text: String) -> [String] {
        var tags = Frontmatter.parse(text)?.tags ?? []
        for token in MarkdownParser.parse(text) {
            if case .tag(let tag) = token.kind { tags.append(tag) }
        }
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }
}
