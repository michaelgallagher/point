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
            ("read in last 3 months", ListCondition("read", .inLastDays, "3 months")),
            ("read in next 1 week", ListCondition("read", .inNextDays, "1 weeks")),
            ("read between 2024-03-01 and 2025-06-30", ListCondition("read", .between, "2024-03-01 and 2025-06-30")),
            ("read is this year", ListCondition("read", .thisPeriod, "year")),
            ("status is this one", ListCondition("status", .is, "this one")),
            ("read between 2024", nil),
            ("nonsense", nil),
            ("format is", nil),
        ]
        for (line, expected) in cases {
            #expect(ListCondition(parsing: line) == expected, "\(line)")
            if let expected { #expect(expected.written == line, "\(line)") }
        }
    }

    @Test func periodsAreCountedFromToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
        let year = ListCondition("read", .thisPeriod, "year").filter(now: now, calendar: calendar)
        #expect(year == .all([.property("read", .greaterOrEqual("2026-01-01")), .property("read", .lessOrEqual("2026-12-31"))]))
        let months = ListCondition("read", .inLastDays, "3 months").filter(now: now, calendar: calendar)
        #expect(months == .property("read", .withinLastDays(92)))
        #expect(ListCondition("date edited", .inLastDays, "7").filter(now: now, calendar: calendar) == .field(.modified, .withinLastDays(7)))
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
            "Sources/Blank read.md": "---\nformat: Book\nread:\npublished: 1970\ntags: [reading]\n---\n",
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
        // A blank `read:` is no value.
        #expect(try await index.notes(matching: list.query) == ["Sources/Blank read.md", "Sources/Dune.md"])
        let any = ListDefinition(folders: ["Sources"], conditions: [ListCondition("format", .is, "Video"), ListCondition("read", .isSet)], matchesAny: true,
                                 sort: [NoteQuery.Sort(.property("published"), descending: true)])
        // Any: in the folder, or meeting either condition.
        #expect(try await index.notes(matching: any.query) == ["Sources/Talk.md", "Sources/Read already.md", "Sources/Blank read.md", "Sources/Dune.md"])
        // Any: a folder is one of the things a note can meet.
        let anyWithTag = ListDefinition(folders: ["Elsewhere"], conditions: [ListCondition("format", .is, "Video")], matchesAny: true,
                                        sort: [NoteQuery.Sort(.title)])
        #expect(try await index.notes(matching: anyWithTag.query) == ["Sources/Talk.md", "Elsewhere/Book.md"].sorted { $0.split(separator: "/").last! < $1.split(separator: "/").last! })
        let between = ListDefinition(conditions: [ListCondition("read", .between, "2023-12-01 and 2024-01-01")])
        #expect(try await index.notes(matching: between.query) == ["Sources/Read already.md"])
        let before = ListDefinition(conditions: [ListCondition("read", .between, "2023-01-01 and 2023-12-31")])
        #expect(try await index.notes(matching: before.query).isEmpty)
        let notElsewhere = ListDefinition(conditions: [ListCondition("format", .is, "Book"), ListCondition("folder", .isNot, "Elsewhere")])
        #expect(try await index.notes(matching: notElsewhere.query).count == 3)
        let notTagged = ListDefinition(conditions: [ListCondition("tag", .isNot, "reading")])
        #expect(try await index.notes(matching: notTagged.query).isEmpty)
        let readOnes = ListDefinition(folders: ["Sources"], conditions: [ListCondition("read", .isSet)])
        #expect(try await index.notes(matching: readOnes.query) == ["Sources/Read already.md"])
        let notBooks = ListDefinition(folders: ["Sources"], conditions: [ListCondition("format", .isNot, "Book")])
        #expect(try await index.notes(matching: notBooks.query) == ["Sources/Talk.md"])
        let values = try await index.propertyValues(["Author", "published"], of: ["Sources/Dune.md"])
        #expect(values["Sources/Dune.md"]?["author"] == ["Frank Herbert"])
        #expect(values["Sources/Dune.md"]?["published"] == ["1965"])
    }
}
