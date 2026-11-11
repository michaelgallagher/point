import Foundation
import Testing
@testable import ClipKit
import VaultKit

/// Reader mode's writes to your notes, tried on every clip of a copy of a real vault, in memory
/// (see `plan/reader-mode.md` and `plan/live-vault-safety.md`). Runs only when
/// `POINT_AUDIT_COPY` names a copy of a vault; reads only. Writes a report to
/// `POINT_AUDIT_REPORT`, and the clips' paths, one a line, to `POINT_AUDIT_CLIPS` (for
/// EditorKit's highlighting audit).
struct ReaderNotesAudit {
    @Test func everyClipKeepsAllButItsNotes() throws {
        guard let path = ProcessInfo.processInfo.environment["POINT_AUDIT_COPY"] else { return }
        let root = URL(fileURLWithPath: path)
        let kinds = NoteKinds.load(vault: root)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" } ?? []
        var clips: [String] = []
        var withMarker = 0
        var failures: [String] = []
        var tidied = 0
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard Data(text.utf8) == data, Reading.opensForReading(text, kinds: kinds) else { continue }
            let name = url.path.replacingOccurrences(of: root.path + "/", with: "")
            clips.append(name)
            if ReaderNotes.markerLine(in: text) != nil { withMarker += 1 }
            for problem in Self.problems(in: text, tidied: &tidied) { failures.append("\(name): \(problem)") }
        }
        var report = "# Reader notes audit\n\n- Clips: \(clips.count)\n- With the marker already: \(withMarker)\n- Whitespace at the end of the notes tidied on saving: \(tidied)\n- Problems: \(failures.count)\n"
        report += failures.map { "  - \($0)\n" }.joined()
        let out = ProcessInfo.processInfo.environment["POINT_AUDIT_REPORT"] ?? NSTemporaryDirectory() + "reader-notes-audit.md"
        try report.write(toFile: out, atomically: true, encoding: .utf8)
        if let list = ProcessInfo.processInfo.environment["POINT_AUDIT_CLIPS"] {
            try clips.joined(separator: "\n").write(toFile: list, atomically: true, encoding: .utf8)
        }
        #expect(failures.isEmpty)
    }

    /// What's wrong with setting, adding to and clearing the notes of one clip.
    static func problems(in text: String, tidied: inout Int) -> [String] {
        var problems: [String] = []
        let ns = text as NSString
        let start = ReaderNotes.bodyStart(of: text)
        let head = ns.substring(to: start)
        let properties = Frontmatter.parse(text)?.properties.map { "\($0.key)=\($0.values)" }

        // What follows the notes: from the marker on, or (no marker yet) the body as it was.
        func rest(of changed: String) -> String? {
            guard let line = ReaderNotes.markerLine(in: changed) else { return nil }
            return (changed as NSString).substring(from: NSMaxRange(line))
        }
        let restBefore: String = {
            if let line = ReaderNotes.markerLine(in: text) { return ns.substring(from: NSMaxRange(line)) }
            let body = ns.substring(from: start).replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
            return body.isEmpty ? "\n" : "\n\n" + body
        }()

        func check(_ changed: String, _ step: String, notes expected: String) {
            let cns = changed as NSString
            if !changed.hasPrefix(head.hasSuffix("\n") || head.isEmpty ? head : head + "\n") { problems.append("\(step): properties changed") }
            if Frontmatter.parse(changed)?.properties.map({ "\($0.key)=\($0.values)" }) != properties { problems.append("\(step): properties read differently") }
            if rest(of: changed) != restBefore { problems.append("\(step): saved text changed") }
            let read = ReaderNotes.notes(in: changed)
            if read != expected {
                let a = Array(read), b = Array(expected)
                let at = zip(a, b).prefix { $0 == $1 }.count
                func around(_ c: [Character]) -> String { String(c[max(0, at - 12)..<min(c.count, at + 12)]).debugDescription }
                problems.append("\(step): notes read back differently at \(at) of \(b.count): \(around(a)) for \(around(b))")
            }
            if cns.range(of: ReaderNotes.marker).location == NSNotFound { problems.append("\(step): no marker") }
            if changed.contains("\n\n\n" + ReaderNotes.marker) { problems.append("\(step): extra blank lines before the marker") }
        }

        // Saving the notes as they are: with a marker, nothing at all changes.
        let existing = ReaderNotes.notes(in: text)
        let same = ReaderNotes.settingNotes(existing, in: text)
        // (Saving only happens once the notes are changed; then the blank lines and spaces at
        // their end are tidied, and nothing else may differ.)
        if ReaderNotes.markerLine(in: text) != nil, same != text {
            if same.filter({ !$0.isWhitespace }) == text.filter({ !$0.isWhitespace }) { tidied += 1 } else { problems.append("unchanged notes: text changed") }
        }
        check(same, "unchanged notes", notes: existing.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .newlines))

        // A note typed, a quote added, then the notes cleared.
        let typed = (existing.isEmpty ? "" : existing + "\n\n") + "A thought, with *emphasis* and a [[Link]]."
        let withNote = ReaderNotes.settingNotes(typed, in: same)
        check(withNote, "a note typed", notes: typed)
        let quoted = ReaderNotes.addingQuote("A line of the article,\nand the next.", to: typed).notes
        let withQuote = ReaderNotes.settingNotes(quoted, in: withNote)
        check(withQuote, "a quote added", notes: quoted.trimmingCharacters(in: .newlines))
        let back = ReaderNotes.settingNotes(existing, in: withQuote)
        if back != same { problems.append("notes put back: text differs from before") }
        let cleared = ReaderNotes.settingNotes("", in: withQuote)
        check(cleared, "notes cleared", notes: "")
        return problems
    }
}
