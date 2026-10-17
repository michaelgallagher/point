import AppKit
import SwiftUI
import VaultKit

/// Read-only raw text of a note. The real editor replaces this in M1.
struct NotePreview: View {
    let note: Note
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        Group {
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlainTextView(text: text)
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
                message = "Couldn't open this note: \(error.localizedDescription)"
            }
        }
    }
}

private struct PlainTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        guard textView.string != text else { return }
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
    }
}
