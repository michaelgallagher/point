import Foundation

/// iCloud's conflict versions of a note: kept when two devices changed it before either had
/// synced (one of them offline, say). iCloud shows one; the others are hidden, from Files,
/// Obsidian and Point alike. Each is written out as a conflict copy beside the note, named as
/// Point's own are, and only then resolved, so nothing is hidden and nothing is lost.
public enum ICloudConflicts {
    /// Writes out the note's conflict versions (any the same as the note are just resolved), and
    /// returns the copies written. A version that can't be copied is left as it is, unresolved.
    @discardableResult
    public static func surface(_ url: URL) throws -> [URL] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else { return [] }
        let current = try? Data(contentsOf: url)
        var written: [URL] = []
        for version in versions {
            let data = try NoteReader.coordinated(version.url) { try Data(contentsOf: $0) }
            if data != current {
                // As read, byte for byte, whatever it holds.
                written.append(try NoteWriter.writeConflictCopy(data, beside: url, date: version.modificationDate ?? Date()))
            }
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        return written
    }

    /// Whether a note has conflict versions waiting.
    public static func has(_ url: URL) -> Bool {
        !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
    }
}
