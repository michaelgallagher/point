import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Shows and edits one note. The session behind it does the loading and saving.
struct NoteEditor: View {
    @StateObject private var session: EditorSession

    init(note: Note) {
        _session = StateObject(wrappedValue: EditorSession(note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
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
                EditorView(session: session)
            } else {
                Color.clear
            }
        }
        .task { await session.load() }
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

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        session.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {}
}
