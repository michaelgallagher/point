import ClipKit
import EditorKit
import SwiftUI
import VaultKit

/// How notes are set for reading (see plan/reader-mode.md): chosen in the Aa menu, kept on the
/// phone, the same for every note.
struct ReaderSettings: Codable, Equatable {
    /// The body's size in points, at the phone's standard text size.
    var size: Double = 19
    var isSerif = true
    var page: Page = .system
    /// The space a line takes, as a multiple of the type's size.
    var lineHeight: Double = 1.4
    /// The space either side of the text, in points.
    var margin: Double = 24

    static let sizes = 14.0...28.0
    static let lineHeights = 1.2...1.8
    static let margins = 12.0...48.0

    init() {}

    /// Settings kept before line height and margins came in still read, with those as standard.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? size
        isSerif = try values.decodeIfPresent(Bool.self, forKey: .isSerif) ?? isSerif
        page = try values.decodeIfPresent(Page.self, forKey: .page) ?? page
        lineHeight = try values.decodeIfPresent(Double.self, forKey: .lineHeight) ?? lineHeight
        margin = try values.decodeIfPresent(Double.self, forKey: .margin) ?? margin
    }

    enum Page: String, Codable, CaseIterable, Identifiable {
        case system, paper, sepia, night

        var id: String { rawValue }
        var name: String {
            switch self {
            case .system: "Automatic"
            case .paper: "Paper"
            case .sepia: "Sepia"
            case .night: "Night"
            }
        }

        /// The page's colour; the system's own for Automatic.
        var background: UIColor {
            switch self {
            case .system: .systemBackground
            case .paper: UIColor(red: 0.988, green: 0.980, blue: 0.965, alpha: 1)
            case .sepia: UIColor(red: 0.957, green: 0.925, blue: 0.851, alpha: 1)
            case .night: UIColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
            }
        }

        /// Light or dark text on it, whatever the phone's set to; Automatic follows the phone.
        var style: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .paper, .sepia: .light
            case .night: .dark
            }
        }
    }

    /// The type for reading: the body at the chosen size, lines as far apart as chosen,
    /// headings a little smaller against it than when writing.
    var typography: Typography {
        var typography = PhoneTextView.standardTypography
        typography.bodySize = size
        typography.lineHeight = lineHeight
        typography.headings[0].size = 1.3
        typography.headings[1].size = 1.15
        return typography
    }
}

/// Where the reader was in each note, kept on the phone (outside the vault), by note.
/// Not synced between devices: each has its own.
@MainActor
final class ReadingPlaces {
    private let file: URL
    private var places: [String: Reading.Place]
    /// The most kept; the oldest go first.
    private static let limit = 500
    private var order: [String]

    init(file: URL) {
        self.file = file
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        places = saved?.places ?? [:]
        order = saved?.order.filter { saved?.places[$0] != nil } ?? []
    }

    private struct Saved: Codable {
        var places: [String: Reading.Place]
        var order: [String]
    }

    func place(for id: Note.ID) -> Reading.Place? { places[id] }

    func keep(_ place: Reading.Place, for id: Note.ID) {
        guard places[id] != place else { return }
        places[id] = place
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > Self.limit { places[order.removeFirst()] = nil }
        save()
    }

    /// A note renamed or moved: its place follows it.
    func renamed(from id: Note.ID, to newID: Note.ID) {
        guard id != newID, let place = places.removeValue(forKey: id) else { return }
        places[newID] = place
        order = order.map { $0 == id ? newID : $0 }
        save()
    }

    /// Notes that are gone take their places with them.
    func keepOnly(_ ids: Set<Note.ID>) {
        let kept = places.filter { ids.contains($0.key) }
        guard kept.count != places.count else { return }
        places = kept
        order = order.filter { kept[$0] != nil }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(places: places, order: order)).write(to: file, options: .atomic)
    }
}

