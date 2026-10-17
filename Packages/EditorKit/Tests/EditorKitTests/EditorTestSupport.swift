import AppKit
@testable import EditorKit

@MainActor
enum EditorTestSupport {
    /// An editor holding `markdown`, laid out at a fixed size in an offscreen window.
    static func makeEditor(_ markdown: String, width: CGFloat = 760, height: CGFloat = 1400) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        scrollView.frame = window.contentView!.bounds
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        textView.load(markdown)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return textView
    }

    /// Draws the editor to a PNG, for looking at the rendering.
    static func snapshot(_ textView: MarkdownTextView, to url: URL, appearance: NSAppearance.Name = .aqua) throws {
        textView.appearance = NSAppearance(named: appearance)
        let used = textView.layoutManager!.usedRect(for: textView.textContainer!)
        let height = min(used.height + textView.textContainerInset.height * 2, textView.frame.height)
        let bounds = NSRect(x: 0, y: 0, width: textView.frame.width, height: height)
        let rep = textView.bitmapImageRepForCachingDisplay(in: bounds)!
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            textView.cacheDisplay(in: bounds, to: rep)
        }
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
