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
        #expect(recall.names == ["Sam Lee", "Ann"])
        #expect(recall.day == "2026-11-07")
    }

    @Test func takesTheDayFromTheNameWithoutADate() throws {
        let text = "---\ntype: Meeting\npeople: [\"[[Sam Lee]]\"]\n---\n"
        #expect(Recall(frontmatter: Frontmatter.parse(text), name: "2024-01-02 - Team Compass")?.day == "2024-01-02")
        #expect(Recall(frontmatter: Frontmatter.parse(text), name: "Team Compass") == nil)
    }

    @Test func needsATypeAndPeopleOrTopics() {
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

    @Test func byTopicsWithoutPeople() throws {
        let text = "---\ntype: Blog post\ntopics:\n  - \"[[Org design]]\"\n  - \"[[Service design]]\"\n---\n"
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(text), name: "Draft"))
        #expect(recall.basis == .topics)
        #expect(recall.names == ["Org design", "Service design"])
        #expect(recall.summary(count: 23, lastDay: nil) == "23 notes on Org design and Service design")
        #expect(recall.heading == "On Org design and Service design")
        // With people too, it's by people: a meeting's topics don't change what it recalls.
        let meeting = "---\ntype: Meeting\ndate: 2026-11-07\npeople: [\"[[Sam]]\"]\ntopics: [\"[[Org design]]\"]\n---\n"
        #expect(Recall(frontmatter: Frontmatter.parse(meeting), name: "x")?.basis == .people)
    }

    @Test func findsEveryNoteOnAnyOfTheTopics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Recall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Draft.md": "---\ntype: Blog post\ntopics: [\"[[Org design]]\", \"[[Service design]]\"]\n---\n",
            "Old post.md": "---\ntype: Blog post\ndate: 2025-01-01\ntopics: [\"[[Org design]]\"]\n---\n",
            "Book.md": "---\ntype: Media\ntopics:\n  - \"[[service design]]\"\n---\n",
            "Sync.md": "---\ntype: Meeting\ndate: 2026-10-01\npeople: [\"[[Sam]]\"]\ntopics: [\"[[Org design]]\"]\n---\n",
            "Other.md": "---\ntype: Blog post\ntopics: [\"[[Cooking]]\"]\n---\n",
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let notes = try VaultScanner.scan(root)
        let index = try SearchIndex(url: nil)
        try await index.update(notes: notes)
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(files["Draft.md"]!), name: "Draft"))
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.title) })
        let found = try await index.notes(matching: recall.query).map { byID[$0]! }
        #expect(Set(found) == ["Draft", "Old post", "Book", "Sync"])
        #expect(found.firstIndex(of: "Sync")! < found.firstIndex(of: "Old post")!)
    }

    @Test func groupsByTypeOwnFirst() throws {
        let text = "---\ntype: Blog post\ntopics: [\"[[Org design]]\"]\n---\n"
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(text), name: "Draft"))
        var details = RecallDetails()
        details.types = ["a": "Meeting", "b": "Media", "c": "Blog post", "d": "Media", "e": ""]
        let groups = details.groups(of: ["a", "b", "c", "d", "e"], recall: recall)
        #expect(groups.map(\.title) == ["Blog post", "Media", "Meeting", "Other"])
        #expect(groups[1].ids == ["b", "d"])
    }
}
