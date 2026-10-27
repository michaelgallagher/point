import AppKit
import EditorKit
import VaultKit

extension Notification.Name {
    /// Posted by the vault model with the changed file URLs in `userInfo["urls"]`.
    static let pointFilesChanged = Notification.Name("PointFilesChanged")
    /// Posted before a note's file is renamed or deleted, with its URL in `userInfo["url"]`.
    static let pointReleaseFile = Notification.Name("PointReleaseFile")
    /// Asks every open note to save its edits now.
    static let pointSaveNow = Notification.Name("PointSaveNow")
    /// Asks the open note to insert `userInfo["text"]` at its cursor.
    static let pointInsertText = Notification.Name("PointInsertText")
    /// Asks note `userInfo["noteID"]` to apply the filled-in template `userInfo["text"]`
    /// (see `Templates.merge`).
    static let pointApplyTemplate = Notification.Name("PointApplyTemplate")
    /// Asks note `userInfo["note"]` to select and show `userInfo["range"]` (see `EditorSession.reveal`).
    static let pointRevealRange = Notification.Name("PointRevealRange")
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
    /// The note's properties, kept up to date as it changes.
    @Published private(set) var frontmatter: Frontmatter?

    private(set) var note: Note
    private var initialText = ""
    /// Whether the note has no text at all (a new note), for offering templates.
    @Published private(set) var isEmpty = false
    private weak var textView: MarkdownTextView?
    /// The file's contents as last read or written, to tell our edits from other people's.
    private var onDisk: String?
    private var pendingSave: Task<Void, Never>?
    /// Set once the file has been renamed or deleted under this session: no more writes.
    private var isReleased = false

    #if DEBUG
    /// The open sessions, for debug hooks to inspect.
    static let live = NSHashTable<EditorSession>.weakObjects()
    var debugText: String? { textView?.string }
    #endif

