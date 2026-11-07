import AppKit
import IndexKit
import SwiftUI
import VaultKit

/// Under a note's properties, what came before it (see `Recall`): "4 earlier meetings · last on
/// 21 October", or "23 notes on Org design". Clicking it lists them, newest first (by topics,
/// in groups by type, the note's own first), each with who or what it shares and its first
/// line; clicking one opens it (⌘-click: in a new tab). Nothing while there are none, or while
/// the index is still being asked.
struct RecallLine: View {
    @ObservedObject var model: VaultModel
    let recall: Recall
    let noteID: Note.ID
    let paneID: VaultModel.NotePane.ID
    @State private var isShowingList = false
    /// The newest one's day, from its `date:` (else its name).
    @State private var lastDay: String?

    var body: some View {
        if let ids = model.store.noteIDs(matching: recall.query)?.filter({ $0 != noteID }), let newest = ids.first {
            Button { isShowingList.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: recall.basis == .topics ? "rectangle.stack" : "clock.arrow.circlepath")
                        .frame(width: PropertiesStrip.chevronWidth)
                    Text(recall.summary(count: ids.count, lastDay: lastDay))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("List them")
            .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
                RecallList(model: model, recall: recall, ids: ids, paneID: paneID) { isShowingList = false }
            }
            .task(id: newest) {
                guard recall.basis == .people else { return lastDay = nil }
                let dates = await model.store.propertyValues(["date"], of: [newest])
                lastDay = dates[newest]?["date"]?.lazy.compactMap(Recall.day).first
                    ?? model.note(newest).flatMap { Recall.day($0.name) }
            }
        }
    }
}

/// The notes, newest first: by topics, in groups by type, the note's own type first, then the
/// biggest. Each has its day and who or what it shares with this note, its title, and its first
/// line.
private struct RecallList: View {
    @ObservedObject var model: VaultModel
    let recall: Recall
    let ids: [Note.ID]
    let paneID: VaultModel.NotePane.ID
    let close: () -> Void
    @State private var details = RecallDetails()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(recall.heading)
                .font(.headline)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(details.groups(of: ids, recall: recall), id: \.title) { group in
                        if !group.title.isEmpty {
                            Text("\(group.title) · \(group.ids.count.formatted())")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.ids, id: \.self) { id in
                            row(id)
                        }
                    }
                    if ids.count > RecallDetails.shown {
                        Text("And \((ids.count - RecallDetails.shown).formatted()) more")
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
            let shown = Array(ids.prefix(RecallDetails.shown))
            let values = await model.store.propertyValues(RecallDetails.keys(for: recall, typeProperty: model.store.kinds.property), of: shown)
            details.take(values, for: shown, recall: recall, typeProperty: model.store.kinds.property) { model.note($0)?.name }
            details.lines = await model.store.firstLines(of: shown)
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
                if let detail = details.detail(id) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let line = details.lines[id] {
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
