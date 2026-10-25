import AppKit
import EditorKit
import SwiftUI

/// The window's sidebar and notes, side by side, in an AppKit split view that Point owns.
///
/// Showing or hiding the sidebar by hand changes the window's width, not the notes': the
/// window grows rightwards by the sidebar's width (its left edge stays) and shrinks back when
/// it hides. That's one native animation of the window's frame. While it runs, the split view
/// gives every change in width to the sidebar (its holding priority is lowered, and its
/// minimum width lifted), so the notes keep exactly their width and simply slide; and the
/// sidebar's contents keep their full width against the window's edge, clipped by the narrower
/// pane (see `SidebarContainer`), so the notes seem to slide over a sidebar that stays still,
/// as in Things, rather than it squashing. Nothing in
/// SwiftUI is laid out again on the way, which SwiftUI wouldn't do during a window animation.
///
/// The sidebar button is Point's own, placed on every frame just past the window buttons or
/// against the sidebar's edge, whichever is further right, as macOS places a toolbar's items
/// beside a sidebar. (The toolbar's own button moved into an overflow menu while the sidebar
/// was too narrow to hold it.) The toolbar is kept, empty, for the title bar's height.
///
/// (SwiftUI's own split view was used before, but it runs its own collapse animation beside
/// the window's, squashing the sidebar and dropping it for a frame before popping it in, and
/// puts back any change made to its split view from AppKit.)
///
/// When there isn't room, the window first slides left to stay on its screen; if it would be
/// wider than the screen, it takes the screen's width and the notes give up the rest, which
/// they get back when the sidebar hides (and a window that can't shrink below its minimum
/// gives the notes the difference until the sidebar shows again). In full screen, zoomed to
/// fill the screen, in focus mode, or when narrowing the window hid it, the window keeps its
/// size and the notes take the space.
///
/// Every resize is worked out from the sidebar's real width at the time, not a remembered
/// amount (an earlier version did that, and the window drifted whenever a resize was cut short).
@MainActor
final class SidebarSplitController: NSSplitViewController {
    let sidebarHost = NSHostingController(rootView: AnyView(EmptyView()))
    let detailHost = NSHostingController(rootView: AnyView(EmptyView()))
    private lazy var sidebarContainer = SidebarContainer(host: sidebarHost)
    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarContainer)
    /// The sidebar button, drawn by SwiftUI, placed by this.
    private lazy var sidebarButton: NSHostingView<SidebarButton> = {
        let button = NSHostingView(rootView: SidebarButton(action: { [weak self] in self?.toggleSidebar(nil) }))
        button.sizingOptions = []
        // No safe area: in the sidebar's pane, the title bar's 52 points were one, and the
        // button (made to ignore it) drew 8 points above where it was placed.
        if #available(macOS 13.3, *) { button.safeAreaRegions = [] }
        return button
    }()
    private lazy var detailItem = NSSplitViewItem(viewController: detailHost)

    /// The sidebar's narrowest, first and widest widths, for the sidebar layout in use.
    var widths: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (180, 240, 400) {
        didSet {
            guard widths != oldValue else { return }
            applyWidths()
        }
    }
    /// Where the sidebar's width is kept between launches, for the sidebar layout in use. Read
    /// again when it changes: the window sets it after the split view has loaded, which first
    /// read the width under the default key, and the window's minimum and the auto-hide width
    /// then used the wrong width.
    var widthKey = "sidebarWidth" {
        didSet {
            guard widthKey != oldValue else { return }
            applyWidths()
        }
    }

    /// Whether the sidebar is sliding in or out: SwiftUI doesn't lay anything out again during
    /// the window's animation, so views that would change on the way hold still till it ends.
    var slidingChanged: ((Bool) -> Void)?
    /// Hides the sidebar button (in focus mode, which has its own way back to the sidebar).
    var hidesSidebarButton = false {
        didSet { sidebarButton.isHidden = hidesSidebarButton }
    }
    /// The sidebar button, in place of the split view's own toggle, so it shows and hides the
    /// sidebar as ⌘S does.
    var onToggle: (() -> Void)?
    /// The narrowest each side of a split of the notes can be (see `VaultModel`).
    var notesSplitMinimums: (() -> (main: CGFloat, side: CGFloat))?
    /// The sidebar hidden (true) or shown by dragging its divider.
    var collapsedByDragging: ((Bool) -> Void)?
    /// Whether the sidebar was hidden, as last known here (set by every show or hide).
    private var reportedCollapsed: Bool?

    /// The narrowest the notes can be, so the narrowest a window can be without the sidebar.
    /// With it, the window's at least this plus the sidebar: so hiding the sidebar can always
    /// narrow the window by its whole width, and the notes keep theirs. (With a fixed minimum
    /// of 600, a window at its narrowest could only narrow to 420 as the sidebar hid, and the
    /// notes widened by 60 points.)
    static let minimumNotesWidth: CGFloat = 420
    /// The width the sidebar will show at, whenever it changes (the window's minimum follows it).
    var sidebarWidthChanged: ((CGFloat) -> Void)?
    private var reportedWidth: CGFloat?
    private static let duration: TimeInterval = 0.25

    /// While a resize or collapse is animating (the window's resize notifications are then
    /// this's own).
    private(set) var isResizing = false
    /// Counts animations, so each settles once: when it completes, or shortly after it should
    /// have (a window out of sight, or a locked screen, doesn't run its animations).
    private var animationCount = 0
    /// How much the notes' width changed when the window couldn't change by the whole sidebar
    /// (positive when it couldn't grow enough for the screen, negative when it couldn't shrink
    /// enough for its minimum), and how far the window slid left to stay on its screen: both
    /// undone at the next show or hide.
    private var adjustment: CGFloat = 0
    private var slide: CGFloat = 0
    /// The window's frame after this last resized it; if it's changed since, the person moved
    /// or resized the window, and the adjustment and slide no longer apply.
    private var frameAfterResize: NSRect?
    /// The split view's own holding priorities, put back after each resize. (Kept from the
    /// start: read at each resize, one begun while another ran read the resize's own.)
    private var restingPriorities = (sidebar: NSLayoutConstraint.Priority.defaultLow, detail: NSLayoutConstraint.Priority.defaultLow)

    // MARK: Setting up

    override func viewDidLoad() {
        super.viewDidLoad()
        // The split view sizes the hosted views, not the other way round.
        sidebarHost.sizingOptions = []
        detailHost.sizingOptions = []
        splitView.dividerStyle = .thin
        sidebarItem.canCollapse = true
        // Only hidden when asked: not by the split view as the window narrows.
        sidebarItem.canCollapseFromWindowResize = false
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        restingPriorities = (sidebarItem.holdingPriority, detailItem.holdingPriority)
        // Dragging the divider can't squeeze the notes below their narrowest either.
        detailItem.minimumThickness = Self.minimumNotesWidth
        applyWidths()
        NotificationCenter.default.addObserver(self, selector: #selector(splitViewResized(_:)),
                                               name: NSSplitView.didResizeSubviewsNotification, object: splitView)
        // A drag of the divider ends with the mouse's release.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.widthAtDragStart = nil
            return event
        }
    }

    private var mouseUpMonitor: Any?
    /// The sidebar's width when the divider was picked up, kept if the drag hides the sidebar:
    /// the widths it passed through on the way, down to its narrowest, were saved as it went,
    /// and it reopened at its narrowest.
    private var widthAtDragStart: CGFloat?

    override func viewDidLayout() {
        super.viewDidLayout()
        placeSidebarButton()
        placeDividerGrip()
    }

    /// Over the divider and a few points either side, above the panes: shows the resize pointer
    /// there, which the note's text area beside it otherwise took. The split view takes the
    /// drag itself (see the effective rect below).
    private lazy var dividerGrip: ResizeGrip = {
        let grip = ResizeGrip()
        grip.passesClicksThrough = true
        return grip
    }()

    private func placeDividerGrip() {
        let shows = !sidebarItem.isCollapsed && !isResizing
        dividerGrip.isHidden = !shows
        guard shows else { return }
        if dividerGrip.superview !== splitView || splitView.subviews.last !== dividerGrip {
            splitView.addSubview(dividerGrip, positioned: .above, relativeTo: nil)
        }
        let edge = sidebarContainer.view.convert(sidebarContainer.view.bounds, to: splitView).maxX
        let frame = NSRect(x: (edge - ResizeGrip.width / 2).rounded(), y: 0, width: ResizeGrip.width, height: splitView.bounds.height)
        if dividerGrip.frame != frame {
            dividerGrip.frame = frame
            splitView.window?.invalidateCursorRects(for: dividerGrip)
        }
    }

    /// The divider takes the pointer (showing the resize pointer) and a drag a few points either
    /// side of its line: its own area was a point or two.
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        drawnRect.insetBy(dx: -ResizeGrip.width / 2, dy: 0)
    }

    /// Just past the window buttons, or against the sidebar's edge, whichever is further right;
    /// level with the window buttons. Against the edge, it's in the sidebar's pane, pinned to its
    /// right edge, so it moves in the same layout as the sidebar (placed from outside, it ran a
    /// frame behind, over the bar beside it); past the window buttons, it's in the window's frame
    /// view, above everything. It moves from one to the other where the two places meet.
    private func placeSidebarButton() {
        guard let window = view.window, let frameView = window.contentView?.superview,
              let zoom = window.standardWindowButton(.zoomButton),
              let close = window.standardWindowButton(.closeButton) else { return }
        let size = NSSize(width: 36, height: 36)
        let fixedX = (zoom.convert(zoom.bounds, to: nil).maxX + 16).rounded()
        let middle = close.convert(close.bounds, to: nil).midY
        let pane = sidebarContainer.view
        let edge = sidebarItem.isCollapsed ? 0 : pane.convert(pane.bounds, to: nil).maxX
        let againstEdge = (edge - 8 - size.width).rounded()
        if againstEdge > fixedX {
            if sidebarButton.superview !== pane || pane.subviews.last !== sidebarButton {
                pane.addSubview(sidebarButton, positioned: .above, relativeTo: nil)
            }
            sidebarButton.autoresizingMask = [.minXMargin, .minYMargin]
            let inWindow = NSRect(x: againstEdge, y: (middle - size.height / 2).rounded(), width: size.width, height: size.height)
            sidebarButton.frame = pane.convert(inWindow, from: nil)
        } else {
            if sidebarButton.superview !== frameView || frameView.subviews.last !== sidebarButton {
                frameView.addSubview(sidebarButton, positioned: .above, relativeTo: nil)
            }
            sidebarButton.autoresizingMask = []
            let inWindow = NSRect(x: fixedX, y: (middle - size.height / 2).rounded(), width: size.width, height: size.height)
            sidebarButton.frame = frameView.convert(inWindow, from: nil)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installToolbar()
        // At its width now the window has its size: set while the window was first laid out,
        // small, the split view squeezed it to its narrowest, and it stayed so.
        if !sidebarItem.isCollapsed, !isResizing { splitView.setPosition(savedWidth, ofDividerAt: 0) }
    }

    private func applyWidths() {
        guard isViewLoaded else { return }
        sidebarItem.minimumThickness = widths.min
        sidebarItem.maximumThickness = widths.max
        if sidebarItem.isCollapsed { rest() } else { splitView.setPosition(savedWidth, ofDividerAt: 0) }
        reportWidth()
    }

    private func reportWidth() {
        let width = savedWidth
        guard width != reportedWidth else { return }
        reportedWidth = width
        sidebarWidthChanged?(width)
    }

    /// The sidebar's width as it was last left, within its limits, in whole points (the window
    /// grows and shrinks by whole points: a part of one went to the notes, which crept wider).
    private var savedWidth: CGFloat {
        let saved = UserDefaults.standard.double(forKey: widthKey)
        return min(max(saved > 0 ? saved : widths.ideal, widths.min), widths.max).rounded()
    }

    /// Shows or hides the sidebar at once, as the window opens.
    func setInitially(shown: Bool) {
        guard isViewLoaded else { return }
        sidebarItem.isCollapsed = !shown
        reportedCollapsed = !shown
        if shown { splitView.setPosition(savedWidth, ofDividerAt: 0) } else { rest() }
    }

    /// Keeps the hidden sidebar laid out at the size it will show at (see `SidebarContainer`).
    private func rest() {
        sidebarContainer.rest(at: NSSize(width: savedWidth, height: splitView.bounds.height))
    }

    /// The sidebar's width as shown now, or nil while it's hidden.
    private var shownWidth: CGFloat? {
        guard !sidebarItem.isCollapsed else { return nil }
        let width = sidebarContainer.view.frame.width.rounded()
        return width > 1 ? width : nil
    }

    /// Keeps the width the sidebar is dragged to (not the widths it passes through while
    /// sliding), to show it at next time.
    @objc private func splitViewResized(_ notification: Notification) {
        placeSidebarButton()
        placeDividerGrip()
        guard !isResizing else { return }
        let isDragging = NSEvent.pressedMouseButtons & 1 != 0
        if isDragging, widthAtDragStart == nil, !sidebarItem.isCollapsed { widthAtDragStart = savedWidth }
        // Hidden or shown by dragging the divider, not by this: the contents rest at the
        // sidebar's size while hidden, and fill it again once it's dragged open (they stayed at
        // the size they rested at, and didn't follow the divider), and the window hears of it.
        if sidebarItem.isCollapsed { rest() } else { sidebarContainer.release() }
        if sidebarItem.isCollapsed != reportedCollapsed {
            reportedCollapsed = sidebarItem.isCollapsed
            if sidebarItem.isCollapsed, let width = widthAtDragStart {
                UserDefaults.standard.set(Double(width), forKey: widthKey)
                reportWidth()
            }
            collapsedByDragging?(sidebarItem.isCollapsed)
        }
        // Only while the mouse is down (the divider being dragged): the split view also squeezes
        // the sidebar to its narrowest while the window first lays out, small, and that was kept
        // as if chosen.
        guard isDragging, let width = shownWidth, width >= widths.min else { return }
        UserDefaults.standard.set(Double(width), forKey: widthKey)
        reportWidth()
    }

    // MARK: The toolbar

    private static let toolbarID = NSToolbar.Identifier("PointSidebar")

    /// An empty toolbar, which gives the title bar its standard height. No items: any toolbar
    /// item takes the clicks meant for the bars drawn in that row.
    private func installToolbar() {
        guard let window = view.window, window.toolbar?.identifier != Self.toolbarID else { return }
        let toolbar = NSToolbar(identifier: Self.toolbarID)
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        placeSidebarButton()
        // Placed again whenever the window buttons move (as the toolbar makes the title bar
        // taller, which can come after this), and as the window resizes or comes to the front:
        // placed only once, early, it stayed at the very top of the window.
        if let close = window.standardWindowButton(.closeButton) {
            close.postsFrameChangedNotifications = true
            windowObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: close, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeSidebarButton() }
            })
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeSidebarButton() }
            })
        }
        DispatchQueue.main.async { [weak self] in self?.placeSidebarButton() }
    }

    private var windowObservers: [NSObjectProtocol] = []

    override func toggleSidebar(_ sender: Any?) {
        if let onToggle { onToggle() } else { super.toggleSidebar(sender) }
    }

    // MARK: Closing a split

    /// The notes, laid out now with one side where there were two, slide from where the side
    /// left was (its text where its text was) to where it is: one animation of the whole notes
    /// area's layer, as nothing in SwiftUI's own animations moves the editor smoothly.
    func slideNotes(fromSideOnRight onRight: Bool) {
        guard isViewLoaded, let layer = detailHost.view.layer else { return }
        let width = detailHost.view.bounds.width
        let left = SideBySide<EmptyView, EmptyView>.mainWidth(in: width, minimumWidths: notesSplitMinimums?() ?? (240, 240))
        // Where the text starts in an editor this wide (centred, past its margin).
        let column = Self.firstEditor(in: detailHost.view)?.maxTextWidth ?? 720
        func textStart(_ width: CGFloat) -> CGFloat { max(28, ((width - column) / 2).rounded()) }
        let offset = onRight ? left + 1 + textStart(width - left - 1) - textStart(width) : textStart(left) - textStart(width)
        guard abs(offset) > 1 else { return }
        // The note left on the left stays where it is (its bar too: moved, it went under the
        // window buttons), and only its text slides, from where it started in half the width.
        // The note left on the right slides across whole, from its half.
        let moving = onRight ? layer : Self.firstEditor(in: detailHost.view)?.enclosingScrollView?.layer
        guard let moving else { return }
        moving.add(Self.slide(from: offset), forKey: "splitClosed")
    }

    /// As a split opens: slides the left note's text from where it started across the whole
    /// width to where it starts in its half (if the note stays on the left), and returns how
    /// far the new right side starts from its place: from the window's edge, or for a note that
    /// moved from the left to the right, from where its text was.
    func slideForSplitOpening(leftStays: Bool) -> CGFloat? {
        guard isViewLoaded else { return nil }
        let width = detailHost.view.bounds.width
        let left = SideBySide<EmptyView, EmptyView>.mainWidth(in: width, minimumWidths: notesSplitMinimums?() ?? (240, 240))
        let column = Self.firstEditor(in: detailHost.view)?.maxTextWidth ?? 720
        func textStart(_ width: CGFloat) -> CGFloat { max(28, ((width - column) / 2).rounded()) }
        guard leftStays else { return textStart(width) - (left + 1 + textStart(width - left - 1)) }
        let offset = textStart(width) - textStart(left)
        if abs(offset) > 1, let layer = Self.firstEditor(in: detailHost.view)?.enclosingScrollView?.layer {
            layer.add(Self.slide(from: offset), forKey: "splitOpened")
        }
        return width - left - 1
    }

    /// A slide sideways from `offset` to where a view is, on the sidebar's curve and duration.
    static func slide(from offset: CGFloat) -> CABasicAnimation {
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = offset
        slide.toValue = 0
        slide.duration = duration
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return slide
    }

    private static func firstEditor(in view: NSView) -> MarkdownTextView? {
        if let editor = view as? MarkdownTextView { return editor }
        for subview in view.subviews { if let found = firstEditor(in: subview) { return found } }
        return nil
    }

    // MARK: Showing and hiding

    /// Whether the window can change size: not in full screen, nor zoomed to fill its screen
    /// (unless it fills it because showing the sidebar widened it to the screen's width).
    private var canResize: Bool {
        guard let window = view.window, !window.styleMask.contains(.fullScreen), window.screen != nil else { return false }
        return !window.isZoomed || frameAfterResize.map { Self.same($0, window.frame) } == true
    }

    /// Shows or hides the sidebar. By hand (⌘S, the button, a swipe), the window widens or
    /// narrows by the sidebar's width so the notes keep theirs; otherwise, or where the window
    /// can't resize, the notes take the space.
    func setSidebar(shown: Bool, resizingWindow: Bool) {
        guard isViewLoaded, view.window != nil else {
            if isViewLoaded { sidebarItem.isCollapsed = !shown }
            return
        }
        guard sidebarItem.isCollapsed == shown || isResizing else { return } // Already so.
        if resizingWindow, canResize { resize(shown: shown) } else { collapseInPlace(shown: shown) }
    }

    /// The sidebar slides in or out over the notes' side, the window keeping its size.
    private func collapseInPlace(shown: Bool) {
        let width = shown ? savedWidth : (shownWidth ?? savedWidth)
        let count = begin(holding: max(width, savedWidth))
        afterHolding(count) { [self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Only the collapse animates. (With implicit animation on, every frame set on
                // the way animated too, from wherever it was: the first time, views the split
                // view had just made flew in from the middle of the window.)
                sidebarItem.animator().isCollapsed = !shown
            } completionHandler: {
                MainActor.assumeIsolated { self.end(count) }
            }
        }
    }

    /// The window widens or narrows by the sidebar's width, the sidebar taking the change.
    private func resize(shown: Bool) {
        guard let window = view.window, let screen = window.screen?.visibleFrame else { return }
        if let frameAfterResize, !Self.same(frameAfterResize, window.frame) {
            adjustment = 0
            slide = 0
        }
        let width = shown ? savedWidth : (shownWidth ?? savedWidth)
        // Shown again partway through hiding, the window grows by the rest of the sidebar only.
        let partway = shown && isResizing ? (shownWidth ?? 0) : 0
        let from = window.frame
        var frame = from
        var newAdjustment: CGFloat = 0, newSlide: CGFloat = 0
        if shown {
            frame.size.width += width - partway + adjustment
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
            if frame.width < Self.minimumNotesWidth {
                newAdjustment = frame.width - Self.minimumNotesWidth
                frame.size.width = Self.minimumNotesWidth
            }
            // Back to where it was before sliding, as far as the screen allows.
            frame.origin.x = min(frame.minX + slide, screen.maxX - frame.width)
        }
        frame = frame.integral
        Trace.mark("sidebar \(shown ? "show" : "hide"): width \(width), window \(from) → \(frame), adjustment \(newAdjustment), slide \(newSlide)")

        // Its contents at the width it shows at, even when hidden partway through showing.
        let count = begin(holding: max(width, savedWidth))
        afterHolding(count) { [self] in
            // The window's minimum is the one for the sidebar it's leaving until SwiftUI catches
            // up; it mustn't stop the resize. (SwiftUI sets the content's minimum, which wins
            // over the window's: a window at its narrowest didn't move, then jumped.)
            if window.minSize.width > frame.width { window.minSize.width = frame.width }
            if window.contentMinSize.width > frame.width { window.contentMinSize.width = frame.width }
            // While it moves, a change in the window's width goes to the sidebar, down to none,
            // without the split view taking a sidebar at no width for a collapsed one.
            sidebarItem.minimumThickness = 0
            sidebarItem.canCollapse = false
            sidebarItem.holdingPriority = NSLayoutConstraint.Priority(1)
            detailItem.holdingPriority = NSLayoutConstraint.Priority(999)
            if shown, partway == 0 {
                // Opened at no width (or, when the screen is too narrow for the whole sidebar,
                // at what the notes have to give up), in the same pass, before it's drawn.
                sidebarItem.isCollapsed = false
                splitView.setPosition(newAdjustment, ofDividerAt: 0)
            }
            let finish: @MainActor @Sendable () -> Void = { [self] in
                guard animationCount == count, isResizing else { return }
                sidebarItem.holdingPriority = restingPriorities.sidebar
                detailItem.holdingPriority = restingPriorities.detail
                sidebarItem.canCollapse = true
                if shown {
                    splitView.setPosition(width, ofDividerAt: 0)
                } else {
                    sidebarItem.isCollapsed = true
                }
                sidebarItem.minimumThickness = widths.min
                adjustment = newAdjustment
                slide = newSlide
                frameAfterResize = window.frame
                end(count)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated { finish() }
            }
            // Generously late, so a slow first frame doesn't cut a running animation short.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.75) { [self] in
                // Not yet settled (the animation didn't run): put the window where it should be.
                guard animationCount == count, isResizing else { return }
                Trace.mark("sidebar resize didn't complete; setting the frame")
                window.setFrame(frame, display: true)
                finish()
            }
        }
    }

    /// Starts an animation: holds the sidebar's contents at its width while it moves.
    private func begin(holding width: CGFloat) -> Int {
        animationCount += 1
        isResizing = true
        slidingChanged?(true)
        sidebarContainer.hold(width: width)
        return animationCount
    }

    /// Runs the animation (once the held sidebar has been laid out at its width), unless
    /// another has started since.
    private func afterHolding(_ count: Int, _ work: @escaping @MainActor () -> Void) {
        guard animationCount == count else { return }
        work()
    }

    private func end(_ count: Int) {
        guard animationCount == count else { return }
        isResizing = false
        reportedCollapsed = sidebarItem.isCollapsed
        sidebarContainer.release()
        if sidebarItem.isCollapsed { rest() }
        placeDividerGrip()
        placeSidebarButton()
        slidingChanged?(false)
    }

    /// Frames equal to within half a point (AppKit rounds them).
    private static func same(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}

