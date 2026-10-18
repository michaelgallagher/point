import Testing
@testable import MarkdownKit

struct PlainTextTests {
    @Test(arguments: [
        ("# My **idea**\nbody", "My idea"),
        ("\n\n  Plain first line  \nsecond", "Plain first line"),
        ("---\ntags: [a]\n---\n\n## After frontmatter", "After frontmatter"),
        ("- [ ] Buy [[Milk|milk]] 😀", "Buy milk 😀"),
        ("> [!tip] Callout title", "Callout title"),
    ])
    func firstLines(text: String, expected: String) {
        #expect(PlainText.firstLine(of: text) == expected)
    }

    @Test func emptyNotesHaveNoFirstLine() {
        #expect(PlainText.firstLine(of: "") == nil)
        #expect(PlainText.firstLine(of: "\n  \n") == nil)
        #expect(PlainText.firstLine(of: "---\na: b\n---\n") == nil)
    }
}
