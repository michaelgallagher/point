#if canImport(AppKit)
import AppKit

/// When a key typed or a command moves lines (Return, deleting a line break, a line wrapping,
/// indenting, moving lines up or down), each line on screen glides from where it was to where
/// it is, as in Bike, at the cursor's pace, instead of jumping there. The text after a split
/// line glides down from where it was, and the text of a joined line up to its new place.
///
/// The text itself changes at once, as always. A picture of the lines on screen is taken in
/// their new places, and for each line that moved, its piece of the picture is put where it was
/// and slides there, over a patch of background hiding the real line. Then they go. Only on
/// screen, and not with Reduce Motion.
extension MarkdownTextView {
    /// The lines on screen before an edit: where each was, and what it held.
    struct LineMoveStart {
        let text: String
        /// Where the cursor or selection was.
        let selection: NSRange
        let lines: [Line]
        /// Where the grids over tables were, in order.
        let grids: [NSRect]

        struct Line {
            let characters: NSRange
            /// The line, in the view.
            let rect: NSRect
            /// Where its first character is across.
            let start: CGFloat
            /// Where each of its characters is across, for lines near the cursor, where an edit
            /// may split or join them.
            let across: [CGFloat]?
        }

        /// Where a character was, if it was on screen.
        func place(of character: Int) -> NSPoint? {
            guard let line = lines.first(where: { NSLocationInRange(character, $0.characters) }) else { return nil }
            if character == line.characters.location { return NSPoint(x: line.start, y: line.rect.minY) }
            guard let across = line.across, character - line.characters.location < across.count else { return nil }
            return NSPoint(x: across[character - line.characters.location], y: line.rect.minY)
        }
    }

    /// The edits made since `LineMoveStart`, as one: what was put in, in the text as it is now,
    /// and by how much the text grew.
    struct LineMoveEdits {
        var replaced: NSRange
        var delta: Int

        mutating func add(_ range: NSRange, delta added: Int) {
            let oldEnd = NSMaxRange(range) - added
            var earlier = replaced
            if earlier.location >= oldEnd {
                earlier.location += added
            } else if NSMaxRange(earlier) > range.location {
                earlier.length = max(0, earlier.length + added)
            }
            let start = min(range.location, earlier.location)
            replaced = NSRange(location: start, length: max(NSMaxRange(range), NSMaxRange(earlier)) - start)
            delta += added
        }

        /// Where a character now was before, or nil if it's new.
        func before(_ character: Int) -> Int? {
            if character < replaced.location { return character }
            if character >= NSMaxRange(replaced) { return character - delta }
            return nil
        }
    }

    /// A piece of a line that moved: where it is now in the view, and how far it moved to get
    /// there.
    struct LineMove {
        let rect: NSRect
        let offset: CGVector
    }

    /// Runs an edit, sliding the lines it moves into place. Not for a key held down, whose
    /// lines move faster than they could slide.
    func movingLines(_ edit: () -> Void) {
        guard !isRecordingLineMoves, !InsertionCursorView.isKeyRepeating, let start = lineMoveStart() else {
            endLineSlide()
            return edit()
        }
        lineMoveEdits = nil
        isRecordingLineMoves = true
        edit()
        isRecordingLineMoves = false
        slideLines(since: start)
    }

    /// Notes where the lines on screen are, before an edit.
    func lineMoveStart() -> LineMoveStart? {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !hasMarkedText() else { return nil }
        if isTableSyncQueued { syncTableViews() }
        let text = string as NSString
        // Near the cursor: its paragraph, and those either side.
        var near = text.paragraphRange(for: selectedRange())
        if near.location > 0 { near = NSUnionRange(near, text.paragraphRange(for: NSRange(location: near.location - 1, length: 0))) }
        if NSMaxRange(near) < text.length { near = NSUnionRange(near, text.paragraphRange(for: NSRange(location: NSMaxRange(near), length: 0))) }
        return LineMoveStart(text: string, selection: selectedRange(), lines: visibleLines(below: visibleRect.height, near: near), grids: tableGrids.map(\.frame))
    }

