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
    let note: Note
    /// Whether it has been asked once, so the panel can say "No links" rather than nothing.
    @Published private(set) var isLoaded = false
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
            self.isLoaded = true
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
    static let sidePanelWidthKey = "linksPanelWidth"
    /// The strip's panel's height, as last dragged.
    static let stripHeightKey = "linksStripHeight"
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
    let paneID: VaultModel.NotePane.ID
    @EnvironmentObject private var model: VaultModel

    /// How far it sits in from the note's bottom and right edges, and how much room the note
    /// leaves below its text for it.
    static let inset: CGFloat = 14
    static let roomBelowText: CGFloat = 36 + inset * 2

    var body: some View {
        if connections.count > 0, !model.isLinksPanelOpen(paneID) {
            Button {
                withAnimation(LinksSidePanel.animation) { model.setLinksPanelOpen(true, for: paneID) }
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
                if UserDefaults.standard.bool(forKey: "PointShowLinks") { model.setLinksPanelOpen(true, for: paneID) }
            }
            #endif
        }
    }
}

/// With the links at the side: the panel at the right of a side of the window, which it
/// makes narrower, top bar and all (see `PaneView`), as the sidebar does on the left. Its
/// name is level with the top bar, its close button where the bar's menu would be. Its left
/// edge drags to make it wider or narrower. Stays open from note to note until closed.
struct LinksSidePanel: View {
    @ObservedObject var connections: Connections
    let paneID: VaultModel.NotePane.ID
    /// The width of the side it's on: it never takes the note below `noteRoom`.
    let roomBeside: CGFloat
    @EnvironmentObject private var model: VaultModel
    @AppStorage(LinksPlacement.sidePanelWidthKey) private var storedWidth: Double = 320
    /// The width while its edge is dragged; kept until let go.
    @State private var dragWidth: CGFloat?
    @State private var dragStart: CGFloat?
    static let widths: ClosedRange<CGFloat> = 240...640
    /// What the note keeps beside it, at least; past that, the panel narrows (to 200 at most).
    static let noteRoom: CGFloat = 320

    /// The widest it can be beside the note.
    private var widest: CGFloat {
        roomBeside > 0 ? max(200, min(Self.widths.upperBound, roomBeside - Self.noteRoom)) : Self.widths.upperBound
    }

    var body: some View {
        let width = min(dragWidth ?? CGFloat(storedWidth), widest)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TopBar.buttonSpacing) {
                Text(connections.isLoaded ? connections.label : " ")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                BarButton("Close links", systemImage: "xmark", help: "Close links") {
                    withAnimation(LinksSidePanel.animation) { model.setLinksPanelOpen(false, for: paneID) }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, TopBar.buttonSpacing)
            .frame(height: model.topBarHeight)
            .background(WindowDragArea())
            if connections.isLoaded, connections.count == 0 {
                Text("No links to this note.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer(minLength: 0)
            } else {
                ScrollView { LinksList(connections: connections) }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) { edge(width: width) }
    }

    static let animation = Animation.spring(duration: 0.3, bounce: 0)

    /// The hairline at its left, which drags.
    private func edge(width: CGFloat) -> some View {
        Divider()
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? width
                            dragStart = start
                            dragWidth = min(max(start - drag.translation.width, Self.widths.lowerBound), min(Self.widths.upperBound, widest))
                        }
                        .onEnded { _ in
                            if let dragWidth { storedWidth = Double(dragWidth) }
                            dragWidth = nil
                            dragStart = nil
                        })
            }
    }
}

/// With the links at the bottom: a glass button in the note's bottom left corner saying how
/// many and of what ("21 links · By 7 · With 11"; just "21 links" where that won't fit),
/// spaced as the sidebar's filter and sort buttons are. It opens a panel sliding up over the
/// note, across its width: plain, as the side panel is, its top edge dragging to make it
/// taller or shorter. Its height stays as it is while it's open, whatever it shows. Escape,
/// the close button or a click on the note closes it.
struct LinksStrip: View {
    @ObservedObject var connections: Connections
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @AppStorage(LinksPlacement.stripHeightKey) private var storedHeight: Double = 360
    @State private var isExpanded = false
    @State private var dragHeight: CGFloat?
    @State private var dragStart: CGFloat?

    /// As the sidebar's filter field: its height, and its distance from the edges.
    static let buttonHeight = VaultModel.SidebarDensity.comfortable.rowHeight
    static let inset: CGFloat = 10
    private static let animation = Animation.spring(duration: 0.32, bounce: 0)

    var body: some View {
        GeometryReader { geometry in
            let room = max(geometry.size.height - topBarCover - 24, 120)
            let height = min(dragHeight ?? CGFloat(storedHeight), room)
            ZStack(alignment: .bottomLeading) {
                if isExpanded {
                    // A click on the note above closes it.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                    panel(height: height, room: room)
                        .transition(.move(edge: .bottom))
                } else if connections.count > 0 {
                    button(maxWidth: geometry.size.width - Self.inset * 2)
                        .padding(Self.inset)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "PointShowLinks") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { open() }
            }
        }
        #endif
    }

    private func button(maxWidth: CGFloat) -> some View {
        Button(action: open) {
            ViewThatFits(in: .horizontal) {
                content(withSummary: true)
                content(withSummary: false)
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
        .help("Links to this note, and mentions of it")
        .modifier(LinksGlass(shape: Capsule(), isInteractive: true))
    }

    private func content(withSummary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(connections.label).fontWeight(.medium)
            if withSummary {
                Text(connections.summary).foregroundStyle(Color.secondary)
            }
        }
        .lineLimit(1)
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: Self.buttonHeight)
        .contentShape(Capsule())
    }

    private func panel(height: CGFloat, room: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TopBar.buttonSpacing) {
                Text(connections.label)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                BarButton("Close links", systemImage: "xmark", help: "Close links", action: close)
                    .keyboardShortcut(.cancelAction) // Escape
            }
            .padding(.leading, 16)
            .padding(.trailing, TopBar.buttonSpacing)
            .padding(.vertical, 6)
            // At most a text column's width, from the left: wider, a title is far from its date.
            ScrollView {
                LinksList(connections: connections, onOpen: close)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) { edge(height: height, room: room) }
    }

    /// The hairline along its top, which drags.
    private func edge(height: CGFloat, room: CGFloat) -> some View {
        Divider()
            .frame(maxWidth: .infinity)
            .overlay {
                Color.clear
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? height
                            dragStart = start
                            dragHeight = min(max(start - drag.translation.height, 140), room)
                        }
                        .onEnded { _ in
                            if let dragHeight { storedHeight = Double(dragHeight) }
                            dragHeight = nil
                            dragStart = nil
                        })
            }
    }

    private func open() { withAnimation(Self.animation) { isExpanded = true } }
    private func close() { withAnimation(Self.animation) { isExpanded = false } }
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
                        // The type and date whole, the title wrapping instead.
                        if let type {
                            Text(type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        if let date {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
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
