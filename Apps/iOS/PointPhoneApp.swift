import ClipKit
import EditorKit
import SwiftUI
import VaultKit

/// The iPhone app (M4; see plan/m4-iphone.md): home, with search, bookmarks and recent notes,
/// and a note in the shared editor.
@main
struct PointPhoneApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var vault = VaultChoice()

    init() { _ = PhoneVault.launched }

    var body: some Scene {
        WindowGroup {
            VaultRoot(store: vault.store)
                .environmentObject(vault)
                // Another vault chosen: everything shown is made again, from its store.
                .id(ObjectIdentifier(vault.store))
                .alert("Couldn’t open your vault", isPresented: Binding(get: { vault.problem != nil }, set: { if !$0 { vault.problem = nil } })) {
                    Button("OK") { vault.problem = nil }
                } message: {
                    Text(vault.problem ?? "")
                }
        }
    }
}

/// Home, and what shows over it, for one vault's store.
private struct VaultRoot: View {
    @ObservedObject var store: PhoneStore

    var body: some View {
        HomeScreen()
            .environmentObject(store)
            .environmentObject(store.search)
            // Until the vault's been read: home, half filled in, showed lists still filling
            // and "No notes" for a moment.
            .overlay {
                ZStack {
                    if !store.isReady { LaunchCover().transition(.opacity) }
                }
                .animation(.easeOut(duration: 0.3), value: store.isReady)
            }
            // How a clip is going, over whatever's showing.
            .overlay(alignment: .bottom) {
                ZStack {
                    if let status = store.clipStatus { ClipStatusView(status: status).transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .animation(.spring(duration: 0.3, bounce: 0), value: store.clipStatus)
            }
            .alert("Changed on two devices", isPresented: Binding(get: { store.conflictNotice != nil },
                                                                 set: { if !$0 { store.conflictNotice = nil } })) {
                Button("OK") { store.conflictNotice = nil }
            } message: {
                Text(store.conflictNotice ?? "")
            }
            // `point://clip?url=…`, from the share sheet's Clip to Point shortcut.
            .onOpenURL { url in
                if let request = ClipRequest(url) { store.clip(request) }
            }
    }
}

/// What shows while the app gets ready: the app icon's eye in the middle of the page, on the
/// system background (white, or black in dark mode). It follows the launch screen, which is the same.
private struct LaunchCover: View {
    var body: some View {
        // The launch screen's own eye, the app icon's (in Info.plist), centred on the whole screen as it is
        // there, not in the safe area.
        ZStack {
            Color(.systemBackground)
            Image("LaunchEye")
        }
        .ignoresSafeArea()
        .accessibilityElement()
            .accessibilityLabel("Loading")
    }
}

/// How a clip is going: a capsule above the bottom of the screen.
private struct ClipStatusView: View {
    let status: ClipStatus

    var body: some View {
        HStack(spacing: 8) {
            if status.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: status.symbol)
            }
            Text(status.text)
                .lineLimit(2)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 64)
        .accessibilityElement(children: .combine)
    }
}

/// New Note from the app icon's quick action (pressing and holding the icon), passed to home.
@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()
    static let newNote = "org.mikegallagher.point.newNote" // As in Info.plist.
    /// Goes up each time New Note is chosen.
    @Published private(set) var newNoteRequests = 0
    /// How many of those home has made a note for. Each is made once: home appearing again
    /// (iOS can build it afresh, waking the app) made another, empty, as a count alone did.
    private var newNotesMade = 0

    func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.newNote else { return false }
        newNoteRequests += 1
        return true
    }

    /// Whether a New Note chosen is still to be made; if so, it's taken.
    func takeNewNote() -> Bool {
        guard newNotesMade < newNoteRequests else { return false }
        newNotesMade = newNoteRequests
        return true
    }
}

/// Hands the quick action to `QuickActions`, whether it launched the app or found it running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { _ = QuickActions.shared.perform(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.shared.perform(shortcutItem))
    }
}

/// The vault on the phone: Point's own folder in the app's Documents, which the Files app
/// shows (copy notes in there), or a folder chosen in Files, such as the Obsidian vault in
/// iCloud Drive (see `VaultChoice`). Two notes for measuring are made in Point's own folder
/// the first time, never in a chosen one.
enum PhoneVault {
    /// When the app started, for timing how long it takes to be ready.
    static let launched = CACurrentMediaTime()
    /// Point's own folder, in its Documents.
    static let ownFolder: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    /// The vault in use, and its key for what the phone keeps about it. Set by `VaultChoice`
    /// on the main thread, before each `PhoneStore` is made, which reads them once.
    nonisolated(unsafe) private(set) static var root = ownFolder
    nonisolated(unsafe) private(set) static var key = ownKey
    /// Point's own folder's key: what's kept about it stays where it always was.
    static let ownKey = "phone"
    static var isOwnFolder: Bool { key == ownKey }

    static func use(_ root: URL, key: String) {
        self.root = root
        self.key = key
    }

    /// A defaults key for something kept about the vault in use (the note being worked on,
    /// untitled notes, favourites): each vault has its own, so one never acts on another's notes.
    static func defaultsKey(_ name: String) -> String { isOwnFolder ? name : "\(key).\(name)" }

    /// Where something kept about the vault in use goes in the app's own storage, never in the
    /// vault: the search index, what search has learned, drafts.
    static func storage(_ path: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(isOwnFolder ? path : "Vaults/\(key)/\(path)")
    }

    /// A long note with most kinds of Markdown, to time opening and typing; and a short one.
    /// `-SpikeSections <n>` for a longer one: 150 is about 45,000 characters, 900 about 270,000.
    static var sections: Int { max(UserDefaults.standard.integer(forKey: "SpikeSections"), 150) }
    /// The long note's title, by its length, so notes of each length can be kept side by side.
    static var longTitle: String { sections == 150 ? "Spike, long note" : "Spike, long note (\(sections) sections)" }

    static func makeSampleNotes() {
        let root = ownFolder
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

    /// Timings, appended to `spike-timings.txt` beside Point's own folder (in Files), to read
    /// later: never in a chosen vault.
    static func log(_ line: String) {
        let url = ownFolder.deletingLastPathComponent().appendingPathComponent("spike-timings.txt")
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

