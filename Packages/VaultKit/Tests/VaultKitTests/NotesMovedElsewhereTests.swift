import Foundation
import Testing
@testable import VaultKit

struct NotesMovedElsewhereTests {
    private let made = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ id: String, created: Date? = nil) -> Note {
        Note(id: id, url: URL(fileURLWithPath: "/vault/" + id), title: (id as NSString).lastPathComponent,
             modified: made, created: created ?? made, isDownloaded: true)
    }

    @Test func aRenameInOneReadIsFollowed() {
        var moves = NotesMovedElsewhere()
        let pairs = moves.match(before: [note("a.md"), note("Ideas/old.md")], after: [note("a.md"), note("Ideas/new.md")])
        #expect(pairs.map { "\($0.gone.id)>\($0.new.id)" } == ["Ideas/old.md>Ideas/new.md"])
    }

    @Test func aMoveToAnotherFolderIsFollowed() {
        var moves = NotesMovedElsewhere()
        let pairs = moves.match(before: [note("Inbox/x.md", created: made.addingTimeInterval(-99))],
                                after: [note("Work/x.md")])
        #expect(pairs.map(\.new.id) == ["Work/x.md"])
    }

    @Test func aDifferentNoteInTheSameFolderIsntTheSame() {
        var moves = NotesMovedElsewhere()
        #expect(moves.match(before: [note("old.md")], after: [note("new.md", created: made.addingTimeInterval(60))]).isEmpty)
    }

    @Test func aRenameOverTwoReadsIsFollowed() {
        var moves = NotesMovedElsewhere()
        // Gone first, then the new name.
        #expect(moves.match(before: [note("a.md"), note("old.md")], after: [note("a.md")]).isEmpty)
        #expect(moves.vanishedBefore.map(\.id) == ["old.md"])
        #expect(moves.match(before: [note("a.md")], after: [note("a.md"), note("new.md")]).map(\.new.id) == ["new.md"])
        // The new name first, then the old one gone.
        var other = NotesMovedElsewhere()
        #expect(other.match(before: [note("old.md")], after: [note("old.md"), note("new.md")]).isEmpty)
        #expect(other.match(before: [note("old.md"), note("new.md")], after: [note("new.md")]).map(\.gone.id) == ["old.md"])
    }

    @Test func aDeletedNoteWaitsOnlyOneRead() {
        var moves = NotesMovedElsewhere()
        _ = moves.match(before: [note("a.md"), note("old.md")], after: [note("a.md")])
        _ = moves.match(before: [note("a.md")], after: [note("a.md")])
        #expect(moves.vanishedBefore.isEmpty)
        #expect(moves.match(before: [note("a.md")], after: [note("a.md"), note("new.md")]).isEmpty)
    }

    @Test func nothingOnTheFirstRead() {
        var moves = NotesMovedElsewhere()
        #expect(moves.match(before: [], after: [note("a.md")]).isEmpty)
    }
}