    /// The lines on screen (and `extra` further below), in the view.
    private func visibleLines(below extra: CGFloat, near: NSRange? = nil) -> [LineMoveStart.Line] {
        guard let layoutManager, let textContainer else { return [] }
        let origin = textContainerOrigin
        var area = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        area.size.height += extra
        let glyphs = layoutManager.glyphRange(forBoundingRect: area, in: textContainer)
        var lines: [LineMoveStart.Line] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
            let characters = layoutManager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            func across(_ character: Int) -> CGFloat {
                let glyph = layoutManager.glyphIndexForCharacter(at: character)
                return rect.minX + layoutManager.location(forGlyphAt: glyph).x + origin.x
            }
            var all: [CGFloat]?
            if let near, NSIntersectionRange(characters, near).length > 0 {
                all = (characters.location..<NSMaxRange(characters)).map(across)
            }
            lines.append(.init(characters: characters, rect: rect.offsetBy(dx: origin.x, dy: origin.y),
                               start: across(characters.location), across: all))
        }
        return lines
    }

    /// Records an edit made while lines are watched (see `movingLines`).
    func recordLineMoveEdit(_ range: NSRange, delta: Int) {
        guard isRecordingLineMoves else { return }
        if lineMoveEdits == nil {
            lineMoveEdits = LineMoveEdits(replaced: range, delta: delta)
        } else {
            lineMoveEdits?.add(range, delta: delta)
        }
    }

    /// The pieces of lines on screen that moved since `start`, and how far.
    func lineMoves(since start: LineMoveStart) -> [LineMove] {
        guard let edits = lineMoveEdits, let layoutManager else { return [] }
        let text = string as NSString
        let old = start.text as NSString
        let width = bounds.width
        let replaced = edits.replaced
        let replacedBefore = NSRange(location: replaced.location, length: max(0, replaced.length - edits.delta))
        // An edit that adds or removes a line break splits or joins lines, so the text either
        // side of it moves apart; otherwise what was typed moves with its line, as when it wraps.
        let splits = text.substring(with: replaced).contains("\n")
            || NSMaxRange(replacedBefore) <= old.length && old.substring(with: replacedBefore).contains("\n")
        // Return in the middle of a line's text: nothing slides. The rest of the line goes
        // straight to its own, and the lines below straight down.
        let cursor = NSMaxRange(start.selection)
        if cursor < old.length, old.character(at: cursor) != 10,
           Self.lineBreaks(in: text) > Self.lineBreaks(in: old) {
            return []
        }
        var moves: [LineMove] = []
        var matched = Set<Int>()
        // How whole lines below the edit moved, for those that were off screen before.
        var below: CGVector?
        for line in visibleLines(below: 0) {
            let chars = line.characters
            func across(_ character: Int) -> CGFloat {
                let glyph = layoutManager.glyphIndexForCharacter(at: character)
                return line.rect.minX + layoutManager.location(forGlyphAt: glyph).x
            }
            // The line, or its pieces either side of a line break the edit put in or took out.
            var pieces: [NSRange] = []
            if splits {
                let beforeEdit = min(NSMaxRange(chars), replaced.location) - chars.location
                if beforeEdit > 0 { pieces.append(NSRange(location: chars.location, length: beforeEdit)) }
                let afterStart = max(chars.location, NSMaxRange(replaced))
                if afterStart < NSMaxRange(chars) { pieces.append(NSRange(location: afterStart, length: NSMaxRange(chars) - afterStart)) }
            } else {
                // Some of it, besides its line break, was there before.
                let breaks = chars.length > 0 && text.character(at: NSMaxRange(chars) - 1) == 10
                if replaced.location > chars.location || NSMaxRange(replaced) < NSMaxRange(chars) - (breaks ? 1 : 0) {
                    pieces = [chars]
                }
            }

            if pieces.isEmpty {
                // All of it put there by the edit: the same as a line it replaced, moved or
                // indented?
                let mine = Self.lineText(text, chars)
                let candidates = start.lines.enumerated().filter { index, was in
                    !matched.contains(index) && NSIntersectionRange(was.characters, replacedBefore).length > 0
                        && Self.lineText(old, was.characters) == mine
                }
                guard !mine.isEmpty, let match = candidates.min(by: {
                    abs($0.element.rect.minY - line.rect.minY) < abs($1.element.rect.minY - line.rect.minY)
                }) else { continue }
                matched.insert(match.offset)
                let offset = CGVector(dx: match.element.start - line.start, dy: match.element.rect.minY - line.rect.minY)
                if abs(offset.dx) >= 1 || abs(offset.dy) >= 1 {
                    moves.append(LineMove(rect: NSRect(x: 0, y: line.rect.minY, width: width, height: line.rect.height), offset: offset))
                }
                continue
            }

            for piece in pieces {
                // Followed by its first character that was there before.
                var anchor = piece.location
                if NSLocationInRange(anchor, replaced) { anchor = NSMaxRange(replaced) }
                guard anchor < NSMaxRange(piece) else { continue }
                let wholeLine = piece.location == chars.location
                let now = NSPoint(x: anchor == chars.location ? line.start : across(anchor), y: line.rect.minY)
                var offset: CGVector?
                if let was = edits.before(anchor).flatMap(start.place(of:)) {
                    offset = CGVector(dx: was.x - now.x, dy: was.y - now.y)
                } else if piece.location >= NSMaxRange(replaced), wholeLine, let below {
                    offset = below
                }
                guard let offset else { continue }
                if wholeLine, piece.location >= NSMaxRange(replaced), abs(offset.dx) < 1 { below = offset }
                // Along its line only counts for a whole line with only an indent before what
                // moved, not for the rest of a line typed into.
                let lead = text.substring(with: NSRange(location: chars.location, length: anchor - chars.location))
                let indented = wholeLine && lead.allSatisfy { $0 == " " || $0 == "\t" } && abs(offset.dx) >= 1
                guard abs(offset.dy) >= 1 || indented else { continue }
                let left = wholeLine ? 0 : now.x
                let right = NSMaxRange(piece) >= NSMaxRange(chars) ? width : across(NSMaxRange(piece))
                moves.append(LineMove(rect: NSRect(x: left, y: line.rect.minY, width: max(right - left, 1), height: line.rect.height),
                                      offset: offset))
            }
        }

        // Grids over tables move as their tables do.
        for (index, grid) in tableGrids.enumerated() where index < start.grids.count {
            let was = start.grids[index], now = grid.frame
            if was.size == now.size, abs(was.minY - now.minY) >= 1 || abs(was.minX - now.minX) >= 1 {
                moves.append(LineMove(rect: now, offset: CGVector(dx: was.minX - now.minX, dy: was.minY - now.minY)))
            }
        }
        return moves
    }

    /// A line's text, without its indent or line break, to know it again after an edit.
    private static func lineBreaks(in text: NSString) -> Int {
        text.components(separatedBy: "\n").count - 1
    }

    private static func lineText(_ text: NSString, _ range: NSRange) -> String {
        text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Slides the lines moved since `start` from where they were to where they are.
    func slideLines(since start: LineMoveStart) {
        defer { lineMoveEdits = nil }
        guard window != nil else { return }
        if isTableSyncQueued { syncTableViews() }
        let visible = visibleRect
        let moves = lineMoves(since: start).filter { $0.rect.intersects(visible) && abs($0.offset.dy) < visible.height }
        guard !moves.isEmpty else {
            // Typing on while lines still slide (after one wrapped): they carry on, showing what
            // was typed.
            refreshSlidingLines()
            return
        }
        endLineSlide()
        guard let (whole, scale) = picture(of: visible) else { return }

        let container = SlidingLinesView(frame: visible)
        // Under each moved piece where it is now, the background, so the real one doesn't show.
        for move in moves {
            let patch = SlidingLinesView(frame: move.rect.offsetBy(dx: -visible.minX, dy: -visible.minY))
            patch.background = backgroundColor
            patch.fillsBackground = true
            container.addSubview(patch)
        }
        var pieces: [(view: SlidingLinesView, end: NSPoint)] = []
        for move in moves {
            let now = move.rect.offsetBy(dx: -visible.minX, dy: -visible.minY)
            let crop = CGRect(x: now.minX * scale, y: now.minY * scale, width: now.width * scale, height: now.height * scale).integral
            guard let image = whole.cropping(to: crop) else { continue }
            let piece = SlidingLinesView(frame: now.offsetBy(dx: move.offset.dx, dy: move.offset.dy))
            piece.image = NSImage(cgImage: image, size: now.size)
            piece.end = now
            container.addSubview(piece)
            pieces.append((piece, now.origin))
        }
        addSubview(container, positioned: .below, relativeTo: cursorView.superview === self ? cursorView : nil)
        slidingLines = container

        NSAnimationContext.runAnimationGroup { context in
            context.duration = InsertionCursorView.acrossDuration
            context.timingFunction = InsertionCursorView.timing
            context.allowsImplicitAnimation = true
            for piece in pieces { piece.view.animator().setFrameOrigin(piece.end) }
        } completionHandler: { [weak self, weak container] in
            MainActor.assumeIsolated {
                guard let self, let container, self.slidingLines === container else { return }
                self.endLineSlide()
            }
        }
    }

    /// The text as it is, in `rect`, without the cursor or lines sliding over it, and its scale.
    /// Clear but for the text, so a piece sliding over another line doesn't blank it out.
    private func picture(of rect: NSRect) -> (CGImage, CGFloat)? {
        let cursorWasHidden = cursorView.isHidden
        cursorView.isHidden = true
        slidingLines?.isHidden = true
        let drewBackground = drawsBackground
        drawsBackground = false
        defer {
            drawsBackground = drewBackground
            cursorView.isHidden = cursorWasHidden
            slidingLines?.isHidden = false
        }
        guard let picture = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        cacheDisplay(in: rect, to: picture)
        guard let image = picture.cgImage else { return nil }
        return (image, CGFloat(picture.pixelsWide) / rect.width)
    }

    /// Retakes the pictures of the lines sliding, for an edit to them that moved nothing.
    private func refreshSlidingLines() {
        guard let container = slidingLines, let (whole, scale) = picture(of: container.frame) else { return }
        for case let piece as SlidingLinesView in container.subviews {
            guard let end = piece.end else { continue }
            let crop = CGRect(x: end.minX * scale, y: end.minY * scale, width: end.width * scale, height: end.height * scale).integral
            if let image = whole.cropping(to: crop) { piece.image = NSImage(cgImage: image, size: end.size) }
        }
    }

    /// Puts the lines straight where they are, if they're still sliding.
    func endLineSlide() {
        slidingLines?.removeFromSuperview()
        slidingLines = nil
    }
}

/// A piece of a picture of lines that slide, a patch of background, or what holds them: drawn
/// as a layer, and never in the way of clicks.
final class SlidingLinesView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var background: NSColor? {
        didSet { needsDisplay = true }
    }
    /// Whether the background is filled in, rather than showing what's behind.
    var fillsBackground = false {
        didSet { needsDisplay = true }
    }
    /// For a piece of a picture, where it ends up, in what holds it.
    var end: NSRect?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillsBackground ? background?.cgColor : nil
        layer?.contents = image?.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
        layer?.contentsGravity = .resize
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
