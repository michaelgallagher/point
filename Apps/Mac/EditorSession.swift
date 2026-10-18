import AppKit
import EditorKit
import VaultKit

extension Notification.Name {
    /// Posted by the vault model with the changed file URLs in `userInfo["urls"]`.
    static let imprintFilesChanged = Notification.Name("ImprintFilesChanged")
    /// Posted before a note's file is renamed or deleted, with its URL in `userInfo["url"]`.
    static let imprintReleaseFile = Notification.Name("ImprintReleaseFile")
    /// Asks every open note to save its edits now.
    static let imprintSaveNow = Notification.Name("ImprintSaveNow")
}

/// One open note: loading it, saving edits, and keeping it in step with changes made
/// elsewhere (Obsidian, iCloud) without ever silently losing anyone's text.
@MainActor
final class EditorSession: NSObject, ObservableObject {
    enum Conflict {
        /// The file changed on disk while there were unsaved edits here.
        case changedElsewhere(theirs: String)
        /// iCloud kept another device's version alongside this one.
        case iCloud(NSFileVersion)
    }

    @Published private(set) var conflict: Conflict?
    @Published private(set) var message: String?
    @Published private(set) var isLoaded = false

    private(set) var note: Note
    private var initialText = ""
    private weak var textView: MarkdownTextView?
    /// The file's contents as last read or written, to tell our edits from other people's.
    private var onDisk: String?
    private var pendingSave: Task<Void, Never>?
    /// Set once the file has been renamed or deleted under this session: no more writes.
    private var isReleased = false

    init(note: Note) {
        self.note = note
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(filesChanged(_:)), name: .imprintFilesChanged, object: nil)
        center.addObserver(self, selector: #selector(releaseFile(_:)), name: .imprintReleaseFile, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: .imprintSaveNow, object: nil)
    }

    // MARK: Loading

    func load() async {
        do {
            let text = try await read()
            initialText = text
            onDisk = text
            message = nil
            isLoaded = true
            textView?.load(text)
            checkICloudConflicts()
        } catch NoteReader.ReadError.notDownloaded {
            message = "Downloading from iCloud…" // The watcher reports the file when it arrives.
        } catch {
            message = error.localizedDescription
        }
    }

    private func read() async throws -> String {
        let note = note
        return try await Task.detached { try NoteReader.read(note) }.value
    }

    func attach(_ textView: MarkdownTextView) {
        self.textView = textView
        textView.load(initialText)
        textView.onTextChange = { [weak self] _ in self?.textDidChange() }
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }

    // MARK: Saving

    /// Seconds after the last keystroke before saving. Debug builds accept
    /// `-ImprintSaveDelay <seconds>`, to test what happens to unsaved edits.
    private static let saveDelay: Double = {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "ImprintSaveDelay")
        if value > 0 { return value }
        #endif
        return 1
    }()

    private func textDidChange() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    @objc private func appWillResignActive() { save() }

    /// Saves unsaved edits. While a conflict is waiting for a decision, saves only when
    /// `leaving`, and then to a conflict copy, so the edits survive either way.
    func save(leaving: Bool = false) {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isReleased, let textView, let onDisk else { return }
        let text = textView.string
        guard text != onDisk else { return }
        if conflict != nil, !leaving { return }
        do {
            switch try NoteWriter.write(text, to: note.url, expecting: onDisk, ifChanged: leaving ? .saveCopy : .report) {
            case .saved:
                self.onDisk = text
            case .savedAsConflictCopy:
                self.onDisk = text
            case .changedOnDisk(let theirs):
                conflict = .changedElsewhere(theirs: theirs)
            }
        } catch {
            NSLog("Imprint: couldn't save \(note.id): \(error.localizedDescription)")
        }
    }

    @objc private func releaseFile(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL,
              url.resolvingSymlinksInPath().path == note.url.resolvingSymlinksInPath().path else { return }
        save(leaving: true)
        isReleased = true
    }

    // MARK: Changes made elsewhere

    @objc private func filesChanged(_ notification: Notification) {
        guard let urls = notification.userInfo?["urls"] as? [URL] else { return }
        let path = note.url.resolvingSymlinksInPath().path
        guard urls.contains(where: { $0.resolvingSymlinksInPath().path == path }) else { return }
        Task { await diskChanged() }
    }

    func diskChanged() async {
        guard isLoaded else { return await load() }
        guard let theirs = try? await read() else { return } // Deleted or unreadable: keep what we have.
        checkICloudConflicts()
        guard theirs != onDisk, let textView else { return }
        if textView.string == onDisk || textView.string == theirs {
            // No unsaved edits here: just take the new version.
            textView.reload(theirs)
            onDisk = theirs
        } else {
            pendingSave?.cancel()
            conflict = .changedElsewhere(theirs: theirs)
        }
    }

    func keepMine() {
        guard case .changedElsewhere(let theirs) = conflict else { return }
        onDisk = theirs
        conflict = nil
        save()
    }

    func useTheirs() {
        guard case .changedElsewhere(let theirs) = conflict else { return }
        textView?.reload(theirs)
        onDisk = theirs
        conflict = nil
    }

    // MARK: iCloud conflicts

    private func checkICloudConflicts() {
        guard conflict == nil, let other = NSFileVersion.unresolvedConflictVersionsOfItem(at: note.url)?.first else { return }
        conflict = .iCloud(other)
    }

    func keepThisVersion() {
        resolveICloudConflicts()
    }

    func useOtherVersion() {
        guard case .iCloud(let other) = conflict else { return }
        do {
            try other.replaceItem(at: note.url, options: [])
            resolveICloudConflicts()
            Task {
                guard let text = try? await read() else { return }
                textView?.reload(text)
                onDisk = text
            }
        } catch {
            message = "Couldn't use the other version: \(error.localizedDescription)"
        }
    }

    func keepBothVersions() {
        guard case .iCloud(let other) = conflict else { return }
        do {
            let text = try NoteReader.read(contentsOf: other.url)
            try Data(text.utf8).write(to: NoteWriter.conflictCopyURL(for: note.url))
            resolveICloudConflicts()
        } catch {
            message = "Couldn't keep both versions: \(error.localizedDescription)"
        }
    }

    private func resolveICloudConflicts() {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: note.url) ?? [] {
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: note.url)
        conflict = nil
    }
}
