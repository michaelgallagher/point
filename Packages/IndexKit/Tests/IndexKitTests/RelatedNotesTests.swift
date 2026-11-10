import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

struct RelatedNotesTests {
    private let post = "---\ntype: Post\ntopics:\n  - \"[[Org design]]\"\n  - \"[[Service design]]\"\n  - \"[[Policy]]\"\n---\n"

    private func topics(_ names: [String], type: String? = nil, date: String? = nil) -> [String: [String]] {
        var row: [String: [String]] = ["topics": names.map { "[[\($0)]]" }]
        if let type { row["type"] = [type] }
        if let date { row["date"] = [date] }
        return row
    }

    private func related(_ values: [Note.ID: [String: [String]]], order: [Note.ID], backlinks: [Backlink] = [],
                         type: String? = nil, placement: RelatedNotes.Placement = .shared) throws -> RelatedNotes {
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(post), name: "This post"))
        return RelatedNotes(noteID: "this.md", recall: recall, sharedIDs: order, values: values,
                            title: { $0.replacingOccurrences(of: ".md", with: "") }, name: { $0 }, typeProperty: "type",
                            backlinks: backlinks, type: type, placement: placement)
    }

    @Test func ranksByHowMuchIsSharedThenNewestFirst() throws {
        let values: [Note.ID: [String: [String]]] = [
            "a.md": topics(["Org design"], date: "2026-10-01"),
            "b.md": topics(["Org design", "Service design", "Policy"], date: "2026-09-01"),
            "c.md": topics(["Policy", "Service design"], date: "2026-10-05"),
            "d.md": topics(["Policy", "org design"], date: "2026-08-01"),
            "this.md": topics(["Org design", "Service design", "Policy"]),
        ]
        // Newest first, as the recall query gives them.
        let result = try related(values, order: ["this.md", "c.md", "a.md", "b.md", "d.md"])
        #expect(result.tiers.map(\.sharedCount) == [3, 2, 1])
        #expect(result.tiers.map { $0.notes.map(\.noteID) } == [["b.md"], ["c.md", "d.md"], ["a.md"]])
        #expect(result.tiers.map(\.heading) == ["On all 3 topics", "On 2 of 3 topics", "On 1 of 3 topics"])
        #expect(result.sharedTotal == 4)
    }

    @Test func aNoteSharingAndLinkingShowsOnce() throws {
        let values: [Note.ID: [String: [String]]] = ["a.md": topics(["Policy"]), "b.md": topics(["Policy"])]
        let link = Backlink(noteID: "a.md", title: "a", context: "", properties: ["related"])
        let other = Backlink(noteID: "z.md", title: "z", context: "")
        let shared = try related(values, order: ["a.md", "b.md"], backlinks: [link, other])
        #expect(shared.tiers.flatMap(\.notes).map(\.noteID) == ["a.md", "b.md"])
        #expect(shared.links.groups.flatMap(\.backlinks).map(\.noteID) == ["z.md"])

        let linked = try related(values, order: ["a.md", "b.md"], backlinks: [link, other], placement: .links)
        #expect(linked.tiers.flatMap(\.notes).map(\.noteID) == ["b.md"])
        #expect(Set(linked.links.groups.flatMap(\.backlinks).map(\.noteID)) == ["a.md", "z.md"])
    }

    @Test func typeChipsCountAndNarrowBoth() throws {
        let values: [Note.ID: [String: [String]]] = [
            "a.md": topics(["Policy"], type: "Source"),
            "b.md": topics(["Policy"], type: "Post"),
        ]
        var link = Backlink(noteID: "z.md", title: "z", context: "")
        link.type = "Source"
        let all = try related(values, order: ["a.md", "b.md"], backlinks: [link])
        #expect(all.types.map(\.type) == ["Source", "Post"])
        #expect(all.types.map(\.count) == [2, 1])
        let sources = try related(values, order: ["a.md", "b.md"], backlinks: [link], type: "source")
        #expect(sources.tiers.flatMap(\.notes).map(\.noteID) == ["a.md"])
        #expect(sources.links.count == 1)
        // Counted before narrowing, so the readout doesn't change with the chips.
        #expect(sources.sharedTotal == 2)
    }

    @Test func peopleHeadingsAndReadout() throws {
        let meeting = "---\ntype: Meeting\ndate: 2026-11-07\npeople:\n  - \"[[Sam Lee]]\"\n  - \"[[Ann Cole]]\"\n---\n"
        let recall = try #require(Recall(frontmatter: Frontmatter.parse(meeting), name: "Sync"))
        let values: [Note.ID: [String: [String]]] = [
            "m1.md": ["people": ["[[Sam Lee]]", "[[Ann Cole]]"], "date": ["2026-10-21"]],
            "m2.md": ["people": ["[[Ann Cole]]"], "date": ["2026-11-01"]],
        ]
        let result = RelatedNotes(noteID: "sync.md", recall: recall, sharedIDs: ["m2.md", "m1.md"], values: values,
                                  title: { $0 }, name: { $0 }, typeProperty: "type", backlinks: [])
        #expect(result.tiers.map(\.heading) == ["Earlier meetings with all 2", "Earlier meetings with 1 of 2"])
        let now = Recall.dayDate("2026-11-07")!
        #expect(result.readout(ownType: "Meeting", unlinkedMentions: 0, now: now) == "2 earlier meetings · last on 1 November")
    }

    @Test func readoutWithNothingSharedSaysWhatTheLinksAre() {
        var article = Backlink(noteID: "a.md", title: "a", context: "", properties: ["author"])
        article.type = "Article"
        let mention = Backlink(noteID: "b.md", title: "b", context: "")
        var meeting = Backlink(noteID: "c.md", title: "c", context: "", properties: ["people"])
        meeting.type = "Meeting"
        let result = RelatedNotes(noteID: "sam.md", recall: nil, sharedIDs: [], values: [:], title: { $0 }, name: { $0 },
                                  typeProperty: "type", backlinks: [article, mention, meeting])
        #expect(result.readout(ownType: "Person", unlinkedMentions: 2)
                == "5 links (articles by this person, meetings with this person, mentions, and unlinked mentions)")
        let empty = RelatedNotes(noteID: "x.md", recall: nil, sharedIDs: [], values: [:], title: { $0 }, name: { $0 },
                                 typeProperty: "type", backlinks: [])
        #expect(empty.readout(ownType: nil, unlinkedMentions: 0) == nil)
        #expect(empty.isEmpty)
    }

    @Test func aGroupOfMixedTypesIsNotes() {
        let links = ["Book", "Podcast", "Video"].enumerated().map { index, type in
            var link = Backlink(noteID: "\(index).md", title: "\(index)", context: "", properties: ["related"])
            link.type = type
            return link
        }
        #expect(RelatedNotes.commonType(of: links) == nil)
        #expect(RelatedNotes.commonType(of: links + [links[0], links[0]]) == "Book")
    }
}
