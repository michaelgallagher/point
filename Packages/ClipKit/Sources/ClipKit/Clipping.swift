import Foundation
import VaultKit

/// What both apps do with a clip request, apart from making the note and saying how it went:
/// which kind clips are, reading the page (or settling for its link), and how a page clipped
/// before is recognised.
public enum Clipping {
    /// The names a kind for clips may have.
    public static let kindNames = ["Media", "Clipping", "Clippings", "Clip", "Web clip", "Article"]
    /// Where clips go when the vault has no kind for them.
    public static let defaultFolder = "Clippings"
    /// Where a clip is filed once it's read.
    public static let readFolder = "Sources"
    /// The property saying when a clip was read.
    public static let readProperty = "read"

    /// Today, as `read` has it (`2026-11-13`).
    public static func today(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The note with `read` set to `date` (today), unless it has a read date already: added at
    /// the end of its properties, or filled in where the template left it empty, the rest of the
    /// file exactly as it was.
    public static func markingRead(_ text: String, on date: String = today()) -> String {
        let edit: (NSRange, String)
        if let frontmatter = Frontmatter.parse(text) {
            let existing = frontmatter.properties.first { $0.key.caseInsensitiveCompare(readProperty) == .orderedSame }
            if let existing, existing.values.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { return text }
            edit = frontmatter.edit(setting: existing?.key ?? readProperty, to: [date], isList: false)
        } else {
            edit = Frontmatter.edit(adding: readProperty, values: [date], isList: false)
        }
        return (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
    }

    /// The kind clipped pages are: Media, or the like, if the vault has one.
    public static func kind(in kinds: NoteKinds) -> NoteKinds.Kind? {
        for name in kindNames {
            if let kind = kinds.kinds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return kind }
        }
        return nil
    }

    /// The addresses a note clipped from this page may have as its `source`: as given, and
    /// without tracking parameters.
    public static func sources(of url: URL) -> [String] {
        var seen = Set<String>()
        return [url.absoluteString, Clip.cleaned(url).absoluteString].filter { seen.insert($0).inserted }
    }

    /// The page read, or if it can't be, a clip with only its address and title; `couldRead`
    /// says which. A page the browser sent is read as it was shown; Point fetches it only if
    /// none was sent, or no article could be found in it.
    @MainActor
    public static func read(_ request: ClipRequest) async -> (clip: Clip, couldRead: Bool) {
        var clip: Clip
        var couldRead = true
        let extractor = ClipExtractor()
        do {
            if let html = request.html, let sent = try? await extractor.clip(html: html, url: request.url), !sent.markdown.isEmpty {
                clip = sent
            } else {
                clip = try await extractor.clip(request.url)
            }
            if clip.markdown.isEmpty { couldRead = false }
        } catch {
            couldRead = false
            clip = Clip(url: Clip.cleaned(request.url), title: request.title ?? request.url.host ?? request.url.absoluteString,
                        format: Clip.format(of: request.url))
        }
        if let title = request.title, clip.title.isEmpty || clip.title == clip.url.host { clip.title = title }
        return (clip, couldRead)
    }

    /// The note's title and text: the kind's first template filled in, or the clip's
    /// properties alone.
    public static func note(for clip: Clip, request: ClipRequest, kind: NoteKinds.Kind?, template: String?,
                            typeProperty: String, settings: ObsidianSettings) -> (title: String, text: String) {
        let title = NoteFiles.sanitizedTitle(clip.title)
        let text = ClipNote.text(for: clip, selection: request.selection,
                                 template: template.map { Templates.render($0, title: title, settings: settings) },
                                 typeProperty: typeProperty, kind: kind?.name)
        return (title, text)
    }
}
