import Darwin
import Foundation

/// `VaultScanner.scanAll`, reading the folders directly (`readdir` and `lstat`) rather than
/// through `FileManager`. In iCloud Drive on the iPhone, asking `FileManager` for each file's
/// details went through iCloud: 7 seconds for 3,500 notes, 12 with each one's download status.
/// A file whose text iCloud hasn't brought is marked dataless by the system, which `lstat`
/// shows without asking iCloud anything.
extension VaultScanner {
    /// The flag the system sets on a file whose contents aren't on the device (`SF_DATALESS`).
    static let datalessFlag: UInt32 = 0x4000_0000

    public static func quickScan(_ root: URL) throws -> Scan {
        let root = realRoot(root)
        guard let top = opendir(root.path) else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root]) }
        var notes: [Note] = []
        var folders: [String] = []
        var images: [VaultImage] = []

        func walk(_ dir: UnsafeMutablePointer<DIR>, path: String, url: URL, relative: [String]) {
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                guard name != ".", name != ".." else { continue }
                let filePath = path + "/" + name
                guard var info = fileInfo(filePath) else { continue }
                if info.st_mode & S_IFMT == S_IFLNK {
                    // As the enumerator did: a link to a file is that file; a link to a folder isn't followed.
                    guard stat(filePath, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
                }
                if info.st_mode & S_IFMT == S_IFDIR {
                    guard !name.hasPrefix(".") else { continue } // .obsidian, .trash, .git
                    let inner = relative + [name]
                    folders.append(inner.joined(separator: "/"))
                    if let sub = opendir(filePath) {
                        walk(sub, path: filePath, url: url.appendingPathComponent(name, isDirectory: true), relative: inner)
                    }
                    continue
                }
                guard info.st_mode & S_IFMT == S_IFREG else { continue }
                let isLocal = info.st_flags & datalessFlag == 0
                if let (fileName, isDownloaded) = noteFileName(name) {
                    let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
                    notes.append(note(id: (relative + [fileName]).joined(separator: "/"), url: fileURL, info: info,
                                      isDownloaded: isDownloaded && isLocal))
                } else if let (imageName, isDownloaded) = imageFileName(name) {
                    images.append(VaultImage(path: (relative + [imageName]).joined(separator: "/"),
                                             url: url.appendingPathComponent(imageName, isDirectory: false),
                                             isDownloaded: isDownloaded && isLocal))
                }
            }
        }
        walk(top, path: root.path, url: root, relative: [])
        return Scan(notes: notes, folders: folders, images: images)
    }

    /// What changed files make of the notes: each read again (or dropped, if it's gone), the
    /// rest as they were. Nil when a change needs the whole vault read again: a folder, or an
    /// image. Files in folders whose names start with a dot, and other files, change nothing.
    public static func rescan(_ urls: Set<URL>, in root: URL, notes: [Note]) -> [Note]? {
        // Compared as Foundation spells paths (/var, not /private/var), both sides alike; notes
        // made with the root as `quickScan` spells it, as the rest are.
        let real = realRoot(root)
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path + "/"
        var changed: [Note.ID: Note?] = [:]
        for url in urls {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else {
                if path == root.path { return nil }
                continue
            }
            let parts = path.dropFirst(prefix.count).split(separator: "/").map(String.init)
            guard let name = parts.last, !parts.dropLast().contains(where: { $0.hasPrefix(".") }) else { continue }
            let info = fileInfo(path)
            if info.map({ $0.st_mode & S_IFMT == S_IFDIR }) ?? !name.contains(".") {
                // A folder (or what was one): its notes, and the list of folders, changed.
                if name.hasPrefix(".") { continue }
                return nil
            }
            if imageFileName(name) != nil { return nil }
            guard let (fileName, _) = noteFileName(name) else { continue }
            let id = (parts.dropLast() + [fileName]).joined(separator: "/")
            let fileURL = (parts.dropLast() + [fileName]).reduce(real) { $0.appendingPathComponent($1, isDirectory: false) }
            changed[id] = note(id: id, at: fileURL)
        }
        guard !changed.isEmpty else { return notes }
        var result: [Note] = []
        result.reserveCapacity(notes.count + changed.count)
        var placed = Set<Note.ID>()
        for note in notes {
            guard let update = changed[note.id] else {
                result.append(note)
                continue
            }
            placed.insert(note.id)
            if let update { result.append(update) }
        }
        for case let (id, note?) in changed where !placed.contains(id) { result.append(note) }
        return result
    }

    /// The note at `url` now, or nil if it isn't there (as itself, or as an iCloud placeholder).
    static func note(id: Note.ID, at url: URL) -> Note? {
        if let info = fileInfo(url.path), info.st_mode & S_IFMT == S_IFREG {
            return note(id: id, url: url, info: info, isDownloaded: info.st_flags & datalessFlag == 0)
        }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard let info = fileInfo(placeholder.path) else { return nil }
        return note(id: id, url: url, info: info, isDownloaded: false)
    }

    /// The root as the file system has it (`/private/var/…`), as `FileManager`'s enumerator
    /// spelled the notes' URLs.
    private static func realRoot(_ root: URL) -> URL {
        guard let resolved = realpath(root.path, nil) else { return root.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private static func fileInfo(_ path: String) -> stat? {
        var info = stat()
        return lstat(path, &info) == 0 ? info : nil
    }

    private static func note(id: Note.ID, url: URL, info: stat, isDownloaded: Bool) -> Note {
        let modified = date(info.st_mtimespec)
        let created = info.st_birthtimespec.tv_sec > 0 ? date(info.st_birthtimespec) : modified
        return Note(id: id, url: url,
                    title: NoteNames.shownTitle(name: String(url.lastPathComponent.dropLast(3)), url: url, isDownloaded: isDownloaded),
                    modified: modified, created: created, isDownloaded: isDownloaded)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
