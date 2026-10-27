import Foundation
import Testing
@testable import VaultKit

/// Obsidian's bookmarks, as the iPhone app's list of regulars: notes read, added, removed and
/// reordered, with everything else in the file kept.
struct ObsidianBookmarksTests {
    private let sample = """
        {"items":[
          {"type":"file","ctime":1,"path":"People.md","title":"The people"},
          {"type":"search","ctime":2,"query":"tag:#work"},
          {"type":"group","ctime":3,"title":"Projects","items":[
            {"type":"file","ctime":4,"path":"Projects/Plan.md"},
            {"type":"folder","ctime":5,"path":"Projects"}
          ]},
          {"type":"file","ctime":6,"path":"Reading list.md"},
          {"type":"file","ctime":7,"path":"Assets/diagram.png"}
        ],"other":true}
        """

    private func vault(_ json: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Bookmarks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        if let json { try Data(json.utf8).write(to: ObsidianBookmarks.file(in: root)) }
        return root
    }

    private func object(_ root: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ObsidianBookmarks.file(in: root))) as? [String: Any])
    }

    @Test func readsTheNotesInOrderGroupsIncluded() throws {
        let root = try vault(sample)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ObsidianBookmarks.load(vault: root) == [
            .init(path: "People.md", title: "The people"),
            .init(path: "Projects/Plan.md", title: nil),
            .init(path: "Reading list.md", title: nil),
        ])
    }

    @Test func noFileMeansNoBookmarks() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ObsidianBookmarks.load(vault: root).isEmpty)
        try ObsidianBookmarks.add("Inbox.md", vault: root)
        #expect(ObsidianBookmarks.load(vault: root).map(\.path) == ["Inbox.md"])
    }

    @Test func addsAtTheEndOnce() throws {
        let root = try vault(sample)
        defer { try? FileManager.default.removeItem(at: root) }
        try ObsidianBookmarks.add("Ideas.md", vault: root, date: Date(timeIntervalSince1970: 1_800_000_000))
        try ObsidianBookmarks.add("Projects/Plan.md", vault: root) // In a group already.
        #expect(ObsidianBookmarks.load(vault: root).map(\.path) == ["People.md", "Projects/Plan.md", "Reading list.md", "Ideas.md"])
        let last = try #require((try object(root)["items"] as? [[String: Any]])?.last)
        #expect(last["ctime"] as? Int == 1_800_000_000_000)
    }

    @Test func removesWherePutAndKeepsTheRest() throws {
        let root = try vault(sample)
        defer { try? FileManager.default.removeItem(at: root) }
        try ObsidianBookmarks.remove("Projects/Plan.md", vault: root)
        #expect(ObsidianBookmarks.load(vault: root).map(\.path) == ["People.md", "Reading list.md"])
        let saved = try object(root)
        #expect(saved["other"] as? Bool == true)
        let items = try #require(saved["items"] as? [[String: Any]])
        #expect(items.map { $0["type"] as? String } == ["file", "search", "group", "file", "file"])
        #expect((items[2]["items"] as? [[String: Any]])?.map { $0["type"] as? String } == ["folder"])
    }

    @Test func reordersTheNotesKeepingWhatEachHolds() throws {
        let root = try vault(sample)
        defer { try? FileManager.default.removeItem(at: root) }
        try ObsidianBookmarks.reorder(["Reading list.md", "People.md", "Projects/Plan.md"], vault: root)
        #expect(ObsidianBookmarks.load(vault: root) == [
            .init(path: "Reading list.md", title: nil),
            .init(path: "People.md", title: "The people"),
            .init(path: "Projects/Plan.md", title: nil),
        ])
        let items = try #require(try object(root)["items"] as? [[String: Any]])
        #expect(items[1]["type"] as? String == "search")
        #expect(items[4]["path"] as? String == "Assets/diagram.png") // Not a note: left alone.
    }

    @Test func aRenamedNotesBookmarksFollowIt() throws {
        let root = try vault(sample)
        defer { try? FileManager.default.removeItem(at: root) }
        try ObsidianBookmarks.rename("Projects/Plan.md", to: "Projects/Plan for 2027.md", vault: root)
        try ObsidianBookmarks.rename("People.md", to: "Team.md", vault: root)
        #expect(ObsidianBookmarks.load(vault: root) == [
            .init(path: "Team.md", title: "The people"),
            .init(path: "Projects/Plan for 2027.md", title: nil),
            .init(path: "Reading list.md", title: nil),
        ])
        // A note that isn't bookmarked leaves the file as it was.
        let before = try Data(contentsOf: ObsidianBookmarks.file(in: root))
        try ObsidianBookmarks.rename("Elsewhere.md", to: "Moved.md", vault: root)
        #expect(try Data(contentsOf: ObsidianBookmarks.file(in: root)) == before)
    }

    @Test func anUnreadableFileIsLeftAlone() throws {
        let broken = #"{"items": [ {"type": "file", "#
        let root = try vault(broken)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ObsidianBookmarks.load(vault: root).isEmpty)
        #expect(throws: (any Error).self) { try ObsidianBookmarks.add("Ideas.md", vault: root) }
        #expect(try String(contentsOf: ObsidianBookmarks.file(in: root), encoding: .utf8) == broken)
    }
}
