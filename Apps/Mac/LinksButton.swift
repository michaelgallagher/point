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

    /// Opens a note linking here, at its first link to this note.
    func open(_ backlink: Backlink) {
        guard let model else { return }
        let source = model.notes.first { $0.id == backlink.noteID }
        let text = source.flatMap { try? NoteReader.read(contentsOf: $0.url) } as NSString?
        let found = text?.range(of: "[[" + note.title, options: .caseInsensitive) ?? NSRange(location: NSNotFound, length: 0)
        if found.location != NSNotFound {
            model.open(backlink.noteID, revealing: found)
        } else {
            model.selection = backlink.noteID
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

/// Floating over the bottom of a note: a glass button saying how many notes link to it or
/// mention it ("3 links"), which grows into a panel listing them, inside the note (never past
/// the window's edges, as a popover went): links first, then unlinked mentions, each with
/// its line, opening its note at that place, and mentions with a button to turn them into
/// links. (It was a bar along the bottom of the note.)
struct LinksButton: View {
    @ObservedObject var connections: Connections
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @State private var isExpanded = false
    @Namespace private var glass

    /// How far it sits in from the note's bottom and right edges, and how much room the note
    /// leaves below its text for it.
    static let inset: CGFloat = 14
    static let roomBelowText: CGFloat = 36 + inset * 2
    private static let panelWidth: CGFloat = 380
    private static let corner: CGFloat = 18

    var body: some View {
        let count = connections.backlinks.count + connections.mentions.count
        if count > 0 {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    if isExpanded {
                        // A click anywhere else on the note closes it.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                    content(count: count, in: geometry.size)
                        .padding(Self.inset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            #if DEBUG
            // `-PointShowLinks YES`: opens the panel by itself, for checking it.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "PointShowLinks") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { open() }
                }
            }
            #endif
        }
    }

    private func open() { withAnimation(.spring(duration: 0.3, bounce: 0.15)) { isExpanded = true } }
    private func close() { withAnimation(.spring(duration: 0.25, bounce: 0)) { isExpanded = false } }

    @ViewBuilder private func content(count: Int, in size: CGSize) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                if isExpanded {
                    panel(count: count, in: size)
                        .glassEffect(.regular, in: .rect(cornerRadius: Self.corner))
                        .glassEffectID("links", in: glass)
                } else {
                    button(count: count)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("links", in: glass)
                }
            }
        } else if isExpanded {
            panel(count: count, in: size)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .transition(.scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
        } else {
            button(count: count)
                .background(.regularMaterial, in: Capsule())
                .transition(.opacity)
        }
    }

    /// "3 links": the index stops at 50 mentions, so past that, "52+ links".
    private func label(count: Int) -> String {
        let number = connections.mentions.count >= 50 ? "\(connections.backlinks.count + 50)+" : "\(count)"
        return "\(number) \(count == 1 ? "link" : "links")"
    }

    private func button(count: Int) -> some View {
        Button(action: open) {
            Text(label(count: count))
                .font(.callout)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
        .help("Links to this note, and mentions of it")
    }

    /// As wide as it can be up to 380 points, and as tall as its rows, up to the room between
    /// the top bar and the bottom of the note; then it scrolls.
    private func panel(count: Int, in size: CGSize) -> some View {
        let width = min(Self.panelWidth, size.width - Self.inset * 2)
        let maxHeight = max(120, size.height - topBarCover - Self.inset * 2)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label(count: count))
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .withoutFocusRing()
                .keyboardShortcut(.cancelAction) // Escape
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !connections.backlinks.isEmpty {
                section("Links to this note")
                ForEach(connections.backlinks) { backlink in
                    ConnectionRow(title: backlink.title, context: backlink.context) {
                        close()
                        connections.open(backlink)
                    }
                }
            }
            if !connections.mentions.isEmpty {
                section("Unlinked mentions")
                ForEach(connections.mentions) { mention in
                    ConnectionRow(title: mention.title, context: mention.context, onOpen: {
                        close()
                        model.open(mention.noteID, revealing: mention.range)
                    }, onLink: { connections.link(mention) })
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct ConnectionRow: View {
    let title: String
    let context: String
    let onOpen: () -> Void
    var onLink: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(context)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .withoutFocusRing() // No ring on the first row as the panel opens.
            if let onLink {
                Button("Link", action: onLink)
                    .controlSize(.small)
                    .withoutFocusRing()
                    .help("Turn this mention into a link")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? TopBar.selectedTabColor : .clear))
        .onHover { isHovering = $0 }
        .font(.callout)
    }
}

private extension View {
    /// No focus ring, from macOS 14 (before that, buttons in a panel like this don't show one).
    @ViewBuilder func withoutFocusRing() -> some View {
        if #available(macOS 14, *) { focusEffectDisabled() } else { self }
    }
}