    init(note: Note) {
        self.note = note
        super.init()
        #if DEBUG
        Self.live.add(self)
        #endif
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(filesChanged(_:)), name: .pointFilesChanged, object: nil)
        center.addObserver(self, selector: #selector(releaseFile(_:)), name: .pointReleaseFile, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: .pointSaveNow, object: nil)
        center.addObserver(self, selector: #selector(insertText(_:)), name: .pointInsertText, object: nil)
        center.addObserver(self, selector: #selector(applyTemplate(_:)), name: .pointApplyTemplate, object: nil)
        center.addObserver(self, selector: #selector(revealFromNotification(_:)), name: .pointRevealRange, object: nil)
        center.addObserver(self, selector: #selector(setPropertyFromNotification(_:)), name: .pointSetProperty, object: nil)
        center.addObserver(self, selector: #selector(addTagFromNotification(_:)), name: .pointAddTag, object: nil)
        center.addObserver(self, selector: #selector(editorCommand(_:)), name: .pointEditorCommand, object: nil)
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
            applyPendingReveal()
            frontmatter = Frontmatter.parse(text)
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

    /// Shows the note in a text view, which takes the keyboard unless the note was picked
    /// in the list (which keeps it, so the arrow keys go on moving through notes).
    func attach(_ textView: MarkdownTextView, takesFocus: Bool = true) {
        self.textView = textView
        textView.load(initialText)
        if isLoaded { applyPendingReveal() }
        isEmpty = initialText.isEmpty
        textView.onTextChange = { [weak self] _ in self?.textDidChange() }
        if takesFocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    // MARK: Showing a place in the note

    /// Places to show in notes about to open, by note: taken as each one's text view arrives.
    private static var pendingReveals: [Note.ID: NSRange] = [:]

    /// Opens at `range` in note `id`: at once if it's open, or as soon as it opens.
    static func reveal(_ range: NSRange, in id: Note.ID) {
        pendingReveals[id] = range
        NotificationCenter.default.post(name: .pointRevealRange, object: nil, userInfo: ["note": id, "range": NSValue(range: range)])
    }

    /// The property holding a place just shown (a link in the frontmatter), highlighted for
    /// a moment, as the properties stand in for the frontmatter's text.
    @Published private(set) var revealedProperty: String?

    /// Once the note's text is in its view (loading puts the cursor back at the top).
    private func applyPendingReveal() {
        guard textView != nil, let range = Self.pendingReveals.removeValue(forKey: note.id) else { return }
        show(range)
    }

    @objc private func revealFromNotification(_ notification: Notification) {
        guard notification.userInfo?["note"] as? Note.ID == note.id, isLoaded, textView != nil,
              let range = (notification.userInfo?["range"] as? NSValue)?.rangeValue else { return }
        Self.pendingReveals[note.id] = nil
        show(range)
    }

    /// Shows and highlights a place, once the note is on screen and still: it's hidden until
    /// its header has its height, which then moves the text, and a highlight on a hidden view,
    /// or one that scrolls, doesn't show. A place in hidden frontmatter highlights its property.
    private func show(_ range: NSRange, tries: Int = 30) {
        guard let textView else { return }
        guard textView.window != nil, textView.alphaValue == 1 || tries == 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.show(range, tries: tries - 1) }
            return
        }
        if range.location < textView.bodyStart {
            let key = Frontmatter.parse(textView.string)?.properties.first { NSLocationInRange(range.location, $0.range) }?.key
            textView.scroll(.zero)
            revealedProperty = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if self?.revealedProperty == key { self?.revealedProperty = nil }
            }
            return
        }
        // After the header's own animation (the properties opening or closing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { textView.reveal(range) }
    }

    // MARK: Saving

    /// Seconds after the last keystroke before saving. Debug builds accept
    /// `-PointSaveDelay <seconds>`, to test what happens to unsaved edits.
    private static let saveDelay: Double = {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "PointSaveDelay")
        if value > 0 { return value }
        #endif
        return 1
    }()

    private func textDidChange() {
        if let textView, textView.string.isEmpty != isEmpty { isEmpty = textView.string.isEmpty }
        refreshFrontmatter()
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
            NSLog("Point: couldn't save \(note.id): \(error.localizedDescription)")
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
            refreshFrontmatter()
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
        refreshFrontmatter()
    }

    @objc private func insertText(_ notification: Notification) {
        guard !isReleased, let text = notification.userInfo?["text"] as? String, let textView,
              notification.userInfo?["noteID"] as? String == note.id else { return }
        textView.insertText(text, replacementRange: textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
    }

    /// A template applied to this note: its properties merged into the note's (rather than a
    /// second block pasted at the cursor), and its body inserted at the cursor. One step to undo.
    @objc private func applyTemplate(_ notification: Notification) {
        guard !isReleased, let rendered = notification.userInfo?["text"] as? String, let textView,
              notification.userInfo?["noteID"] as? String == note.id else { return }
        let application = Templates.merge(rendered, into: textView.string)
        // The body goes at the cursor, or after the frontmatter if the cursor is in it.
        var at = textView.selectedRange()
        if let block = Frontmatter.parse(textView.string)?.range, at.location <= NSMaxRange(block) {
            let length = (textView.string as NSString).length
            let after = min(NSMaxRange(block) + 1, length)
            at = NSRange(location: after, length: 0)
        } else if at.length == 0 {
            at.location = textView.insertionPointForLines(at: at.location)
        }
        var body = application.body
        // At the start of a line with text on it, that text stays on a line of its own.
        let ns = textView.string as NSString
        if at.location < ns.length, at.location == textView.insertionPointForLines(at: at.location),
           ns.character(at: at.location) != 0x0A, !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        textView.undoManager?.beginUndoGrouping()
        // The body first: it comes after the frontmatter, so the block's range stays right.
        if !body.isEmpty { textView.insertText(body, replacementRange: at) }
        if let range = application.frontmatterRange, let block = application.frontmatter,
           (textView.string as NSString).substring(with: range) != block {
            textView.insertText(block, replacementRange: range)
        }
        textView.undoManager?.endUndoGrouping()
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Commands from the palette

    /// A Format menu command chosen in the palette, for this note: the editor takes the
    /// keyboard back and does it to the selection it had.
    @objc private func editorCommand(_ notification: Notification) {
        guard !isReleased, let textView, notification.userInfo?["noteID"] as? String == note.id,
              let name = notification.userInfo?["action"] as? String else { return }
        textView.window?.makeFirstResponder(textView)
        NSApp.sendAction(NSSelectorFromString(name), to: textView, from: nil)
    }

    // MARK: Properties

    private func refreshFrontmatter() {
        guard let textView else { return }
        let parsed = Frontmatter.parse(textView.string)
        if parsed != frontmatter { frontmatter = parsed }
    }

    /// Sets a property, as an undoable edit to the note's text.
    func setProperty(_ key: String, to values: [String], isList: Bool) {
        guard let textView else { return }
        let edit = frontmatter?.edit(setting: key, to: values, isList: isList)
            ?? Frontmatter.edit(adding: key, values: values, isList: isList)
        textView.applyEdit(replacing: edit.0, with: edit.1)
    }

    @objc private func setPropertyFromNotification(_ notification: Notification) {
        guard !isReleased, let info = notification.userInfo, info["noteID"] as? String == note.id, let key = info["key"] as? String,
              let values = info["values"] as? [String], let isList = info["isList"] as? Bool else { return }
        setProperty(key, to: values, isList: isList)
    }

    /// Adds a tag to the note's `tags` property (creating it if needed), unless it's there.
    @objc private func addTagFromNotification(_ notification: Notification) {
        guard !isReleased, let tag = notification.userInfo?["tag"] as? String,
              notification.userInfo?["noteID"] as? String == note.id else { return }
        let existing = frontmatter?.properties.first { $0.key == "tags" }?.values ?? []
        guard !existing.contains(where: { $0.lowercased() == tag.lowercased() }) else { return }
        setProperty("tags", to: existing + [tag], isList: true)
    }

    /// Moves a property to a new place among the others (an index before the move).
    func moveProperty(_ key: String, to destination: Int) {
        guard let textView, let edit = frontmatter?.edit(moving: key, to: destination, in: textView.string) else { return }
        textView.applyEdit(replacing: edit.0, with: edit.1)
    }

    /// Renames a property, changing only its name in the note.
    func renameProperty(_ key: String, to newKey: String) {
        guard let textView, let edit = frontmatter?.edit(renaming: key, to: newKey, in: textView.string) else { return }
        textView.applyEdit(replacing: edit.0, with: edit.1)
    }

    func removeProperty(_ key: String) {
        guard let textView, let edit = frontmatter?.edit(removing: key) else { return }
        textView.applyEdit(replacing: edit.0, with: edit.1)
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
                refreshFrontmatter()
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
