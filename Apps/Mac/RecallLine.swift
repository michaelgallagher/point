import AppKit
import IndexKit
import SwiftUI
import VaultKit

/// Under a note's properties, what came before it: "4 earlier meetings · last on 21 October",
/// for a note with a type, people and a day. Clicking it lists them, newest first, each with who
/// was in it and its first line; clicking one opens it (⌘-click: in a new tab). Nothing while
/// there are none, or while the index is still being asked.
struct RecallLine: View {
    @ObservedObject var model: VaultModel
    let recall: Recall
    let paneID: VaultModel.NotePane.ID
    @State private var isShowingList = false
    /// The newest one's day, from its `date:` (else its name).
    @State private var lastDay: String?

    var body: some View {
        if let ids = model.store.noteIDs(matching: recall.query), let newest = ids.first {
            Button { isShowingList.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: PropertiesStrip.chevronWidth)
                    Text(Recall.summary(count: ids.count, type: recall.type, lastDay: lastDay))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the earlier \(recall.type.lowercased())s with \(ListFormatter.localizedString(byJoining: recall.people))")
            .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
                RecallList(model: model, recall: recall, ids: ids, paneID: paneID) { isShowingList = false }
            }
            .task(id: newest) {
                let dates = await model.store.propertyValues(["date"], of: [newest])
                lastDay = dates[newest]?["date"]?.lazy.compactMap(Recall.day).first
                    ?? model.note(newest).flatMap { Recall.day($0.name) }
            }
        }
    }
}

/// The earlier notes, newest first: each one's day and who of this note's people were in it,
/// its title, and its first line.
private struct RecallList: View {
    @ObservedObject var model: VaultModel
    let recall: Recall
    let ids: [Note.ID]
    let paneID: VaultModel.NotePane.ID
    let close: () -> Void
    @State private var days: [Note.ID: String] = [:]
    @State private var people: [Note.ID: [String]] = [:]
    @State private var lines: [Note.ID: String] = [:]

    /// How many are read at once for their details, and listed; more are rarely wanted.
    private static let shown = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("With \(ListFormatter.localizedString(byJoining: recall.people))")
                .font(.headline)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ids.prefix(Self.shown), id: \.self) { id in
                        row(id)
                    }
                    if ids.count > Self.shown {
                        Text("And \((ids.count - Self.shown).formatted()) more")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: ids.count < 6)
        .task {
            let shown = Array(ids.prefix(Self.shown))
            let keys = ["date"] + recall.personPropertyNames
            let values = await model.store.propertyValues(keys, of: shown)
            let wanted = Set(recall.people.map { $0.lowercased() })
            for id in shown {
                let row = values[id] ?? [:]
                days[id] = row["date"]?.lazy.compactMap(Recall.day).first ?? model.note(id).flatMap { Recall.day($0.name) }
                people[id] = recall.personPropertyNames.flatMap { row[$0.lowercased()] ?? [] }
                    .compactMap(Recall.personName).filter { wanted.contains($0.lowercased()) }
            }
            lines = await model.store.firstLines(of: shown)
        }
    }

    private func row(_ id: Note.ID) -> some View {
        Button {
            let newTab = NSEvent.modifierFlags.contains(.command)
            close()
            model.open(id, inPane: paneID, as: newTab ? .newTab : .here)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.note(id)?.title ?? id)
                    .lineLimit(1)
                let detail = [days[id].map { Recall.shown(day: $0) }, people[id].flatMap { $0.isEmpty ? nil : ListFormatter.localizedString(byJoining: $0) }]
                    .compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let line = lines[id] {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(RecallRowStyle())
        .help("Open “\(model.note(id)?.title ?? id)” (⌘-click: in a new tab)")
    }
}

/// A row that highlights under the pointer, as a menu's would.
private struct RecallRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.06 : 0))
                .padding(.horizontal, 6))
            .onHover { isHovered = $0 }
    }
}
