import IndexKit
import SwiftUI
import VaultKit

/// What links to a note, and where it's mentioned without a link, kept up to date.
@MainActor
final class Connections: ObservableObject {
    @Published private(set) var backlinks: [Backlink] = []
    @Published private(set) var mentions: [Mention] = []
    private let note: Note
    private weak var model: VaultModel?
    private var refreshTask: Task<Void, Never>?

    init(note: Note, model: VaultModel) {
        self.note = note
        self.model = model
        NotificationCenter.default.addObserver(self, selector: #selector(vaultChanged), name: .pointFilesChanged, object: nil)
    }

    @objc private func vaultChanged() {
        // The index updates after the rescan; give it a moment.
        refresh(after: 1.5)
    }

    func refresh(after delay: Double = 0) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, let model = self.model, let index = model.index, !Task.isCancelled else { return }
            let notes = model.notes
            let note = self.note
            let backlinks = (try? await index.backlinks(to: note, notes: notes)) ?? []
            let mentions = (try? await index.unlinkedMentions(of: note, notes: notes)) ?? []
            guard !Task.isCancelled else { return }
            self.backlinks = backlinks
            self.mentions = mentions
        }
    }

    /// Turns a mention in another note into a link to this one.
    func link(_ mention: Mention) {
        guard let source = model?.notes.first(where: { $0.id == mention.noteID }),
              let text = try? NoteReader.read(contentsOf: source.url),
              let linked = mention.linking(in: text, to: note.title),
              case .saved? = try? NoteWriter.write(linked, to: source.url, expecting: text, ifChanged: .report) else {
            NSSound.beep()
            return refresh()
        }
        mentions.removeAll { $0.id == mention.id }
        refresh(after: 1.5)
    }
}

/// The bar under a note: links to it, and unlinked mentions to turn into links.
struct ConnectionsBar: View {
    @ObservedObject var connections: Connections
    @EnvironmentObject private var model: VaultModel
    @AppStorage("connectionsExpanded") private var isExpanded = false

    var body: some View {
        if !connections.backlinks.isEmpty || !connections.mentions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(summary)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if isExpanded {
                    ScrollView {
                        // Lazy, so a note with many connections doesn't draw them all at once.
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if !connections.backlinks.isEmpty {
                                section("Links to this note")
                                ForEach(connections.backlinks) { backlink in
                                    ConnectionRow(title: backlink.title, context: backlink.context) {
                                        model.selection = backlink.noteID
                                    }
                                }
                            }
                            if !connections.mentions.isEmpty {
                                section("Unlinked mentions")
                                ForEach(connections.mentions) { mention in
                                    ConnectionRow(title: mention.title, context: mention.context, onOpen: {
                                        model.selection = mention.noteID
                                    }, onLink: { connections.link(mention) })
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                    .frame(maxHeight: 220)
                }
            }
            .font(.callout)
            .background(.bar)
        }
    }

    private var summary: String {
        var parts: [String] = []
        let links = connections.backlinks.count
        if links > 0 { parts.append("\(links) \(links == 1 ? "link" : "links") here") }
        let mentions = connections.mentions.count
        if mentions > 0 {
            // The index stops at 50; say so rather than implying that's all.
            let count = mentions >= 50 ? "50+" : "\(mentions)"
            parts.append("\(count) unlinked \(mentions == 1 ? "mention" : "mentions")")
        }
        return parts.joined(separator: " · ")
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
    }
}

private struct ConnectionRow: View {
    let title: String
    let context: String
    let onOpen: () -> Void
    var onLink: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(context)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onLink {
                Button("Link", action: onLink)
                    .controlSize(.small)
                    .help("Turn this mention into a link")
            }
        }
        .padding(.vertical, 3)
    }
}
