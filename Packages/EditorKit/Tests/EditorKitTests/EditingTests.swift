import AppKit
import Testing
@testable import EditorKit

/// An editor holding `markdown`, with the selection given by `|` (cursor) or `‹` … `›`
/// (a selected range) in the text.
@MainActor
private func editor(_ marked: String) -> MarkdownTextView {
    var text = marked
    var selection = NSRange(location: 0, length: 0)
    if let bar = text.range(of: "|") {
        selection.location = (String(text[..<bar.lowerBound]) as NSString).length
        text.removeSubrange(bar)
    } else if let open = text.range(of: "‹"), let close = text.range(of: "›") {
        let start = (String(text[..<open.lowerBound]) as NSString).length
        let end = (String(text[..<close.lowerBound]) as NSString).length - 1
        text.removeSubrange(close)
        text.removeSubrange(open)
        selection = NSRange(location: start, length: end - start)
    }
    let view = EditorTestSupport.makeEditor(text, height: 400)
    view.setSelectionDirectly(selection)
    return view
}

/// The editor's text with the selection marked the same way.
@MainActor
private func marked(_ view: MarkdownTextView) -> String {
    let text = NSMutableString(string: view.string)
    let selection = view.selectedRange()
    if selection.length == 0 {
        text.insert("|", at: selection.location)
    } else {
        text.insert("›", at: NSMaxRange(selection))
        text.insert("‹", at: selection.location)
    }
    return text as String
}

@MainActor
struct InlineFormattingTests {
    @Test func boldWrapsTheSelection() {
        let view = editor("make ‹this› bold")
        view.toggleBold(nil)
        #expect(marked(view) == "make **‹this›** bold")
        view.toggleBold(nil)
        #expect(marked(view) == "make ‹this› bold")
    }

    @Test func boldWithACursorWrapsTheWord() {
        let view = editor("make th|is bold")
        view.toggleBold(nil)
        #expect(view.string == "make **this** bold")
    }

    @Test func boldWithNothingToWrapInsertsAPair() {
        let view = editor("a |")
        view.toggleBold(nil)
        #expect(marked(view) == "a **|**")
        view.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "a **b**")
        #expect(view.tokens.contains { $0.kind == .strong })
    }

    @Test func selectionsAreTrimmedOfSpaces() {
        let view = editor("a‹ word ›b")
        view.toggleItalic(nil)
        #expect(view.string == "a *word* b")
    }

    @Test func highlightAndStrikethrough() {
        let view = editor("‹x›")
        view.toggleHighlight(nil)
        #expect(view.string == "==x==")
        let other = editor("‹y›")
        other.toggleStrikethrough(nil)
        #expect(other.string == "~~y~~")
    }

    @Test func headerSitsAboveTheText() {
        let view = EditorTestSupport.makeEditor("Some text")
        let origin = view.textContainerOrigin.y
        view.sizeToFit()
        let height = view.frame.height
        view.headerView = NSView()
        view.headerHeight = 120
        #expect(view.textContainerOrigin.y == origin + 120)
        // Shown through a clip as tall as the header; the header itself is taller (see `layoutHeader`).
        #expect(view.headerView?.superview?.frame.height == 120)
        #expect(view.headerView?.frame.width == view.bounds.width)
        #expect(view.frame.height >= height + 120 || view.frame.height >= view.minSize.height)
    }

    @Test func undoRestoresTheText() {
        let view = editor("make ‹this› bold")
        view.toggleBold(nil)
        view.undoManager?.undo()
        #expect(view.string == "make this bold")
    }
}

@MainActor
struct LineFormattingTests {
    @Test func headingsToggle() {
        let view = editor("Tit|le")
        view.makeHeading2(nil)
        #expect(marked(view) == "## Tit|le")
        view.makeHeading1(nil)
        #expect(marked(view) == "# Tit|le")
        view.makeHeading1(nil)
        #expect(marked(view) == "Tit|le")
    }

