import AppKit
import SwiftUI

/// A SwiftUI view inside a note's text (the header, a list block): one that scrolls with it.
/// As a note scrolls, AppKit tells every view in it that its safe area changed, as it moves
/// under the window's bars; a plain hosting view then asks for an update, and that laid out
/// the whole window again on every frame of scrolling. Nothing inside a note uses the safe
/// area (the note's own insets keep its text clear of the bars), so the news is let go.
final class InNoteHostingView<Content: View>: NSHostingView<Content> {
    override func willChangeValue(forKey key: String) {
        guard !Self.ignores(key) else { return }
        super.willChangeValue(forKey: key)
    }

    override func didChangeValue(forKey key: String) {
        guard !Self.ignores(key) else { return }
        super.didChangeValue(forKey: key)
    }

    private static func ignores(_ key: String) -> Bool {
        key.hasPrefix("safeArea")
    }
}
