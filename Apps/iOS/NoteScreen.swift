import EditorKit
import SwiftUI
import VaultKit

/// One note, filling the screen, in the shared editor, its title at the top (its file name, as
/// on the Mac: changing it renames the note). Its menu bookmarks it. A new note opens with the
/// cursor in its title. Opened with `-SpikeTypeTest`, what opening and typing cost shows across
/// the top (see the spike).
struct NoteScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @StateObject private var session: NoteSession

    init(note: Note, store: PhoneStore, isNew: Bool = false) {
        _session = StateObject(wrappedValue: NoteSession(note: note, store: store, isNew: isNew))
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Find in Note", systemImage: "text.magnifyingglass") { session.find("") }
                        Button("Properties", systemImage: "list.bullet.rectangle") { session.showsProperties = true }
                        let bookmarked = store.isBookmarked(session.note.id)
                        Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                            store.toggleBookmark(session.note.id)
                        }
                    }
                }
            }
            .sheet(isPresented: $session.showsProperties) {
                PropertiesSheet(session: session).environmentObject(store)
            }
            .onAppear { store.noteOpened(session.note.id) }
            .onChange(of: store.findRequest) { _, text in
                guard let text else { return }
                store.findRequest = nil
                // Once this screen's back in place.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { session.find(text) }
            }
            .onDisappear {
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
    /// The note's frontmatter, as its text is now.
    @Published private(set) var frontmatter: Frontmatter?
    @Published var showsProperties = false
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
        }
        openedTimings = "Read \(Int(read)) ms, shown \(Int(load)) ms (\(text.count / 1000)k characters)"
        if showsTimings {
            timings = openedTimings
            PhoneVault.log("opened \(note.title): \(openedTimings)")
            typeTest()
        }
    }

    func open(_ link: LinkTarget) { store.open(link, from: note.id) }

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

    // MARK: Properties

    private func noteFrontmatter(of text: String) {
        let parsed = text.hasPrefix("---") ? Frontmatter.parse(text) : nil
        guard parsed != frontmatter || frontmatter == nil else { return }
        frontmatter = parsed
        header?.showSummary(parsed.flatMap { $0.properties.isEmpty ? nil : Self.summary(of: $0) })
    }

    /// "3 properties · #work #idea"
    private static func summary(of frontmatter: Frontmatter) -> String {
        let count = frontmatter.properties.count
        var parts = ["\(count) \(count == 1 ? "property" : "properties")"]
        let tags = frontmatter.tags
        if !tags.isEmpty { parts.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
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

/// What's above a note's text: its title, and below that a line summing up its properties, if
/// it has any, which opens them.
final class NoteHeader: UIView {
    let title = TitleView()
    var onSummary: (() -> Void)?
    private let summary = UIButton(type: .system)
    private var summaryHeight: CGFloat { UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 20) }
    private static let gap: CGFloat = 4

    init() {
        super.init(frame: .zero)
        addSubview(title)
        addSubview(summary)
        summary.isHidden = true
        summary.contentHorizontalAlignment = .leading
        summary.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        summary.titleLabel?.adjustsFontForContentSizeCategory = true
        summary.titleLabel?.lineBreakMode = .byTruncatingTail
        summary.setTitleColor(.secondaryLabel, for: .normal)
        summary.addAction(UIAction { [weak self] _ in self?.onSummary?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    func showSummary(_ text: String?) {
        summary.setTitle(text, for: .normal)
        summary.isHidden = text == nil
        superview?.setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let height = title.sizeThatFits(size).height
        return CGSize(width: size.width, height: height + (summary.isHidden ? 0 : Self.gap + summaryHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = title.sizeThatFits(bounds.size).height
        title.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        summary.frame = CGRect(x: 0, y: height + Self.gap, width: bounds.width, height: summaryHeight)
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
        font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 24, weight: .bold))
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
        header.onSummary = { [weak session] in session?.showsProperties = true }
        textView.header = header
        let bar = FormatBar(textView: textView)
        textView.inputAccessoryView = bar
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
