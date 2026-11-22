import AppKit
import Testing
@testable import EditorKit

@MainActor
struct ListBlockTests {
    let note = "Some notes.\n\n```list\nfrom: Reading\nsort: title\n```\n\nMore notes.\n\n```list\n```\n"

    /// An editor drawing every `list` block `height` tall (nil: none drawn), and what it was asked.
    private func editor(_ text: String, height: CGFloat? = 200, showsMarkdown: Bool = false) -> (MarkdownTextView, [BlockEmbed]) {
        let textView = EditorTestSupport.makeEditor(text)
        var asked: [BlockEmbed] = []
        textView.showsMarkdown = showsMarkdown
        textView.makeBlockEmbedView = { _ in NSView() }
        textView.blockEmbedHeight = { embed in
            asked.append(embed)
            if case .list = embed { return height }
            return nil
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return (textView, asked)
    }

    @Test func asksForEachBlockByItsBodyAndPlace() {
        let (_, asked) = editor(note)
        #expect(Set(asked) == [.list(body: "from: Reading\nsort: title\n", index: 0), .list(body: "", index: 1)])
    }

    @Test func hidesTheBlockAndMakesRoomAboveIt() throws {
        let (textView, _) = editor(note)
        let storage = try #require(textView.textStorage)
        let ns = note as NSString
        let fence = ns.range(of: "```list")
        let decoration = try #require(storage.attribute(.pointBlockEmbed, at: fence.location, effectiveRange: nil) as? BlockEmbedDecoration)
        #expect(decoration.height == 200)
        // Every line of it is hidden and collapsed, the fences and the body.
        for word in ["```list", "from: Reading", "sort: title"] {
            let at = ns.range(of: word).location
            #expect(storage.attribute(.pointHidden, at: at, effectiveRange: nil) != nil, "\(word)")
            #expect(storage.attribute(.pointCollapsed, at: at, effectiveRange: nil) != nil, "\(word)")
        }
        #expect(storage.attribute(.pointBlock, at: ns.range(of: "from").location, effectiveRange: nil) == nil)
        // The opening fence's line holds the room.
        let layoutManager = try #require(textView.layoutManager)
        let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: fence.location), effectiveRange: nil)
        #expect(line.height > 200)
        // The text after it is still shown.
        #expect(storage.attribute(.pointHidden, at: ns.range(of: "More notes.").location, effectiveRange: nil) == nil)
    }

    @Test func aBlockTheAppDoesntDrawStaysCode() throws {
        let (textView, _) = editor(note, height: nil)
        let storage = try #require(textView.textStorage)
        let at = (note as NSString).range(of: "from: Reading").location
        #expect(storage.attribute(.pointBlockEmbed, at: (note as NSString).range(of: "```list").location, effectiveRange: nil) == nil)
        #expect(storage.attribute(.pointHidden, at: at, effectiveRange: nil) == nil)
        #expect(storage.attribute(.pointBlock, at: at, effectiveRange: nil) as? BlockDecoration == .code)
    }

    @Test func anUnclosedBlockStaysCode() throws {
        let text = "Notes.\n\n```list\nfrom: Reading\n"
        let (textView, asked) = editor(text)
        #expect(asked.allSatisfy { if case .list = $0 { false } else { true } })
        #expect(textView.textStorage?.attribute(.pointHidden, at: (text as NSString).range(of: "from").location, effectiveRange: nil) == nil)
        // Its opening fence shows as typed, until the block is closed.
        let fence = (text as NSString).range(of: "```list").location
        #expect(textView.textStorage?.attribute(.pointHidden, at: fence, effectiveRange: nil) == nil)
        #expect(textView.textStorage?.attribute(.pointCollapsed, at: fence, effectiveRange: nil) == nil)
    }

    @Test func aClosedCodeBlocksFencesAreHidden() {
        let text = "```swift\nlet a = 1\n```\n"
        let (textView, _) = editor(text)
        #expect(textView.textStorage?.attribute(.pointCollapsed, at: 0, effectiveRange: nil) != nil)
    }

    @Test func otherCodeBlocksArentLists() {
        let (_, asked) = editor("```swift\nlet a = 1\n```\n\n```List\nfrom: A\n```\n")
        #expect(asked.isEmpty)
    }

    @Test func withMarkdownShowingItsLinesShow() throws {
        let (textView, _) = editor(note, showsMarkdown: true)
        let at = (note as NSString).range(of: "from: Reading").location
        #expect(textView.textStorage?.attribute(.pointHidden, at: at, effectiveRange: nil) == nil)
    }

    // MARK: Rewriting and putting in blocks

    @Test func findsEachBlocksLines() throws {
        let (textView, _) = editor(note)
        let ns = note as NSString
        #expect(textView.listBlockBody(at: 0).map(ns.substring) == "from: Reading\nsort: title\n")
        #expect(textView.listBlockBody(at: 1).map { $0.length } == 0)
        #expect(textView.listBlockBody(at: 2) == nil)
    }

    @Test func rewritesABlockAsOneUndoableEdit() throws {
        let (textView, _) = editor(note)
        let window = textView.window // The undo manager is the window's.
        #expect(textView.replaceListBlockBody(at: 0, with: "from: Archive\n", actionName: "Change List"))
        #expect(textView.string == "Some notes.\n\n```list\nfrom: Archive\n```\n\nMore notes.\n\n```list\n```\n")
        #expect(!textView.replaceListBlockBody(at: 0, with: "from: Archive\n", actionName: "Change List"))
        #expect(textView.replaceListBlockBody(at: 1, with: "tags: [reading]\n", actionName: "Change List"))
        #expect(textView.string.hasSuffix("```list\ntags: [reading]\n```\n"))
        textView.undoManager?.undo()
        textView.undoManager?.undo()
        #expect(textView.string == note)
        _ = window
    }

    @Test func replacesAWholeBlockFencesAndAll() throws {
        let (textView, _) = editor(note)
        let window = textView.window
        let table = "| Title |\n| --- |\n| [[A]] |"
        #expect(textView.replaceListBlock(at: 0, with: table, actionName: "Convert to Table"))
        #expect(textView.string == "Some notes.\n\n\(table)\n\nMore notes.\n\n```list\n```\n")
        #expect(textView.selectedRange() == NSRange(location: ("Some notes.\n\n" + table as NSString).length, length: 0))
        // The other block is now the first.
        #expect(textView.replaceListBlock(at: 0, with: table, actionName: "Convert to Table"))
        #expect(textView.string.hasSuffix("More notes.\n\n\(table)\n"))
        #expect(!textView.replaceListBlock(at: 0, with: table, actionName: "Convert to Table"))
        textView.undoManager?.undo()
        textView.undoManager?.undo()
        #expect(textView.string == note)
        _ = window
    }

    /// Puts a list in with the cursor at `|`, and gives the text with the cursor marked.
    private func inserting(_ marked: String) -> (String, [Int]) {
        let at = (marked as NSString).range(of: "|").location
        let (textView, _) = editor(marked.replacingOccurrences(of: "|", with: ""))
        textView.setSelectedRange(NSRange(location: at, length: 0))
        var told: [Int] = []
        textView.onListBlockInserted = { told.append($0) }
        textView.insertListBlock(nil)
        let text = NSMutableString(string: textView.string)
        text.insert("|", at: textView.selectedRange().location)
        return (text as String, told)
    }

    @Test func insertsAListOnABlankLine() {
        #expect(inserting("Before\n\n|\nAfter").0 == "Before\n\n```list\n```\n|\nAfter")
        #expect(inserting("Before\n|\nAfter").0 == "Before\n\n```list\n```\n|\nAfter")
        #expect(inserting("|").0 == "```list\n```\n|")
    }

    @Test func insertsAListAfterALineOfText() {
        #expect(inserting("Some te|xt").0 == "Some text\n\n```list\n```\n|")
        #expect(inserting("Some te|xt\nAfter").0 == "Some text\n\n```list\n```\n|\nAfter")
        #expect(inserting("Some te|xt\n\nAfter").0 == "Some text\n\n```list\n```\n|\nAfter")
    }

    @Test func saysWhichBlockItPutIn() {
        #expect(inserting("|\n\n```list\n```\n").1 == [0])
        #expect(inserting("```list\n```\n\nAfter|").1 == [1])
    }
}

