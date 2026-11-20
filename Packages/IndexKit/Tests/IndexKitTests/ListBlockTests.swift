import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

struct ListBlockTests {
    let books = """
        from: Reading
        where:
          - format is Book
          - read is not set
        sort: published descending
        show:
          - author
          - published

        """

    @Test func readsTheSameChoicesAsAListNote() throws {
        let list = try #require(ListDefinition(block: books))
        #expect(list == ListDefinition(folders: ["Reading"], conditions: [ListCondition("format", .is, "Book"), ListCondition("read", .isNotSet)],
                                       sort: [NoteQuery.Sort(.property("published"), descending: true)], columns: ["author", "published"]))
        // As a list note with the same choices reads them.
        let note = "---\n" + books.split(separator: "\n").map { line in
            line.first?.isLetter == true ? "list-" + line : String(line)
        }.joined(separator: "\n") + "\n---\n"
        #expect(ListDefinition(frontmatter: Frontmatter.parse(note)) == list)
    }

    @Test func readsTagsMatchAndInlineLists() throws {
        let list = try #require(ListDefinition(block: "Tags: [reading, \"#later\"]\nmatch: any\nwhere: rating > 3\n# a comment\n"))
        #expect(list.tags == ["reading", "later"])
        #expect(list.matchesAny)
        #expect(list.conditions == [ListCondition("rating", .greater, "3")])
    }

    @Test func anEmptyBlockListsEveryNote() {
        #expect(ListDefinition(block: "") == ListDefinition())
        #expect(ListDefinition(block: "\n\n") == ListDefinition())
        #expect(ListDefinition(block: "# nothing yet\n") == ListDefinition())
    }

    @Test func whatDoesntReadIsNotAList() {
        let cases = [
            "group: author\n",                      // not a list's key
            "from: Reading\nfrom: Archive\n",       // a key twice
            "from Reading\n",                       // not `key: value`
            "  - format is Book\n",                 // an item under no key
            "from: Reading\n  stray\n",             // an indented line that isn't an item
            "where:\n  - format Book\n",            // a condition that doesn't read
            "where: read between 2024\n",
            "from: Reading\n---\nsort: title\n",    // `---` would end it early
            "list-from: Reading\n",                 // a list note's key, not a block's
        ]
        for body in cases { #expect(ListDefinition(block: body) == nil, "\(body)") }
    }

    @Test func writingTheSameListChangesNothing() throws {
        let handWritten = "From: [[Reading]]\nwhere: [\"format is Book\", read is not set]\n\n# by date\nsort: published desc\n"
        let list = try #require(ListDefinition(block: handWritten))
        #expect(list.blockBody(over: handWritten) == handWritten)
        #expect(try #require(ListDefinition(block: books)).blockBody(over: books) == books)
    }

    @Test func writesOnlyWhatChanged() throws {
        var list = try #require(ListDefinition(block: books))
        list.conditions.append(ListCondition("rating", .greater, "3"))
        #expect(list.blockBody(over: books) == """
            from: Reading
            where:
              - format is Book
              - read is not set
              - rating > 3
            sort: published descending
            show:
              - author
              - published

            """)

        // The block's spelling of a key, and its comments and blank lines, are kept.
        let spelled = "# books\nWhere: format is Book\n\nshow: [author]\n"
        var other = try #require(ListDefinition(block: spelled))
        other.columns = ["author", "published"]
        #expect(other.blockBody(over: spelled) == "# books\nWhere: format is Book\n\nshow:\n  - author\n  - published\n")
    }

    @Test func removesKeysNoLongerSetAndAddsNewOnesInTheirPlace() throws {
        var list = try #require(ListDefinition(block: books))
        list.sort = []
        list.columns = []
        list.matchesAny = true
        #expect(list.blockBody(over: books) == "from: Reading\nwhere:\n  - format is Book\n  - read is not set\nmatch: any\n")
        // A blank line between keys stays where it was.
        let spaced = "from: Reading\n\nsort: title\n"
        var unsorted = try #require(ListDefinition(block: spaced))
        unsorted.sort = []
        #expect(unsorted.blockBody(over: spaced) == "from: Reading\n\n")
        // A new key goes before the first that follows it in the usual order, not at the end.
        let full = "from: Reading\nwhere: format is Book\nsort: title\nshow:\n  - author\n"
        var tagged = try #require(ListDefinition(block: full))
        tagged.tags = ["later"]
        #expect(tagged.blockBody(over: full) == "from: Reading\ntags:\n  - later\nwhere: format is Book\nsort: title\nshow:\n  - author\n")
        var any = tagged
        any.conditions.append(ListCondition("read", .isNotSet))
        any.matchesAny = true
        #expect(any.blockBody(over: full).contains("  - read is not set\nmatch: any\nsort: title\n"))
    }

    @Test func aNewBlock() {
        #expect(ListDefinition().block == "```list\n```\n")
        let list = ListDefinition(tags: ["reading"], conditions: [ListCondition("format", .is, "Book")],
                                  sort: [NoteQuery.Sort(.title)], columns: ["author"])
        #expect(list.block == "```list\ntags:\n  - reading\nwhere:\n  - format is Book\nsort: title\nshow:\n  - author\n```\n")
        // And back.
        let body = String(list.block.dropFirst("```list\n".count).dropLast("```\n".count))
        #expect(ListDefinition(block: body) == list)
    }

    @Test func aBodyWithoutAFinalLineBreak() throws {
        let body = "from: Reading"
        let list = try #require(ListDefinition(block: body))
        #expect(list.folders == ["Reading"])
        var changed = list
        changed.folders = ["Archive"]
        #expect(changed.blockBody(over: body) == "from: Archive\n")
    }
}
