import IndexKit
import SwiftUI
import VaultKit

/// Everything related to a note, kept up to date: the notes sharing its topics or people (see
/// `Recall`), what links to it, and where it's mentioned without a link. One list, in one panel
/// (links and recall made one, 8 November 2026: see `RelatedNotes`).
@MainActor
final class Connections: ObservableObject {
    @Published private(set) var backlinks: [Backlink] = []
    @Published private(set) var mentions: [Mention] = []
    /// The type the list is narrowed to, if any.
    @Published var type: String? { didSet { if type != oldValue { rebuild() } } }
    /// The list, narrowed to `type`.
    @Published private(set) var related = RelatedNotes.empty
    /// The line under the note's properties that opens the list, nil with nothing to show.
    @Published private(set) var readout: String?
    /// Whether what's shared leads the readout (it has an icon to say so).
    @Published private(set) var readoutIsRecall = false
    /// Links and unlinked mentions together.
    var count: Int { backlinks.count + mentions.count }
    let note: Note
    /// Whether it has been asked once, so the panel can say "Nothing related" rather than nothing.
    @Published private(set) var isLoaded = false
    /// What it shares, as its frontmatter says (see `take(_:name:)`), and its own type.
    private(set) var recall: Recall?
    private(set) var ownType: String?
    /// What the recall's query found, newest first, and their values.
    private var sharedIDs: [Note.ID] = []
    private var sharedValues: [Note.ID: [String: [String]]] = [:]
    private var placement = RelatedNotes.Placement.current
    private weak var model: VaultModel?
    private var refreshTask: Task<Void, Never>?

    init(note: Note, model: VaultModel) {
        self.note = note
        self.model = model
        NotificationCenter.default.addObserver(self, selector: #selector(vaultChanged), name: .pointFilesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func vaultChanged() {
        // The index updates after the rescan; give it a moment.
        refresh(after: 1.5)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.placement != RelatedNotes.Placement.current else { return }
            self.placement = RelatedNotes.Placement.current
            self.rebuild()
        }
    }

    /// Takes the note's frontmatter as it is now: what it shares can change as it's edited.
    func take(_ frontmatter: Frontmatter?, name: String) {
        guard let model else { return }
        let recall = model.store.recall(of: frontmatter, name: name)
        let typeProperty = model.store.kinds.property
        let ownType = frontmatter?.properties.first { $0.key.caseInsensitiveCompare(typeProperty) == .orderedSame }?
            .values.first?.trimmingCharacters(in: .whitespaces)
        let typeChanged = ownType != self.ownType
        self.ownType = ownType?.isEmpty == false ? ownType : nil
        if recall != self.recall {
            self.recall = recall
            // While it's being typed; the editor's first refresh, as it loads, comes sooner.
            refresh(after: 0.3)
        } else if typeChanged {
            rebuild()
        }
    }

