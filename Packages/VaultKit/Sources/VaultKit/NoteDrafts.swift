import CryptoKit
import Foundation

/// Edits that couldn't be saved to their note, kept outside the vault (in the app's own
/// storage) so they're never lost: offered back when the note is next opened, and removed
/// once the note is saved or the draft is dismissed.
public struct NoteDrafts: Sendable {
    /// One note's unsaved text.
    public struct Draft: Codable, Equatable, Sendable {
        /// The note, by its path in the vault.
        public let noteID: String
        public let text: String
        public let saved: Date
    }

    /// The folder holding this vault's drafts.
    public let folder: URL

    /// Drafts for one vault, in `storage` (the app's own folder, never the vault).
    public init(storage: URL, vaultKey: String) {
        folder = storage.appendingPathComponent(vaultKey, isDirectory: true)
    }

    /// Keeps a note's unsaved text, replacing any earlier draft of it. Written whole or not
    /// at all.
    public func keep(_ text: String, for noteID: String, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Draft(noteID: noteID, text: text, saved: date))
        try data.write(to: url(for: noteID), options: .atomic)
    }

    /// The note's draft, if one is kept.
    public func draft(for noteID: String) -> Draft? {
        guard let data = try? Data(contentsOf: url(for: noteID)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    /// Forgets the note's draft (its text was saved, or the draft dismissed).
    public func remove(for noteID: String) {
        try? FileManager.default.removeItem(at: url(for: noteID))
    }

    /// Every draft kept for the vault.
    public func all() -> [Draft] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(Draft.self, from: $0) }
        }
    }

    /// A file name for the note, from a hash of its path (which may hold any characters).
    private func url(for noteID: String) -> URL {
        let hash = SHA256.hash(data: Data(noteID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".json")
    }
}
