import Foundation
import Testing
@testable import VaultKit

/// From the review of 27 October: a save that failed was only logged, and the edits lost
/// when the note closed. They're kept as a draft instead, outside the vault.
struct NoteDraftsTests {
    private func makeDrafts() -> (NoteDrafts, URL) {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("Drafts-\(UUID().uuidString)")
        return (NoteDrafts(storage: storage, vaultKey: "vault"), storage)
    }

    @Test func keepsFindsAndRemovesADraft() throws {
        let (drafts, storage) = makeDrafts()
        defer { try? FileManager.default.removeItem(at: storage) }
        #expect(drafts.draft(for: "Projects/Idea.md") == nil)
        let date = Date(timeIntervalSince1970: 1_000)
        try drafts.keep("Unsaved text", for: "Projects/Idea.md", at: date)
        #expect(drafts.draft(for: "Projects/Idea.md") == .init(noteID: "Projects/Idea.md", text: "Unsaved text", saved: date))
        #expect(drafts.draft(for: "Idea.md") == nil) // Another note with the same name.
        drafts.remove(for: "Projects/Idea.md")
        #expect(drafts.draft(for: "Projects/Idea.md") == nil)
    }

    @Test func aLaterDraftReplacesAnEarlierOne() throws {
        let (drafts, storage) = makeDrafts()
        defer { try? FileManager.default.removeItem(at: storage) }
        try drafts.keep("First", for: "Idea.md")
        try drafts.keep("Second", for: "Idea.md")
        #expect(drafts.draft(for: "Idea.md")?.text == "Second")
        #expect(drafts.all().map(\.text) == ["Second"])
    }

    @Test func anyNoteNameWorks() throws {
        let (drafts, storage) = makeDrafts()
        defer { try? FileManager.default.removeItem(at: storage) }
        let id = "A/B: c?*\"<>|/Ünïcode 🙂.md"
        try drafts.keep("text", for: id)
        #expect(drafts.draft(for: id)?.noteID == id)
    }

    @Test func draftsAreKeptPerVault() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("Drafts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: storage) }
        try NoteDrafts(storage: storage, vaultKey: "one").keep("text", for: "Idea.md")
        #expect(NoteDrafts(storage: storage, vaultKey: "two").draft(for: "Idea.md") == nil)
    }
}
