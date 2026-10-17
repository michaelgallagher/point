import Foundation

public enum NoteReader {
    public enum ReadError: Error {
        /// The note is in iCloud but not on this device yet. A download has been requested.
        case notDownloaded
    }

    /// Reads a note's text. If iCloud has evicted it, starts a download and throws
    /// `ReadError.notDownloaded`; scan again once the download finishes.
    public static func read(_ note: Note) throws -> String {
        guard note.isDownloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: note.url)
            throw ReadError.notDownloaded
        }
        let data = try Data(contentsOf: note.url)
        // Obsidian writes UTF-8. Decode leniently so one bad byte doesn't hide a note.
        return String(decoding: data, as: UTF8.self)
    }
}