    func refresh(after delay: Double = 0) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, let model = self.model, let index = model.index, !Task.isCancelled else { return }
            let notes = model.notes
            let note = self.note
            let typeProperty = model.store.kinds.property
            let backlinks = (try? await index.backlinks(to: note, notes: notes, typeProperty: typeProperty)) ?? []
            let mentions = (try? await index.unlinkedMentions(of: note, notes: notes)) ?? []
            var sharedIDs: [Note.ID] = []
            var sharedValues: [Note.ID: [String: [String]]] = [:]
            if let recall = self.recall {
                sharedIDs = ((try? await index.notes(matching: recall.query)) ?? []).filter { $0 != note.id }
                // Room for the ones left out as links, with `placement` `.links`.
                let ranked = Array(sharedIDs.prefix(RelatedNotes.sharedLimit + backlinks.count))
                sharedValues = (try? await index.propertyValues(RecallDetails.keys(for: recall, typeProperty: typeProperty), of: ranked)) ?? [:]
            }
            guard !Task.isCancelled else { return }
            self.backlinks = backlinks
            self.mentions = mentions
            self.sharedIDs = sharedIDs
            self.sharedValues = sharedValues
            self.isLoaded = true
            self.rebuild()
        }
    }

    /// Ranks and groups what was found (quick: no lookups).
    private func rebuild() {
        guard let model else { return }
        let make = { [note, recall, sharedIDs, sharedValues, backlinks, placement] (type: String?) in
            RelatedNotes(noteID: note.id, recall: recall, sharedIDs: sharedIDs, values: sharedValues,
                         title: { model.note($0)?.title }, name: { model.note($0)?.name },
                         typeProperty: model.store.kinds.property, backlinks: backlinks, type: type, placement: placement)
        }
        let all = make(nil)
        if let type, !all.types.contains(where: { $0.type.caseInsensitiveCompare(type) == .orderedSame }) {
            self.type = nil // Rebuilds again.
            return
        }
        let related = type == nil ? all : make(type)
        if related != self.related { self.related = related }
        let readout = all.readout(ownType: ownType, unlinkedMentions: mentions.count)
        if readout != self.readout { self.readout = readout }
        readoutIsRecall = all.sharedTotal > 0
    }

    /// Opens a note linking here, at its first link to this note.
    func open(_ backlink: Backlink, inPane paneID: VaultModel.NotePane.ID) {
        guard let model else { return }
        if NSEvent.modifierFlags.contains(.command) {
            model.open(backlink.noteID, inPane: paneID, as: .newTab)
        } else if backlink.range.location != NSNotFound {
            model.open(backlink.noteID, revealing: backlink.range)
        } else {
            model.open(backlink.noteID, inPane: paneID, as: .here)
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
        rebuild()
        refresh(after: 1.5)
    }
}

extension RelatedNotes.Placement {
    /// Where a note that both shares something and links here shows, chosen in Settings › Notes.
    static let key = "relatedNotesPlacement"
    @MainActor static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .shared }
    var title: String {
        switch self {
        case .shared: "With the notes sharing topics or people"
        case .links: "With the links, by what they are"
        }
    }
}

/// Where the related notes show, chosen in Settings › Notes.
enum LinksPlacement: String, CaseIterable, Identifiable {
    /// A panel at the right of a side of the window that pushes the note over, as the sidebar
    /// does on the left.
    case side
    /// A panel sliding up over the note's bottom, the note above it scrolling as ever.
    case bottom
    var id: Self { self }
    var title: String {
        switch self {
        case .side: "Panel at the side"
        case .bottom: "Panel sliding up from the bottom"
        }
    }
    static let key = "linksPlacement"
    static let defaultValue = LinksPlacement.bottom
    /// Whether the panel is open, in every window, until closed.
    static let sidePanelKey = "showsLinksPanel"
    static let sidePanelWidthKey = "linksPanelWidth"
    /// The sliding panel's height, as last dragged.
    static let stripHeightKey = "linksStripHeight"
    static let defaultStripHeight: Double = 360
    /// How far the word count sits in from the note's edges, and how much room the note leaves
    /// below its text for it.
    static let inset: CGFloat = 14
    static let roomBelowText: CGFloat = 36 + inset * 2
}

// MARK: The readout

/// Under a note's properties (or its title, without any), what's related to it: "4 earlier
/// meetings · last on 21 October", "23 notes on Org design", or with nothing shared, "12 links
/// (articles by this person, mentions, and meetings with this person)". Clicking it opens the
/// panel, or closes it. Nothing while there's nothing, or while the index is being asked.
struct RelatedReadout: View {
    @ObservedObject var connections: Connections
    @ObservedObject var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    /// Alone under the title, not in the properties: spaced as they'd be.
    var standalone = false

