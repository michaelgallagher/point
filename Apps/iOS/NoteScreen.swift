import EditorKit
import SwiftUI
import VaultKit

/// One note, filling the screen, in the shared editor. Its menu bookmarks it. Opened with
/// `-SpikeTypeTest`, what opening and typing cost shows across the top (see the spike).
struct NoteScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let note: Note
    @State private var timings = ""

    var body: some View {
        EditorView(note: note, store: store, timings: $timings)
            .ignoresSafeArea(.container, edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !timings.isEmpty {
                    Text(timings)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        let bookmarked = store.isBookmarked(note.id)
                        Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                            store.toggleBookmark(note.id)
                        }
                    }
                }
            }
            .onAppear { store.noteOpened(note.id) }
    }
}

/// The editor, saving as the Mac does: a second after typing stops, and on leaving; never
/// over a change made elsewhere.
struct EditorView: UIViewRepresentable {
    let note: Note
    let store: PhoneStore
    @Binding var timings: String

    func makeCoordinator() -> Coordinator { Coordinator(note: note, store: store) }

    func makeUIView(context: Context) -> PhoneTextView {
        let textView = PhoneTextView()
        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.show = { timings = $0 }
        textView.onTextChange = { coordinator.changed($0) }
        DispatchQueue.main.async { coordinator.open() }
        return textView
    }

    func updateUIView(_ textView: PhoneTextView, context: Context) {}

    static func dismantleUIView(_ textView: PhoneTextView, coordinator: Coordinator) {
        coordinator.save()
    }

    @MainActor
    final class Coordinator {
        let note: Note
        let store: PhoneStore
        /// Timings shown only for the spike's typing test.
        private let showsTimings = UserDefaults.standard.bool(forKey: "SpikeTypeTest")
        weak var textView: PhoneTextView?
        var show: (String) -> Void = { _ in }
        private var onDisk: String?
        private var pendingSave: Task<Void, Never>?
        private var opened = ""

        init(note: Note, store: PhoneStore) {
            self.note = note
            self.store = store
        }

        func open() {
            guard let textView else { return }
            let readStart = CACurrentMediaTime()
            guard let text = try? NoteReader.read(note) else { return show("Couldn’t read this note") }
            let read = (CACurrentMediaTime() - readStart) * 1000
            let load = textView.load(text)
            onDisk = text
            opened = "Read \(Int(read)) ms, shown \(Int(load)) ms (\(text.count / 1000)k characters)"
            if showsTimings { show(opened) }
            PhoneVault.log("opened \(note.title): \(opened)")
            if showsTimings { typeTest() }
        }

        func changed(_ text: String) {
            guard let textView else { return }
            if textView.text != onDisk { store.noteEdited(note.id) }
            if showsTimings { show("\(opened)\nLast keystroke \(String(format: "%.1f", textView.lastEditMilliseconds)) ms, slowest \(String(format: "%.1f", textView.slowestEditMilliseconds)) ms") }
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.save()
            }
        }

        func save() {
            pendingSave?.cancel()
            guard let textView, let onDisk, textView.text != onDisk else { return }
            let text = textView.text ?? ""
            if case .saved? = try? NoteWriter.write(text, to: note.url, expecting: onDisk, ifChanged: .saveCopy) {
                self.onDisk = text
            }
        }

        /// `-SpikeTypeTest YES`: types 200 characters at the end of the note, one at a time,
        /// as the keyboard would, and logs what each cost.
        private func typeTest() {
            guard let textView else { return }
            let sentence = "Typing at a workshop, one word after another. "
            var times: [Double] = []
            var parses: [Double] = [], edits: [Double] = []
            textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
            for (index, character) in sentence.repeated(to: 200).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(index) * 0.03) {
                    let start = CACurrentMediaTime()
                    textView.insertText(String(character))
                    // Laid out where the cursor is, as the screen needs it.
                    textView.layoutManager.ensureLayout(forCharacterRange: NSRange(location: textView.selectedRange.location, length: 0))
                    times.append((CACurrentMediaTime() - start) * 1000)
                    parses.append(textView.lastParseMilliseconds)
                    edits.append(textView.lastEditMilliseconds)
                    if times.count == 200 {
                        let sorted = times.sorted()
                        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
                        let summary = String(format: "typing 200 characters: median %.1f ms (parsing %.1f, restyling %.1f), 95th %.1f ms, slowest %.1f ms",
                                             sorted[100], median(parses), median(edits) - median(parses), sorted[190], sorted[199])
                        PhoneVault.log("\(self.note.title): \(summary)")
                        self.show("\(self.opened)\n\(summary)")
                    }
                }
            }
        }
    }
}

private extension String {
    func repeated(to count: Int) -> String {
        String(String(repeating: self, count: count / max(self.count, 1) + 1).prefix(count))
    }
}
