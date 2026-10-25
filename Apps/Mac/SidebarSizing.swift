import AppKit

/// Shows and hides a window's sidebar by changing the window's width, so the notes keep
/// theirs: the window grows rightwards by the sidebar's width (its left edge stays), and
/// shrinks back when the sidebar hides.
///
/// When there isn't room, the window first slides left to stay on its screen; if it would
/// be wider than the screen, it takes the screen's width and the notes give up the rest,
/// which they get back when the sidebar hides (and likewise a window that can't shrink below
/// its minimum gives the notes the difference until the sidebar shows again). In full screen, or zoomed to fill
/// the screen, the window keeps its size and the notes take the space, as before.
///
/// Every resize is worked out from the sidebar's real width at the time, not a remembered
/// amount (an earlier version did that, and the window drifted whenever a resize was cut
/// short). The window's frame and the sidebar's collapse animate together, in one AppKit
/// animation, so the notes don't jitter.
@MainActor
final class SidebarSizing {
    weak var window: NSWindow? {
        didSet { watchSidebar() }
    }

    /// The sidebar's width when it last showed, to show it at next.
    private var sidebarWidth: CGFloat?
    /// How much the notes' width changed when the window couldn't change by the whole
    /// sidebar (positive when it couldn't grow enough for the screen, negative when it
    /// couldn't shrink enough for its minimum), and how far the window slid left to stay on
    /// its screen: both undone at the next show or hide.
    private var adjustment: CGFloat = 0
    private var slide: CGFloat = 0

    /// The narrowest a window can be, with the sidebar and without.
    static let minimumWidth = (shown: CGFloat(600), hidden: CGFloat(420))
    /// The window's frame after this last resized it; if it's changed since, the person
    /// moved or resized the window, and the adjustment and slide no longer apply.
    private var frameAfterResize: NSRect?
    /// While a resize is animating (the window's resize notifications are then this's own).
    private(set) var isResizing = false
    /// Counts resizes, so each settles once: when its animation completes, or shortly after
    /// it should have (a window out of sight doesn't run its animations until it's seen).
    private var resizeCount = 0

    private static let duration: TimeInterval = 0.25

    // MARK: The split view

