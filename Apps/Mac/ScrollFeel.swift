#if DEBUG
import AppKit
import EditorKit
import QuartzCore

/// `-PointScrollFeel <note ID>`: opens that note and scrolls it with a two-finger flick on the
/// trackpad, handed to the note's text view on the main queue as the window would (the fingers moving, then the
/// momentum, at 120 events a second, whether or not the app keeps up), or with
/// `-PointScrollWheel YES`, a mouse wheel's notches. Traces how far it should have gone and
/// how far it went, and how often a frame came late, then quits.
@MainActor
enum ScrollFeel {
    static func runIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointScrollFeel") else { return }
        let wheel = UserDefaults.standard.bool(forKey: "PointScrollWheel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.selection = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { start(in: model, wheel: wheel) }
        }
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
    }

    private static func start(in model: VaultModel, wheel: Bool) {
        guard let window = model.window, let content = window.contentView,
              let scrollView = scrollViews(in: content).first(where: { $0.documentView is MarkdownTextView }) else {
            Trace.mark("scroll feel: no editor"); return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let clip = scrollView.contentView
        let middle = window.convertPoint(toScreen: scrollView.convert(NSPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil))
        let location = CGPoint(x: middle.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - middle.y)

        // (delta, scroll phase, momentum phase, line units)
        var steps: [(Int32, Int64, Int64)] = []
        if UserDefaults.standard.bool(forKey: "PointScrollSmooth") {
            // A trackpad's smooth scrolling without its phases: each event taken as it comes.
            steps = Array(repeating: (-12, 0, 0), count: 240)
        } else if wheel {
            steps = Array(repeating: (-3, 0, 0), count: max(UserDefaults.standard.integer(forKey: "PointScrollNotches"), 24))
        } else {
            steps.append((-4, 1, 0)) // began
            steps += Array(repeating: (-24, 2, 0), count: 12) // changed
            steps.append((0, 4, 0)) // ended
            var speed = 40.0
            steps.append((-Int32(speed), 0, 1)) // momentum began
            while speed >= 1 {
                speed *= 0.955
                steps.append((-Int32(speed.rounded()), 0, 2))
            }
            steps.append((0, 0, 3)) // momentum ended
        }
        let expected = steps.reduce(0) { $0 + Int(-$1.0) }
        let watcher = FrameWatcher(clip: clip)
        let link = content.displayLink(target: watcher, selector: #selector(FrameWatcher.tick(_:)))
        link.add(to: .main, forMode: .common)
        let startY = clip.bounds.minY
        let windowNumber = window.windowNumber
        let gap = wheel && !UserDefaults.standard.bool(forKey: "PointScrollSmooth") ? 1.0 / 20 : 1.0 / 120
        Trace.mark("scroll feel: \(wheel ? "wheel" : "trackpad"), \(steps.count) events, from \(startY)")
        // Posted off the main thread at a steady rate, as the hardware sends them.
        DispatchQueue.global(qos: .userInteractive).async {
            var next = CACurrentMediaTime()
            for step in steps {
                let event = CGEvent(scrollWheelEvent2Source: nil, units: wheel && !UserDefaults.standard.bool(forKey: "PointScrollSmooth") ? .line : .pixel, wheelCount: 1, wheel1: step.0, wheel2: 0, wheel3: 0)
                if UserDefaults.standard.bool(forKey: "PointScrollSmooth") {
                    event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                } else if !wheel {
                    event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: step.1)
                    event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: step.2)
                }
                event?.location = location
                event?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowNumber))
                event?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowNumber))
                
                if let event, let nsEvent = NSEvent(cgEvent: event) {
                    nonisolated(unsafe) let posted = nsEvent, target = scrollView
                    // To the view under the pointer, as the window's hit test sends it: the
                    // text, or with `-PointScrollOverList YES`, a list block's table.
                    DispatchQueue.main.async { MainActor.assumeIsolated { receiver(in: target).scrollWheel(with: posted) } }
                }
                next += gap
                let wait = next - CACurrentMediaTime()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps.count) * gap + 1.5) {
            link.invalidate()
            let moved = clip.bounds.minY - startY
            let intervals = zip(watcher.frames.dropFirst(), watcher.frames).map { ($0.0.time - $0.1.time) * 1000 }
            let moving = zip(watcher.frames.dropFirst(), watcher.frames).filter { $0.0.y != $0.1.y }.count
            let late = intervals.filter { $0 > 12 }.count
            let stalls = watcher.frames.indices.dropFirst().filter { i in
                watcher.frames[i].y == watcher.frames[i - 1].y && i + 1 < watcher.frames.count && watcher.frames[i + 1].y != watcher.frames[i].y
            }.count
            Trace.mark(String(format: "scroll feel: expected %d, moved %.0f; %d frames, %d moving, %d late (>12 ms), longest %.1f ms, %d stalls mid-scroll; slowest handler %.1f ms",
                              expected, moved, watcher.frames.count, moving, late, intervals.max() ?? 0, stalls, watcher.slowest))
            NSApp.terminate(nil)
        }
    }

    static func receiver(in scrollView: NSScrollView) -> NSView {
        guard UserDefaults.standard.bool(forKey: "PointScrollOverList"), let text = scrollView.documentView else { return scrollView.documentView! }
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for sub in view.subviews { if let found = table(in: sub) { return found } }
            return nil
        }
        return table(in: text) ?? text
    }

    /// Each frame's time and where the note was scrolled to.
    final class FrameWatcher: NSObject {
        let clip: NSClipView
        var frames: [(time: CFTimeInterval, y: CGFloat)] = []
        var slowest: Double = 0
        private var observer: CFRunLoopObserver?

        init(clip: NSClipView) {
            self.clip = clip
            super.init()
            // How long the main thread is busy between waits: a slow scroll step shows here.
            var began = CACurrentMediaTime()
            observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
                let now = CACurrentMediaTime()
                if activity == .afterWaiting { began = now } else {
                    let spent = (now - began) * 1000
                    self?.slowest = max(self?.slowest ?? 0, spent)
                    if spent > 30 { Trace.mark(String(format: "scroll feel: busy chunk %.0f ms", spent)) }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        @objc func tick(_ link: CADisplayLink) {
            frames.append((link.timestamp, clip.bounds.minY))
        }
    }
}
#endif

#if DEBUG
/// `-PointScrollTrace YES` (with `-PointTrace <file>`): records real scrolling of notes, a
/// gesture at a time (the note moving, until it rests for a quarter of a second): how many
/// frames it moved in, and each slow one (over 25 ms since the last move), with what the main
/// thread did in it: laying out (and which views needed it), drawing, updating tracking areas,
/// and anything else. For finding what makes scrolling stick.
@MainActor
enum ScrollTrace {
    struct Gesture {
        var start: CFTimeInterval
        var startY: CGFloat
        var lastMove: CFTimeInterval
        var moves = 0
        var slow: [String] = []
        var worst: Double = 0
    }

    /// Time spent in each kind of work since the last move.
    static var layout: Double = 0, display: Double = 0, tracking: Double = 0, constraints: Double = 0
    static var laidOut: [String: Int] = [:]
    static var busy: Double = 0
    static var gesture: Gesture?
    static var clip: NSClipView?
    static var ending: DispatchWorkItem?
    static var whyCount = 0

    static func startIfAsked() {
        guard UserDefaults.standard.bool(forKey: "PointScrollTrace") else { return }
        swap(NSWindow.self, #selector(NSWindow.layoutIfNeeded), #selector(NSWindow.point_tracedLayoutIfNeeded))
        swap(NSWindow.self, #selector(NSWindow.displayIfNeeded), #selector(NSWindow.point_tracedDisplayIfNeeded))
        swap(NSWindow.self, #selector(NSWindow.updateConstraintsIfNeeded), #selector(NSWindow.point_tracedUpdateConstraintsIfNeeded))
        if let manager = NSClassFromString("_NSTrackingAreaAKManager") {
            let selector = NSSelectorFromString("displayCycleUpdateStructuralRegions")
            if let original = class_getInstanceMethod(manager, selector),
               let traced = class_getInstanceMethod(NSObject.self, #selector(NSObject.point_tracedUpdateStructuralRegions)) {
                class_addMethod(manager, #selector(NSObject.point_tracedUpdateStructuralRegions), method_getImplementation(traced), method_getTypeEncoding(traced))
                method_exchangeImplementations(original, class_getInstanceMethod(manager, #selector(NSObject.point_tracedUpdateStructuralRegions))!)
            }
        }
        if UserDefaults.standard.bool(forKey: "PointScrollWhy") {
            swap(NSView.self, #selector(setter: NSView.needsLayout), #selector(NSView.point_tracedSetNeedsLayout(_:)))
        }
        // How long the main thread works between waits.
        var began = CACurrentMediaTime()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { began = now } else { MainActor.assumeIsolated { busy += (now - began) * 1000 } }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: nil) { note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let changed = object as? NSClipView, changed.documentView is MarkdownTextView else { return }
                moved(changed)
            }
        }
        Trace.mark("scroll trace: on")
    }

    private static func swap(_ cls: AnyClass, _ a: Selector, _ b: Selector) {
        method_exchangeImplementations(class_getInstanceMethod(cls, a)!, class_getInstanceMethod(cls, b)!)
    }

    static func moved(_ changed: NSClipView) {
        let now = CACurrentMediaTime()
        if var g = gesture, changed === clip {
            let gap = (now - g.lastMove) * 1000
            if gap > 25 {
                let other = max(busy - layout - display - tracking - constraints, 0)
                let views = laidOut.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
                g.slow.append(String(format: "%.0f ms (busy %.0f: layout %.0f, display %.0f, tracking %.0f, constraints %.0f, other %.0f%@)",
                                     gap, busy, layout, display, tracking, constraints, other, views.isEmpty ? "" : "; laid out: " + views))
                g.worst = max(g.worst, gap)
            }
            g.lastMove = now
            g.moves += 1
            gesture = g
        } else {
            if gesture != nil { finish() }
            clip = changed
            gesture = Gesture(start: now, startY: changed.bounds.minY, lastMove: now)
        }
        layout = 0; display = 0; tracking = 0; constraints = 0; busy = 0; laidOut = [:]
        ending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { finish() } }
        ending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    static func finish() {
        guard let g = gesture else { return }
        gesture = nil
        let moved = (clip?.bounds.minY ?? 0) - g.startY
        let seconds = g.lastMove - g.start
        Trace.mark(String(format: "scroll trace: %.2fs, moved %.0f in %d frames (%.0f a second), %d slow, worst %.0f ms", seconds, moved, g.moves, seconds > 0 ? Double(g.moves) / seconds : 0, g.slow.count, g.worst))
        for line in g.slow { Trace.mark("scroll trace:   slow frame " + line) }
    }

    /// The views in a window waiting to be laid out, named by their class and where they are.
    static func noteViewsNeedingLayout(in window: NSWindow) {
        func visit(_ view: NSView, _ path: String) {
            let name = String(describing: type(of: view))
            let short = name.count > 60 ? String(name.prefix(60)) + "…" : name
            if view.needsLayout { laidOut[(path.isEmpty ? "" : path + " > ") + short, default: 0] += 1 }
            let here = view is MarkdownTextView ? "MarkdownTextView" : view is NSScrollView ? path : path
            for sub in view.subviews { visit(sub, here) }
        }
        if let frame = window.contentView?.superview { visit(frame, "") }
    }
}

extension NSView {
    /// Swapped for `needsLayout`'s setter with `-PointScrollWhy YES`: says, a few times, what
    /// marks the note's header as needing layout while a note scrolls.
    @objc dynamic func point_tracedSetNeedsLayout(_ flag: Bool) {
        point_tracedSetNeedsLayout(flag)
        guard flag, String(describing: type(of: self)).contains("NoteHeaderHost") else { return }
        MainActor.assumeIsolated {
            guard let g = ScrollTrace.gesture, g.moves > 3, ScrollTrace.whyCount < 2 else { return }
            ScrollTrace.whyCount += 1
            Trace.mark("scroll trace: header needs layout, from:\n" + Thread.callStackSymbols.prefix(28).joined(separator: "\n"))
        }
    }
}

extension NSWindow {
    @objc dynamic func point_tracedLayoutIfNeeded() {
        let start = CACurrentMediaTime()
        MainActor.assumeIsolated { if ScrollTrace.gesture != nil { ScrollTrace.noteViewsNeedingLayout(in: self) } }
        point_tracedLayoutIfNeeded()
        let spent = (CACurrentMediaTime() - start) * 1000
        MainActor.assumeIsolated { ScrollTrace.layout += spent }
    }

    @objc dynamic func point_tracedDisplayIfNeeded() {
        let start = CACurrentMediaTime()
        point_tracedDisplayIfNeeded()
        let spent = (CACurrentMediaTime() - start) * 1000
        MainActor.assumeIsolated { ScrollTrace.display += spent }
    }

    @objc dynamic func point_tracedUpdateConstraintsIfNeeded() {
        let start = CACurrentMediaTime()
        point_tracedUpdateConstraintsIfNeeded()
        let spent = (CACurrentMediaTime() - start) * 1000
        MainActor.assumeIsolated { ScrollTrace.constraints += spent }
    }
}

extension NSObject {
    /// Swapped in for AppKit's tracking-area update, each display cycle.
    @objc func point_tracedUpdateStructuralRegions() {
        let start = CACurrentMediaTime()
        point_tracedUpdateStructuralRegions()
        let spent = (CACurrentMediaTime() - start) * 1000
        MainActor.assumeIsolated { ScrollTrace.tracking += spent }
    }
}
#endif
