import Foundation

public enum NoteReader {
    public enum ReadError: Error, LocalizedError {
        /// The note is in iCloud but not on this device yet. A download has been requested.
        case notDownloaded
        /// The file isn't valid UTF-8, so editing it couldn't keep its bytes exactly.
        case notLossless

        public var errorDescription: String? {
            switch self {
            case .notDownloaded: "This note is still downloading from iCloud."
            case .notLossless: "This file isn't plain UTF-8 text, so Imprint won't edit it. Open it in Obsidian instead."
            }
        }
    }

    /// Reads a note's text. If iCloud has evicted it, starts a download and throws
    /// `ReadError.notDownloaded`; scan again once the download finishes.
    public static func read(_ note: Note) throws -> String {
        guard note.isDownloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: note.url)
            throw ReadError.notDownloaded
        }
        return try read(contentsOf: note.url)
    }

    /// Reads a file's text, refusing anything that wouldn't write back byte-for-byte.
    public static func read(contentsOf url: URL) throws -> String {
        let data = try coordinated(url) { try Data(contentsOf: $0) }
        let text = String(decoding: data, as: UTF8.self)
        // Decoding replaces invalid bytes, so a mismatch means the file isn't valid UTF-8.
        guard Data(text.utf8) == data else { throw ReadError.notLossless }
        return text
    }

    static func coordinated<T>(_ url: URL, _ read: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try read(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }
}
