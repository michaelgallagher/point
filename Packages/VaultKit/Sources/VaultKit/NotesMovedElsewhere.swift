import Foundation

/// Notes renamed or moved on another device (or in another app), found between two reads of
/// the vault: one note gone and another appeared that's the same note (see `isSameNote`), so
/// what's known about it, and any window showing it, can follow it. Used by both apps.
///
/// A rename can arrive over two reads (the old name gone in one, the new one there in the
/// next, or the other way round), so a note gone, or appeared, and not matched waits one more
/// read before it counts as deleted, or new.
public struct NotesMovedElsewhere: Sendable {
    /// Notes gone in the last read and not matched, waiting one more.
    public private(set) var vanishedBefore: [Note] = []
    /// Notes that appeared in the last read and weren't matched, waiting one more.
    private var appearedBefore: [Note] = []

    public init() {}

    /// The same note under a new name or in a new folder: the same file name in another
    /// folder (moved), or in the same folder, made at the same moment (renamed; a rename
    /// keeps the file's created date).
    public static func isSameNote(_ gone: Note, _ new: Note) -> Bool {
        let goneFolder = FolderTree.folder(of: gone.id)
        let newFolder = FolderTree.folder(of: new.id)
        if gone.url.lastPathComponent == new.url.lastPathComponent { return goneFolder != newFolder }
        return goneFolder == newFolder && abs(gone.created.timeIntervalSince(new.created)) < 1
    }

    /// The notes moved between `before` (the last read) and `after` (this one), each gone note
    /// with the one it became. Nothing on the first read, when `before` is empty.
    public mutating func match(before: [Note], after: [Note]) -> [(gone: Note, new: Note)] {
        let known = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let afterIDs = Set(after.map(\.id))
        let newlyAppeared = known.isEmpty ? [] : after.filter { known[$0.id] == nil }
        var appeared = newlyAppeared + appearedBefore.filter { afterIDs.contains($0.id) && known[$0.id] != nil }
        let vanished = before.filter { !afterIDs.contains($0.id) }
        var unmatched: [Note] = []
        var pairs: [(gone: Note, new: Note)] = []
        for gone in vanished + vanishedBefore.filter({ !afterIDs.contains($0.id) }) {
            guard let index = appeared.firstIndex(where: { Self.isSameNote(gone, $0) }) else {
                unmatched.append(gone)
                continue
            }
            pairs.append((gone, appeared.remove(at: index)))
        }
        // Only those gone in this read wait another; those already waiting have had theirs.
        vanishedBefore = unmatched.filter { known[$0.id] != nil }
        appearedBefore = newlyAppeared.filter { new in appeared.contains { $0.id == new.id } }
        return pairs
    }
}
