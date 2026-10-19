import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Shows and edits one note. The session behind it does the loading and saving.
struct NoteEditor: View {
    @EnvironmentObject private var model: VaultModel
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
            if session.conflict != nil {
                ConflictBanner(session: session)
            }
            // Where the note lives, then its title (its file name), above everything: most
            // notes don't start with a heading.
            VStack(alignment: .leading, spacing: 4) {
                NotePath(note: session.note, vault: model.root?.lastPathComponent ?? "Vault")
                Text(session.note.title)
                    .font(.system(size: 24 * model.textScale, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(.top, 14)
            .padding(.leading, 5) // Lines up with the text, which is inset a little.
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            if let frontmatter = session.frontmatter {
                PropertiesStrip(frontmatter: frontmatter, session: session)
            }
            if let message = session.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isLoaded {
                if offersTemplates, session.isEmpty, !model.templates.isEmpty {
                    TemplateChoices()
                }
                EditorView(session: session, model: model, paneID: paneID, showsMarkdown: model.showsMarkdown, textScale: model.textScale)
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
        .frame(maxWidth: 720, alignment: .leading)
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
    /// Passed as a value, not read from the model, so SwiftUI updates the view when it changes.
    let showsMarkdown: Bool
    let textScale: Double

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        // The keyboard stays in the list after picking a note there, and with two sides it
        // stays with the side being worked on (an editor on the other side, rebuilt when the
        // window splits, mustn't take it).
        let isActivePane = model.paneIndex(paneID) == model.activePane
        session.attach(textView, takesFocus: !model.consumeListFocus() && isActivePane)
        let noteID = session.note.id
        textView.onOpenLink = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID) }
        textView.onOpenLinkInNewTab = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID, as: .newTab) }
        textView.onOpenLinkToSide = { [weak model, paneID] link in model?.open(link, from: noteID, inPane: paneID, as: .otherSide) }
        // Typing or clicking in a note makes its pane the one the list and menus act on.
        textView.onFocus = { [weak model, paneID] in
            DispatchQueue.main.async { model?.activate(pane: paneID) }
        }
        textView.completeNoteTitle = { [weak model] partial in model?.titleSuggestions(for: partial) ?? [] }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.showsMarkdown = showsMarkdown
        textView.textScale = textScale
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {}
}
