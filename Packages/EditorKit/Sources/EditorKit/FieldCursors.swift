#if canImport(AppKit)
import AppKit

/// The editor's gliding cursor (see +AnimatedCursor) in every other text field: a note's title
/// and properties, search, renaming, the palette, sheets and a table's cells. They all type
/// through a text view, mostly the window's shared field editor, so one watcher follows
/// whichever has the keyboard and puts the cursor there. Since macOS 14, which lets the
/// system's own be hidden.
@MainActor
public final class FieldCursors {
    public static let shared = FieldCursors()

    private let cursor = InsertionCursorView()
    /// The text view the cursor is in, and what that was in when it was put there: a window's
    /// field editor moves from field to field.
    private weak var textView: NSTextView?
    private weak var holder: NSView?
    /// The text view's own insertion point colour, while it's made clear (see `update`).
    private var shownColor: NSColor?
    private var observers: [NSObjectProtocol] = []
    private var isQueued = false
    private var animates = false
    private var clicked = false
    private var keepsUp = false

    /// Starts following the text fields of every window.
    public func start() {
        guard #available(macOS 14.0, *), observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsUpdate(animated: true) }
            },
            center.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsUpdate(animated: true, edited: true) }
            },
            // The keyboard moving to another field or window, or away.
            center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let next = Self.focused()
                    if next !== self.textView || next?.superview !== self.holder { self.setNeedsUpdate() }
                }
            },
        ]
    }

    /// The text view with the keyboard in the key window, unless it's the editor, which has
    /// its own.
    static func focused() -> NSTextView? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView,
              !(view is MarkdownTextView), view.isEditable, view.window != nil else { return nil }
        return view
    }

    /// Puts the cursor in place soon, once the field and its layout have settled, as the
    /// editor does (see `setNeedsCursorUpdate`).
    private func setNeedsUpdate(animated: Bool = false, edited: Bool = false) {
        animates = animates || animated
        if animated, InsertionCursorView.isClicking { clicked = true }
        if edited, InsertionCursorView.isKeyRepeating { keepsUp = true }
        guard !isQueued else { return }
        isQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isQueued = false
                let animated = self.animates && !self.keepsUp, clicked = self.clicked
                self.animates = false
                self.clicked = false
                self.keepsUp = false
                self.update(animated: animated, clicked: clicked)
            }
        }
    }

    private func update(animated: Bool, clicked: Bool) {
        let next = Self.focused()
        if next !== textView || next?.superview !== holder {
            // Into another field: it appears there rather than gliding from the last.
            cursor.removeFromSuperview()
            cursor.isHidden = true
            if next !== textView, let shownColor { textView?.insertionPointColor = shownColor }
            if next !== textView { shownColor = nil }
            textView = next
            holder = next?.superview
        }
        guard let view = next else { return }
        // A field editor lays out with TextKit 2, which keeps the system's cursor deeper than
        // the editor's (TextKit 1) and makes it again as it likes, so hiding it isn't enough:
        // it's also made clear, while ours is there, and given its colour back after.
        InsertionCursorView.hideSystemIndicator(in: view, deep: true)
        if view.insertionPointColor != .clear {
            shownColor = view.insertionPointColor
            view.insertionPointColor = .clear
        }
        if cursor.superview !== view || view.subviews.last !== cursor {
            view.addSubview(cursor, positioned: .above, relativeTo: nil)
        }
        guard view.selectedRange().length == 0, let target = Self.cursorRect(in: view) else {
            cursor.isHidden = true
            return
        }
        cursor.color = shownColor ?? .controlAccentColor
        cursor.move(to: target, animated: animated, clicked: clicked, reach: view.visibleRect.height + 1)
    }

    /// Where the system would put the insertion point in `view`, as tall as the text's font in
    /// the middle of its line.
    static func cursorRect(in view: NSTextView) -> NSRect? {
        guard let window = view.window else { return nil }
        let place = NSRange(location: view.selectedRange().location, length: 0)
        let screen = view.firstRect(forCharacterRange: place, actualRange: nil)
        guard screen != .zero else { return nil }
        let line = view.convert(window.convertFromScreen(screen), from: nil)
        let font = view.typingAttributes[.font] as? NSFont ?? view.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let height = min(line.height, (font.ascender - font.descender).rounded(.up))
        return NSRect(x: line.minX.rounded(.down), y: line.midY - height / 2, width: InsertionCursorView.width, height: height)
    }
}
#endif
