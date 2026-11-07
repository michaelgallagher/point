import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

struct RecallTests {
    private func meeting(_ day: String, _ people: [String], type: String = "Meeting") -> String {
        "---\ntype: \(type)\ndate: \(day)\npeople:\n" + people.map { "  - \"[[\($0)]]\"\n" }.joined() + "---\nNotes from \(day).\n"
    }

    @Test func readsTypePeopleAndDay() throws {
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(meeting("2026-11-07", ["Sam Lee", "Ann|Annie"])), name: "Sync"))
        #expect(recall.type == "Meeting")
        #expect(recall.people == ["Sam Lee", "Ann"])
        #expect(recall.day == "2026-11-07")
    }

    @Test func takesTheDayFromTheNameWithoutADate() throws {
        let text = "---\ntype: Meeting\npeople: [\"[[Sam Lee]]\"]\n---\n"
        #expect(Recall(frontmatter: Frontmatter.parse(text), name: "2024-01-02 - Team Compass")?.day == "2024-01-02")
        #expect(Recall(frontmatter: Frontmatter.parse(text), name: "Team Compass") == nil)
    }

    @Test func needsATypeAndPeople() {
        #expect(Recall(frontmatter: Frontmatter.parse("---\ndate: 2026-11-07\npeople: [\"[[Sam]]\"]\n---\n"), name: "x") == nil)
        #expect(Recall(frontmatter: Frontmatter.parse("---\ntype: Meeting\ndate: 2026-11-07\npeople:\n---\n"), name: "x") == nil)
        #expect(Recall(frontmatter: nil, name: "2026-11-07 - x") == nil)
    }

    @Test func daysMustBeReal() {
        #expect(Recall.day("2026-10-21") == "2026-10-21")
        #expect(Recall.day("2026-10-21T09:30") == "2026-10-21")
        #expect(Recall.day("2026-10-21 - Sync") == "2026-10-21")
        #expect(Recall.day("2026-13-01") == nil)
        #expect(Recall.day("2026-10-210") == nil)
        #expect(Recall.day("Sync") == nil)
    }

    @Test func summaries() {
        let now = Recall.dayDate("2026-11-07")!
        #expect(Recall.summary(count: 4, type: "Meeting", lastDay: "2026-10-21", now: now) == "4 earlier meetings · last on 21 October")
        #expect(Recall.summary(count: 1, type: "Meeting", lastDay: "2025-10-21", now: now) == "1 earlier meeting · on 21 October 2025")
        #expect(Recall.summary(count: 2, type: "Daily note", lastDay: nil, now: now) == "2 earlier daily notes")
        #expect(Recall.summary(count: 3, type: "Study", lastDay: nil, now: now) == "3 earlier studies")
    }

    @Test func findsEarlierNotesOfTheTypeWithAnyOfThePeople() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Recall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Now.md": meeting("2026-11-07", ["Sam Lee", "Ann"]),
            "Sam a.md": meeting("2026-10-21", ["Sam Lee"]),
            "Ann b.md": meeting("2026-09-01", ["Ann", "Bo"]),
            "Bo only.md": meeting("2026-10-01", ["Bo"]),
            "Later.md": meeting("2026-11-20", ["Sam Lee"]),
            "Same day.md": meeting("2026-11-07", ["Sam Lee"]),
            "Post.md": meeting("2026-10-10", ["Sam Lee"], type: "Blog post"),
            "Old.md": meeting("2024-03-05", ["sam lee"]),
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path), options: []) }
        let notes = try VaultScanner.scan(root)
        let index = try SearchIndex(url: nil)
        try await index.update(notes: notes)
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(files["Now.md"]!), name: "Now"))
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.title) })
        let found = try await index.notes(matching: recall.query).map { byID[$0]! }
        #expect(found == ["Sam a", "Ann b", "Old"])
    }
}
