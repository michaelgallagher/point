import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

/// A throwaway vault, indexed, for asking queries of.
private struct QueryVault {
    let root: URL
    let notes: [Note]
    let index: SearchIndex

    init(_ files: [String: String], modified: [String: String] = [:]) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NoteQuery-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            if let day = modified[path], let date = PropertyDate.parse(day)?.date {
                try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
            }
        }
        notes = try VaultScanner.scan(root)
        index = try SearchIndex(url: nil)
        try await index.update(notes: notes)
    }

    /// The titles a query finds, in its order.
    func titles(_ filters: [NoteQuery.Filter], sort: [NoteQuery.Sort] = [NoteQuery.Sort(.title)], now: Date = Date()) async throws -> [String] {
        let ids = try await index.notes(matching: NoteQuery(filters, sort: sort), now: now)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.title) })
        return ids.map { byID[$0]! }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

struct NoteQueryTests {
    let files = [
        "Posts/Fonts.md": "---\nstatus: draft\nrating: 4\npublished: 2026-11-01\npeople:\n  - \"[[Sam Lee]]\"\ntags: [writing]\n---\nAbout type for low-vision readers.",
        "Posts/Search.md": "---\nstatus: Published\nrating: 10\npublished: 2026-10-20\n---\nHow search learns. #writing/tech",
        "Posts/Drafts/Tables.md": "---\nstatus: draft\nrating: 2.5\n---\nGrids over Markdown. Links to [[Fonts]].",
        "Meetings/Standup.md": "---\npeople: [\"[[Sam Lee]]\", \"[[Ann]]\"]\ndate: 2026-11-06T09:30\nstatus:\n---\nTalked about ![[diagram.png]].",
        "Inbox.md": "Nothing here but text about fonts.",
    ]

