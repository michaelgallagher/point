import AppKit
import EditorKit
import IndexKit
import VaultKit

extension Notification.Name {
    /// Posted by the vault model with the changed file URLs in `userInfo["urls"]`.
    static let pointFilesChanged = Notification.Name("PointFilesChanged")
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
    /// Why the last save failed, until one works. The edits are kept as a draft meanwhile.
    @Published private(set) var saveProblem: String?
    /// Whether it failed because the file's gone (deleted in another app, say), so it can be
    /// made again, if asked: it never is unasked.
    @Published private(set) var fileIsMissing = false
    /// Edits from an earlier time this note was open that couldn't be saved, to restore.
    @Published private(set) var recoveredDraft: NoteDrafts.Draft?
    @Published private(set) var isLoaded = false
    /// The note's properties, kept up to date as it changes.
    @Published private(set) var frontmatter: Frontmatter?

    private(set) var note: Note
    private var initialText = ""
    /// Whether the note has no text at all (a new note), for offering templates.
    @Published private(set) var isEmpty = false
    private weak var textView: MarkdownTextView?

    /// The note's word count, while it's shown (View › Show Word Count): the text's words,
    /// not the properties', and the selection's when there is one.
    @Published private(set) var wordTally: WordCount.Tally?
    /// Whether to keep `wordTally` up to date. Off, nothing is counted.
    var countsWords = false {
        didSet {
            guard countsWords != oldValue else { return }
            if countsWords { recountWords(after: 0) } else { pendingCount?.cancel(); wordTally = nil }
        }
    }
    private var pendingCount: Task<Void, Never>?
    nonisolated(unsafe) private var selectionObserver: NSObjectProtocol?

    deinit { selectionObserver.map(NotificationCenter.default.removeObserver) }
    /// The file's contents as last read or written, to tell our edits from other people's.
    private var onDisk: String?
    private var pendingSave: Task<Void, Never>?
    /// Set once the file has been renamed or deleted under this session: no more writes.
    private var isReleased = false
    /// Where edits that can't be saved are kept.
    private let drafts: NoteDrafts?

    /// The open sessions, so the vault can have a note's edits saved before it moves the note,
    /// and stop them writing to it after.
    static let live = NSHashTable<EditorSession>.weakObjects()
    #if DEBUG
    var debugText: String? { textView?.string }
    var debugTextView: MarkdownTextView? { textView }
    #endif

