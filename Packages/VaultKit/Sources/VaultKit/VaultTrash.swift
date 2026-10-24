import Foundation

/// The vault's trash: its `.trash` folder, as Obsidian uses it when set to "Move to Obsidian
/// trash". Notes deleted in Imprint always go there, so they can be listed and put back, and
/// Obsidian sees the same ones. When each was deleted, and where from, is kept by the app.
public enum VaultTrash {
    /// A note in the trash.
    public struct Item: Identifiable, Hashable, Sendable {
        /// Its file name in the trash, such as `Idea.md`.
        public let name: String
        public let url: URL
        public var title: String { url.deletingPathExtension().lastPathComponent }
        /// When it was deleted (or first found in the trash, if Imprint didn't delete it).
        public let deleted: Date
        /// The folder it came from ("" for the vault's top level), if known.
        public let folder: String?
        public var id: String { name }
    }

    /// What the app remembers about a note it put in the trash.
    public struct Record: Codable, Hashable, Sendable {
        public var deleted: Date
        public var folder: String
        public init(deleted: Date, folder: String) {
            self.deleted = deleted
            self.folder = folder
        }
    }

    public static func folder(in root: URL) -> URL { root.appendingPathComponent(".trash") }

    /// Moves a note into the trash and returns its name there (`Idea 2.md` if `Idea.md` is
    /// taken).
    public static func move(_ url: URL, vault root: URL) throws -> String {
        let trash = folder(in: root)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = NoteFiles.availableURL(for: url.deletingPathExtension().lastPathComponent, in: trash)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination.lastPathComponent
    }

    /// The notes in the trash, newest first, with what's remembered about them. A note with
    /// no record counts as deleted at `now`.
    public static func items(in root: URL, records: [String: Record], now: Date = Date()) -> [Item] {
        let trash = folder(in: root)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        return names.filter { $0.lowercased().hasSuffix(".md") && !$0.hasPrefix(".") }
            .map { name in
                let record = records[name]
                return Item(name: name, url: trash.appendingPathComponent(name), deleted: record?.deleted ?? now, folder: record?.folder)
            }
            .sorted { $0.deleted > $1.deleted }
    }

    /// Puts a note back in the folder it came from (or the top level, if that folder's gone),
    /// under a free name, and returns its new URL.
    public static func restore(_ item: Item, vault root: URL) throws -> URL {
        var folder = item.folder.map { $0.isEmpty ? root : root.appendingPathComponent($0) } ?? root
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) || !isDirectory.boolValue { folder = root }
        let destination = NoteFiles.availableURL(for: item.title, in: folder)
        try FileManager.default.moveItem(at: item.url, to: destination)
        return destination
    }

    /// Removes a note from the trash for good.
    public static func delete(_ item: Item) throws {
        try FileManager.default.removeItem(at: item.url)
    }
}
