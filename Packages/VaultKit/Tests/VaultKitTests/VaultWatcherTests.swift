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
}
