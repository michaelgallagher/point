import Foundation
import MarkdownKit

/// Highlighting while reading (see plan/reader-mode.md): a selection, however it falls, made
/// into well-formed `==highlights==`, one to each line it covers.
extension MarkdownEditing {
    /// Highlights the selection: on each line it covers, the selected text in `==…==`, outside
    /// the line's own markers (`> `, `- `, `## `), widened to take in whole any bold, italic,
    /// link or code it only partly covers (so markers stay paired), and joined into any
    /// highlight it overlaps or touches. Lines in code blocks, tables and the properties are
    /// left alone, and so is `skipping` (reader mode's marker). Nil if nothing would change.
    public func highlightingSelection(skipping: String? = nil) -> MarkdownEdit? {
        let segments = highlightSegments(skipping: skipping)
        guard let first = segments.first, let last = segments.last else { return nil }
        var replacement = ""
        var at = first.location
        for segment in segments {
            replacement += text.substring(with: NSRange(location: at, length: segment.location - at))
            replacement += "==" + withoutHighlightMarkers(segment) + "=="
            at = NSMaxRange(segment)
        }
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        guard replacement != text.substring(with: range) else { return nil }
        return MarkdownEdit(range: range, replacement: replacement,
                            selection: NSRange(location: first.location, length: (replacement as NSString).length))
    }

    /// Takes the highlighting off every highlight the selection touches (or the cursor's in),
    /// leaving their text. Nil if there are none.
    public func removingHighlights(skipping: String? = nil) -> MarkdownEdit? {
        let touched = tokens.filter { token in
            guard token.kind == .highlight, token.syntax.count == 2, !isSkipped(token.range, skipping) else { return false }
            return selection.length == 0
                ? NSLocationInRange(selection.location, token.range) || NSMaxRange(token.range) == selection.location
                : NSIntersectionRange(token.range, selection).length > 0
        }.sorted { $0.range.location < $1.range.location }
        guard let first = touched.first, let last = touched.last else { return nil }
        let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        let markers = touched.flatMap(\.syntax)
        let replacement = text(in: range, leavingOut: markers)
        return MarkdownEdit(range: range, replacement: replacement,
                            selection: NSRange(location: range.location, length: (replacement as NSString).length))
    }

    /// The selection as Markdown that stands on its own, for quoting: each line's part of it,
    /// widened as for highlighting (so its markers are paired), without highlight markers;
    /// lines of one paragraph one under another, paragraphs a blank line apart.
    public func quotableSelection(skipping: String? = nil) -> String {
        var quoted = ""
        var lastLineEnd: Int?
        for segment in highlightSegments(skipping: skipping, joiningHighlights: false) {
            let line = text.lineRange(for: NSRange(location: segment.location, length: 0))
            if let lastLineEnd {
                // A blank line (or more) between them: another paragraph.
                let between = text.substring(with: NSRange(location: lastLineEnd, length: max(0, line.location - lastLineEnd)))
                quoted += between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && between.contains("\n") ? "\n\n" : "\n"
            }
            quoted += withoutHighlightMarkers(segment)
            lastLineEnd = NSMaxRange(line)
        }
        return quoted
    }

    /// The note's highlights from `start` on, each with its text (markers left out), in order.
    public static func highlights(in text: String, from start: Int = 0, skipping: String? = nil) -> [(range: NSRange, text: String)] {
        let editing = MarkdownEditing(text: text, selection: NSRange(location: 0, length: 0))
        return editing.tokens.filter { $0.kind == .highlight && $0.syntax.count == 2 && $0.range.location >= start && !editing.isSkipped($0.range, skipping) }
            .map { token in
                let inner = NSRange(location: NSMaxRange(token.syntax[0]), length: token.syntax[1].location - NSMaxRange(token.syntax[0]))
                return (token.range, editing.text.substring(with: inner))
            }
    }

    // MARK: Workings

    /// Whether `range` is on a line that's exactly `skipping`.
    private func isSkipped(_ range: NSRange, _ skipping: String?) -> Bool {
        guard let skipping else { return false }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        return text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == skipping
    }

