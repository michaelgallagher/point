import ClipKit
import EditorKit
import IndexKit
import MarkdownKit
import QuickLook
import SwiftUI
import VaultKit

/// One note, filling the screen, in the shared editor, its title at the top (its file name, as
/// on the Mac: changing it renames the note), and below it, its properties and the notes linking
/// to it. Along the bottom, finding in it, Search (the map), and the actions: moving, bookmarking, sharing and
/// deleting it among them. While writing, hiding the keyboard is at the top right. A new note
/// opens with the cursor in its title. Opened with `-SpikeTypeTest`, what opening and typing
/// cost shows across the top (see the spike).
struct NoteScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @StateObject private var session: NoteSession
    /// Images, for the one tapped to show full screen.
    @ObservedObject private var embeds: PhoneEmbeds
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var showsMove = false
    @State private var showsReaderControls = false
    /// Makes a note in the given folder.
    private let newNote: (String) -> Void

    init(note: Note, store: PhoneStore, isNew: Bool = false, newNote: @escaping (String) -> Void) {
        _session = StateObject(wrappedValue: NoteSession(note: note, store: store, isNew: isNew))
        _embeds = ObservedObject(wrappedValue: store.embeds)
        self.newNote = newNote
    }

    var body: some View {
        EditorView(session: session)
            // Under the top bar too, so the text scrolls beneath it, which shows through, as
            // the system's bars do (the text view keeps clear of them while still).
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .safeAreaInset(edge: .top, spacing: 0) { banners }
            // The title is in the note itself.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.isReading {
                    ToolbarItem(placement: .principal) {
                        ReadingProgress(progress: session.progress, minutesLeft: session.minutesLeft)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Text and page", systemImage: "textformat.size") { showsReaderControls = true }
                            .popover(isPresented: $showsReaderControls) {
                                ReaderControls(settings: $store.reader)
                            }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { session.edit() }
                    }
                } else if session.canRead {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { session.doneEditing() }
                            .buttonStyle(.glassProminent)
                    }
                } else if session.isWriting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { session.hideKeyboard() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .pageBar(.find({ session.find("") }, beside: session.isReading
                ? AnyView(Button("Your notes", systemImage: "note.text") { session.openNotes() })
                : nil)) {
                Button("New note", systemImage: "square.and.pencil") { newNote(FolderTree.folder(of: session.note.id)) }
                Divider()
                Button("Move note", systemImage: "folder") { showsMove = true }
                TemplateMenu(session: session)
                // Keeps its pictures from the web in the vault, when asked (never unasked).
                if session.hasWebImages || session.isSavingWebImages {
                    Button(session.isSavingWebImages ? "Saving web images…" : "Save web images", systemImage: "photo.badge.arrow.down") {
                        session.saveWebImages()
                    }
                    .disabled(session.isSavingWebImages)
                }
                Toggle("Show Markdown", systemImage: "chevron.left.forwardslash.chevron.right", isOn: $store.showsMarkdown)
                let bookmarked = store.isBookmarked(session.note.id)
                Button(bookmarked ? "Remove bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                    store.toggleBookmark(session.note.id)
                }
                Button("Share", systemImage: "square.and.arrow.up") { session.share() }
                Divider()
                Button("Delete note", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
            // A hardware keyboard leaves the format bar at the bottom, on top of this one.
            .toolbarVisibility(session.isWriting || session.barsHidden ? .hidden : .automatic, for: .bottomBar)
            // Reading, the bars go as the text scrolls on, and come back as it scrolls back.
            .toolbarVisibility(session.barsHidden ? .hidden : .automatic, for: .navigationBar)
            .statusBarHidden(session.barsHidden)
            .sheet(isPresented: $session.showsProperties) {
                PropertiesSheet(session: session).environmentObject(store)
            }
            .sheet(isPresented: $session.showsNotes, onDismiss: { session.finishNotes() }) {
                NotesSheet(session: session).environmentObject(store)
            }
            .sheet(isPresented: $session.showsRelated) {
                RelatedSheet(session: session).environmentObject(store)
            }
            .sheet(isPresented: $showsMove) {
                FolderPicker(title: "Move note", current: FolderTree.folder(of: session.note.id)) { session.move(to: $0) }
                    .environmentObject(store)
            }
            .alert("Delete “\(session.note.title)”?", isPresented: $confirmsDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    // Gone from the list once this screen has left, not while it's showing.
                    isDeleting = true
                    dismiss()
                }
            } message: {
                Text("It moves to Deleted notes, where you can put it back.")
            }
            // A tapped image, full screen, to zoom, share or save.
            .quickLookPreview($embeds.shownImage)
            .onAppear { store.noteOpened(session.note.id) }
            .onChange(of: store.showsMarkdown) { _, shows in session.showMarkdown(shows) }
            .onChange(of: store.typography) { _, _ in session.applyReading() }
            .onChange(of: store.reader) { _, _ in session.applyReading() }
            // The index has taken in changed notes: what links here may have changed.
            .onChange(of: store.indexUpdates) { _, _ in session.refreshRelated() }
            .onDisappear {
                guard !isDeleting else { return session.moveToTrash() }
                session.keepPlace()
                // Left: its title taken, saved, then (if it has no title) named from its first
                // line, or removed if it's still empty.
                session.commitTitle()
                guard session.save() else { return }
                store.finishUntitled(session.note.id)
            }
    }

    @ViewBuilder private var banners: some View {
        if let problem = session.titleProblem {
            Banner(text: problem) {
                Button("OK") { session.dismissTitleProblem() }
            }
        } else if let problem = session.saveProblem {
            Banner(text: problem) {
                if session.fileIsMissing {
                    Button("Save it again") { session.recreateFile() }
                } else {
                    Button("Try again") { session.save() }
                }
            }
        } else if let notice = session.notice {
            Banner(text: notice) {
                Button("OK") { session.dismissNotice() }
            }
        } else if let draft = session.recoveredDraft {
            Banner(text: "Changes made \(draft.saved.formatted(date: .abbreviated, time: .shortened)) couldn’t be saved at the time.") {
                Button("Discard") { session.discardDraft() }
                Button("Restore") { session.restoreDraft() }
                    .fontWeight(.semibold)
            }
        } else if !session.timings.isEmpty {
            Text(session.timings)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.bar)
        }
    }
}

/// The vault's templates, to apply one to a note. Off if the vault has none.
struct TemplateMenu: View {
    @EnvironmentObject private var store: PhoneStore
    let session: NoteSession

    var body: some View {
        Menu("Apply template", systemImage: "doc.text") {
            ForEach(store.templates, id: \.url) { template in
                Button(template.name) { session.applyTemplate(at: template.url) }
            }
        }
        .disabled(store.templates.isEmpty)
    }
}

