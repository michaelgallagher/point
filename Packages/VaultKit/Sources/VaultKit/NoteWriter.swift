import Foundation

public enum NoteWriter {
    public enum Outcome: Equatable, Sendable {
        case saved
        /// The file had changed on disk since it was read, so the text went to a copy instead.
        case savedAsConflictCopy(URL)
    }

    /// Writes `text` to `url`, unless the file has changed since it held `expected`.
    ///
    /// The file is rewritten in place, as Obsidian does, so it keeps its creation date. If
    /// someone else (Obsidian, another device) changed it in the meantime, their version is
    /// left alone and `text` is saved next to it as a conflict copy, so nothing is lost.
    public static func write(_ text: String, to url: URL, expecting expected: String) throws -> Outcome {
        var coordinationError: NSError?
        var result: Result<Outcome, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result {
                let onDisk = try? Data(contentsOf: url)
                if let onDisk, onDisk != Data(expected.utf8) {
                    let copy = conflictCopyURL(for: url)
                    try Data(text.utf8).write(to: copy)
                    return .savedAsConflictCopy(copy)
                }
                try Data(text.utf8).write(to: url)
                return .saved
            }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    static func conflictCopyURL(for url: URL, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(name) (conflict \(formatter.string(from: date))).md")
    }
}
