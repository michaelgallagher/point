import AppKit
import Testing
@testable import EditorKit

/// The iPhone's rules around hidden Markdown against the Mac's: from the same text and cursor,
/// each must end up where `MarkdownTextView` does.
@MainActor
struct HiddenMarkersTests {
    nonisolated static let notes = [
        "plain text",
        "# Heading\nbody",
        "text\n## Heading",
        "- one\n- two",
        "\t- nested",
        "- [ ] a task\n- [x] done",
        "1. first\n2. second",
        "- ",
        "> quoted\n> more",
        "> [!note] A callout\n> text",
        "some **bold** text",
        "**bold** at the start",
        "*it* and ==high== and `code`",
        "a [[Link]] here",
        "[[Link|an alias]] first",
        "a [link](https://example.com) here",
        "before\n```\ncode\n```\nafter",
        "```\ncode\n```",
        "---\ntitle: x\n---\nBody\n- item",
        "---\ntitle: x\n---\n# Heading",
        "above\n\n---\n\nbelow",
    ]

    static func markers(_ view: MarkdownTextView) -> HiddenMarkers {
        HiddenMarkers(storage: view.textStorage!, tokens: view.tokens, bodyStart: view.bodyStart)
    }

    @Test(arguments: notes)
    func cursorMatchesTheMac(note: String) {
        let view = EditorTestSupport.makeEditor(note, height: 300)
        let markers = Self.markers(view)
        let length = (note as NSString).length
        for previous in 0...length {
            view.setSelectionDirectly(NSRange(location: previous, length: 0))
            for location in 0...length {
                let mac = view.snappedLocation(location, forward: location >= previous)
                #expect(markers.snapped(location, from: previous) == mac, "\(location) from \(previous) in \(note.debugDescription)")
            }
        }
    }

    /// Delete from everywhere the cursor can rest.
    @Test(arguments: notes)
    func deleteMatchesTheMac(note: String) {
        let length = (note as NSString).length
        for location in 0...length {
            let view = EditorTestSupport.makeEditor(note, height: 300)
            view.setSelectionDirectly(NSRange(location: location, length: 0))
            guard Self.markers(view).snapped(location, from: location) == location else { continue }
            let delete = Self.markers(view).delete(at: location)
            view.deleteBackward(nil)

            var text = note as NSString
            var cursor = location
            switch delete {
            case .nothing:
                break
            case .removeMarkers(let run):
                text = text.replacingCharacters(in: run, with: "") as NSString
                cursor = run.location
            case .delete(let from) where from > 0:
                let character = text.rangeOfComposedCharacterSequence(at: from - 1)
                text = text.replacingCharacters(in: character, with: "") as NSString
                cursor = character.location
            case .delete:
                break
            }
            #expect(text as String == view.string, "at \(location) in \(note.debugDescription)")
            // The edit restyles the text, and the cursor settles in what's hidden now.
            let settled = text as String == note ? cursor : Self.markers(EditorTestSupport.makeEditor(text as String, height: 300)).snapped(cursor, from: location)
            #expect(settled == view.selectedRange().location, "at \(location) in \(note.debugDescription)")
        }
    }

    @Test func findsSelectionsOfOnlyHiddenText() {
        let markers = Self.markers(EditorTestSupport.makeEditor("- item **bold**", height: 300))
        #expect(markers.isHidden(NSRange(location: 0, length: 2)))
        #expect(markers.isHidden(NSRange(location: 7, length: 2)))
        #expect(!markers.isHidden(NSRange(location: 0, length: 3)))
    }

    @Test(arguments: [
        ("some **bold** text", NSRange(location: 7, length: 4)),
        ("some **bold** text", NSRange(location: 5, length: 8)),
        ("some **bold** text", NSRange(location: 8, length: 2)),
        ("a [[Link]] here", NSRange(location: 4, length: 4)),
        ("a `code` and *it*", NSRange(location: 0, length: 17)),
        ("plain text", NSRange(location: 2, length: 3)),
    ])
    func selectionsMatchTheMac(note: String, selection: NSRange) {
        let view = EditorTestSupport.makeEditor(note, height: 300)
        view.setSelectionDirectly(selection)
        view.expandSelectionToWholeTokens()
        #expect(Self.markers(view).wholeTokens(in: selection) == view.selectedRange())
    }
}