/// Above the note: something went wrong, and what can be done.
private struct Banner<Actions: View>: View {
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .symbolRenderingMode(.multicolor)
            HStack(spacing: 16) {
                Spacer()
                actions
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// One open note: loading it, and saving as the Mac does, a second after typing stops and on
/// leaving or the app going to the background, never over a change made elsewhere. A save
/// that fails keeps the edits as a draft, outside the vault, and says so; they're offered back
/// when the note is next opened.
@MainActor
final class NoteSession: NSObject, ObservableObject, UITextViewDelegate {
    /// The note, renamed as its title is changed.
    @Published private(set) var note: Note
    let isNew: Bool
    private(set) var store: PhoneStore
    weak var textView: PhoneTextView?
    weak var titleField: TitleView?
    weak var header: NoteHeader?
    /// Held here too, as it's taken off the text view while reading.
    var formatBar: FormatBar?
    /// The note's frontmatter, as its text is now.
    @Published private(set) var frontmatter: Frontmatter?
    @Published var showsProperties = false
    /// What's related to this note, as on the Mac (links and recall made one): the notes
    /// sharing its topics or people, most shared first, then those linking here, by relation.
    /// Narrowed to `relatedType` when one's chosen.
    @Published private(set) var related = RelatedNotes.empty
    @Published var relatedType: String? { didSet { if relatedType != oldValue { rebuildRelated() } } }
    /// Whether the related notes have been asked for once, so the sheet can say "Nothing related".
    @Published private(set) var relatedIsLoaded = false
    @Published var showsRelated = false
    /// What it shares, as its frontmatter says, and its own type.
    private(set) var recall: Recall?
    private(set) var ownType: String?
    /// The notes linking here, and those sharing something (newest first) with their values.
    private var backlinks: [Backlink] = []
    private var sharedIDs: [Note.ID] = []
    private var sharedValues: [Note.ID: [String: [String]]] = [:]
    private var relatedTask: Task<Void, Never>?
    /// Writing in the note, when the format bar takes the bottom of the screen.
    @Published private(set) var isWriting = false
    /// A note for reading (see plan/reader-mode.md): one of the clip kind, opened set for
    /// reading, not editable until Edit.
    @Published private(set) var canRead = false
    @Published private(set) var isReading = false
    /// How far through it the reader is, and the minutes left.
    @Published private(set) var progress: Double = 0
    @Published private(set) var minutesLeft = 0
    private var minutesToRead = 1
    /// Reading, the bars (and the status bar) are out of the way, for the text alone.
    @Published private(set) var barsHidden = false
    private var scrolling: NSKeyValueObservation?
    private var pendingPlace: Task<Void, Never>?
    /// Why a title couldn't be used (the name's taken, say), until dismissed.
    @Published private(set) var titleProblem: String?

    @Published private(set) var saveProblem: String?
    /// The note's file went (deleted, renamed or moved on another device) and wasn't found
    /// again: edits are kept as a draft, and can be saved again where it was.
    @Published private(set) var fileIsMissing = false
    /// Something to know that isn't a problem (writing carries on in a conflict copy), until dismissed.
    @Published private(set) var notice: String?
    /// Notes that appeared in the last read of the vault before this one: a rename can show its
    /// new name a read before the old one goes.
    private var appearedBefore: [Note] = []
    @Published private(set) var recoveredDraft: NoteDrafts.Draft?
    /// What opening and typing cost, shown only for the spike's typing test.
    @Published private(set) var timings = ""
    /// Whether the note might show pictures from the web (a quick look, as it was last read or
    /// saved), to offer to keep them in the vault; and whether they're being kept now.
    @Published private(set) var hasWebImages = false
    @Published private(set) var isSavingWebImages = false

    private var onDisk: String?
    private var pendingSave: Task<Void, Never>?
    private let showsTimings = UserDefaults.standard.bool(forKey: "SpikeTypeTest")
    private var openedTimings = ""

    /// The list this note is, if it is one, shown under its title.
    private(set) var list: ListDefinition?
    /// What draws the lists embedded in it, and its own, kept while they show.
    private var listControllers: [UIViewController] = []

    init(note: Note, store: PhoneStore, isNew: Bool) {
        self.note = note
        self.store = store
        self.isNew = isNew
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(embedsChanged), name: .phoneEmbedsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(saveNow), name: .phoneSaveNow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(vaultScanned(_:)), name: .phoneVaultScanned, object: store)
        NotificationCenter.default.addObserver(self, selector: #selector(editingChanged), name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editingChanged), name: UITextView.textDidEndEditingNotification, object: nil)
    }

    /// An image arrived, or a list found more or fewer notes: the room for them is made again.
    @objc private func embedsChanged() {
        textView?.restyleEmbeds()
    }

    // MARK: Embeds

    func imageURL(_ target: String) -> URL? { store.embeds.imageURL(for: target, from: note.id) }

    func listEmbedHeight(_ target: String) -> CGFloat? { store.embeds.listEmbedHeight(target, from: note.id) }

    func showImage(_ url: URL) {
        hideKeyboard()
        store.embeds.shownImage = url
    }

    /// The view drawn for a list embedded in the note: its first ten notes, and "Show all".
    func makeEmbedView(_ target: String) -> UIView {
        guard let (id, list) = store.embeds.embeddedList(target, from: note.id) else { return UIView() }
        let store = store
        let view = PhoneListView(embeds: store.embeds, list: list, limit: PhoneListView.embedLimit) { opened in
            store.linkedRoute = .note(opened ?? id)
        }
        return host(view)
    }

    private func host(_ view: PhoneListView) -> UIView {
        let controller = UIHostingController(rootView: view)
        controller.sizingOptions = []
        controller.view.backgroundColor = .clear
        listControllers.append(controller)
        return controller.view
    }

    /// Shows the note's own results under its title, if it's a list, as its properties change.
    private func showList(_ changed: ListDefinition?) {
        guard changed != list else { return }
        list = changed
        guard let header else { return }
        guard let changed else {
            header.list = nil
            return textView?.setNeedsLayout() ?? ()
        }
        let store = store
        let view = PhoneListView(embeds: store.embeds, list: changed, limit: 200, open: { opened in
            if let opened { store.linkedRoute = .note(opened) }
        }, onHeight: { [weak self] height in
            guard let self, let header = self.header, header.listHeight != height else { return }
            header.listHeight = height
            self.textView?.setNeedsLayout()
        })
        header.list = host(view)
        textView?.setNeedsLayout()
    }

    @objc private func editingChanged(_ notification: Notification) {
        guard let view = notification.object as? UITextView, view === textView || view === titleField else { return }
        isWriting = textView?.isFirstResponder == true || titleField?.isFirstResponder == true
        formatBar?.showsTools = textView?.isFirstResponder == true
    }

    /// Going to the background (the phone locked, another app): saved.
    @objc private func resignActive() {
        save()
        keepPlace()
        if let textView { store.noteCursor(textView.selectedRange.location) }
    }

    /// The vault is about to change: saved, into the vault it belongs to.
    @objc private func saveNow() { save() }

    /// The vault's been read again: a note that was downloading opens once it's here, and one
    /// changed elsewhere (on the Mac) is read again if it has no edits here. One with edits
    /// keeps them; saving them then puts them in a conflict copy, as before.
    @objc private func vaultScanned(_ notification: Notification) {
        let appeared = notification.userInfo?["appeared"] as? [Note] ?? []
        defer { appearedBefore = appeared }
        if isDownloading { return open() }
        // Renamed or moved on another device, and found by the store: followed.
        let current = store.currentID(note.id)
        if current != note.id, let moved = store.note(current), !FileManager.default.fileExists(atPath: note.url.path) {
            return follow(moved)
        }
        if let known = store.note(note.id), known.title != note.title, known.isDownloaded {
            // Retitled on another device (a note Point named keeps its title in the text).
            note = known
            if titleField?.isFirstResponder != true, !store.isUntitled(known.id) { titleField?.text = known.title }
        }
        if store.note(note.id) == nil, !FileManager.default.fileExists(atPath: note.url.path) {
            noteWentElsewhere(appeared: appeared + appearedBefore)
        } else {
            if fileIsMissing {
                // Back where it was.
                fileIsMissing = false
                saveProblem = nil
                save()
            }
            reloadIfUnedited()
        }
    }

    /// The note's file is gone. Renamed or moved on another device, it's followed: found by its
    /// text among the notes that have just appeared, edits and all. Otherwise it was deleted (or
    /// changed as well as moved), and that's said; edits are kept and can be saved again.
    private func noteWentElsewhere(appeared: [Note]) {
        guard let onDisk else { return }
        let name = note.url.lastPathComponent
        // Moved: the same name first. Then renamed, up to a sensible number of reads.
        let candidates = (appeared.filter { $0.url.lastPathComponent == name } + appeared.filter { $0.url.lastPathComponent != name })
            .filter { $0.isDownloaded && store.note($0.id) != nil }
            .prefix(20)
        if let found = candidates.first(where: { (try? NoteReader.read(contentsOf: $0.url)) == onDisk }) {
            store.noteMovedElsewhere(from: note.id, to: found)
            return follow(found)
        }
        guard !fileIsMissing else { return }
        fileIsMissing = true
        let edited = textView.map { $0.text != onDisk } ?? false
        if edited, let text = textView?.text { _ = try? store.drafts.keep(text, for: note.id) }
        saveProblem = "This note was deleted, renamed or moved on another device." + (edited ? " Your changes are kept." : "")
    }

    /// Carries on in the note where it is now, with anything typed meanwhile, and takes in
    /// any change made to it there.
    private func follow(_ moved: Note) {
        note = moved
        titleField?.text = store.isUntitled(moved.id) ? "" : moved.title
        fileIsMissing = false
        saveProblem = nil
        save()
        reloadIfUnedited()
    }

    /// Writes the note back where it was, after its file went: only when asked.
    func recreateFile() {
        guard let text = textView?.text else { return }
        do {
            try NoteWriter.recreate(text, at: note.url)
            onDisk = text
            saveProblem = nil
            fileIsMissing = false
            store.drafts.remove(for: note.id)
            store.refresh()
        } catch {
            saveProblem = "Point couldn’t write the note again (\(error.localizedDescription)). Your changes are kept."
        }
    }

    func dismissNotice() { notice = nil }

    /// Changed on another device since it was read here, the edits went to a conflict copy
    /// beside it. Writing carries on in the copy, so later saves don't each make another; the
    /// note itself has the other device's version.
    private func continueInCopy(_ copy: URL) {
        let original = note
        let folder = (original.id as NSString).deletingLastPathComponent
        let name = copy.deletingPathExtension().lastPathComponent
        note = Note(id: folder.isEmpty ? copy.lastPathComponent : "\(folder)/\(copy.lastPathComponent)", url: copy,
                    title: name, modified: Date(), created: Date(), isDownloaded: true)
        titleField?.text = name
        notice = "“\(original.title)” was changed on another device while you were writing. Your version is now a note of its own, “\(name)”, beside it."
        store.refresh()
    }

    /// Whether the note is still on its way from iCloud: shown as such, and not editable, so
    /// nothing typed into the empty page is lost.
    private var isDownloading = false
    /// The note couldn't be read, so it isn't editable, until it can.
    private var couldntRead = false

    func open() {
        guard let textView else { return }
        let readStart = CACurrentMediaTime()
        let text: String
        do {
            text = try NoteReader.read(note)
        } catch {
            // A note that's gone from the vault isn't downloading.
            let isGone = store.hasScanned && store.note(note.id) == nil
            isDownloading = (error as? NoteReader.ReadError) == .notDownloaded && !isGone
            couldntRead = true
            textView.isEditable = false
            saveProblem = isDownloading ? "This note is still downloading from iCloud."
                : isGone ? "This note was deleted, renamed or moved on another device." : "Point couldn’t read this note."
            return
        }
        if isDownloading || couldntRead {
            isDownloading = false
            couldntRead = false
            saveProblem = nil
        }
        let read = (CACurrentMediaTime() - readStart) * 1000
        // A clip opens for reading, the first time it's opened here (not while the Markdown
        // shows, which is for fixing things).
        let firstOpen = onDisk == nil
        if firstOpen {
            canRead = !isNew && !store.showsMarkdown && Reading.opensForReading(text, kinds: store.kinds)
            isReading = canRead
        }
        textView.showsMarkdown = store.showsMarkdown
        header?.showsProperties = !store.showsMarkdown
        applyReading()
        textView.isEditable = !isReading
        let load = textView.load(text)
        if isReading { minutesToRead = Reading.minutes(toRead: text) }
        onDisk = text
        noteWebImages(in: text)
        noteFrontmatter(of: text)
        if let draft = store.drafts.draft(for: note.id) {
            if draft.text == text { store.drafts.remove(for: note.id) } else { recoveredDraft = draft }
        }
        titleField?.text = store.isUntitled(note.id) ? "" : note.title
        // A new note: straight to typing its title. Come back to: straight back to typing.
        // Reading: back where the reader was.
        let resumed = store.resumeCursor(for: note.id)
        if isNew {
            focusTitle()
        } else if isReading {
            if firstOpen { observeScrolling() }
            if firstOpen, let place = store.places.place(for: note.id) {
                let location = Reading.location(of: place, in: text)
                DispatchQueue.main.async { [weak self] in
                    self?.textView?.scroll(toTop: location)
                    self?.updateProgress()
                }
            }
        } else if let cursor = resumed {
            textView.placeCursor(at: cursor)
            textView.becomeFirstResponder()
        } else if let link = store.revealRange(for: note.id), NSMaxRange(link) <= (text as NSString).length {
            // Opened from one of another note's backlinks: at the link to that note.
            textView.scrollRangeToVisible(link)
        }
        refreshRelated()
        openedTimings = "Read \(Int(read)) ms, shown \(Int(load)) ms (\(text.count / 1000)k characters)"
        if showsTimings {
            timings = openedTimings
            PhoneVault.log("opened \(note.title): \(openedTimings)")
            typeTest()
        }
    }

    func open(_ link: LinkTarget) { store.open(link, from: note.id) }

    /// Lets go of the keyboard, from the title or the note's text. Leaving the title hands the
    /// cursor to the note's text, its superview, so that's let go of as well.
    func hideKeyboard() {
        textView?.window?.endEditing(true)
        DispatchQueue.main.async { [weak self] in _ = self?.textView?.resignFirstResponder() }
    }

    // MARK: Reading

    /// Sets the note for reading (the reader's type, margins and page, the byline under the
    /// title) or for writing, as it is now.
    func applyReading() {
        guard let textView else { return }
        // What's at the top stays there as the type changes size.
        let top = isReading && textView.window != nil && textView.textStorage.length > 0 ? textView.topVisibleLocation : nil
        let reader = store.reader
        textView.typography = isReading ? reader.typography : store.typography
        textView.isSerif = isReading && reader.isSerif
        textView.dividerLine = isReading ? ReaderNotes.marker : nil
        let margin: CGFloat = isReading ? reader.margin : 16
        if textView.textContainerInset.left != margin {
            textView.textContainerInset.left = margin
            textView.textContainerInset.right = margin
        }
        let page = isReading ? reader.page : .system
        textView.backgroundColor = page.background
        textView.overrideUserInterfaceStyle = page.style
        // Selecting while reading is for highlighting, not formatting.
        let accessory = isReading ? nil : formatBar
        if textView.inputAccessoryView !== accessory {
            textView.inputAccessoryView = accessory
            if textView.isFirstResponder { textView.reloadInputViews() }
        }
        titleField?.setReading(isReading, serif: reader.isSerif)
        header?.showReading(isReading ? Reading.byline(of: frontmatter, minutes: minutesToRead) : nil)
        textView.setNeedsLayout()
        if let top {
            textView.layoutIfNeeded()
            textView.scroll(toTop: top)
            updateProgress()
        }
    }

    /// Edit: the note as any other, editable, the cursor at the top of what was showing.
    func edit() {
        guard isReading, let textView else { return }
        keepPlace()
        let top = textView.topVisibleLocation
        isReading = false
        setBarsHidden(false)
        applyReading()
        textView.isEditable = true
        textView.scroll(toTop: top)
        textView.selectedRange = NSRange(location: max(top, textView.bodyStart), length: 0)
        textView.becomeFirstResponder()
    }

    /// Done: saved, and set for reading again, where the editing was.
    func doneEditing() {
        guard canRead, !isReading, let textView else { return }
        save()
        hideKeyboard()
        let top = textView.topVisibleLocation
        isReading = true
        minutesToRead = Reading.minutes(toRead: textView.text)
        textView.isEditable = false
        applyReading()
        DispatchQueue.main.async { [weak self] in
            self?.textView?.scroll(toTop: top)
            self?.updateProgress()
        }
    }

    private func observeScrolling() {
        scrolling = textView?.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.scrolled() }
        }
    }