/// A strip over a divider that shows the resize pointer wherever it is, whatever's beneath
/// (an editor's I-beam, a list's arrow), and takes the mouse to drag the divider.
final class ResizeGrip: NSView {
    static let width: CGFloat = 10
    /// Only shows the pointer, leaving the clicks to the views beneath (a split view, which
    /// runs its own drag).
    var passesClicksThrough = false
    /// The drag: how far the pointer has moved from the press, and whether it's the press
    /// (zero) or a move.
    var onDrag: ((_ distance: CGFloat, _ isStart: Bool) -> Void)?
    private var start: CGFloat = 0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesClicksThrough ? nil : super.hitTest(point)
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow.x
        onDrag?(0, true)
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        onDrag?(event.locationInWindow.x - start, false)
    }
}

/// A `ResizeGrip` in SwiftUI.
struct ResizeGripView: NSViewRepresentable {
    let onDrag: (_ distance: CGFloat, _ isStart: Bool) -> Void

    func makeNSView(context: Context) -> ResizeGrip {
        let grip = ResizeGrip()
        grip.onDrag = onDrag
        return grip
    }

    func updateNSView(_ grip: ResizeGrip, context: Context) {
        grip.onDrag = onDrag
    }
}

/// Puts the sidebar and the notes, as SwiftUI views, in the window's `SidebarSplitController`.
struct SidebarSplitView: NSViewControllerRepresentable {
    let controller: SidebarSplitController
    let sidebar: AnyView
    let detail: AnyView
    let widths: (min: CGFloat, ideal: CGFloat, max: CGFloat)
    let widthKey: String
    let showsSidebar: Bool