struct BlockEmbedViewReuseTests {
    @Test func aRewrittenBlockKeepsItsViewAndIsTold() {
        var views: [(target: BlockEmbed, view: String)] = [(.list(body: "a", index: 0), "A"), (.list(body: "b", index: 1), "B")]
        var updated: [String] = [], removed: [String] = []
        let changed = BlockEmbed.list(body: "a2", index: 0)
        #expect(blockEmbedView(&views, at: 0, for: changed, make: { "new" }, update: { view, _ in updated.append(view) }, remove: { removed.append($0) }) == "A")
        #expect(blockEmbedView(&views, at: 1, for: .list(body: "b", index: 1), make: { "new" }, update: { view, _ in updated.append(view) }, remove: { removed.append($0) }) == "B")
        #expect(views.map(\.target) == [changed, .list(body: "b", index: 1)])
        #expect(updated == ["A"])
        #expect(removed.isEmpty)
    }

    @Test func anEmbedNamingAnotherNoteGetsANewView() {
        var views: [(target: BlockEmbed, view: String)] = [(.note("X"), "X"), (.note("Y"), "Y")]
        var removed: [String] = []
        #expect(blockEmbedView(&views, at: 0, for: .note("Z"), make: { "Z" }, update: { _, _ in }, remove: { removed.append($0) }) == "Z")
        #expect(blockEmbedView(&views, at: 1, for: .note("Y"), make: { "new" }, update: { _, _ in }, remove: { removed.append($0) }) == "Y")
        #expect(views.map(\.view) == ["Z", "Y"])
        #expect(removed == ["X"])
    }

    @Test func aBlockTakenAwayTakesItsView() {
        var views: [(target: BlockEmbed, view: String)] = [(.note("X"), "X"), (.note("Y"), "Y")]
        var removed: [String] = []
        #expect(blockEmbedView(&views, at: 0, for: .note("Y"), make: { "new" }, update: { _, _ in }, remove: { removed.append($0) }) == "Y")
        #expect(removed == ["X"])
        #expect(views.map(\.view) == ["Y"])
    }
}
