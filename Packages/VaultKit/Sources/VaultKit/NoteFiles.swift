import Foundation

/// Creating, renaming and removing note files.
public enum NoteFiles {
    public enum FileError: Error, LocalizedError, Equatable {
        case emptyTitle
        case titleTaken(String)

        public var errorDescription: String? {
            switch self {
            case .emptyTitle: "A note needs a name."
            case .titleTaken(let title): "There's already a note called “\(title)”."
            }
        }
    }

    /// Makes a title safe as an Obsidian filename. Obsidian disallows `* " \ / < > : | ?` in
    /// filenames, and `# ^ [ ] |` would break links to the note.
    public static func sanitizedTitle(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "*\"\\/<>:|?#^[]")
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = String(collapsed.prefix(120)).trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") { result.removeFirst() } // A leading dot would hide the file.
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// The name for a note that doesn't have a title yet, such as `2026-10-18 0942`.
    public static func untitledName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: date)
    }

    /// `folder/title.md`, or `title 2.md` and so on if that name is taken.
    /// Names are compared without regard to case, as on the Mac's file system.
    public static func availableURL(for title: String, in folder: URL, excluding existing: URL? = nil) -> URL {
        var candidate = folder.appendingPathComponent("\(title).md")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path), candidate.standardizedFileURL != existing?.standardizedFileURL {
            candidate = folder.appendingPathComponent("\(title) \(number).md")
            number += 1
        }
        return candidate
    }

    /// Creates a note and returns its URL.
    public static func create(title: String, text: String = "", in folder: URL) throws -> URL {
        let title = sanitizedTitle(title)
        guard !title.isEmpty else { throw FileError.emptyTitle }
        let url = availableURL(for: title, in: folder)
        try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    /// Renames a note in place and returns its new URL. Links to it are updated separately.
    public static func rename(_ url: URL, to title: String) throws -> URL {
        let title = sanitizedTitle(title)
        guard !title.isEmpty else { throw FileError.emptyTitle }
        let destination = url.deletingLastPathComponent().appendingPathComponent("\(title).md")
        if destination.standardizedFileURL == url.standardizedFileURL { return url }
        // A change of case alone is allowed; any other existing file is not overwritten.
        let isCaseChange = destination.path.lowercased() == url.path.lowercased()
        if !isCaseChange, FileManager.default.fileExists(atPath: destination.path) {
            throw FileError.titleTaken(title)
        }
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
        return destination
    }

    /// Moves a note into another folder (keeping its name, or adding a number if it's taken)
    /// and returns its new URL. Links to it are updated separately.
    public static func move(_ url: URL, toFolder folder: URL) throws -> URL {
        let destination = availableURL(for: url.deletingPathExtension().lastPathComponent, in: folder)
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do {
                try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
        return destination
    }

    /// Moves a note to the trash Obsidian is set to use.
    public static func trash(_ url: URL, vault root: URL, option: ObsidianSettings.TrashOption) throws {
        switch option {
        case .local:
            let trash = root.appendingPathComponent(".trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let title = url.deletingPathExtension().lastPathComponent
            try FileManager.default.moveItem(at: url, to: availableURL(for: title, in: trash))
        case .system, .none:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}