    func makeNSViewController(context: Context) -> SidebarSplitController {
        _ = controller.view // Loads it.
        controller.widthKey = widthKey
        controller.widths = widths
        controller.sidebarHost.rootView = sidebar
        controller.detailHost.rootView = detail
        controller.setInitially(shown: showsSidebar)
        return controller
    }

    func updateNSViewController(_ controller: SidebarSplitController, context: Context) {
        controller.widthKey = widthKey
        controller.widths = widths
        controller.sidebarHost.rootView = sidebar
        controller.detailHost.rootView = detail
    }
}

/// The sidebar's pane: its SwiftUI view, normally filling it. While the sidebar slides, and
/// while it's hidden, the view keeps the sidebar's full width, pinned to the pane's left edge
/// (the window's), and the pane clips it: so the sidebar stays still and the notes slide over
/// it, rather than it squashing; nothing is laid out again on the way; and it's never laid
/// out at no width while hidden.
/// (It was, at first: the first time it showed after the window opened, or after changing to
/// two columns, SwiftUI laid out the whole sidebar again from nothing as it slid, and the
/// window jerked.)
@MainActor
final class SidebarContainer: NSViewController {
    private let host: NSViewController
    /// How its view is placed: filling the pane; held at the sidebar's width while it slides;
    /// or, while the sidebar's hidden, resting at the size it will show at.
    private enum Placement { case filling, held(CGFloat), resting(NSSize) }
    private var placement = Placement.filling

