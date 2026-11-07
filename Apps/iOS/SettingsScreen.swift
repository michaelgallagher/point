import EditorKit
import SwiftUI

/// Settings, from home's top right: how note text is set, where the notes are, and how many,
/// and forgetting what search has learned.
struct SettingsScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsForget = false

    var body: some View {
        NavigationStack {
            Form {
                HomeSettings()
                TypographySettings(typography: $store.typography)
                Section {
                    LabeledContent("Notes", value: "\(store.notes.count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Notes are kept in Point’s folder on this iPhone, which the Files app shows. They don’t sync yet.")
                }
                Section {
                    Button("Forget what search has learned", role: .destructive) { confirmsForget = true }
                        .disabled(store.history.isEmpty)
                } footer: {
                    Text("Search puts the notes you open and pick most first. What it learns stays on this iPhone.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .confirmationDialog("Forget what search has learned?", isPresented: $confirmsForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { store.forgetSearchHistory() }
            } message: {
                Text("Your notes aren’t changed.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// What home's panel shows.
private struct HomeSettings: View {
    @EnvironmentObject private var store: PhoneStore
    @AppStorage(HomeTile.folders.key) private var showsFolders = true
    @AppStorage(HomeTile.tags.key) private var showsTags = true
    @AppStorage(HomeTile.bookmarks.key) private var showsBookmarks = true
    @AppStorage(HomeTile.types.key) private var showsTypes = true

    var body: some View {
        Section {
            Toggle("Folders", isOn: $showsFolders)
            Toggle("Tags", isOn: $showsTags)
            Toggle("Bookmarks", isOn: $showsBookmarks)
            Toggle("Types", isOn: $showsTypes)
                .disabled(store.kinds.isEmpty)
        } header: {
            Text("Home")
        } footer: {
            Text(store.kinds.isEmpty ? "Types shows once the vault has kinds of note." : "Four show two by two.")
        }
    }
}

/// How note text is set, as on the Mac: the body's size and line height, and each heading's
/// size, weight and slant, each shown in its own style. Sizes are at the iPhone's standard text
/// size; a larger one scales them all.
private struct TypographySettings: View {
    @Binding var typography: Typography

    var body: some View {
        Section("Text") {
            Stepper(value: $typography.bodySize, in: 12...28, step: 1) {
                LabeledContent("Size", value: "\(Int(typography.bodySize)) pt")
            }
            Stepper(value: $typography.lineHeight, in: 1...2.2, step: 0.05) {
                LabeledContent("Line height", value: typography.lineHeight.formatted(.number.precision(.fractionLength(2))))
            }
            Text("The quick brown fox jumps over the lazy dog, and the line after it shows the spacing between lines of a paragraph.")
                .font(.system(size: typography.bodySize))
                .lineSpacing(typography.bodySize * (typography.lineHeight - 1))
                .foregroundStyle(.secondary)
        }
        Section("Headings") {
            ForEach(0..<6, id: \.self) { index in
                NavigationLink {
                    HeadingSettings(typography: $typography, index: index)
                } label: {
                    LabeledContent {
                        Text("\(Int(points(index).rounded())) pt")
                    } label: {
                        Text("Heading \(index + 1)")
                            .font(font(for: index))
                            .lineLimit(1)
                    }
                }
            }
        }
        Section {
            Button("Restore defaults") { typography = PhoneTextView.standardTypography }
                .disabled(typography == PhoneTextView.standardTypography)
        }
    }

    private func points(_ index: Int) -> Double { typography.headings[index].size * typography.bodySize }

    private func font(for index: Int) -> Font {
        let style = typography.headings[index]
        let font = Font.system(size: min(points(index), 30), weight: style.weight.font)
        return style.italic ? font.italic() : font
    }
}

/// One heading's size, weight and slant.
private struct HeadingSettings: View {
    @Binding var typography: Typography
    let index: Int

    var body: some View {
        let style = typography.headings[index]
        Form {
            Section {
                Text("Heading \(index + 1)")
                    .font(.system(size: min(points, 34), weight: style.weight.font))
                    .italic(style.italic)
                    .lineLimit(1)
                    .listRowBackground(Color.clear)
            }
            Section {
                Stepper(value: Binding(get: { points }, set: { setPoints($0) }), in: 8...60, step: 1) {
                    LabeledContent("Size", value: "\(Int(points.rounded())) pt")
                }
                Picker("Weight", selection: $typography.headings[index].weight) {
                    ForEach(Typography.Weight.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Toggle("Italic", isOn: $typography.headings[index].italic)
            }
        }
        .navigationTitle("Heading \(index + 1)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Its size in points, at the body size chosen.
    private var points: Double { typography.headings[index].size * typography.bodySize }

    private func setPoints(_ points: Double) {
        typography.headings[index].size = min(max(points.rounded(), 8), 60) / typography.bodySize
    }
}

private extension Typography.Weight {
    var font: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}
