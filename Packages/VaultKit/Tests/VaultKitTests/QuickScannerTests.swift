import Foundation
import Testing
@testable import VaultKit

struct QuickScannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeVault(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuickScanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for path in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if path.hasSuffix("/") { continue }
            try Data("# \(path)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now, .creationDate: now], ofItemAtPath: url.path)
        }
        return root
    }

    private let files = ["Inbox.md", "Projects/Imprint.md", "Projects/Archive/Old idea.md", "Empty folder/",
                         ".obsidian/workspace.md", ".trash/Deleted.md", "attachments/photo.png", "board.canvas",
                         ".Evicted.md.icloud", "Café notes.md"]

    @Test func findsWhatTheEnumeratorFinds() throws {
        let root = try makeVault(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let quick = try VaultScanner.quickScan(root)
        let full = try VaultScanner.scanAll(root)
        #expect(Set(quick.notes.map(\.id)) == Set(full.notes.map(\.id)))
        #expect(Set(quick.notes.map(\.title)) == Set(full.notes.map(\.title)))
        #expect(Set(quick.notes.map(\.isDownloaded)) == Set(full.notes.map(\.isDownloaded)))
        #expect(Set(quick.notes.map(\.url.path)) == Set(full.notes.map(\.url.path)))
        #expect(Set(quick.folders) == Set(full.folders))
        #expect(Set(quick.images.map(\.path)) == Set(full.images.map(\.path)))
        let byID = Dictionary(uniqueKeysWithValues: full.notes.map { ($0.id, $0) })
        for note in quick.notes where note.isDownloaded {
            #expect(abs(note.modified.timeIntervalSince(byID[note.id]!.modified)) < 0.001)
        }
        #expect(quick.notes.first { $0.id == "Evicted.md" }?.isDownloaded == false)
    }

    @Test func rescanChangesOnlyWhatChanged() throws {
        let root = try makeVault(["Inbox.md", "Projects/Imprint.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = try VaultScanner.quickScan(root).notes
        // Edited, added, deleted.
        try Data("# Inbox\n\nMore.\n".utf8).write(to: root.appendingPathComponent("Inbox.md"))
        try Data("# New\n".utf8).write(to: root.appendingPathComponent("Projects/New.md"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Projects/Imprint.md"))
        let urls: Set<URL> = [root.appendingPathComponent("Inbox.md"), root.appendingPathComponent("Projects/New.md"),
                              root.appendingPathComponent("Projects/Imprint.md"), root.appendingPathComponent(".obsidian/workspace.json")]
        let updated = try #require(VaultScanner.rescan(urls, in: root, notes: notes))
        #expect(Set(updated.map(\.id)) == ["Inbox.md", "Projects/New.md"])
        #expect(updated.first { $0.id == "Inbox.md" }!.modified != now)
        #expect(Set(updated.map(\.url.path)) == Set(try VaultScanner.scanAll(root).notes.map(\.url.path)))
    }

    @Test func aFolderOrImageNeedsEverythingRead() throws {
        let root = try makeVault(["Inbox.md", "Projects/Imprint.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = try VaultScanner.quickScan(root).notes
        #expect(VaultScanner.rescan([root.appendingPathComponent("Projects")], in: root, notes: notes) == nil)
        #expect(VaultScanner.rescan([root.appendingPathComponent("Gone folder")], in: root, notes: notes) == nil)
        #expect(VaultScanner.rescan([root.appendingPathComponent("photo.png")], in: root, notes: notes) == nil)
        #expect(VaultScanner.rescan([root], in: root, notes: notes) == nil)
        #expect(VaultScanner.rescan([root.appendingPathComponent(".obsidian")], in: root, notes: notes) == notes)
    }
}