    private func scrolled() {
        guard isReading else { return }
        updateProgress()
        hideOrShowBars()
        // Kept once scrolling stops, not at every step.
        pendingPlace?.cancel()
        pendingPlace = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.keepPlace()
        }
    }

    /// Scrolled on a little by hand, the bars go; scrolled back a little, or at the top or the
    /// end, they come back. Measured by the finger, as the offset jumps as the bars go.
    private func hideOrShowBars() {
        guard let textView else { return }
        let offset = textView.contentOffset.y
        let top = -textView.adjustedContentInset.top
        let end = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
        if offset <= top + 20 || offset >= end - 4 { return setBarsHidden(false) }
        guard textView.isTracking else { return }
        let dragged = textView.panGestureRecognizer.translation(in: textView).y
        if dragged < -24 { setBarsHidden(true) } else if dragged > 24 { setBarsHidden(false) }
    }

    func setBarsHidden(_ hidden: Bool) {
        guard hidden != barsHidden, isReading || !hidden else { return }
        withAnimation(.easeInOut(duration: 0.25)) { barsHidden = hidden }
        // No fading at the edges, with nothing there to keep clear of.
        textView?.topEdgeEffect.isHidden = hidden
        textView?.bottomEdgeEffect.isHidden = hidden
    }

    /// A tap on the text while reading (not on a link or a selection) brings the bars back, or
    /// puts them away.
    func readerTapped() {
        guard isReading, let textView, textView.selectedRange.length == 0 else { return }
        setBarsHidden(!barsHidden)
    }

    private func updateProgress() {
        guard let textView else { return }
        let top = -textView.adjustedContentInset.top
        let end = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
        let through = end > top ? (textView.contentOffset.y - top) / (end - top) : 1
        let clamped = min(max(Double(through), 0), 1)
        if abs(clamped - progress) > 0.002 || (clamped == 1) != (progress == 1) { progress = clamped }
        let left = clamped >= 0.995 ? 0 : max(1, Int((Double(minutesToRead) * (1 - clamped)).rounded(.up)))
        if left != minutesLeft { minutesLeft = left }
    }

    /// Shows the note as it is now (changed on another device, or your notes saved), while
    /// reading: the same paragraph stays at the top.
    private func showWhileReading(_ text: String) {
        guard let textView else { return }
        let place = Reading.place(at: textView.topVisibleLocation, in: textView.text)
        textView.load(text)
        onDisk = text
        minutesToRead = Reading.minutes(toRead: text)
        noteFrontmatter(of: text)
        header?.showReading(Reading.byline(of: frontmatter, minutes: minutesToRead))
        textView.layoutIfNeeded()
        textView.scroll(toTop: Reading.location(of: place, in: text))
        updateProgress()
    }

    // MARK: Your notes

    /// Your notes as the sheet opened with them, or as last saved: if they're different on
    /// disk when saving, they were changed elsewhere meanwhile.
    private var notesBase: String?
    private var pendingNotes: (text: String, task: Task<Void, Never>)?
    @Published var showsNotes = false

    /// Your notes, as the file has them.
    var notes: String { ReaderNotes.notes(in: onDisk ?? "") }
    /// What the notes sheet opens with: your notes, or with a quote just added, a blank line
    /// under it for the cursor.
    private(set) var notesToEdit = ""

    func openNotes() {
        guard isReading, onDisk != nil else { return }
        notesBase = notes
        notesToEdit = notes
        showsNotes = true
    }

    /// Typed in the notes sheet: saved a second after typing stops.
    func notesChanged(_ text: String) {
        pendingNotes?.task.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNotes(text)
        }
        pendingNotes = (text, task)
    }

    /// The sheet closed: what's waiting is saved now.
    func finishNotes() {
        if let pending = pendingNotes { saveNotes(pending.text) }
        notesBase = nil
        notesView = nil
    }

    /// Saves your notes into the file as it is on disk now: the properties and the saved text
    /// are whatever it holds, so a change synced from elsewhere while you wrote is kept. If your
    /// notes themselves were changed elsewhere meanwhile, yours go to a conflict copy, as typing
    /// in the editor does. Nothing changed, nothing's written (an old clip gets no marker).
    @discardableResult
    func saveNotes(_ typed: String) -> Bool {
        pendingNotes?.task.cancel()
        pendingNotes = nil
        guard let base = notesBase, let onDisk else { return true }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != base.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
        var spliced = ReaderNotes.settingNotes(typed, in: onDisk)
        do {
            let disk = try NoteReader.read(note)
            let expecting: String
            if ReaderNotes.notes(in: disk) == base {
                spliced = ReaderNotes.settingNotes(typed, in: disk)
                expecting = disk
            } else {
                // Your notes changed elsewhere too: written over what was read, which no longer
                // matches, so they go to a copy.
                expecting = onDisk
            }
            let outcome = try NoteWriter.write(spliced, to: note.url, expecting: expecting, ifChanged: .saveCopy)
            notesBase = ReaderNotes.notes(in: spliced)
            saveProblem = nil
            store.drafts.remove(for: note.id)
            if case .savedAsConflictCopy(let copy) = outcome { continueInCopy(copy) }
            showWhileReading(spliced)
            store.noteEdited(note.id)
            return true
        } catch {
            let kept = (try? store.drafts.keep(spliced, for: note.id)) != nil
            fileIsMissing = (error as? NoteWriter.WriteError) == .missing
            saveProblem = (fileIsMissing ? "This note was deleted, renamed or moved on another device, so your notes weren’t saved."
                : "Point couldn’t save your notes (\(error.localizedDescription)).")
                + (kept ? " They’re kept." : " Copy them somewhere safe.")
            return false
        }
    }

    // MARK: Highlights

    /// The notes sheet's editor while it's open, to take a quote added from the article.
    weak var notesView: PhoneTextView?

    /// The reader's edit menu over a selection: Highlight, Remove highlight (if it touches
    /// one) and Add to notes (from the saved text). Nothing while editing.
    func readerMenu(for range: NSRange) -> [UIMenuElement] {
        guard isReading, let onDisk, let textView, textView.text == onDisk else { return [] }
        let editing = MarkdownEditing(text: onDisk, selection: range)
        let marker = ReaderNotes.marker
        var actions: [UIMenuElement] = []
        if editing.highlightingSelection(skipping: marker) != nil {
            actions.append(UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                self?.highlight(range)
            })
        }
        if editing.removingHighlights(skipping: marker) != nil {
            actions.append(UIAction(title: "Remove highlight", image: UIImage(systemName: "eraser")) { [weak self] _ in
                self?.removeHighlights(range)
            })
        }
        let inArticle = ReaderNotes.markerLine(in: onDisk).map { range.location > $0.location } ?? true
        if inArticle, range.length > 0, !editing.quotableSelection(skipping: marker).isEmpty {
            actions.append(UIAction(title: "Add to notes", image: UIImage(systemName: "text.badge.plus")) { [weak self] _ in
                self?.addToNotes(range)
            })
        }
        return actions
    }

    func highlight(_ range: NSRange) {
        writeWhileReading { text in
            MarkdownEditing(text: text, selection: range).highlightingSelection(skipping: ReaderNotes.marker)
                .map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) }
        }
    }

    func removeHighlights(_ range: NSRange) {
        writeWhileReading { text in
            MarkdownEditing(text: text, selection: range).removingHighlights(skipping: ReaderNotes.marker)
                .map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) }
        }
    }

    /// Quotes the selection at the end of your notes, highlights it in the article, in one
    /// write, and opens your notes there, for a comment under it.
    func addToNotes(_ range: NSRange) {
        // What's being typed in the sheet goes in first.
        if let pending = pendingNotes { saveNotes(pending.text) }
        var added: String?
        let wrote = writeWhileReading { text in
            let editing = MarkdownEditing(text: text, selection: range)
            let quote = editing.quotableSelection(skipping: ReaderNotes.marker)
            guard !quote.isEmpty else { return nil }
            let highlighted = editing.highlightingSelection(skipping: ReaderNotes.marker)
                .map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) } ?? text
            let notes = ReaderNotes.addingQuote(quote, to: ReaderNotes.notes(in: highlighted)).notes
            added = notes
            return ReaderNotes.settingNotes(notes, in: highlighted)
        }
        guard wrote, let added else { return }
        notesBase = ReaderNotes.notes(in: onDisk ?? "")
        if let notesView {
            notesView.load(added)
            notesView.placeCursor(at: (added as NSString).length)
        } else {
            notesToEdit = added
            showsNotes = true
        }
    }

    /// The note's highlights in the saved text, for the notes sheet's list.
    var highlights: [(range: NSRange, text: String)] {
        guard let onDisk else { return [] }
        let start = ReaderNotes.markerLine(in: onDisk).map(NSMaxRange) ?? 0
        return MarkdownEditing.highlights(in: onDisk, from: start, skipping: ReaderNotes.marker)
    }

    /// Goes to a highlight: its paragraph at the top of the screen.
    func go(to highlight: NSRange) {
        textView?.scroll(toTop: highlight.location)
        updateProgress()
        keepPlace()
    }

    /// Changes the note while reading, as `change` makes it from the file as shown, and writes
    /// it. Changed on another device since it was shown, it's shown as it is now and nothing's
    /// written: a selection made in the old version might not be the same words.
    @discardableResult
    private func writeWhileReading(_ change: (String) -> String?) -> Bool {
        guard isReading, let onDisk else { return false }
        do {
            let disk = try NoteReader.read(note)
            guard disk == onDisk else {
                showWhileReading(disk)
                notice = "This note was changed on another device, so it’s been read again. Try that again."
                return false
            }
            guard let changed = change(disk), changed != disk else { return false }
            let outcome = try NoteWriter.write(changed, to: note.url, expecting: disk, ifChanged: .saveCopy)
            saveProblem = nil
            if case .savedAsConflictCopy(let copy) = outcome { continueInCopy(copy) }
            showWhileReading(changed)
            store.noteEdited(note.id)
            return true
        } catch {
            fileIsMissing = (error as? NoteWriter.WriteError) == .missing
                || (error as? NoteReader.ReadError) != nil && store.hasScanned && store.note(note.id) == nil
            saveProblem = fileIsMissing ? "This note was deleted, renamed or moved on another device, so that wasn’t saved."
                : "Point couldn’t save that (\(error.localizedDescription))."
            return false
        }
    }

    /// Keeps where the reader is: the paragraph at the top of the screen.
    func keepPlace() {
        guard canRead, let textView, textView.textStorage.length > 0 else { return }
        pendingPlace?.cancel()
        store.places.keep(Reading.place(at: textView.topVisibleLocation, in: textView.text), for: note.id)
    }

    /// Shows the raw Markdown, or the formatted note, as on the Mac. With the Markdown showing,
    /// the properties are edited as text, so their button goes.
    func showMarkdown(_ shows: Bool) {
        textView?.showsMarkdown = shows
        header?.showsProperties = !shows
        textView?.setNeedsLayout()
    }

    /// Asks the index what's related to the note: what links here, and what shares its topics
    /// or people (see `Recall`), then ranks and groups them (`RelatedNotes`), as the Mac does.
    func refreshRelated(after delay: Double = 0) {
        relatedTask?.cancel()
        let note = note, recall = recall
        relatedTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            let store = self.store
            let typeProperty = store.kinds.property
            let backlinks = await store.backlinks(to: note)
            var sharedIDs: [Note.ID] = []
            var sharedValues: [Note.ID: [String: [String]]] = [:]
            if let recall, let index = store.searchIndex {
                sharedIDs = ((try? await index.notes(matching: recall.query)) ?? []).filter { $0 != note.id }
                let ranked = Array(sharedIDs.prefix(RelatedNotes.sharedLimit + backlinks.count))
                sharedValues = await store.embeds.propertyValues(RecallDetails.keys(for: recall, typeProperty: typeProperty), of: ranked)
            }
            guard !Task.isCancelled, self.note == note, self.recall == recall else { return }
            self.backlinks = backlinks
            self.sharedIDs = sharedIDs
            self.sharedValues = sharedValues
            self.relatedIsLoaded = true
            self.rebuildRelated()
        }
    }

    /// Ranks and groups what was found (quick: no lookups), and updates the readout.
    private func rebuildRelated() {
        let store = store
        let make = { [note, recall, sharedIDs, sharedValues, backlinks] (type: String?) in
            RelatedNotes(noteID: note.id, recall: recall, sharedIDs: sharedIDs, values: sharedValues,
                         title: { store.note($0)?.title }, name: { store.note($0)?.name },
                         typeProperty: store.kinds.property, backlinks: backlinks, type: type)
        }
        let all = make(nil)
        if let type = relatedType, !all.types.contains(where: { $0.type.caseInsensitiveCompare(type) == .orderedSame }) {
            relatedType = nil // Rebuilds again.
            return
        }
        let narrowed = relatedType == nil ? all : make(relatedType)
        if narrowed != related { related = narrowed }
        let icon = all.sharedTotal > 0 ? (recall?.basis == .topics ? "rectangle.stack" : "clock.arrow.circlepath") : "link"
        header?.showRelated(all.readout(ownType: ownType, unlinkedMentions: 0), icon: icon)
        textView?.setNeedsLayout()
    }

    /// Opens a note sharing something with this one, from the related notes.
    func openRelated(_ id: Note.ID) {
        showsRelated = false
        store.linkedRoute = .note(id)
    }

    /// Opens a note linking here, at its link, from the related notes.
    func open(_ backlink: Backlink) {
        showsRelated = false
        store.open(backlink)
    }

    /// Opens the system's find bar on the note, with `text` searched for.
    func find(_ text: String) {
        guard let interaction = textView?.findInteraction else { return }
        interaction.searchText = text
        interaction.presentFindNavigator(showingReplace: false)
    }

    /// What the format bar offers for a `[[link` or `#tag` being typed.
    func choices(for completion: MarkdownEditing.Completion) -> [String] {
        switch completion.kind {
        case .note: store.titleSuggestions(for: completion.partial).filter { $0 != note.title }
        case .tag: store.tagSuggestions(for: completion.partial)
        }
    }

    func changed(_ text: String) {
        guard let textView else { return }
        noteFrontmatter(of: text)
        if text != onDisk { store.noteEdited(note.id) }
        if showsTimings {
            timings = "\(openedTimings)\nLast keystroke \(String(format: "%.1f", textView.lastEditMilliseconds)) ms, slowest \(String(format: "%.1f", textView.slowestEditMilliseconds)) ms"
        }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Saves unsaved edits, and says whether they're safely stored (or there were none). Changed
    /// elsewhere meanwhile, the edits go to a conflict copy beside the note, as on the Mac.
    @discardableResult
    func save() -> Bool {
        pendingSave?.cancel()
        guard let textView, let onDisk, let text = textView.text, text != onDisk else { return true }
        do {
            let outcome = try NoteWriter.write(text, to: note.url, expecting: onDisk, ifChanged: .saveCopy)
            self.onDisk = text
            noteWebImages(in: text)
            saveProblem = nil
            fileIsMissing = false
            store.drafts.remove(for: note.id)
            if case .savedAsConflictCopy(let copy) = outcome { continueInCopy(copy) }
            return true
        } catch {
            let kept = (try? store.drafts.keep(text, for: note.id)) != nil
            fileIsMissing = (error as? NoteWriter.WriteError) == .missing
            saveProblem = fileIsMissing
                ? "This note was deleted, renamed or moved on another device, so your changes weren’t saved."
                    + (kept ? " They’re kept." : " Copy them somewhere safe.")
                : "Point couldn’t save this note (\(error.localizedDescription))."
                    + (kept ? " Your changes are kept." : " Copy them somewhere safe.")
            return false
        }
    }

    /// Shares the note's file, as it is now, under the title as typed.
    /// The system's share sheet, for the note's file. Presented by UIKit itself: in a SwiftUI
    /// sheet it came up later, inside a sheet of SwiftUI's own.
    func share() {
        commitTitle()
        guard save(), let window = textView?.window, var presenter = window.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: [note.url], applicationActivities: nil)
        presenter.present(sheet, animated: true)
    }

    /// Moves the note to the trash, with its latest edits. Those that can't be saved keep it here.
    func moveToTrash() {
        if save() { store.moveToTrash(note.id) } else { store.trashProblem = saveProblem }
    }

    /// Moves the note to `folder`, with its latest edits, and takes in any change that made to
    /// the note's own links.
    func move(to folder: String) {
        commitTitle()
        guard save() else { return }
        do {
            let moved = try store.move(note.id, toFolder: folder)
            note = moved.note
            Task { [weak self] in
                await moved.links.value
                self?.reloadIfUnedited()
            }
        } catch {
            titleProblem = "Point couldn’t move this note (\(error.localizedDescription))."
        }
    }

    /// Reads the note again if it's changed on disk and not here.
    private func reloadIfUnedited() {
        guard let textView, let onDisk, textView.text == onDisk, let text = try? NoteReader.read(note), text != onDisk else { return }
        if isReading { return showWhileReading(text) }
        let selection = textView.selectedRange
        textView.load(text)
        self.onDisk = text
        noteFrontmatter(of: text)
        // The cursor stays about where it was, if the text still reaches there.
        let length = (text as NSString).length
        textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
    }

    /// Applies a template, filled in, as on the Mac: its properties merged into the note's, and
    /// its body inserted at the cursor, or at the start if the cursor's yet to be placed. One step
    /// to undo.
    func applyTemplate(at url: URL) {
        commitTitle()
        guard let textView, let template = try? NoteReader.read(contentsOf: url) else { return }
        let title = store.isUntitled(note.id) ? "" : note.title
        let application = Templates.merge(Templates.render(template, title: title, settings: store.settings), into: textView.text)
        let text = textView.text as NSString
        let at = max(textView.selectedRange.location, textView.bodyStart)
        var body = application.body
        // Frontmatter with no line break after it: the body starts on a line of its own.
        if at > 0, at == textView.bodyStart, text.character(at: at - 1) != 10, !body.isEmpty { body = "\n" + body }
        // At the start of a line with text on it, that text stays on a line of its own.
        if at < text.length, at == text.lineRange(for: NSRange(location: at, length: 0)).location,
           text.character(at: at) != 10, !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        textView.undoManager?.beginUndoGrouping()
        // The body first: it comes after the frontmatter, so the block's range stays right.
        if !body.isEmpty { textView.applyAboveBody(NSRange(location: at, length: 0), with: body) }
        if let range = application.frontmatterRange, let block = application.frontmatter, text.substring(with: range) != block {
            textView.applyAboveBody(range, with: block)
        }
        textView.undoManager?.endUndoGrouping()
    }

    // MARK: Web images

    private func noteWebImages(in text: String) {
        let has = WebImages.mightHaveAny(in: text)
        if has != hasWebImages { hasWebImages = has }
    }

    /// Keeps the note's pictures from the web in the vault, as on the Mac: all downloaded at
    /// once, each saved in the attachment folder named after the note, and the note pointed at
    /// the copies, as one step to undo, around anything typed meanwhile. Those that can't be
    /// downloaded stay as they were; a notice says how it went.
    func saveWebImages() {
        guard !isSavingWebImages, let textView else { return }
        commitTitle()
        let addresses = WebImages.find(in: textView.text).map(\.address)
        guard !addresses.isEmpty else {
            hasWebImages = false
            notice = "This note has no images from the web."
            return
        }
        isSavingWebImages = true
        let note = note, root = store.root, settings = store.settings
        let taken = Set(store.embeds.images.map { $0.name.lowercased() })
        let store = store
        Task { [weak self] in
            let downloads = await WebImages.download(addresses)
            var unique: [String] = []
            for address in addresses where !unique.contains(address) { unique.append(address) }
            let ready = unique.compactMap { address in (try? downloads[address]?.get()).map { (address, $0) } }
            let result = await Task.detached(priority: .userInitiated) {
                WebImages.save(ready, forNote: note, vault: root, setting: settings.attachmentFolder, taken: taken)
            }.value
            store.embeds.images += result.saved.values
            let style = WebImages.LinkStyle(settings: settings)
            guard let self, let textView = self.textView else {
                // The note was left meanwhile: pointed at them in its file, if it's as it was.
                _ = VaultChanges.apply("Saved web images", to: [note]) { text in
                    let edits = WebImages.edits(for: text, saved: result.saved, noteURL: note.url, root: root, style: style)
                    return edits.isEmpty ? nil : WebImages.applying(edits, to: text)
                }
                return
            }
            isSavingWebImages = false
            if !result.saved.isEmpty {
                let edits = WebImages.edits(for: textView.text, saved: result.saved, noteURL: self.note.url, root: root, style: style)
                textView.undoManager?.beginUndoGrouping()
                for edit in edits { textView.applyAboveBody(edit.range, with: edit.replacement) }
                textView.undoManager?.endUndoGrouping()
            }
            let count = unique.count, saved = result.saved.count
            let images = { (n: Int) in n == 1 ? "1 image" : "\(n) images" }
            notice = saved == count ? "Saved \(images(count)) in the vault."
                : saved == 0 ? (count == 1 ? "The image couldn’t be downloaded, so it’s still shown from the web."
                                : "None of the \(count) images could be downloaded, so they’re still shown from the web.")
                : "Saved \(saved) of \(images(count)) in the vault. \(count - saved == 1 ? "1 couldn’t be downloaded, so it’s" : "\(count - saved) couldn’t be downloaded, so they’re") still shown from the web."
        }
    }

    // MARK: Properties

    private func noteFrontmatter(of text: String) {
        let parsed = text.hasPrefix("---") ? Frontmatter.parse(text) : nil
        guard parsed != frontmatter || frontmatter == nil else { return }
        frontmatter = parsed
        header?.showProperties(count: shownProperties.count)
        if isReading { header?.showReading(Reading.byline(of: parsed, minutes: minutesToRead)) }
        showList(ListDefinition(frontmatter: parsed))
        let typeProperty = store.kinds.property
        let type = parsed?.properties.first { $0.key.caseInsensitiveCompare(typeProperty) == .orderedSame }?
            .values.first?.trimmingCharacters(in: .whitespaces)
        let typeChanged = (type?.isEmpty == false ? type : nil) != ownType
        ownType = type?.isEmpty == false ? type : nil
        let changed = store.recall(of: parsed, name: note.name)
        if changed != recall {
            recall = changed
            // While it's typed (as the note opens, its loading asks at once, after this).
            refreshRelated(after: 0.3)
        } else if typeChanged {
            rebuildRelated()
        }
    }

    /// The properties to show, as on the Mac: all but the `title:` of a note Point named (that's
    /// its title, above them), and a list's own keys (shown as the list, under them).
    var shownProperties: [Frontmatter.Property] {
        guard let frontmatter else { return [] }
        let isDated = NoteNames.isDated(note.name)
        let isList = ListDefinition(frontmatter: frontmatter) != nil
        return frontmatter.properties.filter { property in
            !(isDated && property.key.lowercased() == "title") && !(isList && ListDefinition.isListKey(property.key))
        }
    }

    func setProperty(_ key: String, to values: [String], isList: Bool) {
        let edit = frontmatter?.edit(setting: key, to: values, isList: isList)
            ?? Frontmatter.edit(adding: key, values: values, isList: isList)
        textView?.applyAboveBody(edit.0, with: edit.1)
    }

    func renameProperty(_ key: String, to newKey: String) {
        guard let textView, let edit = frontmatter?.edit(renaming: key, to: newKey, in: textView.text) else { return }
        textView.applyAboveBody(edit.0, with: edit.1)
    }

    func removeProperty(_ key: String) {
        guard let edit = frontmatter?.edit(removing: key) else { return }
        textView?.applyAboveBody(edit.0, with: edit.1)
    }

    // MARK: The title

    /// Puts the cursor in the title once it's on screen: opened from a menu, the note's still
    /// arriving when it's loaded, and the cursor ended up in the text instead.
    private func focusTitle(tries: Int = 20) {
        guard let field = titleField else { return }
        if field.window != nil, field.becomeFirstResponder() { return }
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.focusTitle(tries: tries - 1) }
    }

    /// Return in the title: on to the note's text, at its start. A title is one line, however
    /// many it wraps to, so a pasted line break becomes a space.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            commitTitle()
            self.textView?.becomeFirstResponder()
            self.textView?.moveToBodyStart()
            return false
        }
        guard text.rangeOfCharacter(from: .newlines) != nil else { return true }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
        textView.textStorage.replaceCharacters(in: range, with: line)
        textView.selectedRange = NSRange(location: range.location + (line as NSString).length, length: 0)
        textViewDidChange(textView)
        return false
    }

    /// The title grew or shrank by a line: the note's text moves to suit.
    func textViewDidChange(_ textView: UITextView) {
        titleField?.updatePlaceholder()
        header?.setNeedsLayout()
        self.textView?.setNeedsLayout()
    }

    func textViewDidEndEditing(_ textView: UITextView) { commitTitle() }

    /// Renames the note to the title typed, once its edits are saved. A title left empty
    /// goes back to the note's name (or, for a new note, waits: it's named from its first
    /// line when it's left).
    func commitTitle() {
        guard let field = titleField else { return }
        // A note Point named keeps its title as typed (it's in `title:`, not the file name).
        let raw = field.text ?? ""
        let typed = NoteNames.isDated(note.name)
            ? raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            : NoteFiles.sanitizedTitle(raw)
        let untitled = store.isUntitled(note.id)
        guard !typed.isEmpty else {
            if !untitled { field.text = note.title }
            return
        }
        guard typed != note.title || untitled else { return }
        // A note Point named: its `title:` is set in the text here first, then saved with the
        // rest. Set only on disk, the editor's next save found the file changed and put the
        // note's text in a conflict copy, apart from its title.
        if NoteNames.isDated(note.name), let textView {
            let text = textView.text ?? ""
            let (range, replacement) = NoteNames.edit(settingTitle: typed, in: text)
            if (text as NSString).substring(with: range) != replacement { textView.applyAboveBody(range, with: replacement) }
        }
        // Saved first: a rename never leaves edits behind.
        guard save() else {
            field.text = untitled ? "" : note.title
            return
        }
        do {
            note = try store.rename(note.id, to: typed)
            field.text = note.title
        } catch NoteFiles.FileError.titleTaken(_) {
            titleProblem = "There’s already a note called “\(typed)”."
            field.text = untitled ? "" : note.title
        } catch {
            titleProblem = "Point couldn’t rename this note (\(error.localizedDescription))."
            field.text = untitled ? "" : note.title
        }
    }

    func dismissTitleProblem() { titleProblem = nil }

    func restoreDraft() {
        guard let draft = recoveredDraft, let textView else { return }
        recoveredDraft = nil
        textView.text = draft.text
        changed(draft.text)
        save()
    }

    func discardDraft() {
        recoveredDraft = nil
        store.drafts.remove(for: note.id)
    }

    /// `-SpikeTypeTest YES`: types 200 characters at the end of the note, one at a time, as the
    /// keyboard would, and logs what each cost.
    private func typeTest() {
        guard let textView else { return }
        let sentence = "Typing at a workshop, one word after another. "
        let characters = Array(String(repeating: sentence, count: 200 / sentence.count + 1).prefix(200))
        var times: [Double] = [], parses: [Double] = [], edits: [Double] = []
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        for (index, character) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(index) * 0.03) { [weak self] in
                guard let self else { return }
                let start = CACurrentMediaTime()
                textView.insertText(String(character))
                // Laid out where the cursor is, as the screen needs it.
                textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: textView.selectedRange.location, length: 0))
                times.append((CACurrentMediaTime() - start) * 1000)
                parses.append(textView.lastParseMilliseconds)
                edits.append(textView.lastEditMilliseconds)
                guard times.count == characters.count else { return }
                let median = { (values: [Double]) in values.sorted()[values.count / 2] }
                let sorted = times.sorted()
                let summary = String(format: "typing 200 characters: median %.1f ms (parsing %.1f, restyling %.1f), 95th %.1f ms, slowest %.1f ms",
                                     median(times), median(parses), median(edits) - median(parses), sorted[190], sorted[199])
                PhoneVault.log("\(self.note.title): \(summary)")
                self.timings = "\(self.openedTimings)\n\(summary)"
            }
        }
    }
}

