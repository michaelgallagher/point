import Foundation
import Testing
@testable import VaultKit

struct NoteKindsTests {
    private let meeting = NoteKinds.Kind(name: "Meeting", symbol: "person.2", templates: ["Meeting template", "1-1 template", "Missing"])
    private let book = NoteKinds.Kind(name: "Book", folder: "Sources", templates: ["Book template"])
    private let topic = NoteKinds.Kind(name: "Topic", folder: "Topics")
    private var kinds: NoteKinds { NoteKinds(kinds: [meeting, book, topic]) }

    @Test func loadsInOrderSkippingNamelessAndRepeatedKinds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NoteKinds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(NoteKinds.load(vault: root).isEmpty)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".point"), withIntermediateDirectories: true)
        try Data("""
        {"kinds": [{"name": "Meeting", "templates": ["Meeting template"]}, {"name": " "}, {"name": "Book", "folder": "Sources"}, {"name": "meeting"}]}
        """.utf8).write(to: NoteKinds.file(in: root))
        let loaded = NoteKinds.load(vault: root)
        #expect(loaded.property == "type")
        #expect(loaded.kinds.map(\.name) == ["Meeting", "Book"])
        #expect(loaded.kinds[1].folder == "Sources")
        try Data("not json".utf8).write(to: NoteKinds.file(in: root))
        #expect(NoteKinds.load(vault: root).isEmpty)
    }

    @Test func findsANotesKindInAnyCase() {
        #expect(kinds.kind(of: "---\ntype: meeting\n---\nNotes.")?.name == "Meeting")
        #expect(kinds.kind(of: "---\nType: \"Book\"\n---\n")?.name == "Book")
        #expect(kinds.kind(of: "---\ntype: Recipe\n---\n") == nil)
        #expect(kinds.kind(of: "No properties.") == nil)
        #expect(NoteKinds().kind(of: "---\ntype: Meeting\n---\n") == nil)
    }

    @Test func offersOnlyKindsWithTemplates() {
        #expect(kinds.offered.map(\.name) == ["Meeting", "Book"])
    }

    @Test func matchesTemplatesInTheKindsOrderWithShortLabels() {
        let folder = URL(fileURLWithPath: "/Templates")
        let available = ["1-1 template", "Book template", "meeting template"].map { ($0, folder.appendingPathComponent($0 + ".md")) }
        let found = NoteKinds.templates(of: meeting, among: available)
        #expect(found.map(\.label) == ["meeting", "1-1"])
        #expect(found.first?.url.lastPathComponent == "meeting template.md")
        #expect(NoteKinds.label(forTemplate: "Template") == "Template")
        #expect(NoteKinds.label(forTemplate: "Weeknote") == "Weeknote")
    }

    @Test func setsTheKindOnANewNoteUnlessTheTemplateDoes() {
        // Added after the template's properties, which keep their order.
        #expect(kinds.text(for: meeting, from: "---\ndate: 2026-11-07\npeople:\n---\n## Notes\n")
                == "---\ntype: Meeting\ndate: 2026-11-07\npeople:\n---\n## Notes\n")
        // An empty value is filled in.
        #expect(kinds.text(for: book, from: "---\ntitle:\ntype:\ngenre:\n---\n") == "---\ntitle:\ntype: Book\ngenre:\n---\n")
        // A template that says its kind keeps it.
        #expect(kinds.text(for: meeting, from: "---\ntype: Meeting\n---\n") == "---\ntype: Meeting\n---\n")
        // No template, or one without properties.
        #expect(kinds.text(for: meeting) == "---\ntype: Meeting\n---\n")
        #expect(kinds.text(for: meeting, from: "Agenda\n") == "---\ntype: Meeting\n---\nAgenda\n")
    }

    @Test func typeIsOfferedAsAChoiceWithoutBeingSaved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NoteKinds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var types = PointTypes()
        types.implied = ["type": try #require(kinds.choice)]
        #expect(types.definition(forKey: "Type")?.choices == ["Meeting", "Book", "Topic"])
        types.set(.init(type: .rating), forKey: "rating")
        try types.save(vault: root)
        #expect(!(try String(contentsOf: PointTypes.file(in: root), encoding: .utf8)).contains("Meeting"))
        // One chosen in the file wins, and renaming moves only what's in the file.
        types.set(.init(type: .choice, choices: ["A"]), forKey: "type")
        #expect(types.definition(forKey: "type")?.choices == ["A"])
        types.set(nil, forKey: "type")
        types.rename("type", to: "kind")
        #expect(types.definition(forKey: "kind") == nil)
        #expect(NoteKinds().choice == nil)
    }
}

struct PersonKindTests {
    @Test func findsThePersonKind() {
        #expect(NoteKinds(kinds: [.init(name: "Meeting"), .init(name: "Person")]).personKind?.name == "Person")
        #expect(NoteKinds(kinds: [.init(name: "people")]).personKind?.name == "people")
        #expect(NoteKinds(kinds: [.init(name: "Topic")]).personKind == nil)
    }
}

struct KindPluralTests {
    @Test func pluralisesTheLastWord() {
        #expect(NoteKinds.plural("Meeting") == "Meetings")
        #expect(NoteKinds.plural("Daily note") == "Daily notes")
        #expect(NoteKinds.plural("Review") == "Reviews")
        #expect(NoteKinds.plural("Person") == "People")
        #expect(NoteKinds.plural("Media") == "Media")
        #expect(NoteKinds.plural("Blog post") == "Blog posts")
        #expect(NoteKinds.plural("Weekly note") == "Weekly notes")
        #expect(NoteKinds.plural("Recipe") == "Recipes")
        #expect(NoteKinds.plural("Topic") == "Topics")
        #expect(NoteKinds.plural("Project") == "Projects")
        #expect(NoteKinds.plural("Study") == "Studies")
        #expect(NoteKinds.plural("Day") == "Days")
        #expect(NoteKinds.plural("Sketch") == "Sketches")
        #expect(NoteKinds.plural("Class") == "Classes")
        #expect(NoteKinds.plural("Notes") == "Notes")
        #expect(NoteKinds.plural("1-1") == "1-1")
    }
}
