import AppKit
import Testing
@testable import EditorKit

@MainActor
struct FoldingTests {
    private func location(of text: String, in view: MarkdownTextView) -> Int {
        (view.string as NSString).range(of: text).location
    }

    private func isHidden(_ text: String, in view: MarkdownTextView) -> Bool {
        let range = (view.string as NSString).range(of: text)
        return (range.location..<NSMaxRange(range)).allSatisfy(view.isHidden)
    }

    @Test func foldingAHeadingHidesItsSectionUpToTheNextHeadingAsBig() {
        let view = EditorTestSupport.makeEditor("# One\nfirst\n## Sub\nsub text\n\n# Two\nsecond")
        view.setFolded(true, line: 0)
        #expect(isHidden("first", in: view))
        #expect(isHidden("sub text", in: view))
        #expect(!isHidden("Two", in: view))
        #expect(!isHidden("second", in: view))
        #expect(view.string == "# One\nfirst\n## Sub\nsub text\n\n# Two\nsecond") // The text itself is untouched.
    }

    @Test func foldingAListItemHidesTheItemsUnderIt() {
        let view = EditorTestSupport.makeEditor("- parent\n  - child\n    - grandchild\n- sibling")
        let parent = location(of: "- parent", in: view)
        #expect(view.isFoldable(parent))
        #expect(!view.isFoldable(location(of: "- sibling", in: view)))
        view.setFolded(true, line: parent)
        #expect(isHidden("child", in: view))
        #expect(isHidden("grandchild", in: view))
        #expect(!isHidden("sibling", in: view))
    }

    @Test func unfoldingShowsTheLinesAgain() {
        let view = EditorTestSupport.makeEditor("- parent\n  - child\n- sibling")
        view.setFolded(true, line: 0)
        view.setFolded(false, line: 0)
        #expect(!isHidden("child", in: view))
        #expect(view.folds.isEmpty)
    }

    @Test func aFoldMovesWithTextTypedAboveIt() {
        let view = EditorTestSupport.makeEditor("intro\n- parent\n  - child")
        let parent = location(of: "- parent", in: view)
        view.setFolded(true, line: parent)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertText("more ", replacementRange: NSRange(location: 0, length: 0))
        #expect(view.folds == [parent + 5])
        #expect(isHidden("child", in: view))
    }

    @Test func foldCommandFoldsTheItemTheCursorIsUnder() {
        let view = EditorTestSupport.makeEditor("# Head\nsome text\nmore")
        view.setSelectedRange(NSRange(location: location(of: "some", in: view) + 2, length: 0))
        view.foldLine(nil)
        #expect(view.folds == [0])
        #expect(isHidden("some text", in: view))
        // The cursor leaves the hidden lines for the folded one.
        #expect(view.selectedRange().location == 6)
    }
}
