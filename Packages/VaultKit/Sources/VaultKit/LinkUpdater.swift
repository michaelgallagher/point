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
            guard let text = try? NoteReader.read(contentsOf: note.url) else { continue }
            let lowered = text.lowercased()
            guard lowered.contains(needle) || lowered.contains(encodedNeedle) else { continue }
            guard let rewritten = rewrite(text, in: note.id, renamed: renamed, newTitle: newTitle, resolver: resolver) else { continue }
            switch try? NoteWriter.write(rewritten, to: note.url, expecting: text, ifChanged: .report) {
            case .saved?: result.updatedNotes.append(note.id)
            default: result.skippedNotes.append(note.id)
            }
        }
        return result
    }

    /// `text` with its links to `renamed` pointing at `newTitle`, or nil if it has none.
    public static func rewrite(_ text: String, in sourceID: String, renamed: Note, newTitle: String, resolver: LinkResolver) -> String? {
        let ns = text as NSString
        var replacements: [(NSRange, String)] = []
        for token in MarkdownParser.parse(text) {
            switch token.kind {
            case .wikiLink(let target), .embed(let target):
                guard resolver.resolve(wikiTarget: target, from: sourceID)?.id == renamed.id else { continue }
                // The target sits between `[[` (or `![[`) and `|`, `]]`; replace just its name part.
                let open = token.syntax[0]
                let targetRange = NSRange(location: NSMaxRange(open), length: (target as NSString).length)
                let subpath = LinkResolver.stripSubpath(target)
                var name = subpath
                let hadExtension = name.lowercased().hasSuffix(".md")
                if hadExtension { name = String(name.dropLast(3)) }
                let folder = (name as NSString).deletingLastPathComponent
                var replacement = folder.isEmpty ? newTitle : folder + "/" + newTitle
                if hadExtension { replacement += ".md" }
                let nameRange = NSRange(location: targetRange.location, length: (subpath as NSString).length)
                replacements.append((nameRange, replacement))
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
}
