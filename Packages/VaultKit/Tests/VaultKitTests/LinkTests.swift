import Foundation
import Testing
@testable import VaultKit

private func note(_ id: String) -> Note {
    let name = (id as NSString).lastPathComponent
    return Note(id: id, url: URL(fileURLWithPath: "/vault/\(id)"), title: String(name.dropLast(3)),
                modified: .distantPast, created: .distantPast, isDownloaded: true)
}

struct LinkResolverTests {
    let resolver = LinkResolver(notes: [
        note("Inbox.md"), note("Projects/Imprint.md"), note("Daily/Plan.md"), note("Work/Plan.md"), note("My Note.md"),
    ])

    @Test func byName() {
        #expect(resolver.resolve(wikiTarget: "imprint", from: "Inbox.md")?.id == "Projects/Imprint.md")
        #expect(resolver.resolve(wikiTarget: "Imprint#Goals", from: "Inbox.md")?.id == "Projects/Imprint.md")
        #expect(resolver.resolve(wikiTarget: "Imprint.md", from: "Inbox.md")?.id == "Projects/Imprint.md")
        #expect(resolver.resolve(wikiTarget: "Missing", from: "Inbox.md") == nil)
    }

    @Test func sharedNamesPreferTheSameFolder() {
        #expect(resolver.resolve(wikiTarget: "Plan", from: "Work/Today.md")?.id == "Work/Plan.md")
        #expect(resolver.resolve(wikiTarget: "Work/Plan", from: "Inbox.md")?.id == "Work/Plan.md")
        #expect(resolver.isAmbiguous(title: "plan"))
    }

    @Test func markdownLinks() {
        #expect(resolver.resolve(markdownDestination: "My%20Note.md", from: "Inbox.md")?.id == "My Note.md")
        #expect(resolver.resolve(markdownDestination: "../Inbox.md", from: "Projects/Imprint.md")?.id == "Inbox.md")
        #expect(resolver.resolve(markdownDestination: "https://x.com/a.md", from: "Inbox.md") == nil)
    }
}

struct LinkRewriteTests {
    let renamed = note("Projects/Imprint.md")
    var resolver: LinkResolver { LinkResolver(notes: [renamed, note("Inbox.md"), note("Other/Imprint plan.md")]) }

    private func rewrite(_ text: String, from source: String = "Inbox.md") -> String? {
        LinkUpdater.rewrite(text, in: source, renamed: renamed, newTitle: "Imprint App", resolver: resolver)
    }

    @Test func wikiLinksKeepHeadingsAndAliases() {
        #expect(rewrite("See [[Imprint]], [[imprint#Goals|the goals]] and ![[Imprint]].")
                == "See [[Imprint App]], [[Imprint App#Goals|the goals]] and ![[Imprint App]].")
    }

    @Test func pathsAndExtensionsAreKept() {
        #expect(rewrite("[[Projects/Imprint]] [[Imprint.md]]") == "[[Projects/Imprint App]] [[Imprint App.md]]")
    }

    @Test func markdownLinksKeepTheirEncoding() {
        #expect(rewrite("[a](Projects/Imprint.md#x) [b](<Projects/Imprint.md>)")
                == "[a](Projects/Imprint%20App.md#x) [b](<Projects/Imprint App.md>)")
    }

    @Test func otherLinksAndPlainTextAreUntouched() {
        #expect(rewrite("[[Imprint plan]] and the word Imprint") == nil)
        #expect(rewrite("`[[Imprint]]` in code") == nil)
    }
}

/// From the live vault's phase 2: renames missed every link in frontmatter (661 of them).
struct FrontmatterLinkTests {
    let renamed = note("Projects/Imprint.md")
    var resolver: LinkResolver { LinkResolver(notes: [renamed, note("Inbox.md"), note("Other/Imprint plan.md")]) }

    @Test func renamesUpdateLinksInFrontmatter() {
        let text = "---\nproject: \"[[Imprint]]\"\npeople:\n  - \"[[Imprint|the app]]\"\n  - \"[[Imprint plan]]\"\n---\nSee [[Imprint]].\n"
        #expect(LinkUpdater.rewrite(text, in: "Inbox.md", renamed: renamed, newTitle: "Imprint App", resolver: resolver)
                == "---\nproject: \"[[Imprint App]]\"\npeople:\n  - \"[[Imprint App|the app]]\"\n  - \"[[Imprint plan]]\"\n---\nSee [[Imprint App]].\n")
    }

    @Test func movesUpdatePathLinksInFrontmatter() {
        let text = "---\nproject: \"[[Projects/Imprint]]\"\nother: \"[[Imprint]]\"\n---\n"
        #expect(LinkUpdater.rewrite(text, in: "Inbox.md", moved: renamed, newID: "Archive/Imprint.md", resolver: resolver)
                == "---\nproject: \"[[Archive/Imprint]]\"\nother: \"[[Imprint]]\"\n---\n")
    }

    @Test func aRenamedNotesLinksToItselfAreUpdated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Old.md")
        try Data("See [[Old#Top]].\n".utf8).write(to: url)
        let old = Note(id: "Old.md", url: url, title: "Old", modified: .distantPast, created: .distantPast, isDownloaded: true)
        let renamedURL = try NoteFiles.rename(url, to: "New")
        _ = LinkUpdater.updateLinks(to: old, newTitle: "New", notes: [old])
        #expect(try String(contentsOf: renamedURL, encoding: .utf8) == "See [[New#Top]].\n")
        try? FileManager.default.removeItem(at: root)
    }

    /// A note iCloud hasn't downloaded (only its placeholder is there) can't be checked for
    /// links, so it's reported rather than passed over.
    @Test func notesThatCantBeReadAreReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Old.md")
        try Data("Old.\n".utf8).write(to: url)
        let old = Note(id: "Old.md", url: url, title: "Old", modified: .distantPast, created: .distantPast, isDownloaded: true)
        let evicted = Note(id: "Away.md", url: root.appendingPathComponent("Away.md"), title: "Away",
                           modified: .distantPast, created: .distantPast, isDownloaded: false)
        _ = try NoteFiles.rename(url, to: "New")
        let result = LinkUpdater.updateLinks(to: old, newTitle: "New", notes: [old, evicted])
        #expect(result.unreadNotes == ["Away.md"])
        try? FileManager.default.removeItem(at: root)
    }
}

struct QuotedValueTests {
    @Test func singleQuotesAreUnescaped() {
        let text = "---\ntitle: 'It''s here'\nother: \"Say \\\"hi\\\"\"\n---\n"
        let frontmatter = Frontmatter.parse(text)!
        #expect(frontmatter.properties[0].values == ["It's here"])
        #expect(frontmatter.properties[1].values == ["Say \"hi\""])
        let edit = frontmatter.edit(setting: "title", to: ["It's there"])
        #expect(edit.1 == "title: 'It''s there'\n")
    }
}