    var body: some View {
        if let readout = connections.readout {
            let isOpen = model.isLinksPanelOpen(paneID)
            Button {
                withAnimation(RelatedPanel.animation) { model.setLinksPanelOpen(!isOpen, for: paneID) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .frame(width: PropertiesStrip.chevronWidth)
                    Text(readout)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Hide related notes" : "Show related notes")
            .modifier(Standalone(isOn: standalone, columnWidth: model.store.textColumnWidth))
        }
    }

    private var icon: String {
        guard connections.readoutIsRecall, let recall = connections.recall else { return "link" }
        return recall.basis == .topics ? "rectangle.stack" : "clock.arrow.circlepath"
    }

    /// Spaced as the properties are, under the title.
    private struct Standalone: ViewModifier {
        let isOn: Bool
        let columnWidth: Double
        func body(content: Content) -> some View {
            if isOn {
                content
                    .padding(.bottom, 12)
                    .padding(.leading, 5)
                    .frame(maxWidth: columnWidth, alignment: .leading)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity)
            } else {
                content
            }
        }
    }
}

// MARK: The list

/// The notes related to one: first those sharing its topics or people, most shared first,
/// newest first in each; then those linking to it, grouped by what they are to it (articles by
/// this person, meetings with them…), newest first; then mentions that aren't links yet. Each
/// group folds.
struct RelatedList: View {
    @ObservedObject var connections: Connections
    let paneID: VaultModel.NotePane.ID
    /// Whether the type chips are in the list (at the side), not beside the panel's title.
    var showsChips = false
    @EnvironmentObject private var model: VaultModel
    @State private var folded: Set<String> = []

