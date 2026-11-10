import Foundation
import Testing
@testable import VaultKit

struct NoteNamesTests {
    @Test func slugsArePlainLowercaseWords() {
        #expect(NoteNames.slug("Questions: about my vault?") == "questions-about-my-vault")
        #expect(NoteNames.slug("Café crème — déjà vu") == "cafe-creme-deja-vu")
        #expect(NoteNames.slug("Mike's notes 🎉 2026") == "mikes-notes-2026")
        #expect(NoteNames.slug("  --  ") == "")
        #expect(NoteNames.slug("東京") == "dong-jing")
        #expect(NoteNames.slug("Straße / Œuvre") == "strasse-oeuvre")
        let long = String(repeating: "word ", count: 40)
        #expect(NoteNames.slug(long).count == 40 * 5 - 1) // Long titles stay long.
    }

    @Test func namesHaveTheDayAndTheTitle() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))!
        #expect(NoteNames.name(for: "Questions about my vault", created: date, calendar: calendar) == "2026-11-06-questions-about-my-vault")
        #expect(NoteNames.name(for: "🎉", created: date, calendar: calendar) == "2026-11-06-untitled")
        #expect(NoteNames.renamed("2026-11-06-old-title", to: "New title") == "2026-11-06-new-title")
        #expect(NoteNames.renamed("Old title", to: "New") == nil)
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 21, minute: 38, second: 9))!
        #expect(NoteNames.untitledName(created: late, calendar: calendar) == "2026-11-06-untitled-213809")
        #expect(NoteNames.isDated("2026-11-06-untitled-213809"))
        #expect(NoteNames.fallbackTitle(for: "2026-11-06-untitled-213809") == "Untitled")
        #expect(NoteNames.fallbackTitle(for: "2026-11-06-untitled-3") == "Untitled")
        #expect(NoteNames.fallbackTitle(for: "2026-11-06-untitled") == "Untitled")
        #expect(NoteNames.fallbackTitle(for: "2026-11-06-plan-2") == "Plan 2")
    }

    @Test func knowsPointsNames() {
        #expect(NoteNames.isDated("2026-11-06-questions-about-my-vault"))
        #expect(NoteNames.isDated("2026-11-06-untitled-2"))
        #expect(!NoteNames.isDated("2026-11-06")) // A daily note.
        #expect(!NoteNames.isDated("2026-11-06 Weekly planning"))
        #expect(!NoteNames.isDated("2026-11-06-Weekly")) // Capitals: not one Point made.
        #expect(NoteNames.day(of: "2026-11-06-a") == "2026-11-06")
        #expect(NoteNames.fallbackTitle(for: "2026-11-06-questions-about-it") == "Questions about it")
    }

    @Test func readsAndSetsTheTitle() {
        #expect(NoteNames.title(in: "---\ntitle: \"Questions: about it?\"\n---\nBody") == "Questions: about it?")
        #expect(NoteNames.title(in: "---\ntitle:\n---\n") == nil)
        #expect(NoteNames.settingTitle("Questions: about it?", in: "Body") == "---\ntitle: \"Questions: about it?\"\n---\nBody")
        #expect(NoteNames.settingTitle("New", in: "---\ntags: [a]\n---\nBody") == "---\ntitle: New\ntags: [a]\n---\nBody")
        #expect(NoteNames.settingTitle("New", in: "---\ntags: [a]\ntitle: Old\n---\nBody") == "---\ntags: [a]\ntitle: New\n---\nBody")
    }

    @Test func scannedNotesTakeTheirTitleOnlyIfPointNamedThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NoteNames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("---\ntitle: Questions: about it?\n---\n".utf8).write(to: root.appendingPathComponent("2026-11-06-questions-about-it.md"))
        try Data("---\ntitle: Something else\n---\n".utf8).write(to: root.appendingPathComponent("Clipped page.md"))
        try Data("No title here".utf8).write(to: root.appendingPathComponent("2026-11-06-untitled.md"))
        let notes = try VaultScanner.scan(root).sorted { $0.id < $1.id }
        #expect(notes.map(\.title) == ["Questions: about it?", "Untitled", "Clipped page"])
        #expect(notes.map(\.name) == ["2026-11-06-questions-about-it", "2026-11-06-untitled", "Clipped page"])
        // Links find a note by its file name, not its title.
        let resolver = LinkResolver(notes: notes)
        #expect(resolver.resolve(wikiTarget: "2026-11-06-questions-about-it", from: "x.md")?.title == "Questions: about it?")
    }

    @Test func renamingRetitlesLabelsThatWereTheTitle() {
        let old = Note(id: "2026-11-06-old.md", url: URL(fileURLWithPath: "/v/2026-11-06-old.md"), title: "Old", modified: Date(), created: Date(), isDownloaded: true)
        let resolver = LinkResolver(notes: [old])
        let text = "See [[2026-11-06-old|Old]], [[2026-11-06-old|my label]] and [[2026-11-06-old#Part|old]]."
        #expect(LinkUpdater.rewrite(text, in: "x.md", renamed: old, newTitle: "2026-11-06-new", resolver: resolver, retitling: ("Old", "New"))
                == "See [[2026-11-06-new|New]], [[2026-11-06-new|my label]] and [[2026-11-06-new#Part|New]].")
        // Only the title changed, not the name: the labels still follow.
        #expect(LinkUpdater.rewrite(text, in: "x.md", renamed: old, newTitle: "2026-11-06-old", resolver: resolver, retitling: ("Old", "Older"))
                == "See [[2026-11-06-old|Older]], [[2026-11-06-old|my label]] and [[2026-11-06-old#Part|Older]].")
    }
}
