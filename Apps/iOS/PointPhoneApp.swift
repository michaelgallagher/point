import EditorKit
import SwiftUI
import VaultKit

/// The iPhone app (M4; see plan/m4-iphone.md): home, with search, bookmarks and recent notes,
/// and a note in the shared editor.
@main
struct PointPhoneApp: App {
    @StateObject private var store = PhoneStore()

    var body: some Scene {
        WindowGroup {
            HomeScreen()
                .environmentObject(store)
        }
    }
}

/// The vault on the phone, for now: a folder in the app's Documents, which the Files app
/// shows (copy notes in there). Two notes for measuring are made the first time.
enum PhoneVault {
    static let root: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    /// A long note with most kinds of Markdown, to time opening and typing; and a short one.
    /// `-SpikeSections <n>` for a longer one: 150 is about 45,000 characters, 900 about 270,000.
    static var sections: Int { max(UserDefaults.standard.integer(forKey: "SpikeSections"), 150) }
    /// The long note's title, by its length, so notes of each length can be kept side by side.
    static var longTitle: String { sections == 150 ? "Spike, long note" : "Spike, long note (\(sections) sections)" }

    static func makeSampleNotes() {
        let long = root.appendingPathComponent(longTitle + ".md")
        guard !FileManager.default.fileExists(atPath: long.path) else { return }
        var text = "---\ntags: [spike]\nstatus: draft\n---\n# A long note\n\n"
        for section in 1...sections {
            text += "## Section \(section)\n\n"
            text += "Some **bold** and *italic* text, a [[Link to a note]], a #tag, and `code`. "
            text += "Another sentence so the paragraph wraps across a few lines on a phone screen.\n\n"
            text += "- A bullet\n  - Nested under it\n- [ ] A task to do\n- [x] A task done\n1. Numbered\n2. Items\n\n"
            text += "> A quote, with ==highlighted== words.\n\n"
            if section % 10 == 0 { text += "```\nlet code = \(section)\n```\n\n" }
        }
        try? Data(text.utf8).write(to: long)
        try? Data("# A short note\n\nJust a few lines.\n\n- [ ] Try typing here\n".utf8)
            .write(to: root.appendingPathComponent("Spike, short note.md"))
    }

    /// Timings, appended to `spike-timings.txt` beside the vault (in Files), to read later.
    static func log(_ line: String) {
        let url = root.deletingLastPathComponent().appendingPathComponent("spike-timings.txt")
        let stamped = "\(Date().formatted(date: .numeric, time: .standard)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }
}