    var body: some View {
        let related = connections.related
        let ownType = connections.ownType
        LazyVStack(alignment: .leading, spacing: 1) {
            if showsChips, !related.types.isEmpty {
                TypeChips(types: related.types, selection: $connections.type)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            ForEach(related.tiers) { tier in
                let key = "shared \(tier.sharedCount)"
                heading(tier.heading, count: tier.notes.count, key: key)
                if !folded.contains(key) {
                    // Which of them, unless it's all or there's only one.
                    let showsNames = tier.sharedCount < (related.recall?.names.count ?? 0)
                    ForEach(tier.notes) { shared in
                        ConnectionRow(title: shared.title, type: connections.type == nil ? shared.type : nil, date: shared.date,
                                      context: showsNames ? shared.names.joined(separator: " · ") : nil) {
                            open(shared.noteID)
                        }
                    }
                }
            }
            if related.sharedBeyondLimit > 0 {
                Text("And \(related.sharedBeyondLimit.formatted()) more, sharing less")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(related.links.groups) { group in
                let key = "links \(group.relation.label)"
                heading(Self.capitalized(RelatedNotes.phrase(for: group, ownType: ownType)),
                        count: group.backlinks.count, key: key)
                if !folded.contains(key) {
                    ForEach(group.backlinks) { backlink in
                        ConnectionRow(title: backlink.title, type: connections.type == nil ? backlink.type : nil, date: backlink.date,
                                      context: group.relation == .mentioned ? backlink.context : nil) {
                            connections.open(backlink, inPane: paneID)
                        }
                    }
                }
            }
            if connections.type == nil, !connections.mentions.isEmpty {
                heading("Unlinked mentions", count: connections.mentions.count, key: "mentions")
                if !folded.contains("mentions") {
                    ForEach(connections.mentions) { mention in
                        ConnectionRow(title: mention.title, context: mention.context, onOpen: {
                            model.open(mention.noteID, revealing: mention.range)
                        }, onLink: { connections.link(mention) })
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private func open(_ id: Note.ID) {
        model.open(id, inPane: paneID, as: NSEvent.modifierFlags.contains(.command) ? .newTab : .here)
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// A group's heading, bold and as big as the panel's title, folding it on a click.
    private func heading(_ title: String, count: Int, key: String) -> some View {
        let isFolded = folded.contains(key)
        return Button {
            if isFolded { folded.remove(key) } else { folded.insert(key) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(count.formatted())
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isFolded ? -90 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
        .help(isFolded ? "Show these" : "Hide these")
    }
}

/// The types among a note's related notes, with how many of each, to narrow them to one; All
/// first. They wrap onto as many lines as they need.
struct TypeChips: View {
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
        return CGSize(width: min(proposal.width ?? width, width), height: height)
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

// MARK: The panels

enum RelatedPanel {
    static let animation = Animation.spring(duration: 0.3, bounce: 0)
    static let title = "Related notes"
    static let empty = "Nothing related to this note yet."
}

/// The list scrolling under a header that gets a hairline once it has: the list's top is
/// tracked in the scroll view's space.
private struct ScrollingList<Content: View>: View {
    @Binding var isScrolled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Color.clear.preference(key: ScrolledKey.self, value: geometry.frame(in: .named("related")).minY < -1)
                }
                .frame(height: 0)
                content
            }
        }
        .coordinateSpace(name: "related")
        .onPreferenceChange(ScrolledKey.self) { isScrolled = $0 }
    }

}

private struct ScrolledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The panel sliding up over the note's bottom, across its width, the list no wider than the
/// note's text and lined up with it. The note above scrolls as ever (and has room at its end
/// to scroll clear of it). Its top edge drags to make it taller or shorter. It stays open from
/// note to note until closed: the close button, Escape or the readout.
struct RelatedSlideUp: View {
    @ObservedObject var connections: Connections
    let paneID: VaultModel.NotePane.ID
    @EnvironmentObject private var model: VaultModel
    @Environment(\.topBarCover) private var topBarCover
    @AppStorage(LinksPlacement.stripHeightKey) private var storedHeight = LinksPlacement.defaultStripHeight
    @State private var dragHeight: CGFloat?
    @State private var dragStart: CGFloat?
    @State private var isScrolled = false
    /// Whether it's there at all (also while sliding away), and whether it's up. It slides as
    /// one, by its own animation: opened from the note's header (a view of its own, which
    /// doesn't animate), a transition moved only the list, and nothing moved on the way out.
    @State private var isPresent = false
    @State private var isUp = false

    var body: some View {
        GeometryReader { geometry in
            let room = Self.room(in: geometry.size.height, topBarCover: topBarCover)
            let height = min(dragHeight ?? CGFloat(storedHeight), room)
            ZStack(alignment: .bottom) {
                if isPresent {
                    panel(height: height, room: room)
                        .offset(y: isUp ? 0 : height + 2)
                        .allowsHitTesting(isUp)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
        }
        // Open already, from note to note: there at once.
        .onAppear {
            isPresent = wantsOpen
            isUp = wantsOpen
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "PointShowLinks") { model.setLinksPanelOpen(true, for: paneID) }
            #endif
        }
        .onChange(of: wantsOpen) { open in
            if open {
                isPresent = true
                // Laid out below first, then up.
                DispatchQueue.main.async { withAnimation(RelatedPanel.animation) { isUp = true } }
            } else {
                withAnimation(RelatedPanel.animation) { isUp = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if !wantsOpen { isPresent = false } }
            }
        }
    }

    /// Out of the way for a note with nothing related (it has no readout to close it with);
    /// back for the next one that has.
    private var wantsOpen: Bool { model.isLinksPanelOpen(paneID) && !isEmpty }

    private var isEmpty: Bool { connections.isLoaded && connections.related.isEmpty && connections.mentions.isEmpty }

    /// The tallest it gets: the note keeps a little at the top.
    static func room(in height: CGFloat, topBarCover: CGFloat) -> CGFloat { max(height - topBarCover - 24, 120) }

    private var columnWidth: CGFloat { CGFloat(model.store.textColumnWidth) }

    private func panel(height: CGFloat, room: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // In the note's column, as the list is. The chips beside the title while they
                // fit on its line; narrower, on rows of their own below it.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        title
                        chips.fixedSize()
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        chips
                    }
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16) // Lined up with the rows' text, and the note's.
                .modifier(Column(width: columnWidth, trailingRoom: 40))
                BarButton("Close", systemImage: "xmark", help: "Close related notes (Escape)") {
                    model.setLinksPanelOpen(false, for: paneID)
                }
                .modifier(EscapeCloses(isOn: isUp))
                .padding(.trailing, TopBar.buttonSpacing)
            }
            .padding(.top, 10)
            Divider().opacity(isScrolled ? 1 : 0)
            ScrollingList(isScrolled: $isScrolled) {
                RelatedList(connections: connections, paneID: paneID)
                    .modifier(Column(width: columnWidth, trailingRoom: 0))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) { edge(height: height, room: room) }
    }

    private var title: some View {
        Text(RelatedPanel.title)
            .font(.headline)
            .lineLimit(1)
            .fixedSize()
            .frame(height: 28)
    }

    @ViewBuilder private var chips: some View {
        if !connections.related.types.isEmpty {
            TypeChips(types: connections.related.types, selection: $connections.type)
        }
    }

    /// Escape closes it while it's up (not while it's sliding away, or Escape would be taken
    /// from the note).
    private struct EscapeCloses: ViewModifier {
        let isOn: Bool
        func body(content: Content) -> some View {
            if isOn { content.keyboardShortcut(.cancelAction) } else { content }
        }
    }

    /// No wider than the note's text, lined up with it (the rows' text with the note's: they're
    /// inset 16 from their highlight, the text 5 from its column, in 28).
    private struct Column: ViewModifier {
        let width: CGFloat
        let trailingRoom: CGFloat
        func body(content: Content) -> some View {
            // The close button's room inside the column, so it stays centred with the note.
            content
                .padding(.trailing, trailingRoom)
                .frame(maxWidth: width + 22, alignment: .leading)
                .padding(.horizontal, 28 - 11)
                .frame(maxWidth: .infinity)
        }
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
}

/// With the panel at the side: at the right of a side of the window, which it makes narrower,
/// top bar and all (see `PaneView`), as the sidebar does on the left. Its name is level with
/// the top bar, its close button where the bar's menu would be. Its left edge drags to make it
/// wider or narrower. Stays open from note to note until closed.
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
    @State private var isScrolled = false
    static let widths: ClosedRange<CGFloat> = 240...640
    /// What the note keeps beside it, at least; past that, the panel narrows (to 200 at most).
    static let noteRoom: CGFloat = 320

    /// The widest it can be beside the note.
    private var widest: CGFloat {
        roomBeside > 0 ? max(200, min(Self.widths.upperBound, roomBeside - Self.noteRoom)) : Self.widths.upperBound
    }

    var body: some View {
        let width = min(dragWidth ?? CGFloat(storedWidth), widest)
        // The header over the list, not above it: from macOS 26 a scroll view reaches up under
        // the title bar's strip whatever's above it, and took the close button's clicks.
        ZStack(alignment: .top) {
            if connections.isLoaded, connections.related.isEmpty, connections.mentions.isEmpty {
                Text(RelatedPanel.empty)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .padding(.top, model.topBarHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollingList(isScrolled: $isScrolled) {
                    RelatedList(connections: connections, paneID: paneID, showsChips: true)
                        .padding(.top, model.topBarHeight)
                }
            }
            HStack(spacing: TopBar.buttonSpacing) {
                Text(RelatedPanel.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                BarButton("Close", systemImage: "xmark", help: "Close related notes") {
                    withAnimation(RelatedPanel.animation) { model.setLinksPanelOpen(false, for: paneID) }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, TopBar.buttonSpacing)
            .frame(height: model.topBarHeight)
            .background(WindowDragArea())
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .bottom) { Divider().opacity(isScrolled ? 1 : 0) }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) { edge(width: width) }
    }

    static let animation = RelatedPanel.animation

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

/// Glass on macOS 26, a material before: behind the word count.
struct LinksGlass<S: Shape>: ViewModifier {
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

/// A related note: its title, type and date on one line; below, for a mention in the text the
/// line it's on, for a note sharing some topics or people which.
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
            .help("Open “\(title)” (⌘-click: in a new tab)")
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
