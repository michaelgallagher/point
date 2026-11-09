import AppKit
import EditorKit
import IndexKit
import SwiftUI
import VaultKit

/// Shows and edits one note. The session behind it does the loading and saving.
struct NoteEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @StateObject private var session: EditorSession
    @ObservedObject private var connections: Connections
    @AppStorage(LinksPlacement.key) private var linksPlacement = LinksPlacement.side
    /// View › Show Word Count, kept by the store.
    @AppStorage("showsWordCount") private var showsWordCount = false
    /// The pane it's in, where links clicked in it open.
    let paneID: VaultModel.NotePane.ID
    /// The tab it's in, which keeps where it was in the note (see `VaultModel.notePlaces`).
    let tabID: VaultModel.NoteTab.ID?
    /// Whether to offer templates while the note is empty (a note just made).
    var offersTemplates = false
    init(note: Note, model: VaultModel, paneID: VaultModel.NotePane.ID, tabID: VaultModel.NoteTab.ID? = nil, offersTemplates: Bool = false) {
        self.paneID = paneID
        self.tabID = tabID
        self.offersTemplates = offersTemplates
        _session = StateObject(wrappedValue: EditorSession(note: note, drafts: model.store.drafts))
        connections = model.connections(for: note)
    }

    var body: some View {
        page
            // Over the note: at its bottom right, the button opening the links at the side
            // (the panel is beside the pane: see `PaneView`); or at its bottom left, the
            // strip growing up into them.
            .overlay {
                switch linksPlacement {
                case .side: LinksButton(connections: connections, paneID: paneID)
                case .bottom: LinksStrip(connections: connections)
                }
            }
            // In the corner the links leave free.
            .overlay {
                WordCountLabel(tally: session.wordTally, alignment: linksPlacement == .side ? .bottomLeading : .bottomTrailing)
            }
            .onAppear { session.countsWords = showsWordCount }
            .onChange(of: showsWordCount) { session.countsWords = $0 }
        .task {
            await session.load()
            connections.refresh()
        }
        .onDisappear {
            // Closed with edits that couldn't be saved: they're kept, and offered next time.
            if !session.save(leaving: true) { model.store.reportUnsaved(session.note) }
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            // Below the see-through top bars; only the text scrolls beneath them.
            Color.clear.frame(height: session.conflict != nil || session.message != nil
                              || session.saveProblem != nil || session.recoveredDraft != nil ? topBarCover : 0)
            if session.conflict != nil {
                ConflictBanner(session: session)
            }
            SaveBanner(session: session)
            if let message = session.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isLoaded {
                // The header (path, title, properties) is inside the editor, so it scrolls
                // away with the text instead of taking up room above it.
                EditorView(session: session, model: model, paneID: paneID, tabID: tabID, offersTemplates: offersTemplates,
                           showsMarkdown: model.showsMarkdown(inPane: paneID), textScale: model.textScale, typography: model.store.typography,
                           textColumnWidth: model.store.textColumnWidth, barBelowTitleBar: max(topBarCover - model.topBarHeight, 0))
            } else {
                Color.clear
            }
        }
    }
}

/// Above the text, scrolling with it: the note's title (its file name: most notes don't
/// start with a heading), the folders it's in above it, its properties, and for a new note,
/// templates. A hairline always separates it from the text.
private struct NoteHeader: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    let offersTemplates: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                NotePath(note: session.note, model: model)
                // Its file name, which can be edited here to rename the note.
                TitleField(note: session.note, model: model)
            }
            .padding(.top, 16)
            .padding(.bottom, shownFrontmatter == nil || model.showsMarkdown(inPane: paneID) ? 12 : 2)
            .padding(.leading, 5) // Lines up with the text, which is inset a little.
            .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            // In Markdown mode the properties are in the text, as written, so not shown twice.
            if let frontmatter = shownFrontmatter, !model.showsMarkdown(inPane: paneID) {
                PropertiesStrip(frontmatter: frontmatter, session: session, paneID: paneID,
                                isExpanded: model.store.propertiesOpen[session.note.id] ?? UserDefaults.standard.bool(forKey: "propertiesExpanded"))
            }
            if let list = ListDefinition(frontmatter: session.frontmatter) {
                ListPanel(list: list, session: session, model: model, store: model.store, paneID: paneID)
            }
            if offersTemplates, session.isEmpty, !model.templates.isEmpty {
                TemplateChoices()
            }
        }
    }
}

