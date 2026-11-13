import SwiftUI
import VaultKit

/// The note as it was before it changed here, newest first: each says when, and the first
/// line where it differs from the note now, to find the one wanted; opened, the whole of it,
/// to put back.
struct VersionsSheet: View {
    @ObservedObject var session: NoteSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let versions = session.earlierVersions
        let now = session.currentText ?? ""
        NavigationStack {
            List(versions) { version in
                NavigationLink {
                    VersionView(version: version) {
                        session.restore(version)
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.when(version.kept))
                        Text(Self.difference(of: version.text, from: now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .overlay {
                if versions.isEmpty {
                    ContentUnavailableView("No earlier versions", systemImage: "clock.arrow.circlepath",
                                           description: Text("A note is kept as it was each time you start changing it here."))
                }
            }
            .navigationTitle("Earlier versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "Today at 10:43", "Wednesday at 09:12", "02/11/2026 at 18:30".
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today" : HomeScreen.label(for: date)
        return "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// The version's first line that isn't the note's now, as it'd come back; or what's
    /// missing from its end.
    static func difference(of version: String, from now: String) -> String {
        let old = version.components(separatedBy: "\n"), new = now.components(separatedBy: "\n")
        for (index, line) in old.enumerated() where index >= new.count || new[index] != line {
            let shown = line.trimmingCharacters(in: .whitespaces)
            return shown.isEmpty ? "A blank line" : shown
        }
        return old.count < new.count ? "Shorter: ends before what was added" : "The same as now"
    }
}

/// One earlier version, whole, with Restore.
private struct VersionView: View {
    let version: NoteVersions.Version
    let restore: () -> Void

    var body: some View {
        ScrollView {
            Text(version.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(VersionsSheet.when(version.kept))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore", action: restore)
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
            }
        }
    }
}
