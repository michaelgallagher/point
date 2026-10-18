import AppKit
import Testing
@testable import EditorKit

/// Typing on a freshly made list item, with text after it (the case reported as a bug).
@MainActor
struct NewListItemTests {
    @Test(arguments: ["- a", "1. a", "- [ ] a"])
    func canTypeOnANewItem(first: String) {
        let text = first + "\nafter"
        let view = EditorTestSupport.makeEditor(text, height: 300)
        view.setSelectionDirectly(NSRange(location: (first as NSString).length, length: 0))
        view.insertNewline(nil)
        view.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string.hasSuffix("b\nafter"), "got \(view.string.debugDescription)")
    }
}
