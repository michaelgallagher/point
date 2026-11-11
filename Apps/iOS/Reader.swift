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

    static let sizes = 14.0...28.0

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

    /// The type for reading: the body at the chosen size, lines further apart, headings a
    /// little smaller against it than when writing.
    var typography: Typography {
        var typography = PhoneTextView.standardTypography
        typography.bodySize = size
        typography.lineHeight = 1.5
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

/// The Aa menu: text size, serif or sans, and the page's colour.
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
