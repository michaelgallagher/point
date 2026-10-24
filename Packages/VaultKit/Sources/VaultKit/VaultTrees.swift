import Foundation

/// The vault's folders: those its notes are in, and any others found on disk (empty ones).
public struct FolderTree: Sendable {
    /// Each folder's path (`Projects/Archive`; the vault root is "") and how many notes are in
    /// it, including in its subfolders.
    public let noteCounts: [String: Int]

    public init(notes: [Note], folders: [String] = []) {
        var counts: [String: Int] = [:]
        for note in notes {
            var folder = Self.folder(of: note.id)
            while !folder.isEmpty {
                counts[folder, default: 0] += 1
                folder = Self.parent(of: folder)
            }
        }
        // Folders without notes still show, with a count of 0 (as do the folders above them).
        for path in folders {
            var folder = path
            while !folder.isEmpty {
                if counts[folder] == nil { counts[folder] = 0 }
                folder = Self.parent(of: folder)
            }
        }
        noteCounts = counts
    }

    /// The folders directly inside `path`, in Finder order.
    public func subfolders(of path: String) -> [String] {
        noteCounts.keys
            .filter { Self.parent(of: $0) == path }
            .sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
    }

    /// The folder a note is in: `Projects/Archive` for `Projects/Archive/Idea.md`, "" for the root.
    public static func folder(of noteID: String) -> String {
        noteID.split(separator: "/").dropLast().joined(separator: "/")
    }

    public static func parent(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    public static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// The vault's tags as a hierarchy, `work` above `work/imprint`.
public struct TagTree: Sendable {
    public struct Entry: Sendable, Equatable, Identifiable {
        /// The full tag, such as `work/imprint`.
        public let tag: String
        /// How deep it is: 0 for `work`, 1 for `work/imprint`.
        public let depth: Int
        /// Notes with this tag or any tag under it.
        public let count: Int
        public var id: String { tag.lowercased() }
        /// The last part, such as `imprint`.
        public var name: String { tag.split(separator: "/").last.map(String.init) ?? tag }
    }

    /// Every tag in tree order: each parent followed by its children, alphabetically.
    public let entries: [Entry]

    /// - Parameter tagsByNote: each note's tags, as written.
    public init(tagsByNote: [[String]]) {
        var counts: [String: Int] = [:]   // Keyed by lowercased tag.
        var spelling: [String: String] = [:]
        for tags in tagsByNote {
            var seen = Set<String>()
            for tag in tags {
                // Count the note once for the tag and once for each parent above it.
                let parts = tag.split(separator: "/").map(String.init)
                for depth in parts.indices {
                    let path = parts[0...depth].joined(separator: "/")
                    let key = path.lowercased()
                    if spelling[key] == nil { spelling[key] = path }
                    if seen.insert(key).inserted { counts[key, default: 0] += 1 }
                }
            }
        }
        // Sorting by path segments keeps every child right after its parent.
        let keys = counts.keys.sorted { a, b in
            let x = a.split(separator: "/"), y = b.split(separator: "/")
            for (p, q) in zip(x, y) where p != q {
                return String(p).localizedStandardCompare(String(q)) == .orderedAscending
            }
            return x.count < y.count
        }
        entries = keys.map { key in
            Entry(tag: spelling[key]!, depth: key.split(separator: "/").count - 1, count: counts[key]!)
        }
    }

    /// The tags directly under `tag`.
    public func children(of tag: String) -> [Entry] {
        let prefix = tag.lowercased() + "/"
        let depth = tag.split(separator: "/").count
        return entries.filter { $0.id.hasPrefix(prefix) && $0.depth == depth }
    }

    /// Whether a note's tags include `tag` or a tag under it (ignoring case).
    public static func tags(_ tags: [String], include tag: String) -> Bool {
        let wanted = tag.lowercased()
        return tags.contains { $0.lowercased() == wanted || $0.lowercased().hasPrefix(wanted + "/") }
    }
}

/// A place in the sidebar to browse.
public enum SidebarPlace: Hashable, Sendable, Codable {
    /// The vault's top level: its folders, and the notes not in any.
    case allNotes
    /// A folder, by path from the vault root.
    case folder(String)
    case tag(String)
    /// Every note, in one list, whatever folder it's in.
    case everything
    /// Notes deleted, kept for a while before they go for good.
    case trash

    /// For storing pins: `folder:NHS`, `tag:work/imprint`.
    public var key: String {
        switch self {
        case .allNotes: "all"
        case .folder(let path): "folder:" + path
        case .tag(let tag): "tag:" + tag
        case .everything: "everything"
        case .trash: "trash"
        }
    }

    public init?(key: String) {
        if key == "all" { self = .allNotes }
        else if key == "everything" { self = .everything }
        else if key == "trash" { self = .trash }
        else if key.hasPrefix("folder:") { self = .folder(String(key.dropFirst(7))) }
        else if key.hasPrefix("tag:") { self = .tag(String(key.dropFirst(4))) }
        else { return nil }
    }

    /// Where the back arrow goes: a folder's parent folder, a tag's parent tag, else All Notes.
    public var parent: SidebarPlace {
        switch self {
        case .allNotes, .everything, .trash: .allNotes
        case .folder(let path):
            FolderTree.parent(of: path).isEmpty ? .allNotes : .folder(FolderTree.parent(of: path))
        case .tag(let tag):
            tag.contains("/") ? .tag(FolderTree.parent(of: tag)) : .allNotes
        }
    }
}
