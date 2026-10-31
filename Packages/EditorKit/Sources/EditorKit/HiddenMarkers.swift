import Foundation
import MarkdownKit

/// The rules for the cursor and Delete around hidden Markdown, for the iPhone's editor: what the
/// Mac's `MarkdownTextView` does in place, without a text view. `HiddenMarkersTests` holds them
/// to the Mac's results. `storage` must be styled, so that what's hidden is marked.
struct HiddenMarkers {
    let storage: NSAttributedString
    let tokens: [MarkdownToken]
    let bodyStart: Int

    private var text: NSString { storage.string as NSString }

    // MARK: The cursor

    /// Where the cursor belongs when it's put at `location`, coming from `previous`: never
    /// inside hidden markers, so every move visibly moves it.
    func snapped(_ location: Int, from previous: Int) -> Int {
        var forward = location >= previous
        // Collapsed lines (code fences, frontmatter) are skipped entirely, however many.
        guard var line = collapsedLine(containing: location) else {
            return snappedToMarkers(location, from: previous, forward: forward)
        }
        while true {
            if !forward, line.location == 0 { forward = true } // Nothing visible above: go down.
            let next = forward ? min(NSMaxRange(text.lineRange(for: line)), text.length) : line.location - 1
            guard let following = collapsedLine(containing: next), following != line else {
                return snappedToMarkers(next, from: previous, forward: forward)
            }
            line = following
        }
    }

    /// Keeps the cursor out of hidden markers on an ordinary line.
    private func snappedToMarkers(_ location: Int, from previous: Int, forward: Bool) -> Int {
        // The hidden run the location is at the start of, inside, or at the end of.
        guard let run = hiddenRun(at: location) ?? hiddenRun(at: location - 1) else { return location }

        // Markers that start a line (`- `, `# `, `> `): the cursor belongs after them. Left
        // from there goes straight to the previous line rather than to an invisible stop.
        if run.location == lineStart(of: run.location) {
            if !forward, previous == NSMaxRange(run), location < previous, run.location > 0 {
                return run.location - 1
            }
            return NSMaxRange(run)
        }

        // The end of a wikilink's text, just before its hidden `]]`, is a stop of its own:
        // typing there goes on with the link. One more move steps out, after the `]]`.
        if location == run.location, wikiLinkEnding(at: location) != nil { return location }
        if location == NSMaxRange(run), wikiLinkEnding(at: run.location) != nil { return location }

        // Inline markers (`**`, `[[`): never stop inside them.
        if forward, isHidden(location) { return NSMaxRange(run) }
        if !forward, isHidden(location - 1) { return run.location }
        return location
    }

    /// The wikilink whose hidden `]]` starts at `location`, so that the cursor there is at the
    /// end of its text, inside it.
    private func wikiLinkEnding(at location: Int) -> MarkdownToken? {
        tokens.first { token in
            guard case .wikiLink = token.kind, let close = token.syntax.last else { return false }
            return close.location == location && close.length == 2
        }
    }

    // MARK: Delete

    /// What Delete does with the cursor at a place.
    enum Delete: Equatable {
        /// Nothing: it would join the text to something hidden.
        case nothing
        /// Takes off these markers, the formatting of a heading, list item or quote.
        case removeMarkers(NSRange)
        /// Deletes as usual, from this place.
        case delete(from: Int)
    }

    func delete(at location: Int) -> Delete {
        guard location > 0 else { return .delete(from: location) }
        // Not into the frontmatter's last line, which would join the body to it.
        if location == bodyStart { return .nothing }

        if let run = hiddenRun(at: location - 1) {
            if run.location == lineStart(of: run.location), collapsedLine(containing: run.location) == nil {
                return .removeMarkers(run)
            }
            // Otherwise the visible character before the markers goes, not a marker.
            return run.location == 0 ? .nothing : .delete(from: run.location)
        }
        // Never merge a line into a hidden code fence.
        if text.character(at: location - 1) == 10, location >= 2, collapsedLine(containing: location - 2) != nil {
            return .nothing
        }
        return .delete(from: location)
    }

    /// `selection`, with the hidden markers of any formatted span it covers all the visible text
    /// of, so deleting `bold` doesn't leave a stray `****` behind.
    func wholeTokens(in selection: NSRange) -> NSRange {
        var selection = selection
        guard selection.length > 0 else { return selection }
        for token in tokens where token.syntax.count >= 2 && !token.isBlock {
            let open = token.syntax[0], close = token.syntax[token.syntax.count - 1]
            let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
            if selection.location <= inner.location, NSMaxRange(selection) >= NSMaxRange(inner),
               NSIntersectionRange(selection, token.range).length > 0 || inner.length == 0 {
                selection = NSUnionRange(selection, token.range)
            }
        }
        return selection
    }

    // MARK: What's hidden

    func isHidden(_ range: NSRange) -> Bool {
        (range.location..<NSMaxRange(range)).allSatisfy(isHidden)
    }

    private func isHidden(_ index: Int) -> Bool {
        guard index >= 0, index < storage.length else { return false }
        return storage.attribute(.pointHidden, at: index, effectiveRange: nil) != nil
    }

    /// The hidden run containing the character at `index`, limited to its line.
    private func hiddenRun(at index: Int) -> NSRange? {
        guard isHidden(index) else { return nil }
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        var run = NSRange()
        _ = storage.attribute(.pointHidden, at: index, longestEffectiveRange: &run, in: line)
        return run
    }

    /// The line holding `index`, as a range without its line break, if it is collapsed: a code
    /// fence or frontmatter line, which the cursor never stops on.
    private func collapsedLine(containing index: Int) -> NSRange? {
        guard index >= 0, index <= storage.length else { return nil }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        guard start < text.length, storage.attribute(.pointCollapsed, at: start, effectiveRange: nil) != nil else { return nil }
        return NSRange(location: start, length: contentsEnd - start)
    }

    private func lineStart(of index: Int) -> Int {
        text.lineRange(for: NSRange(location: index, length: 0)).location
    }
}