    private static func isInline(_ kind: MarkdownToken.Kind) -> Bool {
        switch kind {
        case .strong, .emphasis, .strikethrough, .highlight, .code, .link, .image, .wikiLink, .embed, .tag, .url,
             .footnoteReference, .escape: true
        default: false
        }
    }

    /// Blocks whose lines can't be highlighted.
    private func isInUnhighlightableBlock(_ location: Int) -> Bool {
        tokens.contains { token in
            switch token.kind {
            case .frontmatter, .codeBlock, .table, .thematicBreak: NSLocationInRange(location, token.range)
            default: false
            }
        }
    }

    /// Where a line's text starts, after its block markers: quote markers, a list item's marker
    /// and checkbox, a heading's hashes.
    private func contentStart(of line: NSRange) -> Int {
        let string = text.substring(with: line)
        let pattern = #"^[ \t]*(?:>[ \t]?)*[ \t]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?(?:#{1,6}[ \t]+)?"#
        guard let match = string.range(of: pattern, options: .regularExpression) else { return line.location }
        return line.location + (String(string[match]) as NSString).length
    }

    /// The selection's part of each line, ready to be highlighted: inside the line's text,
    /// spaces trimmed, widened over any inline span it only partly covers, and (if
    /// `joiningHighlights`) over highlights it touches.
    func highlightSegments(skipping: String? = nil, joiningHighlights: Bool = true) -> [NSRange] {
        guard selection.length > 0, NSMaxRange(selection) <= text.length else { return [] }
        var segments: [NSRange] = []
        let lines = text.lineRange(for: selection)
        text.enumerateSubstrings(in: lines, options: .byLines) { _, line, _, _ in
            guard !isInUnhighlightableBlock(line.location), !isSkipped(line, skipping) else { return }
            var start = max(selection.location, contentStart(of: line))
            var end = min(NSMaxRange(selection), NSMaxRange(line))
            let trimmed = trimmingWhitespace(NSRange(location: start, length: max(0, end - start)))
            guard trimmed.length > 0 else { return }
            start = trimmed.location
            end = NSMaxRange(trimmed)
            var widened = true
            while widened {
                widened = false
                for token in tokens where Self.isInline(token.kind)
                    && token.range.location >= line.location && NSMaxRange(token.range) <= NSMaxRange(line) {
                    let r = token.range
                    let overlaps = r.location < end && NSMaxRange(r) > start
                    let partly = overlaps && (r.location < start || NSMaxRange(r) > end)
                    let touching = joiningHighlights && token.kind == .highlight
                        && (isSpacesOnly(from: NSMaxRange(r), to: start) || isSpacesOnly(from: end, to: r.location))
                    if partly || touching {
                        start = min(start, r.location)
                        end = max(end, NSMaxRange(r))
                        widened = true
                    }
                }
            }
            segments.append(NSRange(location: start, length: end - start))
        }
        return segments
    }

    /// Whether from `start` to `end` is nothing, or only spaces and tabs.
    private func isSpacesOnly(from start: Int, to end: Int) -> Bool {
        guard start <= end, end <= text.length else { return false }
        return text.substring(with: NSRange(location: start, length: end - start)).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// A segment's text without the markers of the highlights inside it.
    private func withoutHighlightMarkers(_ segment: NSRange) -> String {
        let markers = tokens.filter { $0.kind == .highlight && $0.syntax.count == 2 && NSIntersectionRange($0.range, segment).length == $0.range.length }
            .flatMap(\.syntax)
        return text(in: segment, leavingOut: markers)
    }

    private func text(in range: NSRange, leavingOut cuts: [NSRange]) -> String {
        var result = ""
        var at = range.location
        for cut in cuts.sorted(by: { $0.location < $1.location }) where cut.location >= at && NSMaxRange(cut) <= NSMaxRange(range) {
            result += text.substring(with: NSRange(location: at, length: cut.location - at))
            at = NSMaxRange(cut)
        }
        return result + text.substring(with: NSRange(location: at, length: NSMaxRange(range) - at))
    }
}