/// What's above a note's text: its title, and below that, side by side (or one under the other
/// when they don't fit), a button to its properties, saying how many there are, and one to its
/// related notes saying what they are, if it has any.
final class NoteHeader: UIView {
    let title = TitleView()
    var onProperties: (() -> Void)?
    var onRelated: (() -> Void)?
    private let properties = NoteHeader.button()
    private let related = NoteHeader.button()
    /// While reading: who wrote it, where, when, and how long it takes to read, in place of
    /// the buttons.
    private let byline = UILabel()
    private(set) var isReading = false
    private static let gap: CGFloat = 8
    /// Between the buttons, side by side.
    private static let between: CGFloat = 8
    /// Between the buttons and the note's text.
    private static let below: CGFloat = 12
    /// A list note's results, under the buttons, and how tall they are.
    var list: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let list { addSubview(list) }
            setNeedsLayout()
        }
    }
    var listHeight: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }
    private static let listGap: CGFloat = 14
    /// The list's room, when there is one.
    private var listRoom: CGFloat { list == nil ? 0 : listHeight + Self.listGap }

    /// Off while the note's Markdown shows, when its properties are text like the rest.
    var showsProperties = true {
        didSet {
            properties.isHidden = !showsProperties
            setNeedsLayout()
        }
    }

    init() {
        super.init(frame: .zero)
        addSubview(title)
        addSubview(properties)
        addSubview(related)
        byline.font = .preferredFont(forTextStyle: .subheadline)
        byline.adjustsFontForContentSizeCategory = true
        byline.textColor = .secondaryLabel
        byline.numberOfLines = 0
        byline.isHidden = true
        addSubview(byline)
        properties.addAction(UIAction { [weak self] _ in self?.onProperties?() }, for: .touchUpInside)
        related.addAction(UIAction { [weak self] _ in self?.onRelated?() }, for: .touchUpInside)
        showProperties(count: 0)
        showRelated(nil, icon: "link")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// A pale grey capsule.
    private static func button() -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .secondarySystemFill
        configuration.baseForegroundColor = .secondaryLabel
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .preferredFont(forTextStyle: .footnote)
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    func showProperties(count: Int) {
        properties.configuration?.title = count == 0 ? "Add properties" : "\(count) \(count == 1 ? "property" : "properties")"
        setNeedsLayout()
    }

    /// What's related, as the Mac's readout says it: "4 earlier meetings · last on 21 October",
    /// "23 notes on Org design", or "4 links (articles by this person and mentions)". Nothing
    /// related (nil), and the button goes.
    func showRelated(_ readout: String?, icon: String) {
        var configuration = related.configuration
        configuration?.title = readout
        configuration?.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote))
        configuration?.imagePadding = 4
        configuration?.titleLineBreakMode = .byWordWrapping // A long one wraps, at the phone's width.
        related.configuration = configuration
        related.accessibilityHint = "Shows the related notes."
        related.isHidden = readout == nil
        setNeedsLayout()
    }

    /// Reading, with this line under the title, or writing (nil), with the buttons.
    func showReading(_ line: String?) {
        isReading = line != nil
        byline.text = line
        byline.isHidden = line == nil
        for button in [properties, related] { button.alpha = isReading ? 0 : 1 }
        setNeedsLayout()
    }

    /// The buttons showing, in order; none while reading.
    private var buttons: [UIButton] { isReading ? [] : [properties, related].filter { !$0.isHidden } }

    private static let bylineGap: CGFloat = 6
    private func bylineHeight(width: CGFloat) -> CGFloat {
        isReading ? byline.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + Self.bylineGap : 0
    }

    /// Where each button goes, below the title: along a line, onto the next when it doesn't fit,
    /// each no wider than the header.
    private func buttonFrames(width: CGFloat, top: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y = top, lineHeight: CGFloat = 0
        for button in buttons {
            let size = button.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let fitted = min(size.width, width)
            if x > 0, x + fitted > width {
                x = 0
                y += lineHeight + Self.between
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: fitted, height: size.height))
            x += fitted + Self.between
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let height = title.sizeThatFits(size).height + bylineHeight(width: size.width)
        let bottom = buttonFrames(width: size.width, top: height + Self.gap).map(\.maxY).max()
        return CGSize(width: size.width, height: (bottom.map { $0 + Self.below } ?? height + Self.below) + listRoom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleHeight = title.sizeThatFits(bounds.size).height
        title.frame = CGRect(x: 0, y: 0, width: bounds.width, height: titleHeight)
        let height = titleHeight + bylineHeight(width: bounds.width)
        if isReading {
            byline.frame = CGRect(x: 0, y: titleHeight + Self.bylineGap, width: bounds.width, height: height - titleHeight - Self.bylineGap)
        }
        for (button, frame) in zip(buttons, buttonFrames(width: bounds.width, top: height + Self.gap)) {
            button.frame = frame
        }
        if let list {
            let top = (buttons.map { $0.frame.maxY }.max() ?? height) + Self.listGap
            list.frame = CGRect(x: 0, y: top, width: bounds.width, height: listHeight)
        }
    }
}

