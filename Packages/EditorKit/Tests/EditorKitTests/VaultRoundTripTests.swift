import AppKit
import Foundation
import Testing
@testable import EditorKit

/// Opens every note in a vault in the real editor and checks nothing changes.
///
/// Read-only: no file is ever written. Point it at a vault with
/// `IMPRINT_ROUNDTRIP_VAULT=/path/to/vault swift test --filter VaultRoundTripTests`.
@MainActor
struct VaultRoundTripTests {
    nonisolated static let vaultPath = ProcessInfo.processInfo.environment["IMPRINT_ROUNDTRIP_VAULT"]

    @Test(.enabled(if: vaultPath != nil))
    func everyNoteRoundTripsByteForByte() throws {
        let root = URL(fileURLWithPath: Self.vaultPath!)
        let files = markdownFiles(in: root)
        #expect(!files.isEmpty)

        let editor = EditorTestSupport.makeEditor("", height: 800)
        var notUTF8: [String] = []
        var changedByLoading: [String] = []
        var changedByUndo: [String] = []
        var slowest: (path: String, seconds: Double) = ("", 0)
        var largest: (url: URL, size: Int) = (root, 0)
        let started = Date()

        for url in files {
            let path = String(url.path.dropFirst(root.path.count + 1))
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard Data(text.utf8) == data else {
                notUTF8.append(path) // These open read-only in the app.
                continue
            }
            if data.count > largest.size { largest = (url, data.count) }

            let loadStart = Date()
            editor.load(text)
            let seconds = Date().timeIntervalSince(loadStart)
            if seconds > slowest.seconds { slowest = (path, seconds) }

            if Data(editor.string.utf8) != data {
                changedByLoading.append(path)
                continue
            }

            // Format something in the middle, then undo: the bytes must come back exactly.
            let length = (editor.string as NSString).length
            editor.setSelectionDirectly(NSRange(location: length / 2, length: 0))
            editor.toggleBold(nil)
            editor.makeHeading2(nil)
            editor.undoManager?.undo()
            editor.undoManager?.undo()
            if Data(editor.string.utf8) != data {
                changedByUndo.append(path)
            }
        }

        let total = Date().timeIntervalSince(started)
        print("""
        ROUND-TRIP: \(files.count) notes in \(String(format: "%.1f", total)) s
          not UTF-8 (read-only): \(notUTF8.count) \(notUTF8.prefix(5))
          changed by loading: \(changedByLoading.count) \(changedByLoading.prefix(5))
          changed by format + undo: \(changedByUndo.count) \(changedByUndo.prefix(5))
          slowest load: \(slowest.path) \(String(format: "%.1f", slowest.seconds * 1000)) ms
        """)
        #expect(changedByLoading.isEmpty)
        #expect(changedByUndo.isEmpty)

        if largest.size > 0 {
            measureTyping(in: try String(contentsOf: largest.url, encoding: .utf8), name: largest.url.lastPathComponent)
        }
    }

    /// Times opening a note to its first screen, then typing in its middle.
    private func measureTyping(in text: String, name: String) {
        let editor = EditorTestSupport.makeEditor("", height: 800)
        let layoutStart = Date()
        editor.load(text)
        editor.layoutManager!.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: 760, height: 1000), in: editor.textContainer!)
        let layout = Date().timeIntervalSince(layoutStart)

        let middle = (editor.string as NSString).length / 2
        editor.setSelectionDirectly(NSRange(location: middle, length: 0))
        var worst = 0.0
        let typingStart = Date()
        let keys = Array("The quick brown fox jumps over the lazy dog. ")
        for character in keys {
            let start = Date()
            editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            let caret = editor.selectedRange().location
            editor.layoutManager!.ensureLayout(forCharacterRange: NSRange(location: max(0, caret - 2000), length: 4000))
            worst = max(worst, Date().timeIntervalSince(start))
        }
        let average = Date().timeIntervalSince(typingStart) / Double(keys.count)
        print("""
        TYPING in largest note \(name) (\((text as NSString).length) characters):
          open + first screen \(String(format: "%.0f", layout * 1000)) ms; per keystroke avg \(String(format: "%.1f", average * 1000)) ms, worst \(String(format: "%.1f", worst * 1000)) ms
        """)
    }

    private func markdownFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants() }
            } else if url.pathExtension.lowercased() == "md", !url.lastPathComponent.hasPrefix(".") {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
