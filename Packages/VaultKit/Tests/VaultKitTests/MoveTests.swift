import Foundation
import Testing
@testable import VaultKit

private func note(_ id: String) -> Note {
    Note(id: id, url: URL(fileURLWithPath: "/vault/\(id)"), title: String((id as NSString).lastPathComponent.dropLast(3)),
         modified: .distantPast, created: .distantPast, isDownloaded: true)
}

struct MoveLinkTests {
    let moved = note("Inbox/Plan.md")
    var resolver: LinkResolver { LinkResolver(notes: [moved, note("Daily/Today.md"), note("Root.md")]) }

    private func rewrite(_ text: String, from source: String) -> String? {
        LinkUpdater.rewrite(text, in: source, moved: moved, newID: "Work/Projects/Plan.md", resolver: resolver)
    }

    @Test func wikiLinksByNameAreLeftAlone() {
        #expect(rewrite("See [[Plan]] and [[Plan#Goals|goals]].", from: "Root.md") == nil)
    }

    @Test func wikiLinksWithPathsGetTheNewPath() {
        #expect(rewrite("[[Inbox/Plan]] and ![[Inbox/Plan.md#Part]]", from: "Root.md")
                == "[[Work/Projects/Plan]] and ![[Work/Projects/Plan.md#Part]]")
    }

    @Test func markdownLinksKeepTheirStyle() {
        // Relative to the linking note.
        #expect(rewrite("[p](../Inbox/Plan.md#x)", from: "Daily/Today.md") == "[p](../Work/Projects/Plan.md#x)")
        // From the vault root.
        #expect(rewrite("[p](Inbox/Plan.md)", from: "Daily/Today.md") == "[p](Work/Projects/Plan.md)")
        // In angle brackets, spaces stay plain.
        let spaced = note("Inbox/My Plan.md")
        let result = LinkUpdater.rewrite("[p](<Inbox/My Plan.md>) [q](Inbox/My%20Plan.md)", in: "Root.md", moved: spaced,
                                         newID: "Work/My Plan.md", resolver: LinkResolver(notes: [spaced]))
        #expect(result == "[p](<Work/My Plan.md>) [q](Work/My%20Plan.md)")
    }

    @Test func relativePaths() {
        #expect(LinkUpdater.relativePath(from: "", to: "Work/Plan.md") == "Work/Plan.md")
        #expect(LinkUpdater.relativePath(from: "Daily", to: "Work/Plan.md") == "../Work/Plan.md")
        #expect(LinkUpdater.relativePath(from: "Work/Projects", to: "Work/Assets/a.png") == "../Assets/a.png")
        #expect(LinkUpdater.relativePath(from: "Work", to: "Work/Plan.md") == "Plan.md")
    }
}

struct MoveFileTests {
    @Test func movingANoteKeepsItsOwnRelativeLinksWorking() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Move-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Inbox", "Assets", "Work"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("Assets/photo.png"))
        let text = "![photo](../Assets/photo.png) [web](https://a.com) [missing](nowhere.md) [[Other]]"
        try Data(text.utf8).write(to: root.appendingPathComponent("Inbox/Plan.md"))
        let notes = try VaultScanner.scan(root)
        let plan = try #require(notes.first)

        let url = try NoteFiles.move(plan.url, toFolder: root.appendingPathComponent("Work/Projects"))
        #expect(url.lastPathComponent == "Plan.md")
        _ = LinkUpdater.updateLinks(afterMoving: plan, to: "Work/Projects/Plan.md", notes: notes, root: root)
        #expect(try String(contentsOf: url, encoding: .utf8)
                == "![photo](../../Assets/photo.png) [web](https://a.com) [missing](nowhere.md) [[Other]]")
    }

    @Test func moveNeverOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Move-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("A"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("B"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("A/Note.md"))
        try Data("b".utf8).write(to: root.appendingPathComponent("B/Note.md"))
        let moved = try NoteFiles.move(root.appendingPathComponent("A/Note.md"), toFolder: root.appendingPathComponent("B"))
        #expect(moved.lastPathComponent == "Note 2.md")
        #expect(try String(contentsOf: root.appendingPathComponent("B/Note.md"), encoding: .utf8) == "b")
    }
}
