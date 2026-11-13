import CryptoKit
import Foundation

/// Notes as they were before they were changed, kept outside the vault (in the app's own
/// storage) so a slip that undo can't reach any more (the note left, the app closed) can be
/// put right: the text as it was when it was opened, kept as editing starts, and the text
/// being replaced when an earlier one is put back. The latest `limit` for each note.
public struct NoteVersions: Sendable {
    /// One note as it was.
    public struct Version: Codable, Equatable, Identifiable, Sendable {
        /// The note, by its path in the vault.
        public let noteID: String
        public let text: String
        /// When it was kept: when the note was about to change.
        public let kept: Date

        public var id: Date { kept }
    }

    /// The folder holding this vault's versions, a folder for each note.
    public let folder: URL
    /// How many are kept for each note, the oldest going first.
    public let limit: Int

    /// Versions for one vault, in `storage` (the app's own folder, never the vault).
    public init(storage: URL, vaultKey: String, limit: Int = 20) {
        folder = storage.appendingPathComponent(vaultKey, isDirectory: true)
        self.limit = limit
    }

    /// Keeps the note as it is now, unless the latest kept is the same text. Written whole or
    /// not at all; past the limit, the oldest go.
    public func keep(_ text: String, for noteID: String, at date: Date = Date()) throws {
        guard versions(for: noteID).first?.text != text else { return }
        let notes = noteFolder(for: noteID)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Version(noteID: noteID, text: text, kept: date))
        let name = String(format: "%.3f", date.timeIntervalSince1970) + ".json"
        try data.write(to: notes.appendingPathComponent(name), options: .atomic)
        for old in files(in: notes).dropFirst(limit) { try? FileManager.default.removeItem(at: old) }
    }

    /// The note's kept versions, newest first.
    public func versions(for noteID: String) -> [Version] {
        files(in: noteFolder(for: noteID)).compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Version.self, from: $0) }
        }
    }

    /// A note renamed or moved: its versions go with it.
    public func move(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let moving = versions(for: oldID)
        guard !moving.isEmpty else { return }
        for version in moving.reversed() { try? keep(version.text, for: newID, at: version.kept) }
        try? FileManager.default.removeItem(at: noteFolder(for: oldID))
    }

    /// The note's version files, newest first (their names are the times they were kept).
    private func files(in notes: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: notes.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }
            .sorted { (Double($0.dropLast(5)) ?? 0) > (Double($1.dropLast(5)) ?? 0) }
            .map { notes.appendingPathComponent($0) }
    }

    /// A folder name for the note, from a hash of its path (which may hold any characters).
    private func noteFolder(for noteID: String) -> URL {
        let hash = SHA256.hash(data: Data(noteID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash, isDirectory: true)
    }
}
