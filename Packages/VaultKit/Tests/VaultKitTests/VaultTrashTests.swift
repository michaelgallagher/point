import Foundation
import Testing
@testable import VaultKit

struct VaultTrashTests {
    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        return url
    }

    @Test func movingListingAndRestoring() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try NoteFiles.create(title: "Idea", text: "hello", in: root.appendingPathComponent("Projects"))
        let name = try VaultTrash.move(note, vault: root)
        #expect(name == "Idea.md")
        #expect(!FileManager.default.fileExists(atPath: note.path))
        let deleted = Date(timeIntervalSince1970: 1_000)
        let items = VaultTrash.items(in: root, records: [name: .init(deleted: deleted, folder: "Projects")])
        #expect(items.map(\.title) == ["Idea"])
        #expect(items[0].deleted == deleted)
        let restored = try VaultTrash.restore(items[0], vault: root)
        #expect(restored.path == root.appendingPathComponent("Projects/Idea.md").path)
        #expect(try String(contentsOf: restored, encoding: .utf8) == "hello")
        #expect(VaultTrash.items(in: root, records: [:]).isEmpty)
    }

    @Test func restoringToAFolderThatsGoneUsesTheTopLevel() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = try NoteFiles.create(title: "Old", in: root.appendingPathComponent("Projects"))
        let name = try VaultTrash.move(note, vault: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Projects"))
        let item = try #require(VaultTrash.items(in: root, records: [name: .init(deleted: Date(), folder: "Projects")]).first)
        #expect(try VaultTrash.restore(item, vault: root).path == root.appendingPathComponent("Old.md").path)
    }

    @Test func sameNamesDontCollide() throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try NoteFiles.create(title: "Same", in: root)
        let second = try NoteFiles.create(title: "Same", in: root.appendingPathComponent("Projects"))
        #expect(try VaultTrash.move(first, vault: root) == "Same.md")
        #expect(try VaultTrash.move(second, vault: root) == "Same 2.md")
    }
}
