import Foundation
import Testing
@testable import VaultKit

struct VaultChangeTransformTests {
    @Test func renamesAPropertyKeepingItsValueAndEverythingElse() throws {
        let text = "---\ntitle: A\nStatus: draft # soon\nrating: 4\n---\nBody status: here\n"
        #expect(try VaultChanges.renamingProperty("status", to: "state", in: text)
                == "---\ntitle: A\nstate: draft # soon\nrating: 4\n---\nBody status: here\n")
        // A list's items stay as they are.
        #expect(try VaultChanges.renamingProperty("people", to: "with", in: "---\npeople:\n  - \"[[Ann]]\"\n---\n")
                == "---\nwith:\n  - \"[[Ann]]\"\n---\n")
        #expect(try VaultChanges.renamingProperty("missing", to: "x", in: text) == nil)
        #expect(try VaultChanges.renamingProperty("status", to: "x", in: "No frontmatter.") == nil)
    }

    @Test func renamingToANameInUseClashes() {
        #expect(throws: VaultChanges.Clash.self) {
            try VaultChanges.renamingProperty("status", to: "Rating", in: "---\nstatus: a\nrating: 4\n---\n")
        }
    }

    @Test func caseOnlyRenamesWork() throws {
        #expect(try VaultChanges.renamingProperty("status", to: "Status", in: "---\nstatus: a\n---\n") == "---\nStatus: a\n---\n")
        #expect(try VaultChanges.renamingProperty("status", to: "status", in: "---\nstatus: a\n---\n") == nil)
    }

    @Test func aNameYAMLWouldMisreadIsQuoted() throws {
        #expect(try VaultChanges.renamingProperty("a", to: "#b", in: "---\na: 1\n---\n") == "---\n\"#b\": 1\n---\n")
    }

    @Test func renamesAValueAsWritten() {
        #expect(VaultChanges.renamingValue("Draft", to: "review", ofProperty: "status", in: "---\nstatus: draft\n---\nx")
                == "---\nstatus: review\n---\nx")
        // Quoted as before, and only that item in a list.
        #expect(VaultChanges.renamingValue("[[Sam Lee]]", to: "[[Sam Kim]]", ofProperty: "people",
                                           in: "---\npeople:\n  - \"[[Ann]]\"\n  - \"[[Sam Lee]]\"\n---\n")
                == "---\npeople:\n  - \"[[Ann]]\"\n  - \"[[Sam Kim]]\"\n---\n")
        // A list in brackets stays in brackets; a value it has already isn't doubled.
        #expect(VaultChanges.renamingValue("a", to: "b", ofProperty: "topics", in: "---\ntopics: [a, b, c]\n---\n")
                == "---\ntopics: [b, c]\n---\n")
        #expect(VaultChanges.renamingValue("x", to: "y", ofProperty: "status", in: "---\nstatus: draft\n---\n") == nil)
    }

    @Test func renamesTagsInPropertiesAndText() {
        let text = "---\ntags: [work, Work/Point, ideas]\n---\nMeeting #work and #work/point, not #workshop.\n"
        #expect(VaultChanges.renamingTag("work", to: "job", in: text)
                == "---\ntags: [job, job/Point, ideas]\n---\nMeeting #job and #job/point, not #workshop.\n")
        #expect(VaultChanges.renamingTag("#ideas", to: "thoughts", in: "---\ntags:\n  - ideas\n  - thoughts\n---\n")
                == "---\ntags:\n  - thoughts\n---\n")
        #expect(VaultChanges.renamingTag("work", to: "job", in: "---\ntags: work ideas\n---\n") == "---\ntags: job ideas\n---\n")
        #expect(VaultChanges.renamingTag("none", to: "x", in: text) == nil)
    }

    @Test func tagsInCodeStayAsTheyAre() {
        #expect(VaultChanges.renamingTag("work", to: "job", in: "`#work` and #work\n") == "`#work` and #job\n")
    }
}

struct VaultChangeTests {
    private func vault(_ files: [String: String]) throws -> (URL, [Note]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultChanges-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return (root, try VaultScanner.scan(root))
    }

    @Test func appliesAndUndoes() throws {
        let (root, notes) = try vault(["A.md": "---\nstatus: a\n---\n", "B.md": "---\nstatus: b\nstate: c\n---\n", "C.md": "Nothing."])
        defer { try? FileManager.default.removeItem(at: root) }
        let change = VaultChanges.apply("Renamed", to: notes) { try VaultChanges.renamingProperty("status", to: "state", in: $0) }
        #expect(change.updatedNotes == ["A.md"])
        #expect(change.clashingNotes == ["B.md"])
        #expect(try String(contentsOf: root.appendingPathComponent("A.md"), encoding: .utf8) == "---\nstate: a\n---\n")
        #expect(VaultChanges.undo(change).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("A.md"), encoding: .utf8) == "---\nstatus: a\n---\n")
    }

    @Test func undoLeavesANoteChangedSince() throws {
        let (root, notes) = try vault(["A.md": "---\nstatus: a\n---\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let change = VaultChanges.apply("Renamed", to: notes) { try VaultChanges.renamingProperty("status", to: "state", in: $0) }
        let url = root.appendingPathComponent("A.md")
        try Data("---\nstate: a\n---\nEdited since.\n".utf8).write(to: url)
        #expect(VaultChanges.undo(change) == ["A.md"])
        #expect(try String(contentsOf: url, encoding: .utf8) == "---\nstate: a\n---\nEdited since.\n")
    }
}
