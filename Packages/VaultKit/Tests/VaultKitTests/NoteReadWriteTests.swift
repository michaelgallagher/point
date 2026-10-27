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

    /// From the review of 27 October: a note deleted in another app was quietly written again
    /// by the next save. Nothing's written, and the save says why.
    @Test func aDeletedNoteIsntRecreated() throws {
        let url = try file(Data("original".utf8))
        try FileManager.default.removeItem(at: url)
        #expect(throws: NoteWriter.WriteError.missing) { try NoteWriter.write("mine", to: url, expecting: "original") }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Only when asked, and never over a file that's appeared since.
        try NoteWriter.recreate("mine", at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "mine")
        #expect(throws: (any Error).self) { try NoteWriter.recreate("again", at: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "mine")
    }

    /// A note that can't be read can't be checked, so it isn't written over.
    @Test func anUnreadableNoteIsntWrittenOver() throws {
        let url = try file(Data("original".utf8))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: url.path) // Write only.
        #expect(throws: (any Error).self) { try NoteWriter.write("mine", to: url, expecting: "original") }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try String(contentsOf: url, encoding: .utf8) == "original")
    }

    /// From the review of 27 October: two conflict copies in the same second had the same
    /// name, and the second replaced the first.
    @Test func conflictCopiesInTheSameSecondAreBothKept() throws {
        let url = try file(Data("theirs".utf8))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try NoteWriter.writeConflictCopy("first", beside: url, date: date)
        let second = try NoteWriter.writeConflictCopy("second", beside: url, date: date)
        defer { [url, first, second].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(first != second)
        #expect(second.lastPathComponent.hasSuffix(") 2.md"))
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }
}
