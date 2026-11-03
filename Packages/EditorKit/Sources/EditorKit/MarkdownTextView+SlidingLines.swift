#if canImport(AppKit)
import AppKit

/// When a key typed adds or removes a line (Return, deleting a line break, a line wrapping),
/// the lines below slide to their new place, as in Bike, instead of jumping there, at the
/// cursor's pace. The text itself moves at once, as always: a picture of the lines below, taken
/// in their new place, is put where they were and slides after them, then goes. Only on screen,
/// and not with Reduce Motion.
extension MarkdownTextView {
    /// Where the lines below the cursor began before a key was typed: the paragraph after the
    /// cursor's, and its top.
    struct LineSlideStart {
        let paragraph: Int
        let top: CGFloat
        let length: Int
    }

    /// Notes where the lines below the cursor are, before a key is typed.
    func lineSlideStart() -> LineSlideStart? {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !hasMarkedText(),
              let layoutManager else { return nil }
        let text = string as NSString
        let paragraph = NSMaxRange(text.paragraphRange(for: NSRange(location: NSMaxRange(selectedRange()), length: 0)))
        guard paragraph < text.length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: paragraph)
        return LineSlideStart(paragraph: paragraph, top: layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY,
                              length: text.length)
    }

    /// How far the lines below moved since `start`, and where they now begin, in the view;
    /// nil if they didn't move, or the edit wasn't above them.
    func lineSlide(since start: LineSlideStart) -> (top: CGFloat, distance: CGFloat)? {
        guard let layoutManager else { return nil }
        let text = string as NSString
        let paragraph = start.paragraph + text.length - start.length
        // Still the start of a paragraph after the edit.
        guard paragraph > 0, paragraph < text.length, lastEditLocation < paragraph,
              text.character(at: paragraph - 1) == 10 else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: paragraph)
        let top = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let distance = top - start.top
        guard abs(distance) >= 1 else { return nil }
        return (top + textContainerOrigin.y, distance)
    }

    /// Slides the lines below an edit from where they were (`start`) to where they are.
    func slideLines(since start: LineSlideStart) {
        endLineSlide()
        guard window != nil, let (top, distance) = lineSlide(since: start) else { return }
        let visible = visibleRect
        guard abs(distance) < visible.height, top < visible.maxY else { return }
        // The grids over tables go where their tables now are, to be in the picture.
        if isTableSyncQueued { syncTableViews() }

        let shown = NSRect(x: 0, y: top, width: bounds.width, height: visible.maxY - top)
        let cursorWasHidden = cursorView.isHidden
        cursorView.isHidden = true
        guard let picture = bitmapImageRepForCachingDisplay(in: shown) else { cursorView.isHidden = cursorWasHidden; return }
        cacheDisplay(in: shown, to: picture)
        cursorView.isHidden = cursorWasHidden
        let image = NSImage(size: shown.size)
        image.addRepresentation(picture)

        // Over the lines' old place and new. Moving up, the space they leave is blank until
        // they close it; moving down, the new line shows through above them.
        let cover = NSRect(x: 0, y: min(top, top - distance), width: bounds.width, height: visible.maxY - min(top, top - distance))
        let container = SlidingLinesView(frame: cover)
        container.fillsBackground = distance < 0
        container.background = backgroundColor
        let lines = SlidingLinesView(frame: NSRect(x: 0, y: top - distance - cover.minY, width: shown.width, height: shown.height))
        lines.image = image
        container.addSubview(lines)
        addSubview(container, positioned: .below, relativeTo: cursorView.superview === self ? cursorView : nil)
        slidingLines = container

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.cursorAcrossDuration
            context.timingFunction = Self.cursorTiming
            context.allowsImplicitAnimation = true
            lines.animator().setFrameOrigin(NSPoint(x: 0, y: top - cover.minY))
        } completionHandler: { [weak self, weak container] in
            MainActor.assumeIsolated {
                guard let self, let container, self.slidingLines === container else { return }
                self.endLineSlide()
            }
        }
    }

    /// Puts the lines straight where they are, if they're still sliding.
    func endLineSlide() {
        slidingLines?.removeFromSuperview()
        slidingLines = nil
    }
}

/// A picture of lines that slide, or what holds them: drawn as a layer, and never in the way
/// of clicks.
final class SlidingLinesView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var background: NSColor? {
        didSet { needsDisplay = true }
    }
    override var isFlipped: Bool { true }

    /// Whether the background is filled in, rather than showing what's behind.
    var fillsBackground = false {
        didSet { needsDisplay = true }
    }

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
