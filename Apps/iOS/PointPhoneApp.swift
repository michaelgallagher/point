import EditorKit
import SwiftUI
import VaultKit

/// The iPhone app, as a spike (M4 step 0; see plan/m4-iphone.md): notes from a folder on the
/// phone, opened in the shared editor, with what opening and typing cost shown on screen.
/// Not the app's design yet: that's step 1.
@main
struct PointPhoneApp: App {
    var body: some Scene {
        WindowGroup { NoteListScreen() }
    }
}

/// The vault on the phone, for now: a folder in the app's Documents, which the Files app
/// shows (copy notes in there). Two notes for measuring are made the first time.
enum PhoneVault {
    static let root: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    /// A long note with most kinds of Markdown, to time opening and typing; and a short one.
    /// `-SpikeSections <n>` for a longer one: 150 is about 45,000 characters, 900 about 270,000.
    static var sections: Int { max(UserDefaults.standard.integer(forKey: "SpikeSections"), 150) }
    /// The long note's title, by its length, so notes of each length can be kept side by side.
    static var longTitle: String { sections == 150 ? "Spike, long note" : "Spike, long note (\(sections) sections)" }

    static func makeSampleNotes() {
        let long = root.appendingPathComponent(longTitle + ".md")
        guard !FileManager.default.fileExists(atPath: long.path) else { return }
        var text = "---\ntags: [spike]\nstatus: draft\n---\n# A long note\n\n"
        for section in 1...sections {
            text += "## Section \(section)\n\n"
            text += "Some **bold** and *italic* text, a [[Link to a note]], a #tag, and `code`. "
            text += "Another sentence so the paragraph wraps across a few lines on a phone screen.\n\n"
            text += "- A bullet\n  - Nested under it\n- [ ] A task to do\n- [x] A task done\n1. Numbered\n2. Items\n\n"
            text += "> A quote, with ==highlighted== words.\n\n"
            if section % 10 == 0 { text += "```\nlet code = \(section)\n```\n\n" }
        }
        try? Data(text.utf8).write(to: long)
        try? Data("# A short note\n\nJust a few lines.\n\n- [ ] Try typing here\n".utf8)
            .write(to: root.appendingPathComponent("Spike, short note.md"))
    }

    /// Timings, appended to `spike-timings.txt` beside the vault (in Files), to read later.
    static func log(_ line: String) {
        let url = root.deletingLastPathComponent().appendingPathComponent("spike-timings.txt")
        let stamped = "\(Date().formatted(date: .numeric, time: .standard)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }
}

struct NoteListScreen: View {
    @State private var notes: [Note] = []
    @State private var path: [Note.ID] = []

    var body: some View {
        NavigationStack(path: $path) { list }
    }

    private var list: some View {
        List(notes) { note in
            NavigationLink(value: note.id) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                    Text(note.modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Notes")
        .navigationDestination(for: Note.ID.self) { id in
            if let note = notes.first(where: { $0.id == id }) { NoteScreen(note: note) }
        }
        .overlay { if notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text") } }
        .onAppear {
            load()
            // `-SpikeTypeTest YES` opens the long note by itself, to time typing in it.
            if UserDefaults.standard.bool(forKey: "SpikeTypeTest"), path.isEmpty,
               let long = notes.first(where: { $0.title == PhoneVault.longTitle }) {
                path = [long.id]
            }
        }
        .refreshable { load() }
    }

    private func load() {
        PhoneVault.makeSampleNotes()
        let start = CACurrentMediaTime()
        notes = ((try? VaultScanner.scan(PhoneVault.root)) ?? []).sorted { $0.modified > $1.modified }
        PhoneVault.log("scanned \(notes.count) notes in \(Int((CACurrentMediaTime() - start) * 1000)) ms")
    }
}

/// One note in the shared editor, with the timings across the top.
struct NoteScreen: View {
    let note: Note
    @State private var timings = "Opening…"

    var body: some View {
        EditorView(note: note, timings: $timings)
            .ignoresSafeArea(.container, edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(timings)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The editor, saving as the Mac does: a second after typing stops, and on leaving; never
/// over a change made elsewhere.
struct EditorView: UIViewRepresentable {
    let note: Note
    @Binding var timings: String

    func makeCoordinator() -> Coordinator { Coordinator(note: note) }

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
        weak var textView: PhoneTextView?
        var show: (String) -> Void = { _ in }
        private var onDisk: String?
        private var pendingSave: Task<Void, Never>?
        private var opened = ""

        init(note: Note) { self.note = note }

        func open() {
            guard let textView else { return }
            let readStart = CACurrentMediaTime()
            guard let text = try? NoteReader.read(note) else { return show("Couldn't read this note") }
            let read = (CACurrentMediaTime() - readStart) * 1000
            // Read again, to tell the first read's one-off costs (file coordination starting
            // up) from reading itself.
            let againStart = CACurrentMediaTime()
            _ = try? NoteReader.read(note)
            PhoneVault.log("read again: \(String(format: "%.1f", (CACurrentMediaTime() - againStart) * 1000)) ms")
            let load = textView.load(text)
            onDisk = text
            opened = "Read \(Int(read)) ms, shown \(Int(load)) ms (\(text.count / 1000)k characters)"
            show(opened)
            PhoneVault.log("opened \(note.title): \(opened)")
            if UserDefaults.standard.bool(forKey: "SpikeTypeTest") { typeTest() }
        }

        func changed(_ text: String) {
            guard let textView else { return }
            show("\(opened)\nLast keystroke \(String(format: "%.1f", textView.lastEditMilliseconds)) ms, slowest \(String(format: "%.1f", textView.slowestEditMilliseconds)) ms")
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
