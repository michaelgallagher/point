import Foundation
import Testing
@testable import VaultKit

struct MomentFormatTests {
    /// Sunday 18 October 2026, 09:05:07 local time.
    let date: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 10, 18, 9, 5, 7)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test(arguments: [
        ("YYYY-MM-DD", "2026-10-18"),
        ("dddd D MMMM YYYY", "Sunday 18 October 2026"),
        ("ddd Do MMM", "Sun 18th Oct"),
        ("HH:mm:ss", "09:05:07"),
        ("h:mm A", "9:05 AM"),
        ("YY/M/D", "26/10/18"),
        ("[Week] W, GGGG", "Week 42, 2026"),
        ("YYYY/MM/YYYY-MM-DD", "2026/10/2026-10-18"),
        // Moment reads YYY as YY followed by Y (the full year), so Obsidian gives this too.
        ("YYY-MM-DD", "262026-10-18"),
    ])
    func formats(format: String, expected: String) {
        #expect(MomentFormat(format).string(from: date) == expected)
    }
}

struct TemplateRenderTests {
    let date = MomentFormatTests().date

    @Test func fillsInObsidianVariables() {
        var settings = ObsidianSettings()
        settings.templatesDateFormat = "D MMM YYYY"
        let template = "# {{title}}\nCreated {{date}} at {{time}}. Week {{date:W}}. {{ unknown }} <% tp.date.now() %>"
        #expect(Templates.render(template, title: "Plan", date: date, settings: settings)
                == "# Plan\nCreated 18 Oct 2026 at 09:05. Week 42. {{ unknown }} <% tp.date.now() %>")
    }

    @Test func dailyNotesFollowTheSettings() {
        var settings = ObsidianSettings()
        let root = URL(fileURLWithPath: "/vault")
        #expect(Templates.dailyNoteURL(for: date, in: root, settings: settings).path == "/vault/2026-10-18.md")
        settings.dailyNotesFolder = "Daily"
        settings.dailyNotesFormat = "YYYY/MM/DD dddd"
        #expect(Templates.dailyNoteURL(for: date, in: root, settings: settings).path == "/vault/Daily/2026/10/18 Sunday.md")
    }
}

/// Applying a template to a note that may already have properties.
struct TemplateMergeTests {
    /// The note after applying: its frontmatter replaced, the body inserted at `cursor`.
    private func apply(_ template: String, to note: String, at cursor: Int? = nil) -> String {
        let application = Templates.merge(template, into: note)
        var text = note as NSString
        let at = cursor ?? text.length
        text = text.replacingCharacters(in: NSRange(location: at, length: 0), with: application.body) as NSString
        if let range = application.frontmatterRange, let block = application.frontmatter {
            text = text.replacingCharacters(in: range, with: block) as NSString
        }
        return text as String
    }

    @Test func aTemplateWithoutPropertiesGoesInWhole() {
        #expect(apply("## Agenda\n", to: "# Meeting\n") == "# Meeting\n## Agenda\n")
    }

    @Test func aNoteWithoutPropertiesGetsTheTemplates() {
        let template = "---\ntype: meeting\ntags:\n  - work\n---\n## Agenda\n"
        #expect(apply(template, to: "Notes\n") == "---\ntype: meeting\ntags:\n  - work\n---\nNotes\n## Agenda\n")
    }

    @Test func theNotesValuesWinAndNewPropertiesAreAdded() {
        let template = "---\nstatus: draft\ntype: meeting\n---\n## Agenda\n"
        let note = "---\nstatus: done\n---\nText\n"
        #expect(apply(template, to: note) == "---\nstatus: done\ntype: meeting\n---\nText\n## Agenda\n")
    }

    @Test func listsAreCombined() {
        let template = "---\ntags: [work, meeting]\n---\n"
        let note = "---\ntags:\n  - Work\n  - ideas\n---\nText\n"
        #expect(apply(template, to: note) == "---\ntags:\n  - Work\n  - ideas\n  - meeting\n---\nText\n")
    }

    @Test func aSingleTagBecomesAList() {
        let template = "---\ntags: [meeting]\n---\n"
        let note = "---\ntags: work\n---\nText\n"
        #expect(apply(template, to: note) == "---\ntags:\n  - work\n  - meeting\n---\nText\n")
    }

    @Test func nothingChangesWhenTheNoteHasItAll() {
        let template = "---\ntags: [work]\nstatus: draft\n---\n"
        let note = "---\ntags:\n  - work\nstatus: done\n---\nText\n"
        let application = Templates.merge(template, into: note)
        #expect(application.frontmatter == (note as NSString).substring(with: application.frontmatterRange!))
        #expect(application.body == "")
    }

    @Test func newPropertiesKeepTheTemplatesWriting() {
        let template = "---\nattendees:\n  - Ann\n  - Bo\ndue: \"2026-10-26\"\n---\n"
        let note = "---\nstatus: done\n---\n"
        #expect(apply(template, to: note) == "---\nstatus: done\nattendees:\n  - Ann\n  - Bo\ndue: \"2026-10-26\"\n---\n")
    }
}

struct ObsidianSettingsWriteTests {
    @Test func setsOneKeyAndKeepsTheRest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"folder": "Templates", "dateFormat": "D MMM", "other": true}"#.utf8).write(to: folder.appendingPathComponent("templates.json"))

        try ObsidianSettings.set(.templatesFolder, to: "Meta/Templates", vault: root)
        try ObsidianSettings.set(.dailyNotesTemplate, to: "Meta/Templates/Daily", vault: root)
        var settings = ObsidianSettings.load(vault: root)
        #expect(settings.templatesFolder == "Meta/Templates")
        #expect(settings.templatesDateFormat == "D MMM")
        #expect(settings.dailyNotesTemplate == "Meta/Templates/Daily")
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("templates.json"))) as? [String: Any])
        #expect(saved["other"] as? Bool == true)

        // Cleared: Obsidian's default again.
        try ObsidianSettings.set(.templatesDateFormat, to: "", vault: root)
        settings = ObsidianSettings.load(vault: root)
        #expect(settings.templatesDateFormat == "YYYY-MM-DD")
        try? FileManager.default.removeItem(at: root)
    }

    /// From the review of 27 October: a settings file that couldn't be read was taken as
    /// empty and written over, losing everything else in it. It's left as it is.
    @Test func anUnreadableSettingsFileIsLeftAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = Data(#"{"folder": "Templates", "#.utf8) // Cut short, as by a sync in progress.
        let templates = folder.appendingPathComponent("templates.json"), types = folder.appendingPathComponent("types.json")
        try broken.write(to: templates)
        try broken.write(to: types)
        #expect(throws: (any Error).self) { try ObsidianSettings.set(.templatesFolder, to: "Meta", vault: root) }
        #expect(try Data(contentsOf: templates) == broken)
        var propertyTypes = PropertyTypes.load(vault: root)
        propertyTypes.set(.number, forKey: "rating")
        #expect(throws: (any Error).self) { try propertyTypes.save(vault: root) }
        #expect(try Data(contentsOf: types) == broken)
    }

    /// A file that isn't there yet is made.
    @Test func aMissingSettingsFileIsMade() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try ObsidianSettings.set(.templatesFolder, to: "Meta", vault: root)
        #expect(ObsidianSettings.load(vault: root).templatesFolder == "Meta")
    }
}