/// The Aa menu: text size, serif or sans, line spacing, margins, and the page's colour.
struct ReaderControls: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                Button("Smaller", systemImage: "textformat.size.smaller") { settings.size -= 1 }
                    .disabled(settings.size <= ReaderSettings.sizes.lowerBound)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 24)
                Button("Larger", systemImage: "textformat.size.larger") { settings.size += 1 }
                    .disabled(settings.size >= ReaderSettings.sizes.upperBound)
                    .frame(maxWidth: .infinity)
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            Picker("Font", selection: $settings.isSerif) {
                Text("Serif").font(.system(.body, design: .serif)).tag(true)
                Text("Sans").tag(false)
            }
            .pickerStyle(.segmented)
            VStack(spacing: 10) {
                stepper("Line spacing", value: $settings.lineHeight, by: 0.1, in: ReaderSettings.lineHeights)
                stepper("Margins", value: $settings.margin, by: 6, in: ReaderSettings.margins)
            }
            HStack(spacing: 14) {
                ForEach(ReaderSettings.Page.allCases) { page in
                    Button {
                        settings.page = page
                    } label: {
                        swatch(page)
                    }
                    .accessibilityLabel(page.name)
                    .accessibilityAddTraits(settings.page == page ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(width: 290)
        // Light or dark as the page is.
        .preferredColorScheme(settings.page.style == .dark ? .dark : settings.page.style == .light ? .light : nil)
        .presentationCompactAdaptation(.popover)
    }

    /// A setting stepped up and down, by `step`, within `range`.
    private func stepper(_ title: String, value: Binding<Double>, by step: Double, in range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                Button("Less", systemImage: "minus") {
                    value.wrappedValue = max(range.lowerBound, ((value.wrappedValue - step) * 100).rounded() / 100)
                }
                .disabled(value.wrappedValue <= range.lowerBound + 0.001)
                .frame(width: 44, height: 32)
                Divider().frame(height: 18)
                Button("More", systemImage: "plus") {
                    value.wrappedValue = min(range.upperBound, ((value.wrappedValue + step) * 100).rounded() / 100)
                }
                .disabled(value.wrappedValue >= range.upperBound - 0.001)
                .frame(width: 44, height: 32)
            }
            .labelStyle(.iconOnly)
            .background(Color.secondary.opacity(0.12), in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    /// A page colour as a circle, ringed when chosen; Automatic half light, half dark.
    private func swatch(_ page: ReaderSettings.Page) -> some View {
        let chosen = settings.page == page
        return ZStack {
            if page == .system {
                Circle().fill(Color.white)
                Circle().trim(from: 0.25, to: 0.75).fill(Color.black).rotationEffect(.degrees(-90))
            } else {
                Circle().fill(Color(uiColor: page.background))
            }
            Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
        }
        .frame(width: 40, height: 40)
        .padding(3)
        .overlay(Circle().strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
    }
}

/// In the bar while reading: how far through, and how long is left.
struct ReadingProgress: View {
    let progress: Double
    let minutesLeft: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(minutesLeft == 0 ? "Finished" : "\(minutesLeft) min left")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(progress, 0), 1))
                .frame(width: 110)
                .tint(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Your notes on a clip, in a sheet: only what's between its properties and the marker, in the
/// usual editor. Half height to start, so the article stays readable (and scrolls) behind it.
struct NotesSheet: View {
    @ObservedObject var session: NoteSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NotesEditor(text: session.notesToEdit, session: session)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle("Your notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HighlightsMenu(session: session) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// The article's highlights, in order: choosing one closes the sheet and goes to it.
private struct HighlightsMenu: View {
    @ObservedObject var session: NoteSession
    let close: () -> Void

    var body: some View {
        let highlights = session.highlights
        Menu("Highlights", systemImage: "highlighter") {
            if highlights.isEmpty {
                Text("No highlights yet. Select text in the article, then choose Highlight.")
            }
            ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                Button(Self.shortened(highlight.text)) {
                    close()
                    // Once the sheet's out of the way.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { session.go(to: highlight.range) }
                }
            }
        }
    }

    /// The highlight's words, Markdown left out, short enough for a menu.
    static func shortened(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression)
        return plain.count > 80 ? String(plain.prefix(80)).trimmingCharacters(in: .whitespaces) + "…" : plain
    }
}

/// The editor in the notes sheet, with the format bar, the cursor at the end.
private struct NotesEditor: UIViewRepresentable {
    let text: String
    let session: NoteSession

    func makeUIView(context: Context) -> PhoneTextView {
        let textView = PhoneTextView()
        textView.accessibilityLabel = "Your notes"
        textView.typography = session.store.typography
        let bar = FormatBar(textView: textView)
        bar.linkText = { [weak session] in session?.store.linkText(forTitle: $0) ?? $0 }
        textView.inputAccessoryView = bar
        textView.onCompletionChange = { [weak bar, weak session] completion in
            bar?.show(completion, choices: completion.flatMap { session?.choices(for: $0) } ?? [])
        }
        textView.onTextChange = { [weak session] in session?.notesChanged($0) }
        textView.onOpenLink = { [weak session] in session?.open($0) }
        textView.load(text)
        session.notesView = textView
        DispatchQueue.main.async {
            textView.placeCursor(at: (textView.text as NSString).length)
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: PhoneTextView, context: Context) {}
}
