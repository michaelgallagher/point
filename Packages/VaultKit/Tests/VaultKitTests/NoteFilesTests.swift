import Foundation
import Testing
@testable import VaultKit

struct NoteFilesTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoteFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [
        ("Plain title", "Plain title"),
        ("What? A/B: test*", "What A B test"),
        ("  # Heading [[link]]  ", "Heading link"),
        (".hidden", "hidden"),
        ("line one\nline two", "line one line two"),
    ])
    func sanitizesTitles(input: String, expected: String) {
        #expect(NoteFiles.sanitizedTitle(input) == expected)
    }

    @Test func untitledNamesAreTimestamps() {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 10, 18, 9, 42)
        let date = Calendar.current.date(from: components)!
        #expect(NoteFiles.untitledName(at: date) == "2026-10-18 0942")
    }

    @Test func moveFolderTakesEverythingInIt() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("Projects/Old")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        _ = try NoteFiles.create(title: "Idea", in: projects)
        let moved = try NoteFiles.moveFolder(root.appendingPathComponent("Projects"), into: root.appendingPathComponent("Archive"))
        #expect(moved.lastPathComponent == "Projects")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive/Projects/Old/Idea.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects").path))
    }

    @Test func moveFolderRefusesItselfAndTakenNames() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["A/B", "C/A"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        #expect(throws: NoteFiles.FileError.folderIntoItself) {
            try NoteFiles.moveFolder(root.appendingPathComponent("A"), into: root.appendingPathComponent("A/B"))
        }
        #expect(throws: NoteFiles.FileError.folderTaken("A")) {
            try NoteFiles.moveFolder(root.appendingPathComponent("A"), into: root.appendingPathComponent("C"))
        }
    }

    @Test func createAvoidsExistingNames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NoteFiles.create(title: "Idea", in: folder)
        let second = try NoteFiles.create(title: "Idea", text: "two", in: folder)
        #expect(first.lastPathComponent == "Idea.md")
        #expect(second.lastPathComponent == "Idea 2.md")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }

    @Test func renameMovesTheFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try NoteFiles.create(title: "Old", text: "body", in: folder)
        let renamed = try NoteFiles.rename(url, to: "New: name")
        #expect(renamed.lastPathComponent == "New name.md")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "body")
    }

    @Test func renameNeverOverwrites() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try NoteFiles.create(title: "A", in: folder)
        _ = try NoteFiles.create(title: "B", in: folder)
        #expect(throws: NoteFiles.FileError.titleTaken("B")) { try NoteFiles.rename(a, to: "B") }
    }

    @Test func renameCanChangeCase() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try NoteFiles.create(title: "idea", in: folder)
        let renamed = try NoteFiles.rename(url, to: "Idea")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Idea.md"])
        #expect(renamed.lastPathComponent == "Idea.md")
    }

    @Test func localTrashUsesTheVaultsTrashFolder() throws {
        let vault = try makeFolder()
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = try NoteFiles.create(title: "Gone", in: vault)
        try NoteFiles.trash(url, vault: vault, option: .local)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".trash/Gone.md").path))
    }

    @Test func readsObsidianSettings() throws {
        let vault = try makeFolder()
        defer { try? FileManager.default.removeItem(at: vault) }
        let folder = vault.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"attachmentFolderPath": "Meta/Assets", "trashOption": "local"}"#.utf8).write(to: folder.appendingPathComponent("app.json"))
        try Data(#"{"folder": "Meta/Templates", "dateFormat": "YYY-MM-DD"}"#.utf8).write(to: folder.appendingPathComponent("templates.json"))
        let settings = ObsidianSettings.load(vault: vault)
        #expect(settings.attachmentFolder == "Meta/Assets")
        #expect(settings.trashOption == .local)
        #expect(settings.templatesFolder == "Meta/Templates")
        #expect(settings.templatesDateFormat == "YYY-MM-DD")
        #expect(settings.dailyNotesFormat == "YYYY-MM-DD") // No daily-notes.json: Obsidian's default.
        #expect(settings.listCallouts == ObsidianSettings.ListCallout.defaults) // No List Callouts settings.
    }

    @Test func readsListCalloutColours() throws {
        let vault = try makeFolder()
        defer { try? FileManager.default.removeItem(at: vault) }
        let folder = vault.appendingPathComponent(".obsidian/plugins/obsidian-list-callouts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"[{"color": "255, 23, 68", "char": "!"}, {"char": "*", "color": "163, 123, 123", "icon": null, "custom": true}]"#.utf8)
            .write(to: folder.appendingPathComponent("data.json"))
        let callouts = ObsidianSettings.load(vault: vault).listCallouts
        #expect(callouts == [.init(character: "!", red: 255, green: 23, blue: 68), .init(character: "*", red: 163, green: 123, blue: 123)])
    }
}
