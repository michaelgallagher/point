import Foundation
import Testing
@testable import VaultKit

struct PointTypesTests {
    @Test func savesAndLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PointTypes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var types = PointTypes()
        types.set(.init(type: .choice, choices: ["draft", "published"]), forKey: "status")
        types.set(.init(type: .rating, max: 5), forKey: "rating")
        types.people.folder = "People"
        try types.save(vault: root)
        #expect(PointTypes.load(vault: root) == types)
        let json = try String(contentsOf: PointTypes.file(in: root), encoding: .utf8)
        #expect(json.contains("\"choices\""))
        #expect(!json.contains("folder\" : null"))
    }

    @Test func missingOrBrokenFilesAreEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PointTypes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PointTypes.load(vault: root) == PointTypes())
        try FileManager.default.createDirectory(at: PointTypes.file(in: root).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: PointTypes.file(in: root))
        #expect(PointTypes.load(vault: root) == PointTypes())
    }

    @Test func matchesKeysInAnyCaseAndRenames() {
        var types = PointTypes()
        types.set(.init(type: .person), forKey: "People")
        #expect(types.definition(forKey: "people")?.type == .person)
        types.set(.init(type: .choice), forKey: "people")
        #expect(types.properties.keys.sorted() == ["people"])
        types.rename("people", to: "with")
        #expect(types.definition(forKey: "with")?.type == .choice)
        #expect(types.definition(forKey: "people") == nil)
    }

    @Test func findsThePeopleFolder() {
        #expect(PointTypes().peopleFolder(among: ["Work", "people", "Work/People"]) == "people")
        #expect(PointTypes().peopleFolder(among: ["Work/People"]) == nil)
        #expect(PointTypes(people: .init(folder: "Contacts")).peopleFolder(among: ["People"]) == "Contacts")
    }
}