    init(note: Note, drafts: NoteDrafts? = nil) {
        self.note = note
        self.drafts = drafts
        super.init()
        Self.live.add(self)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(filesChanged(_:)), name: .pointFilesChanged, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: .pointSaveNow, object: nil)
        center.addObserver(self, selector: #selector(insertText(_:)), name: .pointInsertText, object: nil)
        center.addObserver(self, selector: #selector(applyTemplate(_:)), name: .pointApplyTemplate, object: nil)
        center.addObserver(self, selector: #selector(revealFromNotification(_:)), name: .pointRevealRange, object: nil)
        center.addObserver(self, selector: #selector(setPropertyFromNotification(_:)), name: .pointSetProperty, object: nil)
        center.addObserver(self, selector: #selector(writeListFromNotification(_:)), name: .pointWriteList, object: nil)
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
            WebImageNotes.shared.note(note.id, in: text)
            applyPendingReveal()
            frontmatter = Frontmatter.parse(text)
            checkICloudConflicts()
            offerDraft(over: text)
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
        selectionObserver.map(NotificationCenter.default.removeObserver)
        selectionObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
                                                                   object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.countsWords == true { self?.recountWords(after: 0.1) } }
        }
        if countsWords { recountWords(after: 0) }
        if takesFocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    /// Gives the text the keyboard (Return in the title, say).
    func focusText() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Showing a place in the note

    /// Places to show in notes about to open, by note: taken as each one's text view arrives.
    private static var pendingReveals: [Note.ID: NSRange] = [:]

    /// Whether a place is waiting to be shown in note `id` as it opens.
    static func hasPendingReveal(in id: Note.ID) -> Bool { pendingReveals[id] != nil }

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
        if countsWords { recountWords(after: 0.3) }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    @objc private func appWillResignActive() { save() }

    /// Counts the words a moment after typing or selecting stops, so a long note doesn't
    /// slow typing down.
    private func recountWords(after delay: TimeInterval) {
        pendingCount?.cancel()
        pendingCount = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.countsWords, let textView = self.textView else { return }
            // Counted away from the main thread, on a copy: a very long note takes a while.
            let text = textView.string
            let start = self.frontmatter.map { NSMaxRange($0.range) } ?? 0
            let selection = textView.selectedRange()
            let tally = await Task.detached(priority: .utility) { () -> WordCount.Tally in
                let text = text as NSString
                let body = NSRange(location: min(start, text.length), length: max(text.length - start, 0))
                let selected = selection.length > 0 ? WordCount.count(text, in: NSIntersectionRange(selection, body)) : nil
                return WordCount.Tally(total: WordCount.count(text, in: body), selected: selected)
            }.value
            guard !Task.isCancelled, self.countsWords else { return }
            if tally != self.wordTally { self.wordTally = tally }
        }
    }

    /// Saves unsaved edits, and says whether they're safely stored (or there were none). While
    /// a conflict is waiting for a decision, saves only when `leaving`, and then to a conflict
    /// copy, so the edits survive either way. A save that fails keeps the edits as a draft,
    /// outside the vault, and says so above the note until a save works.
    @discardableResult
    func save(leaving: Bool = false) -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isReleased, let textView, let onDisk else { return true }
        let text = textView.string
        guard text != onDisk else { return true }
        if conflict != nil, !leaving { return false }
        do {
            switch try NoteWriter.write(text, to: note.url, expecting: onDisk, ifChanged: leaving ? .saveCopy : .report) {
            case .saved, .savedAsConflictCopy:
                self.onDisk = text
                WebImageNotes.shared.note(note.id, in: text)
                if saveProblem != nil { saveProblem = nil }
                fileIsMissing = false
                drafts?.remove(for: note.id)
                return true
            case .changedOnDisk(let theirs):
                conflict = .changedElsewhere(theirs: theirs)
                return false
            }
        } catch {
            NSLog("Point: couldn't save \(note.id): \(error.localizedDescription)")
            let kept = (try? drafts?.keep(text, for: note.id)) != nil
            fileIsMissing = (error as? NoteWriter.WriteError) == .missing
            saveProblem = (fileIsMissing ? "This note’s file was deleted or moved outside Point, so your changes weren’t saved."
                           : "Point couldn't save this note (\(error.localizedDescription)).")
                + (kept ? " They’re kept." : " Copy them somewhere safe.")
            return false
        }
    }

    /// Saves the edits in every editor of the file at `url`, before it's moved or deleted.
    /// False if any couldn't be saved (each says so, and keeps its edits as a draft).
    static func save(_ url: URL) -> Bool {
        sessions(of: url).reduce(true) { $1.save(leaving: true) && $0 }
    }

    /// Stops every editor of the file at `url` writing to it, once it's been moved or deleted
    /// (after `save(_:)`: nothing can be typed in between).
    static func release(_ url: URL) {
        sessions(of: url).forEach { $0.isReleased = true }
    }

    /// The file at `url` was renamed or moved outside Point (on the iPhone, say), and is now
    /// `new`: its editors carry on with it there. Unsaved edits are saved to it at once, or,
    /// if the note's text changed too, kept in a conflict copy beside it, as when leaving a
    /// note; a draft kept from a save that failed meanwhile goes with it.
    static func follow(_ url: URL, to new: Note) {
        for session in sessions(of: url) where !session.isReleased {
            let old = session.note.id
            session.note = new
            session.drafts?.move(from: old, to: new.id)
            if session.fileIsMissing {
                session.fileIsMissing = false
                session.saveProblem = nil
            }
            session.save(leaving: true)
        }
    }

    /// The files open in an editor, by resolved path: each asks what to do with iCloud's
    /// conflict versions of its note itself.
    static func openPaths() -> Set<String> {
        Set(live.allObjects.filter { !$0.isReleased }.map { $0.note.url.resolvingSymlinksInPath().path })
    }

    private static func sessions(of url: URL) -> [EditorSession] {
        let path = url.resolvingSymlinksInPath().path
        return live.allObjects.filter { $0.note.url.resolvingSymlinksInPath().path == path }
    }

    // MARK: Edits that couldn't be saved

    /// A draft kept from an earlier save that failed: offered if it differs from the note,
    /// forgotten if the note already holds it.
    private func offerDraft(over text: String) {
        guard let draft = drafts?.draft(for: note.id) else { return }
        if draft.text == text {
            drafts?.remove(for: note.id)
        } else {
            recoveredDraft = draft
        }
    }

    /// Puts the unsaved edits back in the note, and saves them.
    func restoreDraft() {
        guard let draft = recoveredDraft, let textView else { return }
        recoveredDraft = nil
        textView.load(draft.text)
        textDidChange()
        save()
    }

    func discardDraft() {
        recoveredDraft = nil
        drafts?.remove(for: note.id)
    }

    /// Tries a failed save again.
    func retrySave() { save() }

    /// Writes the note back where it was, after its file went: only when asked.
    func recreateFile() {
        guard let textView else { return }
        let text = textView.string
        do {
            try NoteWriter.recreate(text, at: note.url)
            onDisk = text
            saveProblem = nil
            fileIsMissing = false
            drafts?.remove(for: note.id)
        } catch {
            saveProblem = "Point couldn't write the note again (\(error.localizedDescription)). Your changes are kept."
        }
    }

    // MARK: Changes made elsewhere

    @objc private func filesChanged(_ notification: Notification) {
        guard let urls = notification.userInfo?["urls"] as? [URL] else { return }
        // `all`: changes may have gone unreported, so every open note checks its file.
        if notification.userInfo?["all"] as? Bool != true {
            let path = note.url.resolvingSymlinksInPath().path
            guard urls.contains(where: { $0.resolvingSymlinksInPath().path == path }) else { return }
        }
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

    // MARK: Web images

    /// The editor a note is open in, if it's open.
    static func editing(_ id: Note.ID) -> EditorSession? {
        live.allObjects.first { $0.note.id == id && $0.textView != nil && !$0.isReleased }
    }

    /// The note's text as it is in the editor, unsaved edits and all.
    var text: String? { textView?.string }

    /// Makes edits to the note's text (each range in it as it is now) as one step to undo,
    /// keeping the cursor where it was in the text around them.
    func applyEdits(_ edits: [(range: NSRange, replacement: String)]) {
        guard !isReleased, let textView, !edits.isEmpty else { return }
        textView.undoManager?.beginUndoGrouping()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            textView.applyEdit(replacing: edit.range, with: edit.replacement)
        }
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.setActionName("Save Web Images")
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

    /// Sets several properties, and removes those set to nil, as one undoable edit.
    func setProperties(_ changes: [(key: String, values: [String]?, isList: Bool)]) {
        guard let textView, !changes.isEmpty else { return }
        textView.undoManager?.beginUndoGrouping()
        for change in changes {
            // Read again after each edit: the one before moved everything after it.
            let current = Frontmatter.parse(textView.string)
            if let values = change.values {
                let edit = current?.edit(setting: change.key, to: values, isList: change.isList)
                    ?? Frontmatter.edit(adding: change.key, values: values, isList: change.isList)
                textView.applyEdit(replacing: edit.0, with: edit.1)
            } else if let edit = current?.edit(removing: change.key) {
                textView.applyEdit(replacing: edit.0, with: edit.1)
            }
        }
        textView.undoManager?.endUndoGrouping()
    }

    /// Writes a changed list into the note's properties, as one undoable edit: only the
    /// properties that changed, by their names as the note spells them. A list with nothing
    /// left to choose by keeps an empty `list-where`, so it stays a list (of every note).
    func writeList(_ changed: ListDefinition) {
        let current = ListDefinition(frontmatter: frontmatter)
        guard changed != current else { return }
        let properties = frontmatter?.properties ?? []
        let spelled = Dictionary(properties.map { ($0.key.lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
        let before = Dictionary((current?.properties ?? []).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [(key: String, values: [String]?, isList: Bool)] = []
        for (key, values, isList) in changed.properties
        where before[key]?.values != values || before[key]?.isList != isList || spelled[key] == nil {
            changes.append((key, values, isList))
        }
        let kept = Set(changed.properties.map(\.key))
        for key in ListDefinition.Key.all where !kept.contains(key) && spelled[key] != nil {
            changes.append((key, nil, false))
        }
        if changed.folders.isEmpty, changed.tags.isEmpty, changed.conditions.isEmpty {
            changes.removeAll { $0.key == ListDefinition.Key.conditions }
            changes.append((ListDefinition.Key.conditions, [], true))
        }
        setProperties(changes.map { (spelled[$0.key] ?? $0.key, $0.values, $0.isList) })
    }

    @objc private func writeListFromNotification(_ notification: Notification) {
        guard !isReleased, notification.userInfo?["noteID"] as? String == note.id,
              let list = notification.userInfo?["list"] as? ListDefinition else { return }
        writeList(list)
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
            _ = try NoteWriter.writeConflictCopy(text, beside: note.url)
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