    @Test func equalsIgnoresCaseAndMatchesLinkedNames() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.property("status", .equals("DRAFT"))]) == ["Fonts", "Tables"])
        #expect(try await vault.titles([.property("Status", .equals("published"))]) == ["Search"])
        #expect(try await vault.titles([.property("people", .equals("Sam Lee"))]) == ["Fonts", "Standup"])
        #expect(try await vault.titles([.property("people", .equals("[[ann]]"))]) == ["Standup"])
    }

    @Test func existsMissingAndEmpty() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.property("status", .exists)]) == ["Fonts", "Search", "Standup", "Tables"])
        #expect(try await vault.titles([.property("status", .missing)]) == ["Inbox"])
        #expect(try await vault.titles([.property("status", .empty)]) == ["Standup"])
    }

    @Test func numbersCompareAsNumbers() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        // As text, "10" < "4"; as numbers it isn't.
        #expect(try await vault.titles([.property("rating", .greater("3"))]) == ["Fonts", "Search"])
        #expect(try await vault.titles([.property("rating", .lessOrEqual("4"))]) == ["Fonts", "Tables"])
        #expect(try await vault.titles([.property("rating", .exists)], sort: [NoteQuery.Sort(.property("rating"), descending: true)])
                == ["Search", "Fonts", "Tables"])
    }

    @Test func datesCompareAsDatesAndWholeDays() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.property("published", .less("2026-11-01"))]) == ["Search"])
        #expect(try await vault.titles([.property("published", .lessOrEqual("2026-11-01"))]) == ["Fonts", "Search"])
        #expect(try await vault.titles([.property("published", .greater("2026-10-20"))]) == ["Fonts"])
        // A date with a time is within its day.
        #expect(try await vault.titles([.property("date", .lessOrEqual("2026-11-06"))]) == ["Standup"])
        let now = PropertyDate.parse("2026-11-06T18:00")!.date
        #expect(try await vault.titles([.property("published", .withinLastDays(7))], now: now) == ["Fonts"])
        #expect(try await vault.titles([.property("date", .withinLastDays(1))], now: now) == ["Standup"])
        #expect(try await vault.titles([.property("published", .withinNextDays(30))], now: PropertyDate.parse("2026-10-25")!.date) == ["Fonts"])
    }

    @Test func sortsByPropertyWithMissingLast() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.folder("Posts")], sort: [NoteQuery.Sort(.property("published"))]) == ["Search", "Fonts", "Tables"])
        #expect(try await vault.titles([.folder("Posts")], sort: [NoteQuery.Sort(.property("published"), descending: true)]) == ["Fonts", "Search", "Tables"])
    }

    @Test func foldersTagsLinksAndText() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.folder("Posts")]) == ["Fonts", "Search", "Tables"])
        #expect(try await vault.titles([.folder("Posts", includingSubfolders: false)]) == ["Fonts", "Search"])
        #expect(try await vault.titles([.folder("")]) == ["Inbox"])
        #expect(try await vault.titles([.tag("writing")]) == ["Fonts", "Search"])
        #expect(try await vault.titles([.tag("#writing/tech")]) == ["Search"])
        #expect(try await vault.titles([.linksTo("Fonts")]) == ["Tables"])
        #expect(try await vault.titles([.linksTo("[[Sam Lee]]")]) == ["Fonts", "Standup"])
        #expect(try await vault.titles([.text("font")]) == ["Fonts", "Inbox", "Tables"]) // Tables links to [[Fonts]].
    }

    @Test func combinesFilters() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.folder("Posts"), .not(.property("status", .equals("draft")))]) == ["Search"])
        #expect(try await vault.titles([.any([.tag("writing"), .property("people", .equals("Ann"))])]) == ["Fonts", "Search", "Standup"])
        #expect(try await vault.titles([.all([])]) == ["Fonts", "Inbox", "Search", "Standup", "Tables"])
        #expect(try await vault.titles([.any([])]) == [])
    }

    @Test func fieldsOfTheNote() async throws {
        let vault = try await QueryVault(["Old.md": "a", "New.md": "b", "Projects/Mid.md": "c"],
                                         modified: ["Old.md": "2026-01-01", "New.md": "2026-11-05", "Projects/Mid.md": "2026-06-01"])
        defer { vault.cleanUp() }
        let now = PropertyDate.parse("2026-11-06T12:00")!.date
        #expect(try await vault.titles([.field(.modified, .withinLastDays(7))], now: now) == ["New"])
        #expect(try await vault.titles([.field(.modified, .equals("2026-06-01"))]) == ["Mid"])
        #expect(try await vault.titles([], sort: [NoteQuery.Sort(.modified, descending: true)]) == ["New", "Mid", "Old"])
        #expect(try await vault.titles([.field(.title, .contains("ol"))]) == ["Old"])
        #expect(try await vault.titles([.field(.folder, .equals("projects"))]) == ["Mid"])
    }

    @Test func likeWildcardsAreLiteral() async throws {
        let vault = try await QueryVault(["A.md": "---\ncode: 100%\n---\n", "B.md": "---\ncode: 1000\n---\n", "C.md": "---\ncode: a_b\n---\n"])
        defer { vault.cleanUp() }
        #expect(try await vault.titles([.property("code", .contains("0%"))]) == ["A"])
        #expect(try await vault.titles([.property("code", .contains("_"))]) == ["C"])
    }

    @Test func countsAndLimits() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        #expect(try await vault.index.count(matching: NoteQuery([.property("status", .exists)])) == 4)
        #expect(try await vault.index.notes(matching: NoteQuery([], sort: [NoteQuery.Sort(.title)], limit: 2)).count == 2)
    }

    @Test func summarisesProperties() async throws {
        let vault = try await QueryVault(files.merging(["Other.md": "---\nStatus: draft\n---\n"]) { a, _ in a })
        defer { vault.cleanUp() }
        let summaries = try await vault.index.propertySummaries()
        let status = try #require(summaries.first { $0.id == "status" })
        #expect(status.name == "status")
        #expect(status.otherSpellings == ["Status"])
        #expect(status.noteCount == 5)
        #expect(status.distinctValues == 2) // draft and Published; "Draft" once more is the same.
        let rating = try #require(summaries.first { $0.id == "rating" })
        #expect(rating.numberValues == 3 && rating.valueCount == 3)
        let people = try #require(summaries.first { $0.id == "people" })
        #expect(people.linkValues == 3 && people.listCount == 2)
        #expect(try await vault.index.values(ofProperty: "STATUS").map(\.value) == ["draft", "Published"])
        #expect(try await vault.index.values(ofProperty: "status").first?.count == 3)
    }

    @Test func linksHaveKinds() async throws {
        let vault = try await QueryVault(files)
        defer { vault.cleanUp() }
        let toSam = try await vault.index.linking(to: "Sam Lee")
        #expect(Set(toSam.map(\.kind)) == [.property])
        #expect(Set(toSam.compactMap(\.property)) == ["people"])
        #expect(try await vault.index.linking(to: "diagram.png").map(\.kind) == [.embed])
        #expect(try await vault.index.linking(to: "Fonts").map(\.kind) == [.text])
    }

    @Test func roundTripsAsJSON() throws {
        let query = NoteQuery([.folder("Posts"), .not(.property("status", .equals("draft"))), .any([.tag("a"), .field(.modified, .withinLastDays(7))])],
                              sort: [NoteQuery.Sort(.property("published"), descending: true)], limit: 20)
        let data = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(NoteQuery.self, from: data) == query)
    }
}