/// A note's title: as many lines as it needs, scrolling with the note rather than by itself.
final class TitleView: UITextView {
    override var text: String! {
        didSet {
            updatePlaceholder()
            superview?.setNeedsLayout()
            superview?.superview?.setNeedsLayout()
        }
    }
    private let placeholder = UILabel()

    private static let writingFont = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 28, weight: .bold))

    /// Reading: the title can't be changed, and is set as the text is.
    func setReading(_ reading: Bool, serif: Bool) {
        isEditable = !reading
        let base = UIFont.systemFont(ofSize: 28, weight: .bold)
        let design = reading && serif ? base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 28) } ?? base : base
        font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: design)
        placeholder.font = font
        superview?.setNeedsLayout()
    }

    init() {
        super.init(frame: .zero, textContainer: nil)
        font = Self.writingFont
        adjustsFontForContentSizeCategory = true
        accessibilityLabel = "Title"
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        returnKeyType = .next
        autocapitalizationType = .sentences
        placeholder.text = "Title"
        placeholder.font = font
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        addSubview(placeholder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    func updatePlaceholder() { placeholder.isHidden = !text.isEmpty }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.frame = bounds
    }
}

/// The shared editor, for a note's session.
struct EditorView: UIViewRepresentable {
    let session: NoteSession

