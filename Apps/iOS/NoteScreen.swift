import EditorKit
import IndexKit
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
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var showsMove = false
    /// Makes a note in the given folder.
    private let newNote: (String) -> Void

    init(note: Note, store: PhoneStore, isNew: Bool = false, newNote: @escaping (String) -> Void) {
        _session = StateObject(wrappedValue: NoteSession(note: note, store: store, isNew: isNew))
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
                if session.isWriting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") { session.hideKeyboard() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .pageBar(.find { session.find("") }) {
                Button("New Note", systemImage: "square.and.pencil") { newNote(FolderTree.folder(of: session.note.id)) }
                Divider()
                Button("Move Note", systemImage: "folder") { showsMove = true }
                TemplateMenu(session: session)
                Toggle("Show Markdown", systemImage: "chevron.left.forwardslash.chevron.right", isOn: $store.showsMarkdown)
                let bookmarked = store.isBookmarked(session.note.id)
                Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                    store.toggleBookmark(session.note.id)
                }
                Button("Share", systemImage: "square.and.arrow.up") { session.share() }
                Divider()
                Button("Delete Note", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
            // A hardware keyboard leaves the format bar at the bottom, on top of this one.
            .toolbarVisibility(session.isWriting ? .hidden : .automatic, for: .bottomBar)
            .sheet(isPresented: $session.showsProperties) {
                PropertiesSheet(session: session).environmentObject(store)
            }
            .sheet(isPresented: $session.showsBacklinks) {
                BacklinksSheet(session: session).environmentObject(store)
            }
            .sheet(isPresented: $showsMove) {
                FolderPicker(title: "Move Note", current: FolderTree.folder(of: session.note.id)) { session.move(to: $0) }
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
                Text("It moves to Deleted Notes, where you can put it back.")
            }
            .onAppear { store.noteOpened(session.note.id) }
            .onChange(of: store.showsMarkdown) { _, shows in session.showMarkdown(shows) }
            .onChange(of: store.typography) { _, typography in session.textView?.typography = typography }
            // The index has taken in changed notes: what links here may have changed.
            .onChange(of: store.indexUpdates) { _, _ in session.refreshBacklinks() }
            .onDisappear {
                guard !isDeleting else { return session.moveToTrash() }
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
                Button("Try Again") { session.save() }
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
        Menu("Apply Template", systemImage: "doc.text") {
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
    private let store: PhoneStore
    weak var textView: PhoneTextView?
    weak var titleField: TitleView?
    weak var header: NoteHeader?
    weak var formatBar: FormatBar?
    /// The note's frontmatter, as its text is now.
    @Published private(set) var frontmatter: Frontmatter?
    @Published var showsProperties = false
    /// The notes linking to this one, by title.
    @Published private(set) var backlinks: [Backlink] = []
    @Published var showsBacklinks = false
    /// Writing in the note, when the format bar takes the bottom of the screen.
    @Published private(set) var isWriting = false
    /// Why a title couldn't be used (the name's taken, say), until dismissed.
    @Published private(set) var titleProblem: String?

    @Published private(set) var saveProblem: String?
    @Published private(set) var recoveredDraft: NoteDrafts.Draft?
    /// What opening and typing cost, shown only for the spike's typing test.
    @Published private(set) var timings = ""

    private var onDisk: String?
    private var pendingSave: Task<Void, Never>?
    private let showsTimings = UserDefaults.standard.bool(forKey: "SpikeTypeTest")
    private var openedTimings = ""

    init(note: Note, store: PhoneStore, isNew: Bool) {
        self.note = note
        self.store = store
        self.isNew = isNew
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(resignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editingChanged), name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editingChanged), name: UITextView.textDidEndEditingNotification, object: nil)
    }

    @objc private func editingChanged(_ notification: Notification) {
        guard let view = notification.object as? UITextView, view === textView || view === titleField else { return }
        isWriting = textView?.isFirstResponder == true || titleField?.isFirstResponder == true
        formatBar?.showsTools = textView?.isFirstResponder == true
    }

    /// Going to the background (the phone locked, another app): saved.
    @objc private func resignActive() {
        save()
        if let textView { store.noteCursor(textView.selectedRange.location) }
    }

    func open() {
        guard let textView else { return }
        let readStart = CACurrentMediaTime()
        guard let text = try? NoteReader.read(note) else {
            saveProblem = "Point couldn’t read this note."
            return
        }
        let read = (CACurrentMediaTime() - readStart) * 1000
        textView.typography = store.typography
        textView.showsMarkdown = store.showsMarkdown
        header?.showsProperties = !store.showsMarkdown
        let load = textView.load(text)
        onDisk = text
        noteFrontmatter(of: text)
        if let draft = store.drafts.draft(for: note.id) {
            if draft.text == text { store.drafts.remove(for: note.id) } else { recoveredDraft = draft }
        }
        titleField?.text = store.isUntitled(note.id) ? "" : note.title
        // A new note: straight to typing its title. Come back to: straight back to typing.
        if isNew {
            focusTitle()
        } else if let cursor = store.resumeCursor(for: note.id) {
            textView.placeCursor(at: cursor)
            textView.becomeFirstResponder()
        } else if let link = store.revealRange(for: note.id), NSMaxRange(link) <= (text as NSString).length {
            // Opened from one of another note's backlinks: at the link to that note.
            textView.scrollRangeToVisible(link)
        }
        refreshBacklinks()
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

    /// Shows the raw Markdown, or the formatted note, as on the Mac. With the Markdown showing,
    /// the properties are edited as text, so their button goes.
    func showMarkdown(_ shows: Bool) {
        textView?.showsMarkdown = shows
        header?.showsProperties = !shows
        textView?.setNeedsLayout()
    }

    /// Reads which notes link here, from the search index.
    func refreshBacklinks() {
        let note = note
        Task { [weak self] in
            guard let self else { return }
            let found = await store.backlinks(to: note)
            guard self.note == note, found != backlinks else { return }
            backlinks = found
            header?.showLinks(count: found.count)
            textView?.setNeedsLayout()
        }
    }

    /// Opens a note linking here, at its link, from the backlinks sheet.
    func open(_ backlink: Backlink) {
        showsBacklinks = false
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
            _ = try NoteWriter.write(text, to: note.url, expecting: onDisk, ifChanged: .saveCopy)
            self.onDisk = text
            saveProblem = nil
            store.drafts.remove(for: note.id)
            return true
        } catch {
            let kept = (try? store.drafts.keep(text, for: note.id)) != nil
            saveProblem = "Point couldn’t save this note (\(error.localizedDescription))."
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
        guard let textView, textView.text == onDisk, let text = try? NoteReader.read(note), text != onDisk else { return }
        textView.load(text)
        onDisk = text
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

    // MARK: Properties

    private func noteFrontmatter(of text: String) {
        let parsed = text.hasPrefix("---") ? Frontmatter.parse(text) : nil
        guard parsed != frontmatter || frontmatter == nil else { return }
        frontmatter = parsed
        header?.showProperties(count: parsed?.properties.count ?? 0)
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
        let typed = NoteFiles.sanitizedTitle(field.text ?? "")
        let untitled = store.isUntitled(note.id)
        guard !typed.isEmpty else {
            if !untitled { field.text = note.title }
            return
        }
        guard typed != note.title || untitled else { return }
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

/// What's above a note's text: its title, and below that, side by side, a button to its
/// properties, saying how many there are, and one to the notes linking to it, if any.
final class NoteHeader: UIView {
    let title = TitleView()
    var onProperties: (() -> Void)?
    var onLinks: (() -> Void)?
    private let properties = NoteHeader.button()
    private let links = NoteHeader.button()
    private static let gap: CGFloat = 8
    /// Between the buttons, side by side.
    private static let between: CGFloat = 8
    /// Between the buttons and the note's text.
    private static let below: CGFloat = 12
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
        addSubview(links)
        properties.addAction(UIAction { [weak self] _ in self?.onProperties?() }, for: .touchUpInside)
        links.addAction(UIAction { [weak self] _ in self?.onLinks?() }, for: .touchUpInside)
        showProperties(count: 0)
        showLinks(count: 0)
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

    /// "2 links": how many notes link here. None, and the button goes.
    func showLinks(count: Int) {
        links.configuration?.title = "\(count) \(count == 1 ? "link" : "links")"
        links.accessibilityHint = "Shows the notes linking to this one."
        links.isHidden = count == 0
        setNeedsLayout()
    }

    /// The buttons showing, in order.
    private var buttons: [UIButton] { [properties, links].filter { !$0.isHidden } }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let height = title.sizeThatFits(size).height
        let row = buttons.map { $0.sizeThatFits(size).height }.max()
        return CGSize(width: size.width, height: height + (row.map { Self.gap + $0 + Self.below } ?? Self.below))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = title.sizeThatFits(bounds.size).height
        title.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        var x: CGFloat = 0
        for button in buttons {
            let size = button.sizeThatFits(bounds.size)
            button.frame = CGRect(x: x, y: height + Self.gap, width: min(size.width, bounds.width - x), height: size.height)
            x += size.width + Self.between
        }
    }
}

/// The notes linking to a note, as the Mac's links panel lists them: each with the line its link
/// is on, opening at that link.
private struct BacklinksSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession

    var body: some View {
        NavigationStack {
            List(session.backlinks) { backlink in
                Button { session.open(backlink) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backlink.title)
                        if !backlink.context.isEmpty {
                            Text(backlink.context)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Links to this note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .overlay { if session.backlinks.isEmpty { ContentUnavailableView("No Links", systemImage: "link") } }
        }
        .presentationDetents([.medium, .large])
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

    init() {
        super.init(frame: .zero, textContainer: nil)
        font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 28, weight: .bold))
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
        header.onLinks = { [weak session] in session?.showsBacklinks = true }
        textView.header = header
        let bar = FormatBar(textView: textView)
        textView.inputAccessoryView = bar
        session.formatBar = bar
        textView.onCompletionChange = { [weak bar, weak session] completion in
            bar?.show(completion, choices: completion.flatMap { session?.choices(for: $0) } ?? [])
        }
        textView.onTextChange = { [weak session] in session?.changed($0) }
        textView.onOpenLink = { [weak session] in session?.open($0) }
        DispatchQueue.main.async { session.open() }
        return textView
    }

    func updateUIView(_ textView: PhoneTextView, context: Context) {}
}
