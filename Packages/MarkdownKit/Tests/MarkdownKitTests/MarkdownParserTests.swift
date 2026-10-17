import Foundation
import Testing
@testable import MarkdownKit

/// A token as readable strings: what it is, the text it covers, and its hidden markers.
private struct Found: Equatable, CustomStringConvertible {
    let kind: MarkdownToken.Kind
    let text: String
    let syntax: [String]

    init(_ kind: MarkdownToken.Kind, _ text: String, _ syntax: [String] = []) {
        self.kind = kind
        self.text = text
        self.syntax = syntax
    }

    var description: String { "\(kind) \"\(text)\" \(syntax)" }
}

private func parse(_ markdown: String) -> [Found] {
    let ns = markdown as NSString
    return MarkdownParser.parse(markdown).map {
        Found($0.kind, ns.substring(with: $0.range), $0.syntax.map(ns.substring(with:)))
    }
}

struct BlockTests {
    @Test func headings() {
        #expect(parse("## Title") == [Found(.heading(level: 2), "## Title", ["## "])])
        #expect(parse("###### Six") == [Found(.heading(level: 6), "###### Six", ["###### "])])
        #expect(parse("####### Seven") == [])
    }

    @Test func aHashWithoutASpaceIsATagNotAHeading() {
        #expect(parse("#idea") == [Found(.tag("idea"), "#idea")])
    }

    @Test func frontmatterOnlyAtTheStart() {
        #expect(parse("---\ntags: [a]\n---\n# H") == [
            Found(.frontmatter, "---\ntags: [a]\n---", ["---\ntags: [a]\n---"]),
            Found(.heading(level: 1), "# H", ["# "]),
        ])
        #expect(parse("Text\n\n---\n") == [Found(.thematicBreak, "---", ["---"])])
    }

    @Test func fencedCodeHidesNothingInside() {
        #expect(parse("```swift\nlet a = **b**\n```") == [
            Found(.codeBlock(language: "swift"), "```swift\nlet a = **b**\n```", ["```swift", "```"]),
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(parse("```\ncode\n# not heading") == [
            Found(.codeBlock(language: ""), "```\ncode\n# not heading", ["```"]),
        ])
    }

    @Test func lists() {
        #expect(parse("- a\n  - [ ] b\n1. c\n- [x] d\n-") == [
            Found(.listItem(.bullet, indent: 0), "- a", ["- "]),
            Found(.listItem(.task(done: false), indent: 2), "  - [ ] b", ["- [ ] "]),
            Found(.listItem(.ordered(1), indent: 0), "1. c", ["1. "]),
            Found(.listItem(.task(done: true), indent: 0), "- [x] d", ["- [x] "]),
            Found(.listItem(.bullet, indent: 0), "-", ["-"]),
        ])
    }

    @Test func tabsIndentFourColumns() {
        #expect(parse("\t- a") == [Found(.listItem(.bullet, indent: 4), "\t- a", ["- "])])
    }

    @Test func boldAtTheStartOfALineIsNotAList() {
        #expect(parse("**b** c") == [Found(.strong, "**b**", ["**", "**"])])
    }

    @Test func thematicBreaksBeatLists() {
        #expect(parse("a\n* * *") == [Found(.thematicBreak, "* * *", ["* * *"])])
    }

    @Test func blockquotes() {
        #expect(parse("> a\n> b\n\nc") == [Found(.blockquote, "> a\n> b", ["> ", "> "])])
    }

    @Test func callouts() {
        #expect(parse("> [!note] Title\n> body") == [
            Found(.callout(type: "note"), "> [!note] Title\n> body", ["> ", "[!note] ", "> "]),
        ])
        #expect(parse("> [!Warning]- Folded") == [
            Found(.callout(type: "warning"), "> [!Warning]- Folded", ["> ", "[!Warning]- "]),
        ])
    }

    @Test func tables() {
        #expect(parse("| a | **b** |\n| --- | --- |\n| 1 | 2 |\n\nafter") == [
            Found(.table, "| a | **b** |\n| --- | --- |\n| 1 | 2 |"),
            Found(.strong, "**b**", ["**", "**"]),
        ])
    }

    @Test func footnotes() {
        #expect(parse("Text[^1]\n\n[^1]: Note") == [
            Found(.footnoteReference, "[^1]"),
            Found(.footnoteDefinition, "[^1]: Note"),
        ])
    }

    @Test func windowsLineEndingsStayOutOfTokens() {
        #expect(parse("# A\r\nb") == [Found(.heading(level: 1), "# A", ["# "])])
    }
}

