import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

/// A throwaway vault on disk, its notes, and an index of it.
private struct Fixture {
    let root: URL
    var notes: [Note] = []
    let index: SearchIndex

    init(_ files: [String: String], indexURL: URL? = nil) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("IndexKit-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        notes = try VaultScanner.scan(root)
        index = try SearchIndex(url: indexURL)
        try await index.update(notes: notes)
    }

    func titles(_ query: String) async throws -> [String] {
        try await index.search(query).map(\.title)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

struct SearchTests {
    let files = [
        "Weekly meeting.md": "# Weekly meeting\nAgenda for the team. #work",
        "Running log.md": "Ran 5k today. Running is getting easier; I run three times a week.",
        "Projects/Imprint.md": "---\ntags: [work/imprint, ideas]\n---\nA text editor project with **excellent** search.",
        "Garden.md": "Planted tomatoes. Need a meeting with the allotment committee.",
        "Recipes.md": "Chocolate cake with café crème.",
    ]

    @Test func findsWholeAndPartialWords() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles("tomatoes") == ["Garden"])
        #expect(try await vault.titles("tomat") == ["Garden"])
        #expect(try await vault.titles("ject") == ["Imprint"]) // Inside "project".
    }

    @Test func titlesComeFirst() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles("meeting") == ["Weekly meeting", "Garden"])
    }

    @Test func forgivesTypos() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let typo = try await vault.titles("meetng")
        #expect(typo == ["Weekly meeting", "Garden"])
        #expect(try await vault.titles("chocolat cake").first == "Recipes")
        #expect(try await vault.titles("tomatos") == ["Garden"])
    }

    @Test func matchesWordForms() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles("runs") == ["Running log"])
        #expect(try await vault.titles("planting") == ["Garden"])
    }

    @Test func ignoresAccentsAndCase() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles("CAFE creme") == ["Recipes"])
    }

    @Test func wordsCanComeInAnyOrder() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(try await vault.titles("search excellent editor") == ["Imprint"])
    }

    @Test func filtersByTagIncludingNestedTags() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(Set(try await vault.titles("#work")) == ["Weekly meeting", "Imprint"])
        #expect(try await vault.titles("#work/imprint") == ["Imprint"])
        #expect(try await vault.titles("#work agenda") == ["Weekly meeting"])
        #expect(try await vault.titles("#missing").isEmpty)
    }

    /// A word in hundreds of notes, and a tag on a few of them that rank low for it: the tag
    /// filters inside the search, so they aren't lost below the first 200 matches.
    @Test func tagsFilterBeforeTheBestMatchesAreTaken() async throws {
        var files: [String: String] = [:]
        for n in 0..<300 { files["Budget \(n).md"] = "Budget budget budget." }
        let filler = Array(repeating: "Unrelated words here.", count: 40).joined(separator: " ")
        for n in 0..<3 { files["Tagged \(n).md"] = "#design\n\(filler) A budget, once." }
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        #expect(Set(try await vault.titles("#design budget")) == ["Tagged 0", "Tagged 1", "Tagged 2"])
    }

    @Test func snippetsMarkTheMatchWithoutMarkdown() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let result = try #require(try await vault.index.search("excellent").first)
        #expect(result.snippet?.contains("\u{2}excellent\u{3} search") == true)
        #expect(result.snippet?.contains("**") == false)
    }

    @Test func listsTags() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let tags = try await vault.index.allTags()
        #expect(tags.map(\.tag).sorted() == ["ideas", "work", "work/imprint"])
    }

    @Test func givesEachNotesTags() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let tags = try await vault.index.tagsByNote()
        #expect(Set(tags["Projects/Imprint.md"] ?? []) == ["work/imprint", "ideas"])
        #expect(tags["Garden.md"] == nil)
    }

    @Test func keepsUpWithChangesAndDeletions() async throws {
        var vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let garden = vault.root.appendingPathComponent("Garden.md")
        try Data("Planted potatoes instead.".utf8).write(to: garden)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: garden.path)
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("Recipes.md"))
        vault.notes = try VaultScanner.scan(vault.root)
        #expect(try await vault.index.update(notes: vault.notes) == 1)
        #expect(try await vault.titles("potatoes") == ["Garden"])
        #expect(try await vault.titles("tomatoes").isEmpty)
        #expect(try await vault.titles("chocolate").isEmpty)
    }

    @Test func persistsBetweenLaunches() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        let vault = try await Fixture(files, indexURL: file)
        defer { vault.cleanUp() }
        let reopened = try SearchIndex(url: file)
        #expect(try await reopened.update(notes: vault.notes) == 0) // Nothing to redo.
        #expect(try await reopened.search("tomatoes").map(\.title) == ["Garden"])
    }
}

