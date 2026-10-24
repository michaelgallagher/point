import Foundation

/// A Markdown note in the vault.
public struct Note: Identifiable, Hashable, Sendable {
    /// Path relative to the vault root, such as `Projects/Point.md`. Unique within a vault.
    public let id: String
    /// Where the note's contents live. For a note iCloud has evicted, this is where the
    /// file will be once downloaded, not the placeholder.
    public let url: URL
    /// The filename without its `.md` extension. Obsidian uses this as the note's name.
    public let title: String
    public let modified: Date
    public let created: Date
    /// False when iCloud has evicted the file and only a placeholder is on disk.
    public let isDownloaded: Bool

    public init(id: String, url: URL, title: String, modified: Date, created: Date, isDownloaded: Bool) {
        self.id = id
        self.url = url
        self.title = title
        self.modified = modified
        self.created = created
        self.isDownloaded = isDownloaded
    }
}

/// How the note list is ordered.
public enum NoteSort: String, CaseIterable, Sendable {
    /// Most recently edited first.
    case modified
    /// Most recently created first.
    case created
    /// Alphabetical by title, in Finder order (so "Note 2" comes before "Note 10").
    case title
}

extension Sequence where Element == Note {
    public func sorted(by sort: NoteSort) -> [Note] {
        sorted { a, b in
            switch sort {
            case .modified where a.modified != b.modified:
                return a.modified > b.modified
            case .created where a.created != b.created:
                return a.created > b.created
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedAscending }
            default:
                break
            }
            // Ties fall back to path so the order is stable between scans.
            return a.id.localizedStandardCompare(b.id) == .orderedAscending
        }
    }
}
