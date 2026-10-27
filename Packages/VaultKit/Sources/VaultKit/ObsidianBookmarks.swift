import Foundation

/// Obsidian's bookmarks (`.obsidian/bookmarks.json`, its core Bookmarks plugin): the notes
/// looked at again and again, shared by every app and device using the vault. Point reads and
/// changes the notes in it; everything else there (groups, folders, searches, headings) is kept
/// as it is.
public enum ObsidianBookmarks {
    /// A bookmarked note.
    public struct Bookmark: Equatable, Sendable {
        /// The note's path in the vault, as its ID (`Projects/Plan.md`).
        public let path: String
        /// A name given to the bookmark in Obsidian, shown instead of the note's own.
        public let title: String?
    }

    static func file(in root: URL) -> URL {
        root.appendingPathComponent(".obsidian/bookmarks.json")
    }

    /// The bookmarked notes, in Obsidian's order (those in groups where the group is).
    public static func load(vault root: URL) -> [Bookmark] {
        guard let object = try? ObsidianJSON.object(at: file(in: root)) else { return [] }
        func notes(in items: [[String: Any]]) -> [Bookmark] {
            items.flatMap { item -> [Bookmark] in
                switch item["type"] as? String {
                case "file":
                    guard let path = item["path"] as? String, path.lowercased().hasSuffix(".md") else { return [] }
                    let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    return [Bookmark(path: path, title: title)]
                case "group":
                    return notes(in: item["items"] as? [[String: Any]] ?? [])
                default:
                    return []
                }
            }
        }
        return notes(in: object["items"] as? [[String: Any]] ?? [])
    }

    /// Bookmarks a note, at the end.
    public static func add(_ path: String, vault root: URL, date: Date = Date()) throws {
        try change(vault: root) { items in
            guard !contains(path, in: items) else { return }
            items.append(["type": "file", "path": path, "ctime": Int((date.timeIntervalSince1970 * 1000).rounded())])
        }
    }

    /// Removes a note's bookmarks (wherever they are, groups too).
    public static func remove(_ path: String, vault root: URL) throws {
        try change(vault: root) { items in
            func without(_ items: [[String: Any]]) -> [[String: Any]] {
                items.compactMap { item in
                    if item["type"] as? String == "file", item["path"] as? String == path { return nil }
                    guard item["type"] as? String == "group" else { return item }
                    var group = item
                    group["items"] = without(item["items"] as? [[String: Any]] ?? [])
                    return group
                }
            }
            items = without(items)
        }
    }

    /// Puts the bookmarked notes in a new order. Each note's bookmark moves, with what it holds
    /// (its title, its date), into the place of the note now there; groups and other kinds of
    /// bookmark stay where they are.
    public static func reorder(_ paths: [String], vault root: URL) throws {
        try change(vault: root) { items in
            // The notes as they are, in order, with what each bookmark holds.
            var entries: [String: [String: Any]] = [:]
            func collect(_ items: [[String: Any]]) {
                for item in items {
                    if item["type"] as? String == "file", let path = item["path"] as? String, path.lowercased().hasSuffix(".md") {
                        entries[path] = entries[path] ?? item
                    } else if item["type"] as? String == "group" {
                        collect(item["items"] as? [[String: Any]] ?? [])
                    }
                }
            }
            collect(items)
            var order = paths.filter { entries[$0] != nil }.makeIterator()
            func refill(_ items: [[String: Any]]) -> [[String: Any]] {
                items.map { item in
                    if item["type"] as? String == "file", let path = item["path"] as? String, path.lowercased().hasSuffix(".md") {
                        return order.next().flatMap { entries[$0] } ?? item
                    }
                    guard item["type"] as? String == "group" else { return item }
                    var group = item
                    group["items"] = refill(item["items"] as? [[String: Any]] ?? [])
                    return group
                }
            }
            items = refill(items)
        }
    }

    private static func contains(_ path: String, in items: [[String: Any]]) -> Bool {
        items.contains { item in
            item["type"] as? String == "file" && item["path"] as? String == path
                || item["type"] as? String == "group" && contains(path, in: item["items"] as? [[String: Any]] ?? [])
        }
    }

    /// Reads the file, changes its items, and writes it back keeping everything else. A file
    /// that can't be read is left alone (see `ObsidianJSON`).
    private static func change(vault root: URL, _ edit: (inout [[String: Any]]) -> Void) throws {
        let url = file(in: root)
        var object = try ObsidianJSON.object(at: url)
        var items = object["items"] as? [[String: Any]] ?? []
        edit(&items)
        object["items"] = items
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