struct LinkIndexTests {
    let files = [
        "Imprint.md": "The editor.",
        "Plan.md": "See [[Imprint]] for details.\nAlso [[imprint#Goals|the goals]].",
        "Notes.md": "Imprint should be fast. I like imprint a lot.\nBut `Imprint` in code and [[Imprint]] are not mentions.\nImprinted is a different word.",
        "Other.md": "Nothing here.",
    ]

    @Test func findsBacklinks() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let target = try #require(vault.notes.first { $0.title == "Imprint" })
        let backlinks = try await vault.index.backlinks(to: target, notes: vault.notes)
        #expect(backlinks.map(\.title) == ["Notes", "Plan"])
        #expect(backlinks.last?.context == "See Imprint for details.")
    }

    /// From the live vault: most links to a note can be in other notes' properties.
    @Test func backlinksIncludeLinksInFrontmatter() async throws {
        let vault = try await Fixture([
            "Imprint.md": "# Imprint\n",
            "Meeting.md": "---\nproject: \"[[Imprint]]\"\n---\nNotes from the call.\n",
            "Other.md": "---\npeople:\n  - \"[[Ann]]\"\n---\nNothing here.\n",
        ])
        defer { vault.cleanUp() }
        let target = try #require(vault.notes.first { $0.title == "Imprint" })
        let backlinks = try await vault.index.backlinks(to: target, notes: vault.notes)
        #expect(backlinks.map(\.title) == ["Meeting"])
        #expect(backlinks.first?.context.contains("Imprint") == true)
        // Where the link is, so opening the note can show it.
        let range = try #require(backlinks.first?.range)
        #expect(("---\nproject: \"[[Imprint]]\"\n---\nNotes from the call.\n" as NSString).substring(with: range) == "Imprint")
    }

    @Test func findsUnlinkedMentions() async throws {
        let vault = try await Fixture(files)
        defer { vault.cleanUp() }
        let target = try #require(vault.notes.first { $0.title == "Imprint" })
        let mentions = try await vault.index.unlinkedMentions(of: target, notes: vault.notes)
        #expect(mentions.map(\.matched) == ["Imprint", "imprint"])
        #expect(mentions.allSatisfy { $0.title == "Notes" })
    }

    @Test func mentionsAreCapped() async throws {
        let busy = (0..<20).reduce(into: [String: String]()) { files, n in
            files["Note \(n).md"] = Array(repeating: "Imprint again.", count: 10).joined(separator: " ")
        }.merging(["Imprint.md": "The editor."]) { a, _ in a }
        let vault = try await Fixture(busy)
        defer { vault.cleanUp() }
        let target = try #require(vault.notes.first { $0.title == "Imprint" })
        let mentions = try await vault.index.unlinkedMentions(of: target, notes: vault.notes, perNote: 3, limit: 50)
        #expect(mentions.count == 50)
        #expect(Dictionary(grouping: mentions, by: \.noteID).values.allSatisfy { $0.count <= 3 })
    }

    @Test func linkingAMentionKeepsItsWording() throws {
        let text = "I like imprint a lot."
        let mention = try #require(SearchIndex.mentions(of: "Imprint", in: text, noteID: "Notes.md", noteTitle: "Notes").first)
        #expect(mention.linking(in: text, to: "Imprint") == "I like [[Imprint|imprint]] a lot.")
        #expect(mention.linking(in: "Changed since.", to: "Imprint") == nil)
    }
}

struct FuzzyTests {
    @Test func editDistance() {
        #expect(Fuzzy.editDistance("meetng", "meeting", limit: 1) == 1)
        #expect(Fuzzy.editDistance("teh", "the", limit: 1) == 1) // Swapped letters.
        #expect(Fuzzy.editDistance("garden", "kitchen", limit: 2) == nil)
    }
}
