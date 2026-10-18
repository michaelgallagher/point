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
}

/// Following links, and completing `[[wikilinks]]` from note titles.
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

    /// Opens the link under a plain click. Returns false to let the click place the cursor.
    func openLink(for event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              event.modifierFlags.intersection([.option, .shift, .command, .control]).isEmpty,
              let index = characterIndex(exactlyAt: convert(event.locationInWindow, from: nil)),
              let target = link(at: index), let onOpenLink else { return false }
        onOpenLink(target)
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

    public override var rangeForUserCompletion: NSRange {
        wikiLinkPartialRange() ?? super.rangeForUserCompletion
    }

    public override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard wikiLinkPartialRange() != nil, let completeNoteTitle else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        index.pointee = 0
        return completeNoteTitle((string as NSString).substring(with: charRange))
    }

    public override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        guard flag, wikiLinkPartialRange() != nil, movement != NSCancelTextMovement, movement != NSOtherTextMovement else {
            return super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        }
        // Finish the link, unless its closing brackets are already there.
        let text = string as NSString
        let after = NSMaxRange(charRange)
        let hasClose = after + 2 <= text.length && text.substring(with: NSRange(location: after, length: 2)) == "]]"
        super.insertCompletion(hasClose ? word : word + "]]", forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }

    /// Shows note-title suggestions while a wikilink target is being typed.
    func suggestCompletionsIfInWikiLink() {
        guard completeNoteTitle != nil, wikiLinkPartialRange() != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wikiLinkPartialRange() != nil else { return }
            self.complete(nil)
        }
    }
}
#endif
