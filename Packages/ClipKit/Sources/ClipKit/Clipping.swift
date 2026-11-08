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
    /// says which.
    @MainActor
    public static func read(_ request: ClipRequest) async -> (clip: Clip, couldRead: Bool) {
        var clip: Clip
        var couldRead = true
        do {
            clip = try await ClipExtractor().clip(request.url)
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
