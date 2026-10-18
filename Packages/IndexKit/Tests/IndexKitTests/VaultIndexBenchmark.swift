import Foundation
import Testing
@testable import IndexKit
import VaultKit

/// Indexes a real vault (read-only) and times searches. Opt in with
/// `IMPRINT_INDEX_VAULT=/path/to/vault swift test -c release --filter VaultIndexBenchmark`.
struct VaultIndexBenchmark {
    static let vaultPath = ProcessInfo.processInfo.environment["IMPRINT_INDEX_VAULT"]

    @Test(.enabled(if: vaultPath != nil))
    func indexAndSearch() async throws {
        let notes = try VaultScanner.scan(URL(fileURLWithPath: Self.vaultPath!))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) } }

        var start = Date()
        let index = try SearchIndex(url: file)
        let count = try await index.update(notes: notes)
        let indexing = Date().timeIntervalSince(start)
        start = Date()
        let again = try await index.update(notes: notes)
        let rescan = Date().timeIntervalSince(start)
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0)
            + ((try? FileManager.default.attributesOfItem(atPath: file.path + "-wal")[.size] as? Int) ?? 0)
        print("INDEX: \(count) notes in \(String(format: "%.1f", indexing)) s; unchanged re-check \(again) notes in \(Int(rescan * 1000)) ms; \(size / 1_000_000) MB")

        for query in ["design", "desing", "meet", "user research", "strat", "#work", "nhs servce"] {
            start = Date()
            let results = try await index.search(query)
            print("SEARCH \"\(query)\": \(results.count) results in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        let tags = try await index.allTags()
        print("TAGS: \(tags.count) distinct")
        if let busiest = notes.max(by: { $0.title.count > $1.title.count ? false : true }) {
            start = Date()
            let backlinks = try await index.backlinks(to: busiest, notes: notes)
            let mentions = try await index.unlinkedMentions(of: busiest, notes: notes)
            print("LINKS for a note: \(backlinks.count) backlinks, \(mentions.count) mentions in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
    }
}
