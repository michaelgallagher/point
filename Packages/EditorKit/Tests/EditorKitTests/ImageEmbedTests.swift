import Foundation
import MarkdownKit
import Testing
@testable import EditorKit

struct ImageEmbedTests {
    private func embeds(_ text: String) -> [String] {
        MarkdownParser.parse(text).compactMap { token in
            MarkdownStyler.imageEmbed(token, in: text as NSString).map { "\($0.target)@\($0.width.map { Int($0) } ?? 0)" }
        }
    }

    @Test func readsImageEmbedsAndTheirWidths() {
        #expect(embeds("![[a.png]] ![[b.JPG|300]] ![[Note]] ![[c.png|alt]]") == ["a.png@0", "b.JPG@300", "c.png@0"])
        #expect(embeds("![x|200](Attachments/d.png) ![](https://e.com/f.gif)") == ["Attachments/d.png@200", "https://e.com/f.gif@0"])
        #expect(embeds("[[a.png]] and [link](g.png)") == [])
    }
}
