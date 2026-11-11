import Foundation
import Testing
@testable import EditorKit
import MarkdownKit

/// Reader mode's highlighting, tried on every clip of a copy of a real vault, in memory (see
/// `plan/reader-mode.md`). Runs only when `POINT_AUDIT_COPY` names a copy of a vault and
/// `POINT_AUDIT_CLIPS` lists its clips, one path a line (ClipKit's `ReaderNotesAudit` writes
/// it); reads only. Writes a report to `POINT_AUDIT_REPORT`.
struct HighlightingAudit {
    static let marker = "==---- Text ----=="

    @Test func highlightingChangesOnlyHighlights() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["POINT_AUDIT_COPY"], let list = env["POINT_AUDIT_CLIPS"] else { return }
        let root = URL(fileURLWithPath: path)
        let clips = try String(contentsOfFile: list, encoding: .utf8).split(separator: "\n").map(String.init)
        var random = SeededRandom(seed: 7)
        var selections = 0, highlighted = 0, unchanged = 0
        var problems: [String] = []
        for name in clips {
            guard let text = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) else { continue }
            let ns = text as NSString
            let start = Self.articleStart(of: text)
            guard ns.length - start > 2 else { continue }
            // Selections of every size, and the whole article.
            var ranges = (0..<20).map { _ -> NSRange in
                let location = start + Int(random.next() % UInt64(ns.length - start - 1))
                let length = 1 + Int(random.next() % UInt64(min(600, ns.length - location)))
                return NSRange(location: location, length: min(length, ns.length - location))
            }
            ranges.append(NSRange(location: start, length: ns.length - start))
            for range in ranges {
                selections += 1
                for problem in Self.problems(text, range, articleStart: start, highlighted: &highlighted, unchanged: &unchanged) {
                    problems.append("\(name) \(range.location)+\(range.length): \(problem)")
                }
            }
        }
        var report = "# Highlighting audit\n\n- Clips: \(clips.count)\n- Selections: \(selections)\n- Highlighted: \(highlighted)\n- Nothing to highlight (already highlighted, or only spaces or code): \(unchanged)\n- Problems: \(problems.count)\n"
        report += problems.map { "  - \($0)\n" }.joined()
        try report.write(toFile: env["POINT_AUDIT_REPORT"] ?? NSTemporaryDirectory() + "highlighting-audit.md", atomically: true, encoding: .utf8)
        #expect(problems.isEmpty)
    }

    /// Where the article starts: after the marker's line, or the frontmatter, or 0.
    static func articleStart(of text: String) -> Int {
        let ns = text as NSString
        var found: Int?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, enclosing, stop in
            if line?.trimmingCharacters(in: .whitespaces) == marker { found = NSMaxRange(enclosing); stop.pointee = true }
        }
        if let found { return found }
        let editing = MarkdownEditing(text: text, selection: NSRange(location: 0, length: 0))
        return editing.tokens.first { $0.kind == .frontmatter }.map { NSMaxRange($0.range) } ?? 0
    }

    static func kindCounts(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in MarkdownEditing(text: text, selection: NSRange(location: 0, length: 0)).tokens where token.kind != .highlight {
            counts["\(token.kind)", default: 0] += 1
        }
        return counts
    }

    static func problems(_ text: String, _ range: NSRange, articleStart: Int, highlighted: inout Int, unchanged: inout Int) -> [String] {
        var problems: [String] = []
        let ns = text as NSString
        let editing = MarkdownEditing(text: text, selection: range)
        let quote = editing.quotableSelection(skipping: marker)
        if quote.contains("==") && !ns.substring(with: range).contains("==") { problems.append("quote has highlight markers | " + ns.substring(with: range).prefix(300).debugDescription + " -> " + quote.prefix(300).debugDescription) }
        guard let edit = editing.highlightingSelection(skipping: marker) else { unchanged += 1; return problems }
        highlighted += 1
        let new = ns.replacingCharacters(in: edit.range, with: edit.replacement)
        let strip = { (s: String) in s.replacingOccurrences(of: "==", with: "") }
        let detail = " | " + ns.substring(with: edit.range).prefix(400).debugDescription + " -> " + edit.replacement.prefix(400).debugDescription
        if edit.range.location < articleStart { problems.append("changed before the article") }
        if strip(new) != strip(text) { problems.append("changed more than highlight markers" + detail) }
        if kindCounts(new) != kindCounts(text) { problems.append("other formatting parsed differently" + detail) }
        // Selected again inside the new markers, there's nothing more to do.
        let inside = NSRange(location: edit.selection.location + 2, length: edit.selection.length - 4)
        if let again = MarkdownEditing(text: new, selection: inside).highlightingSelection(skipping: marker) {
            let was = (new as NSString).substring(with: again.range)
            problems.append("highlighting again would change it (not fully highlighted) | again: " + was.prefix(300).debugDescription + " -> " + again.replacement.prefix(300).debugDescription)
        }
        // Taking them off again leaves only the text.
        if let removal = MarkdownEditing(text: new, selection: edit.selection).removingHighlights(skipping: marker) {
            let removed = (new as NSString).replacingCharacters(in: removal.range, with: removal.replacement)
            if strip(removed) != strip(text) { problems.append("removing changed more than highlight markers") }
            if kindCounts(removed) != kindCounts(text) { problems.append("removing: other formatting parsed differently") }
        } else {
            problems.append("nothing to remove after highlighting" + detail)
        }
        return problems
    }
}

/// A repeatable sequence of numbers, so a run can be repeated.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
