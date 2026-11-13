import Foundation
import Testing
@testable import VaultKit

/// A slip on the phone (swipe-typing over a selected word) couldn't be undone once the note
/// was left. Each note is kept as it was before it changed, outside the vault, to put back.
struct NoteVersionsTests {
    private func makeVersions(limit: Int = 20) -> (NoteVersions, URL) {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("Versions-\(UUID().uuidString)")
        return (NoteVersions(storage: storage, vaultKey: "vault", limit: limit), storage)
    }

    @Test func keepsVersionsNewestFirst() throws {
        let (versions, storage) = makeVersions()
        defer { try? FileManager.default.removeItem(at: storage) }
        #expect(versions.versions(for: "Blog/Post.md").isEmpty)
        try versions.keep("First", for: "Blog/Post.md", at: Date(timeIntervalSince1970: 1_000))
        try versions.keep("Second", for: "Blog/Post.md", at: Date(timeIntervalSince1970: 2_000))
        #expect(versions.versions(for: "Blog/Post.md").map(\.text) == ["Second", "First"])
        #expect(versions.versions(for: "Post.md").isEmpty) // Another note with the same name.
    }

    @Test func theSameTextTwiceIsKeptOnce() throws {
        let (versions, storage) = makeVersions()
        defer { try? FileManager.default.removeItem(at: storage) }
        try versions.keep("Same", for: "Note.md", at: Date(timeIntervalSince1970: 1_000))
        try versions.keep("Same", for: "Note.md", at: Date(timeIntervalSince1970: 2_000))
        #expect(versions.versions(for: "Note.md").count == 1)
    }

    @Test func pastTheLimitTheOldestGo() throws {
        let (versions, storage) = makeVersions(limit: 3)
        defer { try? FileManager.default.removeItem(at: storage) }
        for index in 1...5 { try versions.keep("Text \(index)", for: "Note.md", at: Date(timeIntervalSince1970: Double(index) * 1_000)) }
        #expect(versions.versions(for: "Note.md").map(\.text) == ["Text 5", "Text 4", "Text 3"])
    }

    @Test func versionsFollowARename() throws {
        let (versions, storage) = makeVersions()
        defer { try? FileManager.default.removeItem(at: storage) }
        try versions.keep("Old", for: "Ideas/Plan.md", at: Date(timeIntervalSince1970: 1_000))
        try versions.keep("Newer", for: "Ideas/Plan.md", at: Date(timeIntervalSince1970: 2_000))
        versions.move(from: "Ideas/Plan.md", to: "Projects/Plan.md")
        #expect(versions.versions(for: "Ideas/Plan.md").isEmpty)
        #expect(versions.versions(for: "Projects/Plan.md").map(\.kept) == [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
    }
}