    /// The split view controller holding the sidebar: the window's outermost one (the
    /// two-column sidebar has another split view inside it).
    private var splitViewController: NSSplitViewController? {
        guard let root = window?.contentView else { return nil }
        var queue: [NSView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.count >= 2 { return controller }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private var sidebarItem: NSSplitViewItem? { splitViewController?.splitViewItems.first }

    /// The sidebar's width as shown now, or nil while it's hidden.
    private var shownSidebarWidth: CGFloat? {
        guard let item = sidebarItem, !item.isCollapsed else { return nil }
        let width = item.viewController.view.frame.width
        return width > 1 ? width : nil
    }

    private var sidebarObserver: NSObjectProtocol?
    private var collapseObservation: NSKeyValueObservation?
    /// The sidebar state the window was last resized for.
    private var resizedForShown: Bool?
    /// Until when sidebar changes are the app's own, made without resizing the window (at
    /// launch, in focus mode, or when the window's width hid it), so they aren't taken for
    /// the system's button. A moment, not "the next change": if nothing changes, a later
    /// click on the button mustn't be ignored.
    private var ignoresCollapseUntil = Date.distantPast

    /// The sidebar is about to show or hide without the window changing size.
    func willToggleWithoutResizing() {
        ignoresCollapseUntil = Date().addingTimeInterval(0.6)
        resizedForShown = nil
    }

    /// Keeps the sidebar's width up to date as it's dragged wider or narrower, so it shows
    /// at the width it was left at. (Not while it's collapsing: its width then shrinks.)
    private func watchSidebar() {
        if let sidebarObserver { NotificationCenter.default.removeObserver(sidebarObserver) }
        sidebarObserver = nil
        // The split view is there once the window's content has been laid out.
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = sidebarItem?.viewController.view else { return }
            view.postsFrameChangedNotifications = true
            sidebarObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isResizing, let width = self.shownSidebarWidth else { return }
                    self.sidebarWidth = width
                }
            }
            if let width = shownSidebarWidth { sidebarWidth = width }
            // The system's sidebar button collapses the sidebar itself, before the app hears
            // of it: resize the window as it starts, so the two move together.
            collapseObservation = sidebarItem?.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
                guard let collapsed = change.newValue else { return }
                DispatchQueue.main.async {
                    guard let self, !self.isResizing else { return }
                    guard Date() >= self.ignoresCollapseUntil else { return }
                    _ = self.setSidebar(shown: !collapsed, done: {})
                }
            }
        }
    }

    // MARK: Showing and hiding

    /// Whether the window can change size: not in full screen, nor zoomed to fill its screen.
    private var canResize: Bool {
        guard let window, !window.styleMask.contains(.fullScreen), window.screen != nil else { return false }
        return !window.isZoomed
    }

    /// Shows or hides the sidebar, resizing the window to keep the notes' width. Returns
    /// false if it can't (full screen, zoomed, or no split view found), leaving the caller to
    /// show or hide the sidebar without resizing. `done` runs once it has settled.
    func setSidebar(shown: Bool, done: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard canResize, let window, let item = sidebarItem, let screen = window.screen?.visibleFrame else { return false }
        // Already resized for this (the system's button started it): nothing more to do.
        if resizedForShown == shown, isResizing || frameAfterResize.map({ Self.same($0, window.frame) }) == true {
            done()
            return true
        }
        resizedForShown = shown
        if let frameAfterResize, !Self.same(frameAfterResize, window.frame) {
            adjustment = 0
            slide = 0
        }
        let wasCollapsed = item.isCollapsed
        // The sidebar's width: as it shows now if it's showing (or about to hide, from the
        // system's button, which collapses it first), else as it last showed. A collapsed
        // sidebar keeps its width, so that's known even before it has shown here.
        let kept = item.viewController.view.frame.width
        let width: CGFloat
        if shown {
            width = sidebarWidth ?? (kept > 1 ? kept : 240)
        } else {
            width = shownSidebarWidth ?? sidebarWidth ?? (kept > 1 ? kept : 240)
            sidebarWidth = width
        }

        var frame = window.frame
        var newAdjustment: CGFloat = 0, newSlide: CGFloat = 0
        if shown {
            frame.size.width += width + adjustment
            if frame.width > screen.width {
                newAdjustment = frame.width - screen.width
                frame.size.width = screen.width
            }
            // Slide left to stay on the screen (never past its left edge).
            if frame.maxX > screen.maxX {
                let x = max(screen.minX, screen.maxX - frame.width)
                newSlide = frame.minX - x
                frame.origin.x = x
            }
        } else {
            frame.size.width += adjustment - width
            if frame.width < Self.minimumWidth.hidden {
                newAdjustment = frame.width - Self.minimumWidth.hidden
                frame.size.width = Self.minimumWidth.hidden
            }
            // Back to where it was before sliding, as far as the screen allows.
            frame.origin.x = min(frame.minX + slide, screen.maxX - frame.width)
        }
        Trace.mark("sidebar \(shown ? "show" : "hide"): width \(width), window \(window.frame) → \(frame), adjustment \(newAdjustment), slide \(newSlide)")
        // The window's minimum width is the one for the sidebar it's leaving until SwiftUI
        // catches up; it mustn't stop the resize.
        if window.minSize.width > frame.width { window.minSize.width = frame.width }

        isResizing = true
        resizeCount += 1
        let count = resizeCount
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.resizeCount == count, self.isResizing else { return }
            self.settle(shown: shown, expectedWidth: width, adjustment: newAdjustment, slide: newSlide)
            done()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
            if wasCollapsed == shown { item.animator().isCollapsed = !shown }
        } completionHandler: {
            MainActor.assumeIsolated { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.15) {
            // Not yet settled (the animation hasn't run): put the window where it should be.
            guard self.resizeCount == count, self.isResizing else { return }
            Trace.mark("sidebar resize didn't complete; setting the frame")
            window.setFrame(frame, display: true)
            finish()
        }
        return true
    }

    /// After showing, corrects the window by any difference between the width used and the
    /// sidebar's real one (it can't be narrower than its minimum, say), so the notes end
    /// exactly as wide as they were.
    private func settle(shown: Bool, expectedWidth: CGFloat, adjustment newAdjustment: CGFloat, slide newSlide: CGFloat) {
        defer {
            isResizing = false
            frameAfterResize = window?.frame
        }
        adjustment = newAdjustment
        slide = newSlide
        guard shown, let window, let actual = shownSidebarWidth, let screen = window.screen?.visibleFrame else { return }
        sidebarWidth = actual
        let difference = actual - expectedWidth
        guard abs(difference) >= 1 else { return }
        var frame = window.frame
        frame.size.width += difference
        if frame.width > screen.width {
            adjustment += frame.width - screen.width
            frame.size.width = screen.width
        }
        if frame.maxX > screen.maxX {
            let x = max(screen.minX, screen.maxX - frame.width)
            slide += frame.minX - x
            frame.origin.x = x
        }
        Trace.mark("sidebar settle: real width \(actual), correcting by \(difference)")
        window.setFrame(frame, display: true)
    }

    /// Frames equal to within half a point (AppKit rounds them).
    private static func same(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}
