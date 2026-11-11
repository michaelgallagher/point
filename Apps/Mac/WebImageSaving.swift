import AppKit
import VaultKit

/// Which open notes embed pictures from the web, so the menu offers to keep them only where
/// there are some, and which are being kept now.
@MainActor
final class WebImageNotes: ObservableObject {
    static let shared = WebImageNotes()

    @Published private(set) var withWebImages: Set<Note.ID> = []
    @Published private(set) var saving: Set<Note.ID> = []

    /// Notes the note's text as it is now (loaded or saved): a quick look, not a parse.
    func note(_ id: Note.ID, in text: String) {
        let has = WebImages.mightHaveAny(in: text)
        if has != withWebImages.contains(id) {
            if has { withWebImages.insert(id) } else { withWebImages.remove(id) }
        }
    }

    func canSave(_ id: Note.ID?) -> Bool {
        guard let id else { return false }
        return withWebImages.contains(id) && !saving.contains(id)
    }

    fileprivate func setSaving(_ id: Note.ID, _ isSaving: Bool) {
        if isSaving { saving.insert(id) } else { saving.remove(id) }
    }
}

extension VaultStore {
    /// Keeps a note's web pictures in the vault: downloads them all at once, saves each in the
    /// attachment folder named after the note (as a pasted image is), and points the note at
    /// the copies, as one step to undo. Typing goes on meanwhile. A picture that can't be
    /// downloaded stays as it was; an alert says how it went.
    func saveWebImages(in note: Note) {
        guard let root, !WebImageNotes.shared.saving.contains(note.id) else { return }
        let session = EditorSession.editing(note.id)
        guard let text = session?.text ?? (try? NoteReader.read(contentsOf: note.url)) else {
            return Self.showProblem("Couldn’t read “\(note.title)”")
        }
        let addresses = WebImages.find(in: text).map(\.address)
        guard !addresses.isEmpty else {
            WebImageNotes.shared.note(note.id, in: "")
            return Self.showNotice("“\(note.title)” has no images from the web", detail: "Nothing was changed.")
        }
        let settings = settings
        let taken = Set(images.map { $0.name.lowercased() })
        WebImageNotes.shared.setSaving(note.id, true)
        Trace.mark("web images: downloading \(Set(addresses).count)")
        Task {
            let downloads = await WebImages.download(addresses)
            var unique: [String] = []
            for address in addresses where !unique.contains(address) { unique.append(address) }
            let ready = unique.compactMap { address in (try? downloads[address]?.get()).map { (address, $0) } }
            for address in unique { if case .failure(let failure)? = downloads[address] { NSLog("Point: couldn't download \(address): \(failure)") } }
            let result = await Task.detached(priority: .userInitiated) {
                WebImages.save(ready, forNote: note, vault: root, setting: settings.attachmentFolder, taken: taken)
            }.value
            add(Array(result.saved.values))
            pointNote(note, at: result.saved, root: root, style: WebImages.LinkStyle(settings: settings))
            WebImageNotes.shared.setSaving(note.id, false)
            Trace.mark("web images: saved \(result.saved.count) of \(unique.count)")
            report(saved: result.saved.count, of: unique.count, in: note)
        }
    }

    /// Points a note at the saved copies of its pictures: in its editor if it's open (one step
    /// to undo, around anything typed meanwhile), else in its file.
    private func pointNote(_ note: Note, at saved: [String: VaultImage], root: URL, style: WebImages.LinkStyle) {
        guard !saved.isEmpty else { return }
        if let session = EditorSession.editing(note.id), let text = session.text {
            session.applyEdits(WebImages.edits(for: text, saved: saved, noteURL: note.url, root: root, style: style))
            return
        }
        let change = VaultChanges.apply("Saved web images", to: [note]) { text in
            let edits = WebImages.edits(for: text, saved: saved, noteURL: note.url, root: root, style: style)
            return edits.isEmpty ? nil : WebImages.applying(edits, to: text)
        }
        if !change.skippedNotes.isEmpty || !change.unreadNotes.isEmpty {
            Self.showProblem("Couldn’t point “\(note.title)” at its saved images",
                             detail: "The images are saved in the vault, but the note changed while they were downloading.")
        }
    }

    private func report(saved: Int, of count: Int, in note: Note) {
        let images = { (n: Int) in n == 1 ? "1 image" : "\(n) images" }
        switch saved {
        case count:
            Self.showNotice("Saved \(images(count)) in the vault",
                            detail: "“\(note.title)” now shows \(count == 1 ? "the copy" : "the copies") kept in the vault.")
        case 0:
            Self.showProblem("Couldn’t save the images",
                             detail: count == 1 ? "It couldn’t be downloaded, so it’s still shown from the web."
                                 : "None of the \(count) could be downloaded, so they’re still shown from the web.")
        default:
            let failed = count - saved
            Self.showNotice("Saved \(saved) of \(images(count)) in the vault",
                            detail: "\(failed == 1 ? "1 couldn’t be downloaded, so it’s" : "\(failed) couldn’t be downloaded, so they’re") still shown from the web.")
        }
    }

    /// Says how something went, in an alert on the front window.
    static func showNotice(_ message: String, detail: String) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PointNoAlerts") { return Trace.mark("notice: \(message): \(detail)") }
        #endif
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
