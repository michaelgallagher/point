import Foundation

/// Finds every note in a vault, in all folders, as one flat list.
public enum VaultScanner {
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]

    /// Scans `root` recursively. Folders whose names start with a dot (`.obsidian`, `.trash`,
    /// `.git`) are skipped, as Obsidian does. Evicted iCloud files are included and marked
    /// as not downloaded.
    public static func scan(_ root: URL) throws -> [Note] {
        try scanWithFolders(root).notes
    }

    /// Scans `root` for its notes and also every folder (as paths from the root, such as
    /// `Projects/Archive`), including empty ones, which the notes alone wouldn't reveal.
    public static func scanWithFolders(_ root: URL) throws -> (notes: [Note], folders: [String]) {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true } // Skip unreadable items rather than failing the whole scan.
        ) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root])
        }

        var notes: [Note] = []
        var folders: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if name.hasPrefix(".") {
                    enumerator.skipDescendants()
                } else {
                    folders.append(url.pathComponents.suffix(enumerator.level).joined(separator: "/"))
                }
                continue
            }
            guard let (fileName, isDownloaded) = noteFileName(name) else { continue }

            let fileURL = url.deletingLastPathComponent().appendingPathComponent(fileName)
            // The enumerator may spell paths differently from `root` (for example /var versus
            // /private/var), so take the relative path from its depth, not by trimming a prefix.
            let folders = url.pathComponents.suffix(enumerator.level).dropLast()
            let modified = values?.contentModificationDate ?? .distantPast
            notes.append(Note(
                id: (folders + [fileName]).joined(separator: "/"),
                url: fileURL,
                title: String(fileName.dropLast(3)),
                modified: modified,
                created: values?.creationDate ?? modified,
                isDownloaded: isDownloaded
            ))
        }
        return (notes, folders)
    }

    /// Maps a filename on disk to the note's filename and whether its contents are local.
    ///
    /// `Idea.md` gives `("Idea.md", true)`. An iCloud placeholder for an evicted file,
    /// `.Idea.md.icloud`, gives `("Idea.md", false)`. Anything else gives nil.
    static func noteFileName(_ name: String) -> (String, Bool)? {
        if name.hasPrefix(".") {
            guard name.hasSuffix(".icloud") else { return nil }
            let inner = String(name.dropFirst().dropLast(".icloud".count))
            return isMarkdown(inner) ? (inner, false) : nil
        }
        return isMarkdown(name) ? (name, true) : nil
    }

    private static func isMarkdown(_ name: String) -> Bool {
        name.count > 3 && !name.hasPrefix(".") && name.lowercased().hasSuffix(".md")
    }
}