    @Test func aHeadingReplacesAListMarker() {
        let view = editor("- it|em")
        view.makeHeading3(nil)
        #expect(view.string == "### item")
    }

    @Test func listsToggleOverSeveralLines() {
        let view = editor("‹a\nb›")
        view.toggleBulletList(nil)
        #expect(view.string == "- a\n- b")
        view.toggleBulletList(nil)
        #expect(view.string == "a\nb")
    }

    @Test func checklistReplacesABullet() {
        let view = editor("- it|em")
        view.toggleChecklist(nil)
        #expect(marked(view) == "- [ ] it|em")
    }

    @Test func movingLinesUpAndDown() {
        let view = editor("one\ntw|o\nthree")
        view.moveLinesUp(nil)
        #expect(marked(view) == "tw|o\none\nthree")
        view.moveLinesUp(nil) // Already first: nothing changes.
        #expect(marked(view) == "tw|o\none\nthree")
        view.moveLinesDown(nil)
        view.moveLinesDown(nil) // Past the last line, which has no line break.
        #expect(marked(view) == "one\nthree\ntw|o")
        view.moveLinesUp(nil)
        #expect(marked(view) == "one\ntw|o\nthree")
        view.undoManager?.undo() // In a test, the moves are one undo group.
        #expect(view.string == "one\ntwo\nthree")
    }

    @Test func movingSelectedLines() {
        let view = editor("a\nb\nc\nd|")
        // Select from inside "b" to the start of "d": "b" and "c" move, "d" stays.
        view.setSelectedRange(NSRange(location: 2, length: 4))
        view.moveLinesDown(nil)
        #expect(view.string == "a\nd\nb\nc")
        #expect(view.selectedRange() == NSRange(location: 4, length: 3)) // "b\nc", now last.
    }

    @Test func indentAndOutdent() {
        let view = editor("- a\n- b|")
        view.indentLines(nil)
        #expect(marked(view) == "- a\n\t- b|")
        view.outdentLines(nil)
        #expect(marked(view) == "- a\n- b|")
    }

    @Test func tabIndentsListItemsOnly() {
        let view = editor("- b|")
        view.insertTab(nil)
        #expect(view.string == "\t- b")
        let plain = editor("b|")
        plain.insertTab(nil)
        #expect(plain.string == "b\t")
    }
}

@MainActor
struct ReturnKeyTests {
    @Test func continuesBullets() {
        let view = editor("- a|")
        view.insertNewline(nil)
        #expect(marked(view) == "- a\n- |")
    }

    @Test func continuesNumbers() {
        let view = editor("1. a|")
        view.insertNewline(nil)
        #expect(marked(view) == "1. a\n2. |")
    }

    @Test func continuesTasksUnticked() {
        let view = editor("- [x] a|")
        view.insertNewline(nil)
        #expect(marked(view) == "- [x] a\n- [ ] |")
    }

    @Test func anEmptyItemEndsTheList() {
        let view = editor("- a\n- |")
        view.insertNewline(nil)
        #expect(marked(view) == "- a\n|")
    }

    @Test func anEmptyNestedItemOutdents() {
        let view = editor("- a\n\t- |")
        view.insertNewline(nil)
        #expect(marked(view) == "- a\n- |")
    }

    @Test func continuesQuotes() {
        let view = editor("> a|")
        view.insertNewline(nil)
        #expect(marked(view) == "> a\n> |")
    }

    @Test func plainLinesAreUnaffected() {
        let view = editor("a|")
        view.insertNewline(nil)
        #expect(marked(view) == "a\n|")
    }
}

@MainActor
struct HiddenMarkerTests {
    @Test func backspaceDeletesTheVisibleCharacter() {
        let view = editor("**bold**|")
        view.deleteBackward(nil)
        #expect(view.string == "**bol**")
    }

    @Test func backspaceAtTheStartOfAHeadingRemovesIt() {
        let view = editor("# |Title")
        view.deleteBackward(nil)
        #expect(marked(view) == "|Title")
    }

