import Foundation
import Testing
@testable import VaultKit

private func note(_ id: String) -> Note {
    Note(id: id, url: URL(fileURLWithPath: "/v/\(id)"), title: String((id as NSString).lastPathComponent.dropLast(3)),
         modified: .distantPast, created: .distantPast, isDownloaded: true)
}

struct FolderTreeTests {
    let tree = FolderTree(notes: [
        note("Inbox.md"), note("NHS/Plan.md"), note("NHS/Projects/Alpha.md"), note("NHS/Projects/Beta.md"),
        note("Sources/Book.md"), note("Personal/2 Two.md"), note("Personal/10 Ten.md"),
    ])

    @Test func topLevelFoldersInFinderOrder() {
        #expect(tree.subfolders(of: "") == ["NHS", "Personal", "Sources"])
        #expect(tree.subfolders(of: "NHS") == ["NHS/Projects"])
        #expect(tree.subfolders(of: "Sources").isEmpty)
    }

    @Test func countsIncludeSubfolders() {
        #expect(tree.noteCounts["NHS"] == 3)
        #expect(tree.noteCounts["NHS/Projects"] == 2)
    }

    @Test func paths() {
        #expect(FolderTree.folder(of: "NHS/Projects/Alpha.md") == "NHS/Projects")
        #expect(FolderTree.folder(of: "Inbox.md") == "")
        #expect(FolderTree.name(of: "NHS/Projects") == "Projects")
    }
}

struct TagTreeTests {
    let tree = TagTree(tagsByNote: [["work/imprint", "ideas"], ["Work"], ["work/nhs/digital"], ["ideas"]])

    @Test func parentsComeBeforeChildrenWithCounts() {
        #expect(tree.entries.map(\.id) == ["ideas", "work", "work/imprint", "work/nhs", "work/nhs/digital"])
        #expect(tree.entries.map(\.depth) == [0, 0, 1, 1, 2])
        #expect(tree.entries.first { $0.id == "work" }?.count == 3) // Each note once.
        #expect(tree.entries.first { $0.id == "work/nhs" }?.count == 1) // Implied by work/nhs/digital.
    }

    @Test func children() {
        #expect(tree.children(of: "work").map(\.name) == ["imprint", "nhs"])
    }

    @Test func nestedTagsMatchTheirParents() {
        #expect(TagTree.tags(["Work/Imprint"], include: "work"))
        #expect(!TagTree.tags(["workshop"], include: "work"))
    }
}

struct SidebarPlaceTests {
    @Test func keysRoundTrip() {
        for place in [SidebarPlace.allNotes, .folder("NHS/Projects"), .tag("work/imprint")] {
            #expect(SidebarPlace(key: place.key) == place)
        }
    }

    @Test func parents() {
        #expect(SidebarPlace.folder("NHS/Projects").parent == .folder("NHS"))
        #expect(SidebarPlace.folder("NHS").parent == .allNotes)
        #expect(SidebarPlace.tag("work/imprint").parent == .tag("work"))
    }
}
