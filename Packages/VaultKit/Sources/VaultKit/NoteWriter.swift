import Foundation

public enum NoteWriter {
    public enum Outcome: Equatable, Sendable {
        case saved
        /// The file had changed on disk since it was read, so the text went to a copy instead.
        case savedAsConflictCopy(URL)
        /// The file had changed on disk since it was read, so nothing was written.
        /// Carries the file's current text.
        case changedOnDisk(String)
    }

    /// What to do when the file changed on disk since it was read.
    public enum ConflictPolicy: Sendable {
        /// Save the text next to the file as a conflict copy, so nothing is lost.
        case saveCopy
        /// Write nothing and report the change, so the user can decide.
        case report
    }

    /// Writes `text` to `url`, unless the file has changed since it held `expected`.
    ///
    /// The file is rewritten in place, as Obsidian does, so it keeps its creation date.
    /// Someone else's newer version (from Obsidian, or another device) is never overwritten.
    public static func write(_ text: String, to url: URL, expecting expected: String, ifChanged policy: ConflictPolicy = .saveCopy) throws -> Outcome {
        var coordinationError: NSError?
        var result: Result<Outcome, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result {
                if let onDisk = try? Data(contentsOf: url), onDisk != Data(expected.utf8) {
                    switch policy {
                    case .report:
                        return .changedOnDisk(String(decoding: onDisk, as: UTF8.self))
                    case .saveCopy:
                        let copy = conflictCopyURL(for: url)
                        try Data(text.utf8).write(to: copy)
                        return .savedAsConflictCopy(copy)
                    }
                }
                try Data(text.utf8).write(to: url)
                return .saved
            }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    /// `Note (conflict 2026-10-18 093012).md`, next to the original.
    public static func conflictCopyURL(for url: URL, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(name) (conflict \(formatter.string(from: date))).md")
    }
}