    func makeUIView(context: Context) -> PhoneTextView {
        let textView = PhoneTextView()
        textView.accessibilityLabel = "Note"
        session.textView = textView
        // The title, at the top, scrolling with the text.
        let header = NoteHeader()
        let title = header.title
        title.delegate = session
        session.titleField = title
        session.header = header
        header.onProperties = { [weak session] in session?.showsProperties = true }
        header.onRelated = { [weak session] in session?.showsRelated = true }
        textView.header = header
        let bar = FormatBar(textView: textView)
        textView.inputAccessoryView = bar
        session.formatBar = bar
        bar.linkText = { [weak session] in session?.store.linkText(forTitle: $0) ?? $0 }
        textView.onCompletionChange = { [weak bar, weak session] completion in
            bar?.show(completion, choices: completion.flatMap { session?.choices(for: $0) } ?? [])
        }
        textView.onTextChange = { [weak session] in session?.changed($0) }
        textView.onOpenLink = { [weak session] in session?.open($0) }
        textView.editMenuActions = { [weak session] in session?.readerMenu(for: $0) ?? [] }
        textView.onPlainTap = { [weak session] in session?.readerTapped() }
        // Images and lists embedded in the note, drawn over it, as on the Mac.
        textView.makeBlockEmbedView = { [weak session] in session?.makeEmbedView($0) ?? UIView() }
        textView.blockEmbedHeight = { [weak session] in session?.listEmbedHeight($0) }
        textView.imageURL = { [weak session] in session?.imageURL($0) }
        textView.onOpenImage = { [weak session] in session?.showImage($0) }
        DispatchQueue.main.async { session.open() }
        return textView
    }

    func updateUIView(_ textView: PhoneTextView, context: Context) {}
}