struct InlineTests {
    @Test func emphasis() {
        #expect(parse("a **b** *c* _d_ ~~e~~ ==f==") == [
            Found(.strong, "**b**", ["**", "**"]),
            Found(.emphasis, "*c*", ["*", "*"]),
            Found(.emphasis, "_d_", ["_", "_"]),
            Found(.strikethrough, "~~e~~", ["~~", "~~"]),
            Found(.highlight, "==f==", ["==", "=="]),
        ])
    }

    @Test func boldItalic() {
        #expect(parse("***x***") == [
            Found(.emphasis, "***x***", ["*", "*"]),
            Found(.strong, "**x**", ["**", "**"]),
        ])
    }

    @Test func underscoresInsideWordsAreText() {
        #expect(parse("snake_case_word and 2*3") == [])
    }

    @Test func spacesInsideDelimitersPreventEmphasis() {
        #expect(parse("a * b * c") == [])
    }

    @Test func codeSpansWin() {
        #expect(parse("use `**not bold**` here") == [Found(.code, "`**not bold**`", ["`", "`"])])
        #expect(parse("``a ` b``") == [Found(.code, "``a ` b``", ["``", "``"])])
    }

    @Test func wikiLinks() {
        #expect(parse("[[Note]]") == [Found(.wikiLink(target: "Note"), "[[Note]]", ["[[", "]]"])])
        #expect(parse("[[Note#Part|shown]]") == [
            Found(.wikiLink(target: "Note#Part"), "[[Note#Part|shown]]", ["[[", "Note#Part|", "]]"]),
        ])
        #expect(parse("![[photo.png]]") == [Found(.embed(target: "photo.png"), "![[photo.png]]", ["![[", "]]"])])
    }

    @Test func wikiLinksHideFormattingInside() {
        #expect(parse("[[a_b_c]] [[x*y*z]]").count == 2)
    }

    @Test func markdownLinks() {
        #expect(parse("[text](https://x.com)") == [
            Found(.link(destination: "https://x.com"), "[text](https://x.com)", ["[", "](https://x.com)"]),
        ])
        #expect(parse("[**b**](u)") == [
            Found(.link(destination: "u"), "[**b**](u)", ["[", "](u)"]),
            Found(.strong, "**b**", ["**", "**"]),
        ])
        #expect(parse("![alt](pic.png)") == [Found(.image(source: "pic.png"), "![alt](pic.png)", ["![", "](pic.png)"])])
        #expect(parse("[a](<my file.md> \"Title\")") == [
            Found(.link(destination: "my file.md"), "[a](<my file.md> \"Title\")", ["[", "](<my file.md> \"Title\")"]),
        ])
    }

    @Test func bracketsWithoutADestinationAreText() {
        #expect(parse("[not a link] and [x]") == [])
    }

    @Test func tags() {
        #expect(parse("#work/project-x and #2026 and a#b and #日本") == [
            Found(.tag("work/project-x"), "#work/project-x"),
            Found(.tag("日本"), "#日本"),
        ])
    }

    @Test func urls() {
        #expect(parse("See https://a.com/x_y_z. Or (http://b.org/p).") == [
            Found(.url, "https://a.com/x_y_z"),
            Found(.url, "http://b.org/p"),
        ])
    }

    @Test func escapes() {
        #expect(parse(#"\*not\*"#) == [
            Found(.escape, #"\*"#, [#"\"#]),
            Found(.escape, #"\*"#, [#"\"#]),
        ])
    }

    @Test func inlineFormattingInsideBlocks() {
        #expect(parse("# A **b**") == [
            Found(.heading(level: 1), "# A **b**", ["# "]),
            Found(.strong, "**b**", ["**", "**"]),
        ])
        #expect(parse("> [[Link]]") == [
            Found(.blockquote, "> [[Link]]", ["> "]),
            Found(.wikiLink(target: "Link"), "[[Link]]", ["[[", "]]"]),
        ])
    }

    @Test func rangesAreUTF16() {
        let tokens = MarkdownParser.parse("😀 **b**")
        #expect(tokens.first?.range == NSRange(location: 3, length: 5))
    }
}

struct RobustnessTests {
    /// Every token must lie inside the text, and every marker inside its token.
    @Test(arguments: [
        "", "\n", "#", "**", "***", "[[", "]]", "[[]]", "[", "](", "![", "`", "```", "> ", ">", "- [", "- [ ]",
        "---", "---\n", "1.", "==", "~~~", "| a |\n|", "[^", "[^]:", "\\", "http://", "#/", "\r\n\r\n",
        "**a *b** c*", "[a](b", "[[a|", "> [!", "\u{FEFF}---\na\n---",
    ])
    func malformedInputStaysInBounds(text: String) {
        let length = (text as NSString).length
        for token in MarkdownParser.parse(text) {
            #expect(token.range.location >= 0 && NSMaxRange(token.range) <= length)
            for marker in token.syntax {
                #expect(marker.location >= token.range.location && NSMaxRange(marker) <= NSMaxRange(token.range))
            }
        }
    }

    @Test func largeNoteParsesQuickly() {
        let paragraph = "Some **bold** and *italic* text with a [[Link]], a #tag and https://example.com.\n"
        let text = String(repeating: "# Heading\n\n- item\n" + paragraph, count: 5_000) // ~600 KB
        let start = Date()
        let tokens = MarkdownParser.parse(text)
        let elapsed = Date().timeIntervalSince(start)
        #expect(tokens.count == 5_000 * 7)
        #expect(elapsed < 2) // Generous for debug builds; release timing is measured separately.
    }
}
