#if canImport(AppKit)
import AppKit

/// The insertion point, drawn by the editor rather than the system, so that it glides from
/// place to place instead of jumping: briefly as the arrows or a click move it, more briefly
/// still as you type. It blinks as the system's does, staying solid for a moment after each
/// move. With Reduce Motion it moves at once. Only while the editor has the keyboard, in the
/// key window, with nothing selected; a table cell has its own, the system's.
final class InsertionCursorView: NSView {
    var color: NSColor = .textColor {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    // Clicks go through to the text.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension MarkdownTextView {
    /// How long the cursor takes to glide to a new place, moved or typed.
    static let cursorMoveDuration: CFTimeInterval = 0.1
    static let cursorTypingDuration: CFTimeInterval = 0.05
    static let cursorWidth: CGFloat = 2

    /// Puts the cursor in place soon, once the text and its layout have settled.
    /// `animated` asks for the glide; any request without it in the meantime doesn't cancel it.
    func setNeedsCursorUpdate(animated: Bool = false) {
        cursorAnimates = cursorAnimates || animated
        guard !isCursorUpdateQueued else { return }
        isCursorUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCursorUpdateQueued = false
            let animated = self.cursorAnimates
            self.cursorAnimates = false
            self.updateCursor(animated: animated)
        }
    }

    /// Whether our cursor shows: the editor has the keyboard, in the key window, and the
    /// selection is just a place.
    var showsCursor: Bool {
        guard let window, window.isKeyWindow, window.firstResponder === self, isEditable else { return false }
        return selectedRange().length == 0
    }

    /// Where the cursor goes for the selection, in the view: as tall as the text's font, on
    /// its baseline, not the whole line with its extra spacing.
    func cursorRect() -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let text = string as NSString
        let location = min(selectedRange().location, text.length)
        let origin = textContainerOrigin
        let font = cursorFont(at: location)
        let height = font.ascender - font.descender
        if location == text.length, text.length == 0 || text.character(at: text.length - 1) == 10 {
            // On the empty last line: the height of the text there, in the middle of the line.
            layoutManager.ensureLayout(for: textContainer)
            var line = layoutManager.extraLineFragmentRect
            if line.isEmpty {
                guard text.length == 0 else { return nil }
                line = NSRect(x: 0, y: 0, width: textContainer.size.width, height: height)
            }
            let shown = min(height, line.height)
            return NSRect(x: (line.minX + textContainer.lineFragmentPadding + origin.x).rounded(.down),
                          y: line.minY + origin.y + (line.height - shown) / 2, width: Self.cursorWidth, height: shown)
        }
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let atEnd = location == text.length
        let glyph = layoutManager.glyphIndexForCharacter(at: atEnd ? location - 1 : location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let place = layoutManager.location(forGlyphAt: glyph)
        // After the last character, which isn't a line break, the cursor is past its glyph.
        let x = atEnd ? layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).maxX : line.minX + place.x
        let baseline = line.minY + place.y
        return NSRect(x: (x + origin.x).rounded(.down), y: baseline - font.ascender + origin.y,
                      width: Self.cursorWidth, height: height)
    }

    /// The font of the text the cursor is at: what's before it on the line, or else after,
    /// passing over hidden markers.
    private func cursorFont(at location: Int) -> NSFont {
        let text = string as NSString
        let fallback = styler.theme.body
        guard let storage = textStorage, text.length > 0 else { return fallback }
        func shown(_ index: Int) -> NSFont? {
            guard index >= 0, index < text.length, storage.attribute(.pointHidden, at: index, effectiveRange: nil) == nil else { return nil }
            return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        }
        var before = location - 1
        while before >= 0, text.character(at: before) != 10, storage.attribute(.pointHidden, at: before, effectiveRange: nil) != nil { before -= 1 }
        if before >= 0, text.character(at: before) != 10, let font = shown(before) { return font }
        var after = location
        while after < text.length, text.character(at: after) != 10, storage.attribute(.pointHidden, at: after, effectiveRange: nil) != nil { after += 1 }
        return shown(after) ?? fallback
    }

    /// Moves the cursor to the selection, gliding there if `animated`, and shows or hides it.
    func updateCursor(animated: Bool) {
        hideSystemInsertionIndicator()
        if cursorView.superview !== self || subviews.last !== cursorView {
            addSubview(cursorView, positioned: .above, relativeTo: nil)
        }
        let length = (string as NSString).length
        let typed = length != cursorTextLength
        cursorTextLength = length
        guard showsCursor, let target = cursorRect() else {
            cursorView.isHidden = true
            return
        }
        cursorView.color = insertionPointColor
        let wasHidden = cursorView.isHidden
        cursorView.isHidden = false
        guard target != cursorView.frame || wasHidden else { return }

        let layer = cursorView.layer
        let from = layer?.presentation()
        let visible = enclosingScrollView?.contentView.bounds.height ?? bounds.height
        let near = abs(target.midY - cursorView.frame.midY) < visible
        let glides = animated && !wasHidden && near && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAllAnimations()
        cursorView.frame = target
        CATransaction.commit()

        if glides, let layer, let from {
            let timing = CAMediaTimingFunction(name: .easeOut)
            let duration = typed ? Self.cursorTypingDuration : Self.cursorMoveDuration
            for key in ["position", "bounds"] {
                let move = CABasicAnimation(keyPath: key)
                move.fromValue = key == "position" ? NSValue(point: from.position) : NSValue(rect: from.bounds)
                move.toValue = key == "position" ? NSValue(point: layer.position) : NSValue(rect: layer.bounds)
                move.duration = duration
                move.timingFunction = timing
                layer.add(move, forKey: key)
            }
        }
        restartCursorBlink()
    }

    /// How long the cursor takes to fade out or in as it blinks.
    static let cursorFadeDuration: Double = 0.15

    /// Solid for a moment, then fading off and on, as the system's cursor blinks.
    func restartCursorBlink() {
        guard let layer = cursorView.layer else { return }
        let defaults = UserDefaults.standard
        let on = (defaults.object(forKey: "NSTextInsertionPointBlinkPeriodOn") as? Double ?? 500) / 1000
        let off = (defaults.object(forKey: "NSTextInsertionPointBlinkPeriodOff") as? Double ?? 500) / 1000
        let period = on + off
        let fade = min(Self.cursorFadeDuration, on / 2, off / 2)
        // Each period: solid, fading out, off, fading back in.
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1.0, 1.0, 0.0, 0.0, 1.0]
        blink.keyTimes = [0, on - fade, on, period - fade, period].map { NSNumber(value: $0 / period) }
        blink.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        blink.duration = period
        blink.repeatCount = .infinity
        // The first period starts where it's solid, so it's on for a whole `on` before fading.
        blink.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.add(blink, forKey: "blink")
    }

    /// The system draws no cursor of its own beside ours. Since macOS 14 it's a view of its
    /// own; before, it's drawn (see `drawInsertionPoint`).
    private func hideSystemInsertionIndicator() {
        if #available(macOS 14.0, *) {
            for case let indicator as NSTextInsertionIndicator in subviews where indicator.displayMode != .hidden {
                indicator.displayMode = .hidden
            }
        }
    }

    /// Follows the window becoming key or not, which shows or hides the cursor.
    func observeWindowForCursor() {
        cursorWindowObservers.forEach(NotificationCenter.default.removeObserver)
        cursorWindowObservers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            cursorWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsCursorUpdate() }
            })
        }
    }
}
#endif
