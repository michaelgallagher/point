import IndexKit
import SwiftUI
import VaultKit

/// A note's related notes, as the Mac's panel lists them (links and recall made one): first the
/// notes sharing its topics or people, all of them first, then fewer, newest first in each; then
/// the notes linking to it, grouped by what they are to it (articles by this person, meetings
/// with them…). Type chips at the top narrow both. Each group folds. It opens half way, with the
/// note above still scrolling, and goes up to the whole screen.
struct RelatedSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var folded: Set<String> = []

    var body: some View {
        let related = session.related
        NavigationStack {
            List {
                ForEach(related.tiers) { tier in
                    tierSection(tier, related: related)
                }
                ForEach(related.links.groups) { group in
                    linkSection(group)
                }
            }
            .listStyle(.sidebar)
            // The type chips under the title, staying as the list scrolls.
            .safeAreaInset(edge: .top, spacing: 0) {
                if !related.types.isEmpty {
                    TypeChips(types: related.types, selection: $session.relatedType)
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("Related notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .overlay {
                if session.relatedIsLoaded, related.isEmpty {
                    ContentUnavailableView("Nothing related", systemImage: "link")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// The notes sharing as many of this note's topics or people.
    private func tierSection(_ tier: RelatedNotes.Tier, related: RelatedNotes) -> some View {
        let key = "shared \(tier.sharedCount)"
        // Which of them, unless it's all or there's only one.
        let showsNames = tier.sharedCount < (related.recall?.names.count ?? 0)
        let isLast = tier.id == related.tiers.last?.id
        return Section(isExpanded: expanded(key)) {
            ForEach(tier.notes) { (shared: RelatedNotes.Shared) in
                Button { session.openRelated(shared.noteID) } label: {
                    RelatedRow(title: shared.title, type: session.relatedType == nil ? shared.type : nil, date: shared.date,
                               context: showsNames ? shared.names.joined(separator: " · ") : nil)
                }
            }
            // A folding section has no footer.
            if isLast, related.sharedBeyondLimit > 0 {
                Text("And \(related.sharedBeyondLimit.formatted()) more, sharing less")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            heading(tier.heading, count: tier.notes.count)
        }
    }

    /// The notes linking here that are one thing to it (by, about, with…).
    private func linkSection(_ group: LinkGroups.Group) -> some View {
        let key = "links \(group.relation.label)"
        let title = Self.capitalized(RelatedNotes.phrase(for: group, ownType: session.ownType))
        return Section(isExpanded: expanded(key)) {
            ForEach(group.backlinks) { (backlink: Backlink) in
                Button { session.open(backlink) } label: {
                    RelatedRow(title: backlink.title, type: session.relatedType == nil ? backlink.type : nil, date: backlink.date,
                               context: group.relation == .mentioned ? backlink.context : nil)
                }
            }
        } header: {
            heading(title, count: group.backlinks.count)
        }
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    private func expanded(_ key: String) -> Binding<Bool> {
        Binding(get: { !folded.contains(key) }, set: { isOpen in
            if isOpen { folded.remove(key) } else { folded.insert(key) }
        })
    }

    /// A group's heading, bold and in the text colour, with how many it holds. (The list's own
    /// chevron, beside it, folds it.)
    private func heading(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // In the text colour, not the list's grey for headings (decided for the Mac's panel).
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
            Text(count.formatted())
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

/// One related note: its title, then its type and date, then what it shares or the line its
/// link is on.
private struct RelatedRow: View {
    let title: String
    var type: String?
    var date: Date?
    var context: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(2)
            let details = [type, date.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) }].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let context, !context.isEmpty {
                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
}

/// The types among the related notes, with how many of each, to narrow them to one: All first,
/// in a line that scrolls sideways.
private struct TypeChips: View {
    let types: [(type: String, count: Int)]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", count: nil, isOn: selection == nil) { selection = nil }
                ForEach(types, id: \.type) { item in
                    let isOn = selection?.caseInsensitiveCompare(item.type) == .orderedSame
                    chip(item.type, count: item.count, isOn: isOn) { selection = isOn ? nil : item.type }
                }
            }
            .padding(.trailing, 16)
        }
    }

    private func chip(_ title: String, count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(isOn ? .primary : .secondary) }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
