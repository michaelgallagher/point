import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Shows and edits one note, saving changes back to its file.
struct NoteEditor: View {
    let note: Note
    @State private var text: String?
    @State private var message: String?

    var body: some View {
        Group {
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let text {
                EditorView(note: note, text: text)
            } else {
                Color.clear
            }
        }
        // `note` changes identity when its modification date does, so edits made
        // elsewhere are re-read on the next scan.
        .task(id: note) {
            let note = note
            do {
                text = try await Task.detached { try NoteReader.read(note) }.value
                message = nil
            } catch NoteReader.ReadError.notDownloaded {
                message = "Downloading from iCloud…"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private struct EditorView: NSViewRepresentable {
    let note: Note
    let text: String

    /// Owns saving: about a second after typing stops, and whenever the note is left.
    @MainActor
    final class Coordinator: NSObject {
        weak var textView: MarkdownTextView?
        var note: Note?
        /// The file's contents as last read or written, to detect changes made elsewhere.
        var onDisk: String?
        private var pendingSave: Task<Void, Never>?

        override init() {
            super.init()
            // Selector-based, so the observation ends by itself when the coordinator goes.
            NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        }

        @objc private func appWillResignActive() { save() }

        func textDidChange() {
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.save()
            }
        }

        func save() {
            pendingSave?.cancel()
            pendingSave = nil
            guard let textView, let note, let onDisk else { return }
            let text = textView.string
            guard text != onDisk else { return }
            do {
                switch try NoteWriter.write(text, to: note.url, expecting: onDisk) {
                case .saved:
                    self.onDisk = text
                case .savedAsConflictCopy(let copy):
                    // The file changed elsewhere; both versions are kept. Proper merging comes in M2.
                    self.onDisk = text
                    NSLog("Imprint: \(note.id) changed on disk; edits saved to \(copy.lastPathComponent)")
                }
            } catch {
                NSLog("Imprint: couldn't save \(note.id): \(error.localizedDescription)")
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable()
        context.coordinator.textView = textView
        textView.onTextChange = { [weak coordinator = context.coordinator] _ in coordinator?.textDidChange() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        let coordinator = context.coordinator
        let isSameNote = coordinator.note?.id == note.id
        // A re-read that matches what we hold (including our own save) changes nothing.
        guard !isSameNote || coordinator.onDisk != text else {
            coordinator.note = note
            return
        }
        coordinator.save() // Keep edits to the note being left.
        coordinator.note = note
        coordinator.onDisk = text
        textView.load(text)
        textView.window?.makeFirstResponder(textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.save()
    }
}