extension NoteHeader {
    /// The properties to show: for a note Point named, all but its `title:`, which is the title
    /// above them.
    /// (None at all, if that's its only one.)
    var shownFrontmatter: Frontmatter? {
        guard let frontmatter = session.frontmatter else { return nil }
        // A list's own properties are shown as the list, under them.
        let isList = ListDefinition(frontmatter: frontmatter) != nil
        guard NoteNames.isDated(session.note.name) || isList else { return frontmatter }
        var shown = frontmatter
        shown.properties.removeAll { property in
            (NoteNames.isDated(session.note.name) && property.key.lowercased() == "title")
                || (isList && ListDefinition.isListKey(property.key))
        }
        return shown.properties.isEmpty ? nil : shown
    }
}

/// The folders a note is in, above its title: "Projects / Point". Clicking one shows it in
/// the sidebar. Nothing for a note at the vault's top level.
private struct NotePath: View {
    let note: Note
    @ObservedObject var model: VaultModel

    var body: some View {
        let names = note.id.split(separator: "/").dropLast().map(String.init)
        if !names.isEmpty {
            HStack(spacing: 4) {
                ForEach(names.indices, id: \.self) { index in
                    if index > 0 {
                        Text("/").foregroundStyle(.tertiary)
                    }
                    Button(names[index]) { model.reveal(folder: names[...index].joined(separator: "/")) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Show “\(names[index])”")
                }
            }
            // The same size as the properties below, and the menus and date pickers in them,
            // which AppKit draws at 13pt whatever the text size.
            .font(.body)
            .lineLimit(1)
        }
    }
}

/// A note's title, editable: Return (or clicking away) renames the note, and its file, and
/// updates links to it; Escape puts the title back.
private struct TitleField: View {
    let note: Note
    @ObservedObject var model: VaultModel
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("Title", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            // The title is 24pt for 15pt text, and follows the text size chosen.
            .font(.system(size: 24 * model.textScale * model.store.typography.bodySize / 15, weight: .semibold))
            .lineLimit(1...3)
            .focused($isEditing)
            .onSubmit { commit() }
            .onExitCommand {
                draft = note.title
                isEditing = false
            }
            .onChange(of: isEditing) { editing in
                if !editing { commit() }
            }
            .onAppear { draft = note.title }
            .onChange(of: note.title) { title in
                if !isEditing { draft = title }
            }
            .help("Rename")
    }

    private func commit() {
        // A title on several lines (pasted, say) is one line of a file name. A note Point named
        // can have any title: its name is made from it.
        let title = NoteNames.isDated(note.name) ? draft.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            : NoteFiles.sanitizedTitle(draft)
        guard !title.isEmpty, title != note.title else {
            draft = note.title
            return
        }
        model.rename(note, to: title)
    }
}

/// Measures the header, so the editor can put the text below it.
private struct NoteHeaderHost: View {
    let session: EditorSession
    let model: VaultModel
    let paneID: VaultModel.NotePane.ID
    let offersTemplates: Bool
    let onHeight: (CGFloat) -> Void

