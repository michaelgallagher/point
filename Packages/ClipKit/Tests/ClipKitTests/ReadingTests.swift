import Foundation
import Testing
import VaultKit
@testable import ClipKit

struct ReadingTests {
    let kinds = NoteKinds(kinds: [NoteKinds.Kind(name: "Media"), NoteKinds.Kind(name: "Meeting")])

    @Test func onlyTheClipKindOpensForReading() {
        #expect(Reading.opensForReading("---\ntype: Media\n---\nText", kinds: kinds))
        #expect(Reading.opensForReading("---\ntype: media\n---\nText", kinds: kinds))
        #expect(!Reading.opensForReading("---\ntype: Meeting\n---\nText", kinds: kinds))
        #expect(!Reading.opensForReading("No properties", kinds: kinds))
        // A vault with no kind for clips has nothing to read this way.
        #expect(!Reading.opensForReading("---\ntype: Media\n---\n", kinds: NoteKinds(kinds: [NoteKinds.Kind(name: "Meeting")])))
    }

    @Test func minutesToReadLeaveOutTheProperties() {
        let words = Array(repeating: "word", count: 690).joined(separator: " ")
        #expect(Reading.minutes(toRead: "---\ntitle: \(words)\n---\nShort.") == 1)
        #expect(Reading.minutes(toRead: "---\ntype: Media\n---\n\(words)") == 3)
        #expect(Reading.minutes(toRead: "") == 1)
    }

    @Test func bylineSaysWhoWhereWhenAndHowLong() {
        let text = """
        ---
        type: Media
        author:
          - "[[Ann Lee]]"
          - "[[Bo Ng|Bo]]"
        published: 2025-11-03
        source: https://www.example.com/post?id=1
        ---
        Text
        """
        let byline = Reading.byline(of: Frontmatter.parse(text), minutes: 12, locale: Locale(identifier: "en_GB"))
        #expect(byline == "Ann Lee and Bo · example.com · 3 Nov 2025 · 12 min read")
    }

    @Test func bylineLeavesOutWhatIsNotKnown() {
        let text = "---\ntype: Media\nauthor:\npublished: 2019\nsource:\n---\n"
        #expect(Reading.byline(of: Frontmatter.parse(text), minutes: 4, locale: Locale(identifier: "en_GB")) == "2019 · 4 min read")
        #expect(Reading.byline(of: nil, minutes: 1) == "1 min read")
    }

    let article = "---\ntype: Media\n---\nFirst paragraph, about one thing.\n\nSecond paragraph, about another.\n\nThird paragraph.\n"

    @Test func aPlaceIsTheParagraphItIsIn() {
        let ns = article as NSString
        let inSecond = ns.range(of: "about another").location
        let place = Reading.place(at: inSecond, in: article)
        #expect(place.anchor == "Second paragraph, about another.")
        #expect(place.location == ns.range(of: "Second").location)
        #expect(Reading.location(of: place, in: article) == place.location)
    }

    @Test func aPlaceIsFoundAgainAfterAnEditAbove() {
        let place = Reading.place(at: (article as NSString).range(of: "Third").location, in: article)
        let edited = article.replacingOccurrences(of: "First paragraph", with: "A much longer first paragraph, rewritten on the Mac")
        #expect(Reading.location(of: place, in: edited) == (edited as NSString).range(of: "Third").location)
    }

    @Test func aPlaceGoneFallsBackToWhereItWas() {
        let place = Reading.place(at: (article as NSString).range(of: "Third").location, in: article)
        let edited = article.replacingOccurrences(of: "Third paragraph.", with: "Rewritten.")
        #expect(Reading.location(of: place, in: edited) == place.location)
        let shorter = "Short."
        #expect(Reading.location(of: place, in: shorter) == (shorter as NSString).length)
    }

    @Test func theNearestOfRepeatedParagraphsIsFound() {
        let text = "Same.\n\nOther.\n\nSame.\n\nMore.\n"
        let second = (text as NSString).range(of: "Same.", options: .backwards).location
        let place = Reading.place(at: second, in: text)
        #expect(Reading.location(of: place, in: text) == second)
    }

    @Test func aPlaceOnlyMatchesTheStartOfAParagraph() {
        let text = "Intro mentions Second paragraph here.\n\nSecond paragraph.\n"
        let place = Reading.Place(anchor: "Second paragraph", location: 0)
        #expect(Reading.location(of: place, in: text) == (text as NSString).range(of: "\nSecond").location + 1)
    }
}
