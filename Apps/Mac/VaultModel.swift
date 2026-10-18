import AppKit
import MarkdownKit
import VaultKit

/// The open vault and its notes.
@MainActor
final class VaultModel: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var notes: [Note] = []
    @Published private(set) var errorMessage: String?
    @Published var selection: Note.ID? {
        didSet {
            if let oldValue, oldValue != selection { finishUntitledNote(oldValue) }
        }
    }
    /// The note being renamed, while the rename dialog is showing.
    @Published var renaming: Note?
    @Published var sort: NoteSort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Keys.sort)
            notes = notes.sorted(by: sort)
        }
    }

    private var watcher: VaultWatcher?
    private(set) var settings = ObsidianSettings()
    /// Notes created untitled in this session, to be named by their first line when left.
    private var untitled: Set<Note.ID> = []

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let sort = "noteSort"
    }

    init() {
        sort = UserDefaults.standard.string(forKey: Keys.sort).flatMap(NoteSort.init) ?? .modified
        restoreVault()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let selection = self?.selection { self?.finishUntitledNote(selection) }
            }
        }
    }

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose the folder that holds your notes. It can be an existing Obsidian vault."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try VaultLocation.bookmark(for: url), forKey: Keys.bookmark)
        } catch {
            errorMessage = "Imprint couldn't remember this folder: \(error.localizedDescription)"
        }
        open(url)
    }

    func reload() async {
        guard let root else { return }
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try VaultScanner.scan(root)
            }.value
            notes = scanned.sorted(by: sort)
            errorMessage = nil
            if let selection, !notes.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch {
            errorMessage = "Imprint couldn't read the vault: \(error.localizedDescription)"
        }
    }

    private func restoreVault() {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "ImprintVault") {
            open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return
        }
        #endif
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.bookmark) else { return }
        do {
            let (url, isStale) = try VaultLocation.resolve(bookmark)
            open(url)
            if isStale, let fresh = try? VaultLocation.bookmark(for: url) {
                UserDefaults.standard.set(fresh, forKey: Keys.bookmark)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: Keys.bookmark)
            errorMessage = "Imprint lost access to your vault. Open it again."
        }
    }

    private func open(_ url: URL) {
        watcher?.stop()
        root?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        root = url
        notes = []
        selection = nil
        settings = ObsidianSettings.load(vault: url)
        watcher = VaultWatcher(root: url) { [weak self] urls in
            Task { @MainActor in self?.filesChanged(urls) }
        }
        Task { await reload() }
    }

    /// Something in the vault changed, here or elsewhere: rescan, and tell open notes.
    private func filesChanged(_ urls: [URL]) {
        NotificationCenter.default.post(name: .imprintFilesChanged, object: self, userInfo: ["urls": urls])
        Task { await reload() }
    }

    // MARK: Creating, renaming and deleting

    /// Creates an untitled note in the vault root and opens it.
    func createNote(text: String = "") {
        guard let root else { return }
        do {
            let url = try NoteFiles.create(title: NoteFiles.untitledName(), text: text, in: root)
            let now = Date()
            let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                            modified: now, created: now, isDownloaded: true)
            notes = (notes + [note]).sorted(by: sort)
            untitled.insert(note.id)
            selection = note.id
        } catch {
            errorMessage = "Couldn't create a note: \(error.localizedDescription)"
        }
    }

    /// Names a note created untitled after its first line, or removes it if it stayed empty.
    private func finishUntitledNote(_ id: Note.ID) {
        guard untitled.remove(id) != nil, let note = notes.first(where: { $0.id == id }) else { return }
        releaseFile(note.url)
        let text = (try? NoteReader.read(contentsOf: note.url)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: note.url) // Empty, and created by us moments ago.
            notes.removeAll { $0.id == id }
            return
        }
        guard let line = PlainText.firstLine(of: text) else { return }
        let title = NoteFiles.sanitizedTitle(line)
        guard !title.isEmpty, title != note.title else { return }
        let available = NoteFiles.availableURL(for: title, in: note.url.deletingLastPathComponent())
        _ = try? NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent)
        Task { await reload() }
    }

    func rename(_ note: Note, to title: String) {
        do {
            releaseFile(note.url)
            untitled.remove(note.id)
            let vaultBeforeRename = notes
            let url = try NoteFiles.rename(note.url, to: title)
            updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, vault: vaultBeforeRename)
            let folders = note.id.split(separator: "/").dropLast().joined(separator: "/")
            let newID = folders.isEmpty ? url.lastPathComponent : "\(folders)/\(url.lastPathComponent)"
            let wasSelected = selection == note.id
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = Note(id: newID, url: url, title: url.deletingPathExtension().lastPathComponent,
                                    modified: note.modified, created: note.created, isDownloaded: true)
            }
            if wasSelected { selection = newID }
            Task { await reload() }
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    func moveToTrash(_ note: Note) {
        guard let root else { return }
        releaseFile(note.url)
        untitled.remove(note.id)
        do {
            try NoteFiles.trash(note.url, vault: root, option: settings.trashOption)
            notes.removeAll { $0.id == note.id }
            if selection == note.id { selection = nil }
        } catch {
            errorMessage = "Couldn't move “\(note.title)” to the trash: \(error.localizedDescription)"
        }
    }

    /// Points every link to `note` at its new title, in the background. Open notes save
    /// first, and pick up the rewritten links through the vault watcher.
    private func updateLinks(to note: Note, newTitle: String, vault: [Note]) {
        NotificationCenter.default.post(name: .imprintSaveNow, object: self)
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newTitle, notes: vault)
            if !result.skippedNotes.isEmpty {
                NSLog("Imprint: links not updated in \(result.skippedNotes) (changed while updating)")
            }
        }
    }

    /// Asks the editor showing this file to save now and stop writing to it.
    private func releaseFile(_ url: URL) {
        NotificationCenter.default.post(name: .imprintReleaseFile, object: self, userInfo: ["url": url])
    }
}
