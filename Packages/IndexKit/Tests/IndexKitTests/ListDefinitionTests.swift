import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

struct ListDefinitionTests {
    @Test func readsConditionsWrittenInWords() {
        let cases: [(String, ListCondition?)] = [
            ("format is Book", ListCondition("format", .is, "Book")),
            ("format is not Book", ListCondition("format", .isNot, "Book")),
            ("read is empty", ListCondition("read", .isEmpty)),
            ("read is set", ListCondition("read", .isSet)),
            ("read is not set", ListCondition("read", .isNotSet)),
            ("title contains service design", ListCondition("title", .contains, "service design")),
            ("rating > 3", ListCondition("rating", .greater, "3")),
            ("published before 2020", ListCondition("published", .before, "2020")),
            ("date edited in last 7 days", ListCondition("date edited", .inLastDays, "7")),
            ("links to [[Service design]]", ListCondition("", .linksTo, "[[Service design]]")),
            ("has words org design", ListCondition("", .hasWords, "org design")),
            ("Reading status is In progress", ListCondition("Reading status", .is, "In progress")),
            ("nonsense", nil),
            ("format is", nil),
        ]
        for (line, expected) in cases {
            #expect(ListCondition(parsing: line) == expected, "\(line)")
            if let expected { #expect(expected.written == line, "\(line)") }
        }
    }

    @Test func readsAListFromItsProperties() throws {
        let text = "---\ntitle: Books\nlist-from: \"[[Sources]]\"\nlist-tags: [reading]\nlist-where:\n  - format is Book\n  - read is empty\nlist-sort: published descending\nlist-show: [author, published]\n---\n"
        let list = try #require(ListDefinition(frontmatter: Frontmatter.parse(text)))
        #expect(list.folders == ["Sources"])
        #expect(list.tags == ["reading"])
        #expect(list.conditions.map(\.written) == ["format is Book", "read is empty"])
        #expect(list.sort == [NoteQuery.Sort(.property("published"), descending: true)])
        #expect(list.columns == ["author", "published"])
        #expect(ListDefinition(frontmatter: Frontmatter.parse("---\ntitle: Not a list\n---\n")) == nil)
        // Written back as it reads.
        #expect(list.properties.map(\.key) == ["list-from", "list-tags", "list-where", "list-sort", "list-show"])
        #expect(list.properties[3].values == ["published descending"])
    }

    @Test func findsItsNotesInTheIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Lists-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Sources/Dune.md": "---\nformat: Book\nauthor: Frank Herbert\npublished: 1965\ntags: [reading]\n---\n",
            "Sources/Talk.md": "---\nformat: Video\npublished: 2021\ntags: [reading]\n---\n",
            "Sources/Read already.md": "---\nformat: Book\nread: 2024-01-01\npublished: 2001\ntags: [reading]\n---\n",
            "Elsewhere/Book.md": "---\nformat: Book\ntags: [reading]\n---\n",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let index = try SearchIndex(url: nil)
        _ = try await index.update(notes: try VaultScanner.scan(root))
        let list = ListDefinition(folders: ["Sources"], tags: ["reading"],
                                  conditions: [ListCondition("format", .is, "Book"), ListCondition("read", .isNotSet)],
                                  sort: [NoteQuery.Sort(.property("published"), descending: true)], columns: ["author"])
        #expect(try await index.notes(matching: list.query) == ["Sources/Dune.md"])
        let any = ListDefinition(folders: ["Sources"], conditions: [ListCondition("format", .is, "Video"), ListCondition("read", .isSet)], matchesAny: true,
                                 sort: [NoteQuery.Sort(.property("published"), descending: true)])
        #expect(try await index.notes(matching: any.query) == ["Sources/Talk.md", "Sources/Read already.md"])
        let notBooks = ListDefinition(folders: ["Sources"], conditions: [ListCondition("format", .isNot, "Book")])
        #expect(try await index.notes(matching: notBooks.query) == ["Sources/Talk.md"])
        let values = try await index.propertyValues(["Author", "published"], of: ["Sources/Dune.md"])
        #expect(values["Sources/Dune.md"]?["author"] == ["Frank Herbert"])
        #expect(values["Sources/Dune.md"]?["published"] == ["1965"])
    }
}