    var body: some View {
        NoteHeader(session: session, model: model, paneID: paneID, offersTemplates: offersTemplates)
            .environmentObject(model)
            // No SwiftUI animation inside: the editor moves the text and reveals the header
            // together (see `HeaderHeightAnimator`), and the two animating apart look like a jump.
            .transaction { $0.animation = nil }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeight.self, value: proxy.size.height)
            })
            .onPreferenceChange(HeaderHeight.self) { height in
                DispatchQueue.main.async { onHeight(height) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Moves the text down or up as the header grows or shrinks, in step with the header's own
/// animation (the properties opening or closing), rather than jumping to the new place.
@MainActor
private final class HeaderHeightAnimator: NSObject {
    private weak var textView: MarkdownTextView?
    private var timer: Timer?
    private var start: CGFloat = 0
    private var target: CGFloat = 0
    private var began: CFTimeInterval = 0
    /// The properties' open and close animation.
    private let duration: CFTimeInterval = 0.15

    init(textView: MarkdownTextView) {
        self.textView = textView
    }

    func move(to height: CGFloat) {
        guard let textView else { return }
        timer?.invalidate()
        // The first measurement, and slight changes, go straight there.
        guard textView.headerHeight > 0, abs(height - textView.headerHeight) > 2 else {
            textView.headerHeight = height
            return
        }
        start = textView.headerHeight
        target = height
        began = CACurrentMediaTime()
        // The header keeps room for all of itself while the text moves.
        textView.headerViewMinimumHeight = max(start, target)
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 120, target: self, selector: #selector(step),
                                     userInfo: nil, repeats: true)
    }

    @objc private func step() {
        guard let textView else { return timer?.invalidate() ?? () }
        let progress = min(1, (CACurrentMediaTime() - began) / duration)
        // Ease out, like SwiftUI's .easeOut.
        let eased = 1 - pow(1 - progress, 3)
        textView.headerHeight = start + (target - start) * eased
        if progress >= 1 {
            timer?.invalidate()
            timer = nil
            textView.headerViewMinimumHeight = 0
        }
    }
}

private struct HeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Above a new, empty note: start from a template, or just type.
/// Under a new note's title while it's empty: its templates, listed as the new tab page lists
/// notes, to start from one with a click. (They were a row of glass buttons, cut short in a
/// narrow side.)
private struct TemplateChoices: View {
    @EnvironmentObject private var model: VaultModel
    @State private var hovered: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaletteSectionHeader(title: "Start from a template", isFirst: true)
            ForEach(model.templates, id: \.url) { template in
                PaletteRow(item: .template(template.name, template.url), isHighlighted: hovered == template.url)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = template.url } else if hovered == template.url { hovered = nil }
                    }
                    .onTapGesture { model.applyTemplate(at: template.url) }
            }
            Text("or just type")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
        // The rows' icons line up with the title above.
        .padding(.horizontal, 23)
        .padding(.vertical, 8)
        .frame(maxWidth: model.store.textColumnWidth + 46, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// A save that failed (the edits kept meanwhile), or edits kept from an earlier one, to put back.
private struct SaveBanner: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        if let problem = session.saveProblem {
            banner {
                Text(problem)
                Spacer()
                if session.fileIsMissing {
                    Button("Save it again") { session.recreateFile() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Try again") { session.retrySave() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        } else if let draft = session.recoveredDraft {
            banner {
                Text("Changes made \(draft.saved.formatted(date: .abbreviated, time: .shortened)) couldn’t be saved at the time.")
                Spacer()
                Button("Discard") { session.discardDraft() }
                Button("Restore them") { session.restoreDraft() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                content()
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}

private struct ConflictBanner: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                switch session.conflict {
                case .changedElsewhere?:
                    Text("This note was changed in another app while you were editing it.")
                    Spacer()
                    Button("Use theirs") { session.useTheirs() }
                    Button("Keep mine") { session.keepMine() }
                        .keyboardShortcut(.defaultAction)
                case .iCloud(let other)?:
                    Text("iCloud has another version of this note\(other.localizedNameOfSavingComputer.map { " from \($0)" } ?? "").")
                    Spacer()
                    Button("Keep both") { session.keepBothVersions() }
                    Button("Use other") { session.useOtherVersion() }
                    Button("Keep this") { session.keepThisVersion() }
                        .keyboardShortcut(.defaultAction)
                case nil:
                    EmptyView()
                }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}

private struct EditorView: NSViewRepresentable {
    let session: EditorSession
    let model: VaultModel
    let paneID: VaultModel.NotePane.ID
    let tabID: VaultModel.NoteTab.ID?
    let offersTemplates: Bool
    /// Passed as a value, not read from the model, so SwiftUI updates the view when it changes.
    let showsMarkdown: Bool
    let textScale: Double
    let typography: Typography
    let textColumnWidth: Double
    /// How far the top bars reach below the title bar, which the window insets the text from
    /// by itself.
    let barBelowTitleBar: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        scrollView.additionalSafeAreaInsets.top = barBelowTitleBar
        textView.typography = typography
        textView.textScale = textScale
        textView.maxTextWidth = textColumnWidth
        textView.extraBottomSpace = LinksButton.roomBelowText
        // The keyboard stays in the list after picking a note there, and with two sides it
        // stays with the side being worked on (an editor on the other side, rebuilt when the
        // window splits, mustn't take it).
        let isActivePane = model.paneIndex(paneID) == model.activePane
        // Back where this tab left the note, unless it's opening at a place in it (a link's).
        let placeKey = tabID.map { VaultModel.placeKey(tab: $0, note: session.note.id) }
        let revealing = EditorSession.hasPendingReveal(in: session.note.id)
        var place = revealing ? nil : placeKey.flatMap { model.notePlaces[$0] }
        // Until it's shown: the insertion point moves it before it has a place to be.
        var isShown = false
        context.coordinator.placeKey = placeKey
        context.coordinator.model = model
        session.attach(textView, takesFocus: !model.consumeListFocus() && isActivePane)
        if let selection = place?.selection, NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
        }
        // Hidden until the header's height is known, so the text doesn't show at the top for a
        // moment and then move down.
        textView.alphaValue = 0
        let header = NSHostingView(rootView: NoteHeaderHost(
            session: session, model: model, paneID: paneID, offersTemplates: offersTemplates,
            onHeight: { [weak textView, animator = HeaderHeightAnimator(textView: textView)] height in
                animator.move(to: height)
                // Scrolled back once the text is below the header, where it'll stay.
                if let scroll = place?.scroll {
                    textView?.scroll(to: scroll)
                } else if !isShown, !revealing {
                    textView?.scrollToTop()
                }
                place = nil
                isShown = true
                textView?.alphaValue = 1
            }
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak textView] in textView?.alphaValue = 1 }
        header.sizingOptions = [] // The editor sizes it: the full width, at the height it reports.
        textView.headerView = header
        let noteID = session.note.id
        textView.onOpenLink = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID) }
        textView.onOpenLinkInNewTab = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID, as: .newTab) }
        textView.onOpenLinkToSide = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID, as: .otherSide) }
        // Typing or clicking in a note makes its pane the one the list and menus act on.
        textView.onFocus = { [weak model, paneID] in
            DispatchQueue.main.async { model?.activate(pane: paneID) }
        }
        textView.completeNoteTitle = { [weak model] partial in model?.titleSuggestions(for: partial) ?? [] }
        // A note Point named is linked by its name, labelled with its title.
        textView.linkTextForTitle = { [weak model] title in model?.store.linkText(forTitle: title) ?? title }
        // `@` and a name: a link to that person's note.
        textView.completePerson = { [weak model] partial in model?.store.peopleSuggestions(for: partial) ?? [] }
        // Typing ends the chance to reopen a just-closed tab with ⌘Z.
        let onTextChange = textView.onTextChange
        textView.onTextChange = { [weak model] view in
            onTextChange?(view)
            model?.noteEdited()
        }
        // Links to notes that don't exist yet are fainter.
        textView.wikiLinkExists = { [weak model, weak session] target in
            guard let model, let session else { return true }
            return model.store.linkResolver.resolve(wikiTarget: target, from: session.note.id) != nil
        }
        // Images in the vault are shown above their embeds; pasted or dropped ones are saved
        // in the attachment folder, named after the note.
        textView.imageURL = { [weak model, weak session] target in
            guard let model, let session else { return nil }
            return model.store.imageURL(for: target, from: session.note.id)
        }
        // Lists embedded alone on a line show the notes they find, above the embed.
        textView.blockEmbedHeight = { [weak model, weak session] target in
            guard let model, let session else { return nil }
            return model.store.listEmbedHeight(target, from: session.note.id)
        }
        textView.makeBlockEmbedView = { [weak model, weak session, paneID] target in
            guard let model, let session, let id = model.store.embeddedListID(target, from: session.note.id) else { return NSView() }
            let view = NSHostingView(rootView: ListEmbed(listID: id, model: model, store: model.store, paneID: paneID).environmentObject(model))
            // The room the text made for it, not the size SwiftUI would make it.
            view.sizingOptions = []
            return view
        }
        textView.saveImage = { [weak model, weak session] data, type in
            guard let model, let session else { return nil }
            return model.store.saveImage(data, type: type, for: session.note)
        }
        // List items starting `! `, `? ` and so on are coloured, in the vault's colours.
        textView.listHighlights = model.settings.listCallouts.map {
            ($0.character, NSColor(srgbRed: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1))
        }
        context.coordinator.notesGeneration = model.store.notesGeneration
        context.coordinator.watchEmbeds(of: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        scrollView.additionalSafeAreaInsets.top = barBelowTitleBar
        textView.showsMarkdown = showsMarkdown
        textView.textScale = textScale
        textView.typography = typography
        textView.maxTextWidth = textColumnWidth
        // A note added, renamed or removed can change which links lead anywhere.
        if context.coordinator.notesGeneration != model.store.notesGeneration {
            context.coordinator.notesGeneration = model.store.notesGeneration
            textView.restyleAll()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps where the note was, for its tab to come back to.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? MarkdownTextView, let key = coordinator.placeKey else { return }
        coordinator.model?.notePlaces[key] = VaultModel.NotePlace(scroll: textView.scrollAnchor, selection: textView.selectedRange())
    }

    @MainActor
    final class Coordinator: NSObject {
        var notesGeneration = 0
        var placeKey: String?
        weak var model: VaultModel?
        private weak var textView: MarkdownTextView?

        /// Restyles the note when what it embeds changes (images loaded, lists finding more or
        /// fewer notes): SwiftUI doesn't update the editor for that on its own.
        func watchEmbeds(of textView: MarkdownTextView) {
            self.textView = textView
            NotificationCenter.default.removeObserver(self, name: .pointEmbedsChanged, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(embedsChanged), name: .pointEmbedsChanged, object: nil)
        }

        @objc private func embedsChanged() {
            guard let textView, let model else { return }
            notesGeneration = model.store.notesGeneration
            textView.restyleAll()
        }
    }
}
