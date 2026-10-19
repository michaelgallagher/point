import Foundation
import Testing
@testable import VaultKit

struct VaultScannerTests {
    /// Builds a throwaway vault containing `files` (relative paths) and returns its root.
    private func makeVault(_ files: [String: Date] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultKitTests-\(UUID().uuidString)")
        for (path, date) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(path)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
        }
        return root
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func findsNotesInAllFoldersAsAFlatList() throws {
        let root = try makeVault([
            "Inbox.md": now,
            "Projects/Imprint.md": now,
            "Projects/Archive/Old idea.md": now,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let notes = try VaultScanner.scan(root).sorted(by: .title)
        #expect(notes.map(\.id) == ["Projects/Imprint.md", "Inbox.md", "Projects/Archive/Old idea.md"])
        #expect(notes.map(\.title) == ["Imprint", "Inbox", "Old idea"])
        #expect(notes.allSatisfy { $0.isDownloaded })
    }

    @Test func skipsDotFoldersAndOtherFiles() throws {
        let root = try makeVault([
            "Note.md": now,
            ".obsidian/workspace.md": now,
            ".trash/Deleted.md": now,
            "attachments/photo.png": now,
            "board.canvas": now,
            ".hidden.md": now,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try VaultScanner.scan(root).map(\.id) == ["Note.md"])
    }

    @Test func findsEveryFolderIncludingEmptyOnes() throws {
        let root = try makeVault(["Projects/Imprint.md": now, ".obsidian/workspace.md": now])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty/Inner"), withIntermediateDirectories: true)

        let folders = try VaultScanner.scanWithFolders(root).folders.sorted()
        #expect(folders == ["Empty", "Empty/Inner", "Projects"]) // Not .obsidian.
    }

    @Test func includesEvictedICloudFiles() throws {
        let root = try makeVault(["Projects/.Plan.md.icloud": now])
        defer { try? FileManager.default.removeItem(at: root) }

        let note = try #require(try VaultScanner.scan(root).first)
        #expect(note.id == "Projects/Plan.md")
        #expect(note.title == "Plan")
        #expect(note.url.lastPathComponent == "Plan.md")
        #expect(!note.isDownloaded)
    }

    @Test func readsDates() throws {
        let root = try makeVault(["A.md": now])
        defer { try? FileManager.default.removeItem(at: root) }

        let note = try #require(try VaultScanner.scan(root).first)
        #expect(note.modified == now)
        #expect(note.created == now)
    }

    @Test(arguments: [
        ("Idea.md", "Idea.md", true),
        ("Idea.MD", "Idea.MD", true),
        (".Idea.md.icloud", "Idea.md", false),
    ])
    func recognisesNoteFiles(name: String, fileName: String, isDownloaded: Bool) throws {
        let result = try #require(VaultScanner.noteFileName(name))
        #expect(result.0 == fileName)
        #expect(result.1 == isDownloaded)
    }

    @Test(arguments: [".md", "Idea.txt", "Idea.md.bak", ".photo.png.icloud", ".DS_Store", ".hidden.md"])
    func ignoresOtherFiles(name: String) {
        #expect(VaultScanner.noteFileName(name) == nil)
    }
}

struct NoteSortTests {
    private func note(_ title: String, modified: Double, created: Double) -> Note {
        Note(
            id: "\(title).md",
            url: URL(fileURLWithPath: "/vault/\(title).md"),
            title: title,
            modified: Date(timeIntervalSince1970: modified),
            created: Date(timeIntervalSince1970: created),
            isDownloaded: true
        )
    }

    private var notes: [Note] {
        [note("Note 10", modified: 1, created: 3), note("Note 2", modified: 3, created: 1), note("apple", modified: 2, created: 2)]
    }

    @Test func modifiedPutsMostRecentlyEditedFirst() {
        #expect(notes.sorted(by: .modified).map(\.title) == ["Note 2", "apple", "Note 10"])
    }

    @Test func createdPutsNewestFirst() {
        #expect(notes.sorted(by: .created).map(\.title) == ["Note 10", "apple", "Note 2"])
    }

    @Test func titleIsAlphabeticalInFinderOrder() {
        #expect(notes.sorted(by: .title).map(\.title) == ["apple", "Note 2", "Note 10"])
    }

    @Test func tiesAreBrokenByPath() {
        let tied = [note("B", modified: 1, created: 1), note("A", modified: 1, created: 1)]
        #expect(tied.sorted(by: .modified).map(\.title) == ["A", "B"])
    }
}
