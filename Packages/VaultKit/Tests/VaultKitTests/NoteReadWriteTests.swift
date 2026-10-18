import Foundation
import Testing
@testable import VaultKit

struct NoteReadWriteTests {
    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoteRW-\(UUID().uuidString).md")
        try data.write(to: url)
        return url
    }

    @Test func readsAndWritesBackTheSameBytes() throws {
        let bytes = Data("\u{FEFF}# Café\r\nline two\n\n".utf8) // BOM, CRLF and non-ASCII survive.
        let url = try file(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try NoteReader.read(contentsOf: url)
        #expect(try NoteWriter.write(text, to: url, expecting: text) == .saved)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func refusesInvalidUTF8() throws {
        let url = try file(Data([0x61, 0xFF, 0x62]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: NoteReader.ReadError.notLossless) { try NoteReader.read(contentsOf: url) }
    }

    @Test func keepsTheCreationDate() throws {
        let url = try file(Data("a".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        _ = try NoteWriter.write("b", to: url, expecting: "a")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.creationDate] as? Date == created)
    }

    @Test func changesMadeElsewhereAreNeverOverwritten() throws {
        let url = try file(Data("changed in Obsidian".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let outcome = try NoteWriter.write("my edit", to: url, expecting: "original")
        guard case .savedAsConflictCopy(let copy) = outcome else {
            Issue.record("Expected a conflict copy, got \(outcome)")
            return
        }
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "changed in Obsidian")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "my edit")
        #expect(copy.lastPathComponent.contains("(conflict "))
    }

    @Test func canReportAChangeInsteadOfWriting() throws {
        let url = try file(Data("theirs".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try NoteWriter.write("mine", to: url, expecting: "original", ifChanged: .report) == .changedOnDisk("theirs"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "theirs")
    }
}
