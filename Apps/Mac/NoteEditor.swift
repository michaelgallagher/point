import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Shows and edits one note. The session behind it does the loading and saving.
struct NoteEditor: View {
    @EnvironmentObject private var model: VaultModel
    @StateObject private var session: EditorSession
    @StateObject private var connections: Connections

    init(note: Note, model: VaultModel) {
        _session = StateObject(wrappedValue: EditorSession(note: note))
        _connections = StateObject(wrappedValue: Connections(note: note, model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.conflict != nil {
                ConflictBanner(session: session)
            }
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
                EditorView(session: session, model: model, showsMarkdown: model.showsMarkdown, textScale: model.textScale)
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
    /// Passed as a value, not read from the model, so SwiftUI updates the view when it changes.
    let showsMarkdown: Bool
    let textScale: Double

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        session.attach(textView)
        let noteID = session.note.id
        textView.onOpenLink = { [weak model] link in model?.open(link, from: noteID) }
        textView.onOpenLinkInNewTab = { [weak model] link in model?.open(link, from: noteID, inNewTab: true) }
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
