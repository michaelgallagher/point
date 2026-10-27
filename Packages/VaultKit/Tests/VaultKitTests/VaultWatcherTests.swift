#if os(macOS)
import CoreServices
import Foundation
import Testing
@testable import VaultKit

struct VaultWatcherTests {
    /// Collects reported URLs across threads.
    final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ new: [URL]) { lock.withLock { urls += new } }
        var names: Set<String> { lock.withLock { Set(urls.map(\.lastPathComponent)) } }
    }

    @Test func reportsChangedNotesButNotDotFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Watcher-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inbox = Inbox()
        let watcher = VaultWatcher(root: root, latency: 0.05) { inbox.add($0) }
        defer { watcher.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)

        try Data("a".utf8).write(to: root.appendingPathComponent("Note.md"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".obsidian/workspace.json"))

        for _ in 0..<40 where !inbox.names.contains("Note.md") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(inbox.names.contains("Note.md"))
        #expect(!inbox.names.contains("workspace.json"))
    }

    /// From the review of 27 October: a vault inside a dot-folder (`~/.notes/Vault`) was never
    /// told of changes, as every path in it had a dot-folder in it. Only the vault's own count.
    @Test func onlyTheVaultsOwnDotFoldersAreSkipped() {
        let root = "/Users/ann/.notes/Vault"
        let paths = ["\(root)/Note.md", "\(root)/.obsidian/workspace.json", "\(root)/.trash/Old.md",
                     "\(root)/Projects/.Plan.md.icloud", "\(root)/Projects/Plan.md"]
        #expect(VaultWatcher.notePaths(paths, under: [root]) == ["\(root)/Note.md", "\(root)/Projects/.Plan.md.icloud", "\(root)/Projects/Plan.md"])
    }

    /// Dropped events, or the vault's folder moving, mean the whole vault needs looking at.
    @Test func droppedEventsMeanARescan() {
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
                     kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged] {
            #expect(VaultWatcher.meansMissedChanges(FSEventStreamEventFlags(flag | kFSEventStreamEventFlagItemIsFile)))
        }
        #expect(!VaultWatcher.meansMissedChanges(FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile)))
    }

    @Test func aVaultInsideADotFolderIsWatched() async throws {
        let outer = FileManager.default.temporaryDirectory.appendingPathComponent(".Watcher-\(UUID().uuidString)").resolvingSymlinksInPath()
        let root = outer.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outer) }
        let inbox = Inbox()
        let watcher = VaultWatcher(root: root, latency: 0.05) { inbox.add($0) }
        defer { watcher.stop() }
        #expect(watcher.isWatching)
        try await Task.sleep(nanoseconds: 300_000_000)
        try Data("a".utf8).write(to: root.appendingPathComponent("Note.md"))
        for _ in 0..<40 where !inbox.names.contains("Note.md") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(inbox.names.contains("Note.md"))
    }

    /// The vault's folder moved (renamed in Finder, say): told to look at everything again.
    @Test func theVaultMovingIsReported() async throws {
        let outer = FileManager.default.temporaryDirectory.appendingPathComponent("Watcher-\(UUID().uuidString)").resolvingSymlinksInPath()
        let root = outer.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outer) }
        let missed = Inbox()
        let watcher = VaultWatcher(root: root, latency: 0.05, onChange: { _ in }, onMissedChanges: { missed.add([root]) })
        defer { watcher.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)
        try FileManager.default.moveItem(at: root, to: outer.appendingPathComponent("Moved"))
        for _ in 0..<40 where missed.names.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(!missed.names.isEmpty)
    }
}
#endif
