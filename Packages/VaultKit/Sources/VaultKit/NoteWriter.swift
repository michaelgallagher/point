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

    /// Why nothing was written.
    public enum WriteError: LocalizedError, Equatable {
        /// The note's file is gone (deleted or moved by another app, say). It isn't made
        /// again unasked: `recreate` does that.
        case missing
        /// The note's file couldn't be read, so whether it changed can't be told.
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .missing: "The note’s file is no longer there."
            case .unreadable(let reason): "The note’s file couldn’t be read to check it hadn’t changed (\(reason))."
            }
        }
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
                // Only written over what's known to be there: a file that's gone isn't made
                // again, and one that can't be read can't be checked.
                let onDisk: Data
                do {
                    onDisk = try Data(contentsOf: url)
                } catch {
                    if !FileManager.default.fileExists(atPath: url.path) { throw WriteError.missing }
                    throw WriteError.unreadable(error.localizedDescription)
                }
                if onDisk != Data(expected.utf8) {
                    switch policy {
                    case .report:
                        return .changedOnDisk(String(decoding: onDisk, as: UTF8.self))
                    case .saveCopy:
                        return .savedAsConflictCopy(try writeConflictCopy(text, beside: url))
                    }
                }
                try Data(text.utf8).write(to: url)
                return .saved
            }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    /// Writes a note whose file has gone back where it was, asked for: never over a file
    /// that's since appeared there.
    public static func recreate(_ text: String, at url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            do { try Data(text.utf8).write(to: url, options: .withoutOverwriting) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// Writes `text` to a new conflict copy beside `url` and returns where: named for the time,
    /// and numbered if that's taken (two saves in one second), never written over another.
    public static func writeConflictCopy(_ text: String, beside url: URL, date: Date = Date()) throws -> URL {
        let first = conflictCopyURL(for: url, date: date)
        let stem = first.deletingPathExtension().lastPathComponent
        for number in 1...1_000 {
            let copy = number == 1 ? first : first.deletingLastPathComponent().appendingPathComponent("\(stem) \(number).md")
            do {
                try Data(text.utf8).write(to: copy, options: .withoutOverwriting)
                return copy
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
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
