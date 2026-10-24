#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Folding: a heading rolls up everything under it (to the next heading as big or bigger),
/// and a list item rolls up the items and lines indented under it. The folded lines stay in
/// the text, collapsed like frontmatter, so the cursor skips them and saving is unchanged.
/// An arrow beside a line folds or unfolds it; ⌥⌘[ and ⌥⌘] do the same for the cursor's line.
extension MarkdownTextView {
    // MARK: Commands

    /// ⌥⌘[: folds the heading or list item the cursor is on, or failing that, the heading or
    /// list item it's inside.
    @objc public func foldLine(_ sender: Any?) {
        guard let line = foldableLine(around: selectedRange().location), !folds.contains(line) else { return NSSound.beep() }
        setFolded(true, line: line)
    }

    /// ⌥⌘]: unfolds the cursor's line.
    @objc public func unfoldLine(_ sender: Any?) {
        let line = lineStart(of: selectedRange().location)
        guard folds.contains(line) else { return NSSound.beep() }
        setFolded(false, line: line)
    }

    func setFolded(_ folded: Bool, line: Int) {
        guard let storage = textStorage else { return }
        if folded {
            guard !foldedLines(under: line).isEmpty else { return }
            folds.insert(line)
            applyFolds()
            // The cursor can't stay in what's now hidden: it goes to the folded line.
            if let range = foldRange(under: line), NSLocationInRange(selectedRange().location, range) {
                setSelectedRange(NSRange(location: lineContentsEnd(of: line), length: 0))
            }
        } else {
            let range = foldRange(under: line)
            folds.remove(line)
            if let range {
                storage.beginEditing()
                styler.style(storage, range: range, tokens: tokens)
                applyFolds()
                storage.endEditing()
            }
        }
        needsDisplay = true
    }

    // MARK: What folds

    /// Whether the line starting at `line` has anything under it to fold.
    func isFoldable(_ line: Int) -> Bool { !foldedLines(under: line).isEmpty }

    /// The line to fold for the cursor at `index`: its own line if that folds, else the
    /// nearest heading or list item above that contains it.
    func foldableLine(around index: Int) -> Int? {
        let start = lineStart(of: index)
        if isFoldable(start) { return start }
        var candidate = start
        while candidate > 0 {
            candidate = lineStart(of: candidate - 1)
            if let range = foldRange(under: candidate), NSLocationInRange(start, range) { return candidate }
        }
        return nil
    }

    /// The text a fold of `line` hides, from the start of the first line under it to the end
    /// of the last (its line break included), if anything.
    func foldRange(under line: Int) -> NSRange? {
        let lines = foldedLines(under: line)
        guard let first = lines.first, let last = lines.last else { return nil }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    /// The lines (with their line breaks) under a heading or list item.
    func foldedLines(under line: Int) -> [NSRange] {
        let text = string as NSString
        guard line < text.length, let token = blockTokens[line] else { return [] }
        var lines: [NSRange] = []
        var next = NSMaxRange(text.lineRange(for: NSRange(location: line, length: 0)))
        switch token.kind {
        case .heading(let level):
            // Up to the next heading as big or bigger.
            while next < text.length {
                if let heading = blockTokens[next], case .heading(let other) = heading.kind, other <= level { break }
                let range = text.lineRange(for: NSRange(location: next, length: 0))
                lines.append(range)
                next = NSMaxRange(range)
            }
            // Not the blank lines before the next heading: they keep it apart from this one.
            while let last = lines.last, text.substring(with: last).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.removeLast()
            }
        case .listItem(_, let indent):
            // The lines indented further, up to the first blank or shallower line.
            while next < text.length {
                let range = text.lineRange(for: NSRange(location: next, length: 0))
                let content = text.substring(with: range)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      Self.indentColumns(content) > indent else { break }
                lines.append(range)
                next = NSMaxRange(range)
            }
        default:
            return []
        }
        return lines
    }

    /// Leading whitespace in columns, a tab counting as 4, as the parser counts it.
    static func indentColumns(_ line: String) -> Int {
        var columns = 0
        for character in line {
            if character == " " { columns += 1 } else if character == "\t" { columns += 4 } else { break }
        }
        return columns
    }

    func lineContentsEnd(of index: Int) -> Int {
        let text = string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        return contentsEnd
    }

    // MARK: Keeping folds through edits

