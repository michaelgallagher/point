import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Shows and edits one note. The session behind it does the loading and saving.
struct NoteEditor: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @StateObject private var session: EditorSession
    @StateObject private var connections: Connections
    /// The pane it's in, where links clicked in it open.
    let paneID: VaultModel.NotePane.ID
    /// Whether to offer templates while the note is empty (a note just made).
    var offersTemplates = false
    init(note: Note, model: VaultModel, paneID: VaultModel.NotePane.ID, offersTemplates: Bool = false) {
        self.paneID = paneID
        self.offersTemplates = offersTemplates
        _session = StateObject(wrappedValue: EditorSession(note: note))
        _connections = StateObject(wrappedValue: Connections(note: note, model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Below the see-through top bar; only the text scrolls beneath it.
            Color.clear.frame(height: session.conflict != nil || session.message != nil ? topBarCover : 0)
            if session.conflict != nil {
                ConflictBanner(session: session)
            }
            if let message = session.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isLoaded {
                // The header (path, title, properties) is inside the editor, so it scrolls
                // away with the text instead of taking up room above it.
                EditorView(session: session, model: model, paneID: paneID, offersTemplates: offersTemplates,
                           showsMarkdown: model.showsMarkdown, textScale: model.textScale, typography: model.store.typography,
                           textColumnWidth: model.store.textColumnWidth)
            } else {
                Color.clear
            }
            ConnectionsBar(connections: connections)
        }
        .task {
            await session.load()
            connections.refresh()
        }
        .onDisappear { session.save(leaving: true) }
    }
}

/// Above the text, scrolling with it: the note's title (its file name: most notes don't
/// start with a heading), its properties, and for a new note, templates. Where the note
/// lives is in the side's top bar. A hairline always separates it from the text.
private struct NoteHeader: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var model: VaultModel
    let offersTemplates: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                // Its file name, which can be edited here to rename the note.
                TitleField(note: session.note, model: model)
            }
            .padding(.top, 16)
            .padding(.bottom, session.frontmatter == nil || model.showsMarkdown ? 12 : 2)
            .padding(.leading, 5) // Lines up with the text, which is inset a little.
            .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            // In Markdown mode the properties are in the text, as written, so not shown twice.
            if let frontmatter = session.frontmatter, !model.showsMarkdown {
                PropertiesStrip(frontmatter: frontmatter, session: session,
                                isExpanded: model.store.propertiesOpen[session.note.id] ?? UserDefaults.standard.bool(forKey: "propertiesExpanded"))
            }
            if offersTemplates, session.isEmpty, !model.templates.isEmpty {
                TemplateChoices()
            }
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
        // A title on several lines (pasted, say) is one line of a file name.
        let title = NoteFiles.sanitizedTitle(draft)
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
    let offersTemplates: Bool
    let onHeight: (CGFloat) -> Void

    var body: some View {
        NoteHeader(session: session, model: model, offersTemplates: offersTemplates)
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
private struct TemplateChoices: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Start from a template:")
                .foregroundStyle(.secondary)
            ForEach(model.templates, id: \.url) { template in
                Button(template.name) { model.insertTemplate(at: template.url) }
                    .modifier(GlassButtonStyle())
            }
            Text("or just type.")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// Glass buttons where the system has them, bordered ones before.
struct GlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
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
                    Button("Use Theirs") { session.useTheirs() }
                    Button("Keep Mine") { session.keepMine() }
                        .keyboardShortcut(.defaultAction)
                case .iCloud(let other)?:
                    Text("iCloud has another version of this note\(other.localizedNameOfSavingComputer.map { " from \($0)" } ?? "").")
                    Spacer()
                    Button("Keep Both") { session.keepBothVersions() }
                    Button("Use Other") { session.useOtherVersion() }
                    Button("Keep This") { session.keepThisVersion() }
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
    let offersTemplates: Bool
    /// Passed as a value, not read from the model, so SwiftUI updates the view when it changes.
    let showsMarkdown: Bool
    let textScale: Double
    let typography: Typography
    let textColumnWidth: Double

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        textView.typography = typography
        textView.textScale = textScale
        textView.maxTextWidth = textColumnWidth
        // The keyboard stays in the list after picking a note there, and with two sides it
        // stays with the side being worked on (an editor on the other side, rebuilt when the
        // window splits, mustn't take it).
        let isActivePane = model.paneIndex(paneID) == model.activePane
        session.attach(textView, takesFocus: !model.consumeListFocus() && isActivePane)
        // Hidden until the header's height is known, so the text doesn't show at the top for a
        // moment and then move down.
        textView.alphaValue = 0
        let header = NSHostingView(rootView: NoteHeaderHost(
            session: session, model: model, offersTemplates: offersTemplates,
            onHeight: { [weak textView, animator = HeaderHeightAnimator(textView: textView)] height in
                animator.move(to: height)
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
        context.coordinator.notesGeneration = model.store.notesGeneration
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
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

    final class Coordinator {
        var notesGeneration = 0
    }
}