    @Test func backspaceAtTheStartOfAListItemRemovesTheBullet() {
        let view = editor("- |item")
        view.deleteBackward(nil)
        #expect(marked(view) == "|item")
    }

    @Test func deleteForwardSkipsMarkers() {
        let view = editor("|**bold**")
        view.deleteForward(nil)
        #expect(view.string == "**old**")
    }

    @Test func deletingAllVisibleTextTakesTheMarkers() {
        let view = editor("a **‹bold›** b")
        view.deleteBackward(nil)
        #expect(view.string == "a  b")
    }

    @Test func theCursorNeverStopsInsideMarkers() {
        let view = editor("a **bold** b")
        // Arrowing right from just before the markers lands after them.
        view.setSelectionDirectly(NSRange(location: 2, length: 0))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(view.selectedRange().location == 4)
        // Arrowing left into the closing markers lands before them.
        view.setSelectionDirectly(NSRange(location: 10, length: 0))
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(view.selectedRange().location == 8)
    }

    @Test func markersAreHiddenAndTextIsNot() {
        let view = EditorTestSupport.makeEditor("**b** [[Note|shown]]", height: 400) // `|` is literal here.
        let hidden = (0..<(view.string as NSString).length).filter(view.isHidden)
        let visible = (view.string as NSString).length - hidden.count
        #expect(hidden.count == 4 + 2 + 5 + 2)
        #expect(visible == "b shown".count)
    }
}

@MainActor
struct LinkTests {
    @Test func pastingAURLOverTextLinksIt() {
        let view = editor("see ‹Apple› now")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://apple.com", forType: .string)
        view.paste(nil)
        #expect(view.string == "see [Apple](https://apple.com) now")
    }

    @Test func pastingOtherTextReplacesAsUsual() {
        let view = editor("see ‹Apple› now")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("pears", forType: .string)
        view.paste(nil)
        #expect(view.string == "see pears now")
    }

    @Test func pastingAListItemIntoAListItemDropsItsMarker() {
        let view = editor("- one\n- |\n- three")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("- two\n", forType: .string) // As a triple-click copies it.
        view.paste(nil)
        #expect(view.string == "- one\n- two\n- three")
    }

    @Test func pastingATaskIntoATaskDropsItsCheckbox() {
        let view = editor("- [ ] |")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("  - [x] done\n", forType: .string)
        view.paste(nil)
        #expect(view.string == "- [ ] done")
    }

    @Test func pastingAListItemOutsideAListKeepsItsMarker() {
        let view = editor("text\n|")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("- two\n", forType: .string)
        view.paste(nil)
        #expect(view.string == "text\n- two\n")
    }

    @Test func blockQuoteTogglesOnTheSelectedLines() {
        let view = editor("‹one\ntwo›\nthree")
        view.toggleBlockQuote(nil)
        #expect(view.string == "> one\n> two\nthree")
        view.toggleBlockQuote(nil)
        #expect(view.string == "one\ntwo\nthree")
    }

    @Test func inlineCodeWrapsTheSelection() {
        let view = editor("call ‹run› now")
        view.toggleCode(nil)
        #expect(view.string == "call `run` now")
    }

    @Test func cuttingWithNothingSelectedCutsTheLine() {
        let view = editor("- one\n- t|wo\n- three")
        view.cut(nil)
        #expect(view.string == "- one\n- three")
        #expect(NSPasteboard.general.string(forType: .string) == "- two\n")
    }

    @Test func cuttingTheLastLineLeavesNoEmptyLine() {
        let view = editor("- one\n- tw|o")
        view.cut(nil)
        #expect(view.string == "- one")
        #expect(NSPasteboard.general.string(forType: .string) == "- two\n")
    }

    @Test func recognisesURLs() {
        #expect(MarkdownTextView.isURL("https://apple.com/x?y=1"))
        #expect(MarkdownTextView.isURL("  mailto:a@b.com\n"))
        #expect(!MarkdownTextView.isURL("apple.com"))
        #expect(!MarkdownTextView.isURL("https://a.com and more"))
    }
}
