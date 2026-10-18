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
