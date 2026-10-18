import AppKit

/// Hides and shows the note list with a two-finger swipe: left to hide, right to show.
@MainActor
final class SwipeToToggleNoteList {
    private var monitor: Any?
    private var travel: CGFloat = 0
    private var handled = false
    private var lastEvent = Date.distantPast

    init(onSwipe: @escaping (_ toTheLeft: Bool) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.track(event, onSwipe: onSwipe)
            return event // Never swallow scrolling.
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func track(_ event: NSEvent, onSwipe: (Bool) -> Void) {
        guard event.hasPreciseScrollingDeltas else { return } // Trackpad gestures only, not mouse wheels.
        // Start afresh at every gesture boundary, and after any pause, so a gesture that ended
        // out of sight (say, taken over by the text view) can never leave the tracker stuck.
        if Date().timeIntervalSince(lastEvent) > 0.3 { reset() }
        lastEvent = Date()
        switch event.phase {
        case .began, .mayBegin:
            reset()
        case .ended, .cancelled:
            reset()
        case .changed:
            Trace.mark("swipe dx \(event.scrollingDeltaX) dy \(event.scrollingDeltaY) inverted \(event.isDirectionInvertedFromDevice) travel \(travel)")
            // Only clearly sideways movement counts, so vertical scrolling never hides the list.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 2 else { return }
            // Fingers moving left, whichever way the user's scrolling direction is set.
            travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if !handled, abs(travel) > 70 {
                handled = true
                Trace.mark("swipe fired: \(travel < 0 ? "left" : "right")")
                onSwipe(travel < 0)
            }
        default:
            break
        }
    }

    private func reset() {
        travel = 0
        handled = false
    }
}

/// Narrows or widens the window by the note list's width as it hides or shows, so the text
/// keeps its width and slides over rather than stretching.
@MainActor
enum NoteListWindowResizing {
    static func resize(showing: Bool, listWidth: CGFloat) {
        guard listWidth > 0, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var frame = window.frame
        let change = showing ? listWidth : -listWidth
        frame.size.width = max(frame.width + change, window.minSize.width)
        if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - frame.width) // Stay on screen when widening.
        }
        window.setFrame(frame, display: true, animate: true)
    }
}
