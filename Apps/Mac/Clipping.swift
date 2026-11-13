import AppKit
import ClipKit
import IndexKit
import VaultKit

/// Requests to clip a page (`point://clip?url=…`, from the browser extension), kept until the
/// vault is ready to take them.
@MainActor
final class ClipInbox {
    static let shared = ClipInbox()
    private var waiting: [ClipRequest] = []

    /// Who clips: the vault, once it has a window. Requests that came first are passed on.
    var handler: ((ClipRequest) -> Void)? {
        didSet {
            guard let handler else { return }
            let requests = waiting
            waiting = []
            requests.forEach(handler)
        }
    }

    /// Takes the addresses macOS opens Point with; any that aren't clips are ignored.
    func open(_ urls: [URL]) {
        for request in urls.compactMap(ClipRequest.init) {
            if let handler { handler(request) } else { waiting.append(request) }
        }
    }
}

/// Receives `point://` addresses. With this, SwiftUI doesn't open a window for each one.
final class PointAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { ClipInbox.shared.open(urls) }
    }
}

extension VaultStore {
    /// The kind clipped pages are: Media, or the like, if the vault has one.
    var clipKind: NoteKinds.Kind? { Clipping.kind(in: kinds) }

    /// Clips a page into the vault and opens it: its article as a note of the clip kind (in
    /// that kind's folder, from its template), or a note with a link if the article can't be
    /// read. A page clipped before opens its note again.
    func clip(_ request: ClipRequest) {
        Task { @MainActor in
            // Opened by the link, Point may still be reading the vault.
            for _ in 0..<100 where root == nil || index == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard root != nil else { return }
            NSApp.activate(ignoringOtherApps: true)

            if let existing = await clippedNote(of: request.url) {
                open(existing)
                vaultChangeNotice = VaultChangeNotice(text: "Clipped before", canUndo: false, symbol: "doc.on.doc")
                return
            }
            // Perhaps clipped before at another address, or under a title all but the same.
            let candidates = await clipCandidates()
            var asked = false
            let early = ClipMatching.nearMisses(url: request.url, title: request.title, among: candidates)
            if !early.isEmpty {
                asked = true
                guard decide(early, title: request.title ?? request.url.host ?? "This page") else { return }
            }
            let shownTitle = request.title ?? request.url.host ?? "the page"
            vaultChangeNotice = VaultChangeNotice(text: "Clipping “\(shownTitle)”…", canUndo: false, symbol: "scissors", isWorking: true)

            let (clip, couldRead) = await Clipping.read(request)
            // A redirect may lead to a page clipped before.
            if let existing = await clippedNote(of: clip.url) {
                open(existing)
                vaultChangeNotice = VaultChangeNotice(text: "Clipped before", canUndo: false, symbol: "doc.on.doc")
                return
            }
            // Its title, now it's known (the link may not have said), or where it led.
            if !asked {
                let late = ClipMatching.nearMisses(url: clip.url, title: clip.title, among: candidates)
                if !late.isEmpty {
                    vaultChangeNotice = nil
                    guard decide(late, title: clip.title) else { return }
                }
            }

            let kind = clipKind
            let folder = kind?.folder ?? Clipping.defaultFolder
            let template = kind.flatMap { templates(of: $0).first?.url }.flatMap { try? NoteReader.read(contentsOf: $0) }
            let (title, text) = Clipping.note(for: clip, request: request, kind: kind, template: template,
                                              typeProperty: kinds.property, settings: settings)
            if let root { try? FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
            // Named as its title alone, without the day: a clip is the page's, not the day's.
            guard let id = createNote(text: text, titled: title.isEmpty ? nil : title, inFolder: folder, dated: false) else {
                vaultChangeNotice = nil
                return
            }
            open(id)
            vaultChangeNotice = VaultChangeNotice(text: couldRead ? "Clipped to \(folder)" : "Couldn’t read the page, so the note has its link",
                                                  canUndo: false, symbol: couldRead ? "checkmark.circle" : "exclamationmark.triangle")
        }
    }

    /// Every note, with where it was clipped from if it says, to look for near misses in.
    private func clipCandidates() async -> [ClipMatching.Candidate] {
        let sources = (try? await index?.firstValues(of: ["source"])) ?? [:]
        return notesByID.values.map { ClipMatching.Candidate(id: $0.id, title: $0.title, source: sources[$0.id]?["source"]) }
            .sorted { $0.id < $1.id }
    }

    /// Asks whether a page that may be in the vault already should be clipped: true to clip it
    /// anyway. Opening the note it most likely is, or cancelling, is false.
    private func decide(_ matches: [ClipMatching.Match], title: String) -> Bool {
        vaultChangeNotice = nil
        let alert = NSAlert()
        alert.messageText = "Saved already?"
        alert.informativeText = "“\(title)” may be in your notes already:\n"
            + matches.map { "“\($0.title)”: \($0.why.lowercased())" }.joined(separator: "\n")
        alert.addButton(withTitle: "Open “\(matches[0].title)”")
        alert.addButton(withTitle: "Clip anyway")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            open(matches[0].id)
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    /// The note already clipped from this page, if any: its `source` is the address.
    private func clippedNote(of url: URL) async -> Note.ID? {
        guard let index else { return nil }
        for address in Clipping.sources(of: url) {
            if let id = try? await index.notes(matching: NoteQuery([.property("source", .equals(address))])).first,
               notesByID[id] != nil { return id }
        }
        return nil
    }

    /// Opens a note in the frontmost window, in a new tab unless the window shows none.
    private func open(_ id: Note.ID) {
        guard let window = activeWindow else { return }
        if window.selection == nil { window.selection = id } else { window.newTab(noteID: id) }
    }
}