    init(host: NSViewController) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let view = PaneView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.placeContents = { [weak self] in self?.placeHost() }
        self.view = view
        addChild(host)
        host.view.autoresizingMask = []
        view.addSubview(host.view)
        placeHost()
    }

    /// While the sidebar's hidden: its view at the size it will show at, laid out now (out of
    /// sight) if that's changed.
    func rest(at size: NSSize) {
        if case .held = placement { return }
        placement = .resting(size)
        placeHost()
        host.view.layoutSubtreeIfNeeded()
    }

    /// Holds the sidebar's view at this width, against the pane's left edge, laid out now.
    func hold(width: CGFloat) {
        placement = .held(width)
        placeHost()
        host.view.layoutSubtreeIfNeeded()
    }

    /// Back to filling the pane.
    func release() {
        placement = .filling
        placeHost()
    }

    private func placeHost() {
        let bounds = view.bounds
        let size = switch placement {
        case .filling: bounds.size
        case .held(let width): NSSize(width: width, height: bounds.height)
        case .resting(let size): size
        }
        // Against the pane's left edge (the window's), and its top: so as the sidebar shows or
        // hides, it stays still and the notes slide over it, as in Things.
        let frame = NSRect(x: 0, y: bounds.height - size.height, width: size.width, height: size.height)
        if host.view.frame != frame { host.view.frame = frame }
    }

    /// Places its contents itself, as it's resized, frame by frame.
    private final class PaneView: NSView {
        var placeContents: (() -> Void)?
        override func resizeSubviews(withOldSize oldSize: NSSize) { placeContents?() }
    }
}

/// The sidebar button: a round glass button, as the system's was.
struct SidebarButton: View {
    let action: () -> Void

    var body: some View {
        BarButton("Sidebar", systemImage: "sidebar.left", help: "Show or Hide the Sidebar (⌘S)", action: action)
            .ignoresSafeArea() // Placed exactly, in the title bar.
    }
}
