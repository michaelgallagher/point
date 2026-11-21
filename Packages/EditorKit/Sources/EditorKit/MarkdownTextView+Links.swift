#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Where a clicked link points.
public enum LinkTarget: Equatable, Sendable {
    /// A wikilink or embed target, such as `Note#Heading`.
    case note(String)
    /// A Markdown link destination that isn't a web address, such as `Other%20Note.md`.
    case file(String)
    case web(URL)
    case tag(String)

    /// Whether a link opens without asking: web pages and email. Any other kind of address
    /// (`zoommtg:`, `shortcuts:`, an app's own) hands it to whichever app claims it, so a
    /// note from somewhere else could start something with a click: those ask first.
    public static func opensWithoutAsking(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}

/// Following links, and finding the `[[wikilink]]` or `@mention` being typed (the popup offers
/// what it could be: see +Popup).
extension MarkdownTextView {
    // MARK: Following links

    /// The link at a character index, if any.
    public func link(at index: Int) -> LinkTarget? {
        let text = string as NSString
        for token in tokens where NSLocationInRange(index, token.range) {
            switch token.kind {
            case .wikiLink(let target), .embed(let target):
                return .note(target)
            case .link(let destination), .image(let destination):
                if let url = URL(string: destination), let scheme = url.scheme, scheme != "file" { return .web(url) }
                return .file(destination)
            case .url:
                return URL(string: text.substring(with: token.range)).map(LinkTarget.web)
            case .tag(let tag):
                return .tag(tag)
            default:
                continue
            }
        }
        return nil
    }

    /// The character under a point in the view, only if the point is on its glyph
    /// (not in the empty space past the end of a line).
    func characterIndex(exactlyAt point: NSPoint) -> Int? {
        guard let layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let bounds = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard bounds.contains(local) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    /// Opens the link under a plain click (in a new tab with ⌘, beside this note with ⌥⌘).
    /// Returns false to let the click place the cursor, as ⌥-click does.
    func openLink(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.option, .shift, .command, .control])
        guard event.clickCount == 1, modifiers.isEmpty || modifiers == [.command] || modifiers == [.option, .command],
              let index = characterIndex(exactlyAt: convert(event.locationInWindow, from: nil)),
              let target = link(at: index) else { return false }
        if modifiers == [.option, .command] {
            guard let onOpenLinkToSide else { return false }
            onOpenLinkToSide(target)
        } else if modifiers == [.command] {
            guard let onOpenLinkInNewTab else { return false }
            onOpenLinkInNewTab(target)
        } else {
            guard let onOpenLink else { return false }
            onOpenLink(target)
        }
        return true
    }

    // MARK: Completing wikilinks

    /// The partial target being typed inside an unfinished `[[`, ending at the cursor.
    func wikiLinkPartialRange() -> NSRange? {
        let text = string as NSString
        let cursor = selectedRange()
        guard cursor.length == 0 else { return nil }
        let line = text.lineRange(for: NSRange(location: cursor.location, length: 0))
        var index = cursor.location
        while index - 2 >= line.location {
            let c = text.character(at: index - 1)
            if c == 93 || c == 124 { return nil } // "]" or "|": not in a target any more.
            if c == 91, text.character(at: index - 2) == 91 { // "[["
                return NSRange(location: index, length: cursor.location - index)
            }
            index -= 1
        }
        return nil
    }

    // MARK: Mentioning people

    /// The name being typed after an `@`, ending at the cursor: `@Sa` gives the range of `Sa`.
    /// The `@` starts a word (not `me@example.com`), and the name so far has no spaces. Not in
    /// code, a link or a web address.
    func mentionPartialRange() -> NSRange? {
        guard completePerson != nil else { return nil }
        let text = string as NSString
        let cursor = selectedRange()
        guard cursor.length == 0 else { return nil }
        let line = text.lineRange(for: NSRange(location: cursor.location, length: 0))
        var index = cursor.location
        while index > line.location {
            let c = text.character(at: index - 1)
            if c == 64 { // "@"
                if index - 1 > line.location, let before = Unicode.Scalar(text.character(at: index - 2)),
                   !CharacterSet.whitespaces.contains(before), !"([{\"'".unicodeScalars.contains(before) { return nil }
                let range = NSRange(location: index, length: cursor.location - index)
                guard !tokens.contains(where: { token in
                    switch token.kind {
                    case .code, .codeBlock, .wikiLink, .embed, .link, .url, .frontmatter: NSLocationInRange(index - 1, token.range)
                    default: false
                    }
                }) else { return nil }
                return range
            }
            guard let scalar = Unicode.Scalar(c), CharacterSet.alphanumerics.contains(scalar) || c == 45 || c == 46 || c == 39 else { return nil }
            index -= 1
        }
        return nil
    }

}
#endif
