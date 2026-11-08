import IndexKit
import SwiftUI
import VaultKit

/// What links to a note, and where it's mentioned without a link, kept up to date.
@MainActor
final class Connections: ObservableObject {
    @Published private(set) var backlinks: [Backlink] = []
    @Published private(set) var mentions: [Mention] = []
    /// The type the links are narrowed to, if any.
    @Published var type: String?
    /// The links grouped by what they are to this note (by, about, with, mentioned).
    var groups: LinkGroups { LinkGroups(backlinks, type: type) }
    /// Links and unlinked mentions together.
    var count: Int { backlinks.count + mentions.count }
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
            let backlinks = (try? await index.backlinks(to: note, notes: notes, typeProperty: model.store.kinds.property)) ?? []
            let mentions = (try? await index.unlinkedMentions(of: note, notes: notes)) ?? []
            guard !Task.isCancelled else { return }
            self.backlinks = backlinks
            self.mentions = mentions
            if let type = self.type, !backlinks.contains(where: { $0.type?.caseInsensitiveCompare(type) == .orderedSame }) { self.type = nil }
        }
    }

    /// Opens a note linking here, at its first link to this note.
    func open(_ backlink: Backlink) {
        guard let model else { return }
        if backlink.range.location != NSNotFound {
            model.open(backlink.noteID, revealing: backlink.range)
        } else {
            model.selection = backlink.noteID
        }
    }

    /// Turns a mention in another note into a link to this one.
    func link(_ mention: Mention) {
        guard let source = model?.notes.first(where: { $0.id == mention.noteID }),
              let text = try? NoteReader.read(contentsOf: source.url),
              let linked = mention.linking(in: text, to: note.title),
              case .saved? = try? NoteWriter.write(linked, to: source.url, expecting: text, ifChanged: .report, keepingDate: true) else {
            NSSound.beep()
            return refresh()
        }
        mentions.removeAll { $0.id == mention.id }
        refresh(after: 1.5)
    }
}


extension Connections {
    /// "3 links": the index stops at 50 mentions, so past that, "52+ links".
    var label: String {
        let number = mentions.count >= 50 ? "\(backlinks.count + 50)+" : "\(count)"
        return "\(number) \(count == 1 ? "link" : "links")"
    }

    /// "By 8 · With 28 · Mentioned 13": the groups, for the strip along the bottom.
    var summary: String {
        (LinkGroups(backlinks).groups.map { "\($0.relation.label) \($0.backlinks.count)" }
            + (mentions.isEmpty ? [] : ["Not linked \(mentions.count >= 50 ? "50+" : "\(mentions.count)")"]))
            .joined(separator: " · ")
    }
}

/// Where the links to a note show, chosen in Settings › Notes.
enum LinksPlacement: String, CaseIterable, Identifiable {
    /// A button at the note's bottom right, opening a panel at its right that pushes the note
    /// over, as the sidebar does on the left.
    case side
    /// A strip along the note's bottom, growing upward over it.
    case bottom
    var id: Self { self }
    var title: String {
        switch self {
        case .side: "Panel at the side"
        case .bottom: "Strip at the bottom"
        }
    }
    static let key = "linksPlacement"
    /// Whether the side panel is open, in every window, until closed.
    static let sidePanelKey = "showsLinksPanel"
}

/// The notes linking to a note, grouped by what they are to it: by them (`author`), about it
/// (`topics`), any other property, with them (`people`), and mentioned in the text; newest
/// first in each. Above them, the types among them to narrow them to; below, mentions that
/// aren't links yet. A person's articles needn't be found among the meetings they were in.
struct LinksList: View {
    @ObservedObject var connections: Connections
    @EnvironmentObject private var model: VaultModel
    /// Called before a note opens: an overlay closes.
    var onOpen: () -> Void = {}
    @State private var folded: Set<LinkRelation> = []
    @State private var mentionsFolded = false

