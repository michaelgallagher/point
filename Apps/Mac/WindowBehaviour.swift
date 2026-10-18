import AppKit

/// Hides and shows the note list with a two-finger swipe: left to hide, right to show.
///
/// macOS hands a sideways two-finger swipe to the system's "swipe between pages" gesture, so
/// an app only sees its first event. Asking to track it from that event (as Safari does for
/// back and forward) delivers the rest, with its direction.
@MainActor
final class SwipeToToggleNoteList {
    private var monitor: Any?
    /// For when "swipe between pages" is turned off: follow the scroll events ourselves.
    private var travel: CGFloat = 0
    private var handled = false

    /// - Parameters:
    ///   - isNoteListShowing: whether the list is showing now, so only the useful way works.
    ///   - onSwipe: called with true for a swipe to the left.
    init(isNoteListShowing: @escaping () -> Bool, onSwipe: @escaping (_ toTheLeft: Bool) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event, isNoteListShowing: isNoteListShowing, onSwipe: onSwipe)
            return event // Never swallow scrolling.
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, isNoteListShowing: () -> Bool, onSwipe: @escaping (Bool) -> Void) {
        guard event.hasPreciseScrollingDeltas else { return } // Trackpads only, not mouse wheels.
        let sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)

        if NSEvent.isSwipeTrackingFromScrollEventsEnabled {
            guard event.phase == .began, sideways else { return }
            // Only the useful direction: left while the list shows, right while it's hidden.
            // (A positive gesture amount is a swipe to the right.)
            let showing = isNoteListShowing()
            Trace.mark("swipe tracking started, list showing \(showing)")
            var fired = false
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                                  dampenAmountThresholdMin: showing ? -1 : 0,
                                  max: showing ? 0 : 1) { amount, phase, isComplete, stop in
                // Act as soon as the swipe is clearly under way, not when it (and macOS's settling
                // animation) has finished, and stop tracking there.
                guard !fired, abs(amount) > 0.1 else { return }
                fired = true
                stop.pointee = true
                Trace.mark("swipe fired: amount \(amount), phase \(phase.rawValue)")
                onSwipe(amount < 0)
            }
            return
        }

        // Without system swipe tracking, follow the scroll events.
        switch event.phase {
        case .began, .mayBegin, .ended, .cancelled:
            travel = 0
            handled = false
        case .changed:
            guard sideways, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 2 else { return }
            travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if !handled, abs(travel) > 70 {
                handled = true
                onSwipe(travel < 0)
            }
        default:
            break
        }
    }
}

/// Narrows or widens the window by the note list's width as it hides or shows, so the text
/// keeps its width and slides over rather than stretching.
@MainActor
enum NoteListWindowResizing {
    /// The key window's width.
    static var windowWidth: CGFloat {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.frame.width ?? 0
    }

    /// Widens (positive) or narrows (negative) the window by `change` points.
    static func resize(by change: CGFloat) {
        guard abs(change) > 1, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var frame = window.frame
        frame.size.width = max(frame.width + change, window.minSize.width)
        if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - frame.width) // Stay on screen when widening.
        }
        // Quick, and in step with the note list's own animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}
