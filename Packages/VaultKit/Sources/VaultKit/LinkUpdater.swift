import Foundation
import MarkdownKit

/// Rewrites links across the vault after a note is renamed, as Obsidian does.
public enum LinkUpdater {
    public struct Result: Sendable, Equatable {
        public var updatedNotes: [String] = []
        /// Notes that changed while being updated; they were left alone.
        public var skippedNotes: [String] = []
    }

    /// Rewrites every link to `renamed` (identified by its old ID) so it points at `newTitle`.
    /// `notes` is the vault as it was before the rename.
    public static func updateLinks(to renamed: Note, newTitle: String, notes: [Note]) -> Result {
        let resolver = LinkResolver(notes: notes)
        var result = Result()
        let needle = renamed.title.lowercased()
        let encodedNeedle = (renamed.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? renamed.title).lowercased()
        for note in notes {
            // The renamed note itself is under its new name now (its links to itself change too).
            let url = note.id == renamed.id ? renamed.url.deletingLastPathComponent().appendingPathComponent(newTitle + ".md") : note.url
            guard let text = try? NoteReader.read(contentsOf: url) else { continue }
            let lowered = text.lowercased()
            guard lowered.contains(needle) || lowered.contains(encodedNeedle) else { continue }
            guard let rewritten = rewrite(text, in: note.id, renamed: renamed, newTitle: newTitle, resolver: resolver) else { continue }
            switch try? NoteWriter.write(rewritten, to: url, expecting: text, ifChanged: .report) {
            case .saved?: result.updatedNotes.append(note.id)
            default: result.skippedNotes.append(note.id)
            }
        }
        return result
    }

    /// The wikilinks and embeds in a note: where each one's target starts (after `[[`), and the
    /// target (with any `#heading`, without `|alias`). Those in the frontmatter too, which the
    /// Markdown parser leaves alone, written as Obsidian writes links in properties
    /// (`people: "[[Ann]]"`): renames missed them all.
    static func wikiLinks(in text: String) -> [(location: Int, target: String)] {
        var links: [(location: Int, target: String)] = []
        let tokens = MarkdownParser.parse(text)
        for token in tokens {
            switch token.kind {
            case .wikiLink(let target), .embed(let target):
                links.append((NSMaxRange(token.syntax[0]), target))
            default:
                continue
            }
        }
        if let frontmatter = Frontmatter.parse(text) {
            let ns = text as NSString
            for match in frontmatterLink.matches(in: text, range: frontmatter.range) {
                let target = match.range(at: 1)
                links.append((target.location, ns.substring(with: target)))
            }
        }
        return links
    }

