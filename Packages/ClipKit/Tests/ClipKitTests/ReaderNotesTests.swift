import Foundation
import Testing
@testable import ClipKit

struct ReaderNotesTests {
    let properties = "---\ntype: Media\ntitle: A post\n---\n"
    let marker = ReaderNotes.marker

    @Test func findsTheMarkerAndYourNotes() {
        let text = properties + "My thought.\n\n> A quote\n\n\(marker)\n\n## A heading\n\nThe article.\n"
        #expect(ReaderNotes.notes(in: text) == "My thought.\n\n> A quote")
        let line = ReaderNotes.markerLine(in: text)!
        #expect((text as NSString).substring(with: line) == marker)
    }

    @Test func onlyAWholeLineIsTheMarker() {
        let text = properties + "Say \(marker) here.\n\n  \(marker) \n\nArticle\n"
        #expect(ReaderNotes.notes(in: text) == "Say \(marker) here.")
        #expect(ReaderNotes.notes(in: properties + "No marker.\n") == "")
    }

    @Test func settingNotesLeavesEverythingElseAsItWas() {
        let article = "\(marker)\n\n## A heading\n\nThe article, *exactly*.\n"
        let text = properties + "Old notes.\n\n" + article
        let changed = ReaderNotes.settingNotes("New notes.\n\n> Quoted\n\nMore.", in: text)
        #expect(changed == properties + "New notes.\n\n> Quoted\n\nMore.\n\n" + article)
        #expect(ReaderNotes.notes(in: changed) == "New notes.\n\n> Quoted\n\nMore.")
    }

    @Test func emptyNotesLeaveTheMarkerUnderTheProperties() {
        let text = properties + "Old notes.\n\n\(marker)\n\nArticle\n"
        #expect(ReaderNotes.settingNotes("  \n\n", in: text) == properties + "\(marker)\n\nArticle\n")
    }

    @Test func trailingSpaceAndBlankLinesAreTidied() {
        let text = properties + "\(marker)\n\nArticle\n"
        #expect(ReaderNotes.settingNotes("\n\nA note.  \n\n\n", in: text) == properties + "A note.\n\n\(marker)\n\nArticle\n")
    }

    @Test func aNoteWithoutTheMarkerGetsItUnderTheProperties() {
        let text = properties + "\n> Selected when clipped\n\nThe article.\n"
        let changed = ReaderNotes.settingNotes("A note.", in: text)
        #expect(changed == properties + "A note.\n\n\(marker)\n\n> Selected when clipped\n\nThe article.\n")
        // And with nothing to say, only the marker.
        #expect(ReaderNotes.settingNotes("", in: text) == properties + "\(marker)\n\n> Selected when clipped\n\nThe article.\n")
    }

    @Test func aNoteWithoutPropertiesGetsTheMarkerAtTheTop() {
        #expect(ReaderNotes.settingNotes("A note.", in: "The article.\n") == "A note.\n\n\(marker)\n\nThe article.\n")
        #expect(ReaderNotes.settingNotes("A note.", in: "") == "A note.\n\n\(marker)\n")
    }

    @Test func propertiesWithoutAFinalLineBreak() {
        let text = "---\ntype: Media\n---"
        #expect(ReaderNotes.settingNotes("A note.", in: text) == "---\ntype: Media\n---\nA note.\n\n\(marker)\n")
    }

    @Test func aQuoteGoesAtTheEndInAParagraphOfItsOwn() {
        let (notes, cursor) = ReaderNotes.addingQuote("  First line\nSecond line\n\nAfter a gap ", to: "My note.\n")
        #expect(notes == "My note.\n\n> First line\n> Second line\n>\n> After a gap\n\n")
        #expect(cursor == (notes as NSString).length)
        #expect(ReaderNotes.addingQuote("Alone", to: "").notes == "> Alone\n\n")
    }
}
