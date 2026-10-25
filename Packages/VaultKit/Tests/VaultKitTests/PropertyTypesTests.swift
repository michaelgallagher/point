import Foundation
import Testing
@testable import VaultKit

struct PropertyTypesTests {
    private func property(_ key: String, _ values: [String], isList: Bool = false) -> Frontmatter.Property {
        Frontmatter.Property(key: key, values: values, isList: isList, range: NSRange(location: 0, length: 0))
    }

    @Test func guessesFromTheValue() {
        #expect(PropertyType.guess(for: property("status", ["draft"])) == .text)
        #expect(PropertyType.guess(for: property("due", ["2026-10-25"])) == .date)
        #expect(PropertyType.guess(for: property("at", ["2026-10-25T09:30"])) == .datetime)
        #expect(PropertyType.guess(for: property("done", ["true"])) == .checkbox)
        #expect(PropertyType.guess(for: property("rating", ["4.5"])) == .number)
        #expect(PropertyType.guess(for: property("people", ["Ann", "Bo"], isList: true)) == .list)
        #expect(PropertyType.guess(for: property("created", [])) == .date)
    }

    @Test func tagsAreAlwaysTags() {
        // However the note writes them: one word, or a list.
        #expect(PropertyType.guess(for: property("tags", ["work"])) == .tags)
        #expect(PropertyType.guess(for: property("tags", ["a", "b"], isList: true)) == .tags)
    }

    @Test func theVaultsTypeWins() {
        let types = PropertyTypes(raw: ["Rating": "text"])
        #expect(types.type(of: property("rating", ["4"])) == .text)
        #expect(types.type(of: property("status", ["4"])) == .number)
    }

    @Test func convertsBetweenTypes() {
        #expect(PropertyType.list.convert(["a, b,c"], from: .text) == ["a", "b", "c"])
        #expect(PropertyType.text.convert(["a", "b"], from: .list) == ["a, b"])
        #expect(PropertyType.tags.convert(["#work, ideas"], from: .text) == ["work", "ideas"])
        #expect(PropertyType.number.convert(["soon"], from: .text) == [])
        #expect(PropertyType.checkbox.convert(["TRUE"], from: .text) == ["true"])
        #expect(PropertyType.datetime.convert(["2026-10-25"], from: .date) == ["2026-10-25T00:00"])
        #expect(PropertyType.date.convert(["2026-10-25T09:30"], from: .datetime) == ["2026-10-25"])
    }

    @Test func savesWithoutLosingTheRestOfTheFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = #"{"types": {"due": "date", "plugin": "custom-kind"}, "other": 1}"#
        try Data(original.utf8).write(to: folder.appendingPathComponent("types.json"))

        var types = PropertyTypes.load(vault: root)
        #expect(types.type(forKey: "due") == .date)
        #expect(types.type(forKey: "plugin") == nil) // A type Point doesn't know.
        types.set(.number, forKey: "rating")
        try types.save(vault: root)

        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("types.json"))) as? [String: Any])
        #expect(saved["other"] as? Int == 1)
        #expect(saved["types"] as? [String: String] == ["due": "date", "plugin": "custom-kind", "rating": "number"])
        try? FileManager.default.removeItem(at: root)
    }
}
