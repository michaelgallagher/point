import Foundation

/// Works out which note a link points to, following Obsidian's rules.
public struct LinkResolver: Sendable {
    private let notesByTitle: [String: [Note]]
    private let notesByPath: [String: Note]

    public init(notes: [Note]) {
        notesByTitle = Dictionary(grouping: notes) { $0.title.lowercased() }
        notesByPath = Dictionary(notes.map { (Self.pathWithoutExtension($0.id).lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The note a wikilink target (`Name`, `Name#Heading`, `folder/Name`, `Name.md`) points to,
    /// as seen from the note `sourceID`.
    public func resolve(wikiTarget target: String, from sourceID: String) -> Note? {
        var name = Self.stripSubpath(target).trimmingCharacters(in: .whitespaces)
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        guard !name.isEmpty else { return nil }
        if name.contains("/") {
            let path = name.hasPrefix("/") ? String(name.dropFirst()) : name
            if let exact = notesByPath[path.lowercased()] { return exact }
            // A partial path matches any note whose path ends with it.
            return notesByPath.first { $0.key.hasSuffix("/" + path.lowercased()) }?.value
        }
        guard let candidates = notesByTitle[name.lowercased()], !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        // Several notes share the name: prefer one in the same folder, then the shortest path.
        let folder = Self.folder(of: sourceID)
        return candidates.first { Self.folder(of: $0.id) == folder }
            ?? candidates.min { $0.id.count < $1.id.count }
    }

    /// The note a Markdown link destination (`My%20Note.md`, `<folder/My Note.md>`) points to.
    public func resolve(markdownDestination destination: String, from sourceID: String) -> Note? {
        let decoded = (destination.removingPercentEncoding ?? destination).trimmingCharacters(in: .whitespaces)
        let path = Self.stripSubpath(decoded)
        guard path.lowercased().hasSuffix(".md"), !path.contains("://") else { return nil }
        let withoutExtension = String(path.dropLast(3))
        // Relative to the linking note, then from the vault root, then by name.
        let relative = Self.normalise(Self.folder(of: sourceID).isEmpty ? withoutExtension : Self.folder(of: sourceID) + "/" + withoutExtension)
        if let note = notesByPath[relative.lowercased()] { return note }
        if let note = notesByPath[Self.normalise(withoutExtension).lowercased()] { return note }
        return resolve(wikiTarget: (withoutExtension as NSString).lastPathComponent, from: sourceID)
    }

    /// Whether a title is shared by more than one note, so links need a path to be clear.
    public func isAmbiguous(title: String) -> Bool {
        (notesByTitle[title.lowercased()]?.count ?? 0) > 1
    }

    // MARK: Helpers

    /// Drops a `#Heading` or `#^block` from a link target.
    static func stripSubpath(_ target: String) -> String {
        target.firstIndex(of: "#").map { String(target[..<$0]) } ?? target
    }

    static func pathWithoutExtension(_ id: String) -> String {
        id.lowercased().hasSuffix(".md") ? String(id.dropLast(3)) : id
    }

    static func folder(of id: String) -> String {
        id.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Resolves `.` and `..` in a relative path.
    static func normalise(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." || part.isEmpty { continue }
            if part == "..", !parts.isEmpty { parts.removeLast() } else { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }
}