    var body: some View {
        let groups = connections.groups
        VStack(alignment: .leading, spacing: 1) {
            if !groups.types.isEmpty {
                TypeChips(types: groups.types, selection: $connections.type)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            ForEach(groups.groups) { group in
                heading(group.relation.label, count: group.backlinks.count, isFolded: folded.contains(group.relation)) {
                    if folded.contains(group.relation) { folded.remove(group.relation) } else { folded.insert(group.relation) }
                }
                if !folded.contains(group.relation) {
                    ForEach(group.backlinks) { backlink in
                        ConnectionRow(title: backlink.title, type: connections.type == nil ? backlink.type : nil, date: backlink.date,
                                      context: group.relation == .mentioned ? backlink.context : nil) {
                            onOpen()
                            connections.open(backlink)
                        }
                    }
                }
            }
            if connections.type == nil, !connections.mentions.isEmpty {
                heading("Not linked", count: connections.mentions.count, isFolded: mentionsFolded) { mentionsFolded.toggle() }
                if !mentionsFolded {
                    ForEach(connections.mentions) { mention in
                        ConnectionRow(title: mention.title, context: mention.context, onOpen: {
                            onOpen()
                            model.open(mention.noteID, revealing: mention.range)
                        }, onLink: { connections.link(mention) })
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    /// A group's heading, folding it on a click.
    private func heading(_ title: String, count: Int, isFolded: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isFolded ? 0 : 90))
                    .frame(width: 10)
                Text(title).fontWeight(.semibold)
                Text("\(count)").monospacedDigit()
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
    }
}

/// The types among a note's links, with how many of each, to narrow the links to one; All
/// first. They wrap onto as many lines as they need.
private struct TypeChips: View {
    let types: [(type: String, count: Int)]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: 5) {
            chip("All", count: nil, isOn: selection == nil) { selection = nil }
            ForEach(types, id: \.type) { item in
                chip(item.type, count: item.count, isOn: selection?.caseInsensitiveCompare(item.type) == .orderedSame) {
                    selection = selection?.caseInsensitiveCompare(item.type) == .orderedSame ? nil : item.type
                }
            }
        }
    }

    private func chip(_ title: String, count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(isOn ? .primary : .secondary) }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
    }
}

/// Lays its views out in rows, wrapping to the next row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = rows.last.flatMap { row in row.map { $0.y + $0.size.height }.max() } ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(width: bounds.width, subviews: subviews) {
            for item in row {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y), proposal: ProposedViewSize(item.size))
            }
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[(index: Int, x: CGFloat, y: CGFloat, size: CGSize)]] {
        var rows: [[(index: Int, x: CGFloat, y: CGFloat, size: CGSize)]] = [[]]
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                rows.append([])
            }
            rows[rows.count - 1].append((index, x, y, size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}

/// With the links at the side: a glass button at the note's bottom right saying how many
/// ("3 links"), opening the panel. Hidden while the panel is open.
struct LinksButton: View {
    @ObservedObject var connections: Connections
    @AppStorage(LinksPlacement.sidePanelKey) private var isPanelOpen = false

    /// How far it sits in from the note's bottom and right edges, and how much room the note
    /// leaves below its text for it.
    static let inset: CGFloat = 14
    static let roomBelowText: CGFloat = 36 + inset * 2

    var body: some View {
        if connections.count > 0, !isPanelOpen {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0)) { isPanelOpen = true }
            } label: {
                Text(connections.label)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .withoutFocusRing()
            .help("Links to this note, and mentions of it")
            .modifier(LinksGlass(shape: Capsule(), isInteractive: true))
            .padding(Self.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "PointShowLinks") { isPanelOpen = true }
            }
            #endif
        }
    }
}

/// With the links at the side: the panel at the note's right, pushing it over. Stays open
/// from note to note until closed.
struct LinksSidePanel: View {
    @ObservedObject var connections: Connections
    @Environment(\.topBarCover) private var topBarCover
    @AppStorage(LinksPlacement.sidePanelKey) private var isPanelOpen = false
    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinksHeader(title: connections.label) {
                withAnimation(.spring(duration: 0.3, bounce: 0)) { isPanelOpen = false }
            }
            ScrollView { LinksList(connections: connections) }
        }
        .padding(.top, topBarCover)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

/// With the links at the bottom: a strip along the note's bottom saying how many and of
/// what ("12 links · By 3 · With 8 · Mentioned 1"), growing upward over the note into the
/// list, up to most of its height. A click elsewhere on the note, or Escape, closes it.
struct LinksStrip: View {
    @ObservedObject var connections: Connections
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @State private var isExpanded = false
    @Namespace private var glass
    private static let corner: CGFloat = 18

    var body: some View {
        if connections.count > 0 {
            GeometryReader { geometry in
                let width = min(geometry.size.width - LinksButton.inset * 2, model.store.textColumnWidth + 80)
                ZStack(alignment: .bottom) {
                    if isExpanded {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                    Group {
                        if isExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                LinksHeader(title: connections.label, close: close)
                                ViewThatFits(in: .vertical) {
                                    LinksList(connections: connections, onOpen: close)
                                    ScrollView { LinksList(connections: connections, onOpen: close) }
                                }
                            }
                            .frame(maxHeight: max(160, (geometry.size.height - topBarCover) * 0.7), alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .modifier(LinksGlass(shape: RoundedRectangle(cornerRadius: Self.corner, style: .continuous), isInteractive: false))
                        } else {
                            Button(action: open) {
                                HStack(spacing: 10) {
                                    Text(connections.label).fontWeight(.medium)
                                    Text(connections.summary)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .withoutFocusRing()
                            .help("Links to this note, and mentions of it")
                            .modifier(LinksGlass(shape: Capsule(), isInteractive: true))
                        }
                    }
                    .frame(width: max(width, 200))
                    .padding(.bottom, LinksButton.inset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.bool(forKey: "PointShowLinks") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { open() }
                }
            }
            #endif
        }
    }

    private func open() { withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isExpanded = true } }
    private func close() { withAnimation(.spring(duration: 0.25, bounce: 0)) { isExpanded = false } }
}

/// "12 links", with a close button (Escape).
private struct LinksHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title)
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
        .padding(.bottom, 6)
    }
}

/// Glass on macOS 26, a material before.
private struct LinksGlass<S: Shape>: ViewModifier {
    let shape: S
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(isInteractive ? 0 : 0.15), radius: 12, y: 4)
        }
    }
}

/// A note linking here: its title, type and date on one line; for a mention in the text,
/// the line it's on below.
private struct ConnectionRow: View {
    let title: String
    var type: String?
    var date: Date?
    var context: String?
    let onOpen: () -> Void
    var onLink: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let type {
                            Text(type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let date {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let context, !context.isEmpty {
                        Text(context)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
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
        .padding(.vertical, 4)
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