    /// Collapses the lines under every folded line. Called after any restyle, which resets
    /// their look.
    func applyFolds() {
        appliedFoldRanges = foldRanges()
        // Raw Markdown shows everything.
        guard let storage = textStorage, !folds.isEmpty, !styler.showsMarkdown else { return }
        let text = storage.string as NSString
        for line in folds {
            for range in foldedLines(under: line) {
                var contentsEnd = 0, start = 0, end = 0
                text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: range.location, length: 0))
                styler.hideLine(NSRange(location: start, length: contentsEnd - start), storage: storage, text: text)
            }
        }
    }

    /// Moves folds along with an edit (`edited` and `delta` as the text storage reports
    /// them). A fold whose line, or whose hidden lines, the edit touched opens again.
    /// Returns whether any opened, so the caller can restyle.
    func updateFolds(edited: NSRange, delta: Int, hiddenBefore: [Int: NSRange]) -> Bool {
        guard !folds.isEmpty else { return false }
        let before = NSRange(location: edited.location, length: max(0, edited.length - delta))
        var kept = Set<Int>()
        var opened = false
        for line in folds {
            let hidden = hiddenBefore[line]
            let touchesHidden = hidden.map { NSIntersectionRange($0, before).length > 0 || (before.length == 0 && NSLocationInRange(before.location, $0) && before.location != $0.location) } ?? false
            if touchesHidden || (line > before.location && line < NSMaxRange(before)) {
                opened = true
                continue
            }
            let moved = line >= NSMaxRange(before) && line > before.location ? line + delta : line
            if moved >= 0, moved < (string as NSString).length, lineStart(of: moved) == moved, isFoldable(moved) {
                kept.insert(moved)
            } else {
                opened = true
            }
        }
        folds = kept
        return opened
    }

    /// Each fold's hidden range, before an edit changes them.
    func foldRanges() -> [Int: NSRange] {
        var ranges: [Int: NSRange] = [:]
        for line in folds { ranges[line] = foldRange(under: line) }
        return ranges
    }

    // MARK: Arrows

    /// Where a line's fold arrow goes: in the margin, just before its heading text or its
    /// list marker.
    func foldArrowRect(forLine line: Int) -> NSRect? {
        guard let layoutManager = pointLayoutManager, let storage = textStorage, let container = textContainer,
              line < storage.length else { return nil }
        let lineRect = layoutManager.lineRect(containing: line, storage: storage)
        var x = container.lineFragmentPadding
        if let decoration = storage.attribute(.pointListMarker, at: line, effectiveRange: nil) as? ListMarkerDecoration {
            x += styler.theme.indentPerLevel * CGFloat(decoration.level)
        }
        let size: CGFloat = 14
        let origin = textContainerOrigin
        let font = layoutManager.textFont(near: line, storage: storage)
        let visible = layoutManager.firstVisibleCharacter(onLineOf: line, storage: storage) ?? line
        let baseline = lineRect.minY + layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: visible)).y
        let middle = baseline - font.xHeight / 2
        return NSRect(x: origin.x + x - size - 4, y: origin.y + middle - size / 2, width: size, height: size)
    }

    /// The foldable line whose arrow is at `point`, if any.
    func foldArrowLine(at point: NSPoint) -> Int? {
        guard let line = line(at: point), isFoldable(line) || folds.contains(line),
              let rect = foldArrowRect(forLine: line), rect.insetBy(dx: -6, dy: -4).contains(point) else { return nil }
        return line
    }

    /// The start of the line at a point in the view.
    func line(at point: NSPoint) -> Int? {
        guard let layoutManager = pointLayoutManager, let container = textContainer, textStorage?.length ?? 0 > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: max(point.x - origin.x, container.lineFragmentPadding + 1), y: point.y - origin.y)
        let index = layoutManager.characterIndexForPoint(local, in: container)
        return lineStart(of: min(index, (string as NSString).length - 1))
    }

    /// Draws the arrows: one for each folded line (pointing right, with "⋯" after the line),
    /// and one for the foldable line under the pointer (pointing down).
    func drawFoldArrows(in dirtyRect: NSRect) {
        var lines = folds
        if let hovered = hoveredFoldLine { lines.insert(hovered) }
        for line in lines {
            guard let rect = foldArrowRect(forLine: line), rect.intersects(dirtyRect.insetBy(dx: -20, dy: -20)) else { continue }
            let folded = folds.contains(line)
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: folded ? "Unfold" : "Fold")?
                .withSymbolConfiguration(configuration)?
                .draw(in: rect.insetBy(dx: 2, dy: 2), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if folded { drawFoldedMark(afterLine: line) }
        }
    }

    /// A "⋯" after a folded line's text, for what's rolled up under it.
    private func drawFoldedMark(afterLine line: Int) {
        guard let layoutManager = pointLayoutManager, let container = textContainer else { return }
        let end = lineContentsEnd(of: line)
        let lastVisible = max(line, end - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: lastVisible)
        let bounds = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        let origin = textContainerOrigin
        let font = NSFont.systemFont(ofSize: styler.theme.bodySize * 0.8, weight: .bold)
        let label = "⋯" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = label.size(withAttributes: attributes)
        let pill = NSRect(x: origin.x + bounds.maxX + 6, y: origin.y + bounds.midY - size.height / 2 - 1, width: size.width + 10, height: size.height + 2)
        NSColor.textColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        label.draw(at: NSPoint(x: pill.minX + 5, y: pill.minY + 1), withAttributes: attributes)
    }

    /// Follows the pointer, to show the arrow of the foldable line under it.
    func updateHoveredFoldLine(at point: NSPoint?) {
        var line: Int?
        if let point, let candidate = self.line(at: point), isFoldable(candidate) || folds.contains(candidate) {
            line = candidate
        }
        guard line != hoveredFoldLine else { return }
        let old = hoveredFoldLine
        hoveredFoldLine = line
        for changed in [old, line].compactMap({ $0 }) {
            if let rect = foldArrowRect(forLine: changed) { setNeedsDisplay(rect.insetBy(dx: -4, dy: -4)) }
        }
    }
}
#endif