    private static let frontmatterLink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n|]+)"#)

    /// `text` with its links to `renamed` pointing at `newTitle`, or nil if it has none.
    public static func rewrite(_ text: String, in sourceID: String, renamed: Note, newTitle: String, resolver: LinkResolver) -> String? {
        let ns = text as NSString
        var replacements: [(NSRange, String)] = []
        for link in wikiLinks(in: text) {
            let target = link.target
            guard resolver.resolve(wikiTarget: target, from: sourceID)?.id == renamed.id else { continue }
            // The target sits between `[[` (or `![[`) and `|`, `]]`; replace just its name part.
            let targetRange = NSRange(location: link.location, length: (target as NSString).length)
            let subpath = LinkResolver.stripSubpath(target)
            var name = subpath
            let hadExtension = name.lowercased().hasSuffix(".md")
            if hadExtension { name = String(name.dropLast(3)) }
            let folder = (name as NSString).deletingLastPathComponent
            var replacement = folder.isEmpty ? newTitle : folder + "/" + newTitle
            if hadExtension { replacement += ".md" }
            let nameRange = NSRange(location: targetRange.location, length: (subpath as NSString).length)
            replacements.append((nameRange, replacement))
        }
        for token in MarkdownParser.parse(text) {
            switch token.kind {
            case .link(let destination), .image(let destination):
                guard resolver.resolve(markdownDestination: destination, from: sourceID)?.id == renamed.id else { continue }
                let destinationRange = ns.range(of: destination, options: [], range: token.range)
                guard destinationRange.location != NSNotFound else { continue }
                let isBracketed = destinationRange.location > 0 && ns.character(at: destinationRange.location - 1) == 60 // "<"
                replacements.append((destinationRange, renamedDestination(destination, newTitle: newTitle, bracketed: isBracketed)))
            default:
                continue
            }
        }
        guard !replacements.isEmpty else { return nil }
        let result = NSMutableString(string: text)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    /// `folder/Old%20Name.md#part` becomes `folder/New%20Name.md#part`. Spaces are encoded as
    /// `%20` unless the destination is in angle brackets (`<…>`), which allow plain spaces.
    static func renamedDestination(_ destination: String, newTitle: String, bracketed: Bool = false) -> String {
        let hash = destination.firstIndex(of: "#")
        let path = hash.map { String(destination[..<$0]) } ?? destination
        let fragment = hash.map { String(destination[$0...]) } ?? ""
        let folder = (path as NSString).deletingLastPathComponent
        let encoded = bracketed ? newTitle : (newTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newTitle)
        return (folder.isEmpty ? "" : folder + "/") + encoded + ".md" + fragment
    }

    // MARK: Moving notes

    /// Updates links after `moved` (identified by its old ID) moves to `newID`: links in other
    /// notes that spell out a path, and the moved note's own relative links. `notes` is the
    /// vault as it was before the move; `root` is the vault folder.
    public static func updateLinks(afterMoving moved: Note, to newID: String, notes: [Note], root: URL) -> Result {
        let resolver = LinkResolver(notes: notes)
        var result = Result()
        let needle = moved.title.lowercased()
        let encodedNeedle = (moved.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? moved.title).lowercased()
        for note in notes where note.id != moved.id {
            guard let text = try? NoteReader.read(contentsOf: note.url) else { continue }
            let lowered = text.lowercased()
            guard lowered.contains(needle) || lowered.contains(encodedNeedle),
                  let rewritten = rewrite(text, in: note.id, moved: moved, newID: newID, resolver: resolver) else { continue }
            switch try? NoteWriter.write(rewritten, to: note.url, expecting: text, ifChanged: .report) {
            case .saved?: result.updatedNotes.append(note.id)
            default: result.skippedNotes.append(note.id)
            }
        }
        let movedURL = root.appendingPathComponent(newID)
        if let text = try? NoteReader.read(contentsOf: movedURL),
           let rewritten = rewriteOwnLinks(text, from: moved.id, to: newID, root: root) {
            switch try? NoteWriter.write(rewritten, to: movedURL, expecting: text, ifChanged: .report) {
            case .saved?: result.updatedNotes.append(newID)
            default: result.skippedNotes.append(newID)
            }
        }
        return result
    }

    /// `text` (from the note `sourceID`) with links to `moved` pointing at its new place, or nil
    /// if no link needed changing. Wikilinks by name alone still work, so they're left alone.
    public static func rewrite(_ text: String, in sourceID: String, moved: Note, newID: String, resolver: LinkResolver) -> String? {
        let ns = text as NSString
        let newPath = LinkResolver.pathWithoutExtension(newID)
        var replacements: [(NSRange, String)] = []
        for link in wikiLinks(in: text) {
            let name = LinkResolver.stripSubpath(link.target)
            guard name.contains("/"), resolver.resolve(wikiTarget: link.target, from: sourceID)?.id == moved.id else { continue }
            let hadExtension = name.lowercased().hasSuffix(".md")
            let replacement = (name.hasPrefix("/") ? "/" : "") + newPath + (hadExtension ? ".md" : "")
            replacements.append((NSRange(location: link.location, length: (name as NSString).length), replacement))
        }
        for token in MarkdownParser.parse(text) {
            switch token.kind {
            case .link(let destination), .image(let destination):
                guard resolver.resolve(markdownDestination: destination, from: sourceID)?.id == moved.id else { continue }
                let range = ns.range(of: destination, options: [], range: token.range)
                guard range.location != NSNotFound else { continue }
                let bracketed = range.location > 0 && ns.character(at: range.location - 1) == 60
                let decoded = destination.removingPercentEncoding ?? destination
                let fragment = decoded.firstIndex(of: "#").map { String(decoded[$0...]) } ?? ""
                // Keep the link's style: relative to the linking note, or from the vault root.
                let sourceFolder = LinkResolver.folder(of: sourceID)
                let relativeTarget = LinkResolver.normalise(sourceFolder.isEmpty ? LinkResolver.stripSubpath(decoded) : sourceFolder + "/" + LinkResolver.stripSubpath(decoded))
                let wasRelative = relativeTarget.lowercased() == moved.id.lowercased()
                let path = wasRelative ? relativePath(from: sourceFolder, to: newID) : newID
                replacements.append((range, encode(path, bracketed: bracketed) + fragment))
            default:
                continue
            }
        }
        return apply(replacements, to: text)
    }

    /// The moved note's own relative links (to images, or other files by path), recalculated
    /// from its new folder. Only links that pointed at a file that exists are changed.
    public static func rewriteOwnLinks(_ text: String, from oldID: String, to newID: String, root: URL) -> String? {
        let ns = text as NSString
        let oldFolder = LinkResolver.folder(of: oldID), newFolder = LinkResolver.folder(of: newID)
        guard oldFolder != newFolder else { return nil }
        var replacements: [(NSRange, String)] = []
        for token in MarkdownParser.parse(text) {
            let destination: String
            switch token.kind {
            case .link(let link), .image(let link): destination = link
            default: continue
            }
            let decoded = destination.removingPercentEncoding ?? destination
            // Web addresses, vault-root paths and in-note anchors don't depend on the folder.
            guard !decoded.contains(":"), !decoded.hasPrefix("/"), !decoded.hasPrefix("#") else { continue }
            let fragmentIndex = decoded.firstIndex(of: "#")
            let path = fragmentIndex.map { String(decoded[..<$0]) } ?? decoded
            let fragment = fragmentIndex.map { String(decoded[$0...]) } ?? ""
            let target = LinkResolver.normalise(oldFolder.isEmpty ? path : oldFolder + "/" + path)
            // Leave links that didn't point at a real file this way (Obsidian may resolve them by name).
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(target).path) else { continue }
            let range = ns.range(of: destination, options: [], range: token.range)
            guard range.location != NSNotFound else { continue }
            let bracketed = range.location > 0 && ns.character(at: range.location - 1) == 60 // "<"
            replacements.append((range, encode(relativePath(from: newFolder, to: target), bracketed: bracketed) + fragment))
        }
        return apply(replacements, to: text)
    }

    /// The path to `target` (from the vault root) as seen from `folder`, using `../` as needed.
    public static func relativePath(from folder: String, to target: String) -> String {
        let from = folder.split(separator: "/"), to = target.split(separator: "/")
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        return (Array(repeating: "..", count: from.count - common) + to[common...].map(String.init)).joined(separator: "/")
    }

    private static func encode(_ path: String, bracketed: Bool) -> String {
        bracketed ? path : (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }

    private static func apply(_ replacements: [(NSRange, String)], to text: String) -> String? {
        guard !replacements.isEmpty else { return nil }
        let result = NSMutableString(string: text)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String == text ? nil : result as String
    }
}
