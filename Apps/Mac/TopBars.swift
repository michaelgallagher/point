import AppKit
import SwiftUI
import VaultKit

/// The window has no title bar or toolbar of its own: the sidebar and each side of the split
/// have their own bar along the top edge, so a split runs the full height of the window. Where
/// a side's note is shows on its page, above the title (see `NoteHeader`).
enum TopBar {
    /// Twice the distance from the window's top to the middle of its close button, so the
    /// close, minimise and zoom buttons sit centred in the bars. Measured from the window.
    @MainActor static func height(for window: NSWindow?) -> CGFloat? {
        guard let window, let button = window.standardWindowButton(.closeButton) else { return nil }
        let middle = button.convert(button.bounds, to: nil).midY
        return ((window.frame.height - middle) * 2).rounded()
    }

    /// Past the zoom button, with a gap, measured from the window.
    @MainActor static func windowButtonsInset(for window: NSWindow?) -> CGFloat? {
        guard let window, let button = window.standardWindowButton(.zoomButton) else { return nil }
        return (button.convert(button.bounds, to: nil).maxX + 16).rounded()
    }

    /// How far the bar starts past the window buttons while the sidebar is hidden: the sidebar
    /// button (see `SidebarSplitController`), then the gap.
    static let sidebarButtonWidth: CGFloat = 36 + buttonSpacing
    /// The gap between buttons in a bar (the HStack's spacing), and how far a side's bar
    /// starts past the sidebar's edge or the divider, so its buttons never touch either.
    static let buttonSpacing: CGFloat = 8
    /// Notes narrower than this can't spare the sidebar button's room: while the sidebar's
    /// hidden, the button goes (⌘S, the View menu and a swipe still show the sidebar), and the
    /// first side's bar starts just past the window buttons. The narrow bar's width (see
    /// `PaneTabBar`).
    static let sidebarButtonHidingWidth: CGFloat = 520
    /// The same, for each side of a split: higher, as a side's tabs have about half the room
    /// they'd have unsplit, and run short of it long before 520 points.
    static let splitSidebarButtonHidingWidth: CGFloat = 600

    /// The top bar's background, in every layout: the page's own colour.
    static let barColor = Color(nsColor: .textBackgroundColor)
    /// Shading under something hovered in a bar: a little darker than the bar.
    static let selectedTabColor = Color.primary.opacity(0.07)
    /// Shading under a hovered button on glass, a little stronger to show on the lighter glass.
    static let hoverColor = Color.primary.opacity(0.1)

}

/// The sidebar's top bar: room for the window buttons and the sidebar button, which sits at
/// its trailing edge. Its empty space drags the window. In one column, a home button just
/// left of the sidebar button goes back to the top level (it hides with the sidebar, which
/// holds it, and is dimmed at the top level). In two columns, it's over the tree alone: the
/// note list has its own (see `NoteListTopBar`).
struct SidebarTopBar: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        Color.clear
            .frame(height: model.topBarHeight)
            .frame(maxWidth: .infinity)
            .background(WindowDragArea())
            .overlay(alignment: .trailing) {
                if model.browsingStyle == .singleColumn {
                    BarButton("Home", systemImage: "house", help: "All notes") { model.browse(.allNotes) }
                        .disabled(model.place == .allNotes)
                        // Clear of the sidebar button, which sits 8 points in from the edge.
                        .padding(.trailing, TopBar.buttonSpacing + TopBar.sidebarButtonWidth)
                }
            }
    }
}

/// The two-column note list's top bar: the folder or tag's name (and, in the trash, emptying
/// it), clear of the sidebar button at its end. How the notes are sorted is at the list's foot,
/// beside the filter. See-through, like a
/// side's bar: the list scrolls up beneath it and blurs (see `BarEdgeScrollView`). Its empty
/// space drags the window.
struct NoteListTopBar: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: TopBar.buttonSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.place == .allNotes ? (model.root?.lastPathComponent ?? "Notes") : model.title(for: model.place))
                    .font(.headline)
                    .lineLimit(1)
                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.place == .trash { EmptyTrashButton() }
        }
        // In line with the list's text: its date headings, and its notes when not grouped
        // (the source list's row inset, then the row's own padding).
        .padding(.leading, 24)
        .padding(.trailing, TopBar.buttonSpacing + TopBar.sidebarButtonWidth)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
    }

    /// How much is here, under the name, as the sidebar counts it: notes, or for the lists
    /// of tags and types, how many there are.
    private var countLabel: String {
        let count = model.noteCount(of: model.place)
        let noun = switch model.place {
        case .trash: count == 1 ? "item" : "items"
        case .types: count == 1 ? "type" : "types"
        case .tags: count == 1 ? "tag" : "tags"
        default: count == 1 ? "note" : "notes"
        }
        return "\(count.formatted()) \(noun)"
    }
}

/// One side's top bar: back and forward, its tabs (when it has more than one), then on the far
/// right its one menu (the note's options and the split). Its empty space moves the window.
struct PaneTabBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// With the sidebar hidden, the first side starts past the window buttons and the sidebar
    /// button.
    private var startsAtWindowEdge: Bool { paneIndex == 0 && (!model.showsNoteList || model.isFocused) }

    /// Past the window buttons and the sidebar button when the sidebar is hidden; otherwise
    /// just past the sidebar's edge or the divider.
    private var leadingInset: CGFloat {
        guard startsAtWindowEdge else { return TopBar.buttonSpacing }
        return model.windowButtonsInset + (model.hidesSidebarButtonForWidth ? 0 : TopBar.sidebarButtonWidth)
    }

    /// Narrower than this, back and forward tighten (when they show: see `hidesHistory`).
    static let narrowWidth: CGFloat = 520
    private var isNarrow: Bool { width > 0 && width < Self.narrowWidth }

    @State private var width: CGFloat = 0
    @State private var sideWidth: CGFloat = 0

    private func sideResized(_ width: CGFloat) {
        sideWidth = width
        if paneIndex == 0 { model.firstSideResized(width) }
    }

    /// Back and forward go into the side's menu (⌘[ and ⌘] still work) while the sidebar's
    /// hidden and this side is narrow: in the first side, with the sidebar button (see
    /// `VaultModel.hidesSidebarButtonForWidth`); in a split's second, by its own width. Their
    /// room goes to the tabs.
    private var hidesHistory: Bool {
        paneIndex == 0 ? model.hidesSidebarButtonForWidth : model.hidesBarButtons(sideWidth: sideWidth)
    }

    var body: some View {
        HStack(spacing: TopBar.buttonSpacing) {
            if !hidesHistory {
                BackForwardButtons(paneIndex: paneIndex, isNarrow: isNarrow)
                    .transition(.opacity)
            }
            // No tabs for just one note.
            if pane.tabs.count > 1 {
                PaneTabs(pane: pane, paneIndex: paneIndex)
            } else {
                Spacer(minLength: 0)
            }
            PaneMenuButton(pane: pane, includesHistory: hidesHistory, paneIndex: paneIndex)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { width = $0 }
        })
        .padding(.leading, leadingInset)
        // As the sidebar slides, on the window's own curve and duration, so the bar's contents
        // glide with the notes, staying clear of the window buttons, rather than jumping. (Only
        // an animation moves during the window's animation; nothing is laid out again.)
        .animation(.easeInOut(duration: 0.25), value: startsAtWindowEdge)
        // And as the sidebar button fades in or out, so the tabs take or give up its room.
        .animation(.easeInOut(duration: 0.25), value: model.hidesSidebarButtonForWidth)
        .animation(.easeInOut(duration: 0.25), value: hidesHistory)
        .padding(.trailing, TopBar.buttonSpacing)
        .frame(height: model.topBarHeight)
        // The side's whole width: the first side's decides whether the sidebar button shows
        // in its bar (see `VaultModel.notesAreNarrow`).
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { sideResized(geometry.size.width) }
                .onChange(of: geometry.size.width) { sideResized($0) }
        })
        .background(WindowDragArea())
        // A tab dropped on the bar, past the tabs, goes at the end of this side's tabs.
        .background(TabDropArea { id, _, _ in
            id.map { model.location(ofTab: $0) != nil } ?? false
        } drop: { id, _, _ in
            guard model.location(ofTab: id) != nil, model.panes.indices.contains(paneIndex) else { return false }
            model.moveTab(id, toPane: paneIndex, at: model.panes[paneIndex].tabs.count)
            return true
        })
        .background { TopBarBackground() }
    }
}

/// Before macOS 26, the page's colour with a hairline under it. From 26, nothing: the note
/// scrolling beneath blurs itself, under a side's bar (see `BarEdgeScrollView`).
private struct TopBarBackground: View {
    var body: some View {
        if #available(macOS 26, *) {
            Color.clear
        } else {
            TopBar.barColor
                .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        }
    }
}

// MARK: The tabs

/// A side's tabs, as in Safari, Finder and Xcode: a grey capsule holding the tabs, the current
/// one a raised capsule of glass inside it. Unlike theirs, it's as tall as the bar's buttons and as wide as
/// its titles, leaving the rest of the bar empty; when that's more than there's room for, the
/// longest titles are cut first. Hover for a tab's close button, at its leading edge;
/// right-click for its menu. Drag a tab along the row, to the other side's row or page, or to
/// one half of the page to split the window. When the tabs don't all fit at their narrowest,
/// the row scrolls.
struct PaneTabs: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    static let height: CGFloat = 36
    /// Between a tab and the capsule around it.
    static let inset: CGFloat = 2
    static let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let titles = pane.tabs.map { model.note($0.noteID)?.title ?? model.store.image($0.noteID)?.name ?? "New tab" }
            let layout = TabLayout(titles: titles, current: pane.current, available: geometry.size.width)
            HStack(spacing: Self.spacing) {
                ForEach(Array(layout.visible.enumerated()), id: \.element) { position, index in
                    let tab = pane.tabs[index]
                    let next = position + 1 < layout.visible.count ? layout.visible[position + 1] : nil
                    PaneTab(
                        id: tab.id,
                        title: layout.labels[index],
                        help: tab.noteID ?? "",
                        isCurrent: index == pane.current,
                        isActiveSide: paneIndex == model.activePane,
                        showsLine: next != nil && index != pane.current && next != pane.current,
                        width: layout.widths[index] ?? 0,
                        select: { model.selectTab(index, inPane: paneIndex) },
                        close: { model.closeTab(index, inPane: paneIndex) },
                        menu: { TabMenu.menu(for: index, tab: tab, inPane: paneIndex, model: model) }
                    )
                    .modifier(TabDropTarget(paneIndex: paneIndex, index: index))
                }
                if !layout.hidden.isEmpty {
                    TabOverflowButton(titles: layout.hidden.map { titles[$0] }) { picked in
                        model.selectTab(layout.hidden[picked], inPane: paneIndex)
                    }
                }
            }
            .padding(Self.inset)
            .animation(.easeInOut(duration: 0.2), value: pane.current)
            // Solid, so text scrolling under the bars doesn't show through.
            .background(TopBar.barColor.overlay(Color.primary.opacity(0.09)))
            .clipShape(Capsule())
            // Only as wide as the tabs, so the bar's empty space still moves the window.
            .frame(width: min(layout.rowWidth, geometry.size.width), alignment: .leading)
        }
        .frame(height: Self.height)
    }
}

/// Where a side's tabs go in the room they have, and what each says. In stages, each tried
/// only when the one before doesn't fit:
/// 1. Every tab as wide as its whole title.
/// 2. The tabs sharing the room, the widest cut first, while every tab still shows about ten
///    characters.
/// 3. Compact: the current tab keeps a readable width; the others share what's left.
/// 4. Compact, with the tabs that still don't fit in a menu at the end of the row: the current
///    one, and the others in order up to as many as fit.
/// Then each tab's title is fitted to its width (see `TabLabels`).
@MainActor
struct TabLayout {
    /// Indices of the tabs shown, in order.
    var visible: [Int]
    /// Indices of the tabs in the menu, in order.
    var hidden: [Int] = []
    var labels: [String]
    var widths: [Int: CGFloat]
    var isCompact = false
    var rowWidth: CGFloat = 0

    /// Stage 2's narrowest: room for about ten characters, and the padding either side (the
    /// close button shows in the leading one on hover). Set for the flat header and retuned
    /// for these tabs' wider padding (20 points either side, not 22 and 10).
    static let comfortable: CGFloat = 104
    /// Compact, the narrowest a tab other than the current one gets: its padding and about
    /// five letters.
    static let narrowest: CGFloat = 78
    /// Compact, the current tab is never wider than this, nor narrower than `selectedNarrowest`
    /// (unless its title is shorter). It needs the room least: its whole title is on its page,
    /// just below.
    static let selectedWidest: CGFloat = 158
    static let selectedNarrowest: CGFloat = 88
    static let overflowWidth: CGFloat = 40

    private static let font = NSFont.systemFont(ofSize: PaneTab.fontSize)

    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    init(titles: [String], current: Int, available: CGFloat) {
        let count = titles.count
        let current = min(max(current, 0), count - 1)
        func room(_ shown: Int, overflow: Bool) -> CGFloat {
            available - PaneTabs.inset * 2 - PaneTabs.spacing * CGFloat(max(shown - 1, 0))
                - (overflow ? PaneTabs.spacing + Self.overflowWidth : 0)
        }
        let full = { (text: String) in Self.textWidth(text) + PaneTab.padding * 2 }

        // 1. Whole titles.
        let natural = titles.map(full)
        visible = Array(0..<count)
        labels = titles
        widths = Dictionary(uniqueKeysWithValues: zip(visible, natural))
        if natural.reduce(0, +) <= room(count, overflow: false) {
            finish()
            return
        }

        // 2. Shared.
        let shared = Self.share(natural, room(count, overflow: false))
        widths = Dictionary(uniqueKeysWithValues: zip(visible, shared))
        if shared.allSatisfy({ $0 >= Self.comfortable }) {
            finish()
            return
        }

        // 3 and 4. Compact, with fewer tabs shown until they fit.
        isCompact = true
        let selectedNatural = min(natural[current], Self.selectedWidest)
        for shown in stride(from: count, through: 1, by: -1) {
            let others = Array((0..<count).filter { $0 != current }.prefix(shown - 1))
            let room = room(shown, overflow: shown < count)
            let othersNatural = others.map { natural[$0] }
            let selected = min(selectedNatural, room - othersNatural.map { min($0, Self.narrowest) }.reduce(0, +))
            let otherWidths = Self.share(othersNatural, room - selected)
            let fits = selected >= min(selectedNatural, Self.selectedNarrowest)
                && otherWidths.allSatisfy { $0 >= Self.narrowest }
            if fits || shown == 1 {
                visible = (others + [current]).sorted()
                hidden = (0..<count).filter { !visible.contains($0) }
                widths = Dictionary(uniqueKeysWithValues: zip(others, otherWidths))
                widths[current] = max(selected, 0)
                finish()
                return
            }
        }
    }

    private mutating func finish() {
        let padding = PaneTab.padding * 2
        labels = TabLabels.fit(labels, rooms: labels.indices.map { widths[$0].map { $0 - padding } })
        rowWidth = visible.compactMap { widths[$0] }.reduce(0, +)
            + PaneTabs.spacing * CGFloat(max(visible.count - 1, 0)) + PaneTabs.inset * 2
            + (hidden.isEmpty ? 0 : PaneTabs.spacing + Self.overflowWidth)
    }

    /// Shares `room` between tabs wanting `natural`: those narrower than their share keep their
    /// width, leaving more for the rest, which are cut to the same width. The points left over
    /// from rounding down go one each to the first cut tabs, so the row ends where its room does.
    static func share(_ natural: [CGFloat], _ room: CGFloat) -> [CGFloat] {
        guard natural.reduce(0, +) > room, !natural.isEmpty else { return natural }
        var room = room
        var left = natural.count
        for width in natural.sorted() where width <= room / CGFloat(left) {
            room -= width
            left -= 1
        }
        let widest = max((room / CGFloat(max(left, 1))).rounded(.down), 0)
        var spare = Int(max(room - widest * CGFloat(left), 0))
        return natural.map { width in
            guard width > widest else { return width }
            defer { spare -= 1 }
            return spare > 0 ? widest + 1 : widest
        }
    }
}

/// Tab titles fitted to their tabs. A title that fits is shown whole. One that doesn't has its
/// dates shortened ("30 Oct" for "2026-10-30") and is cut at its end, as usual, unless what's
/// left would look like another tab's: then the leading words it shares with that tab go, so
/// "Weeknote - 2026-11-09" and "Weeknote - 2026-11-02" show as "9 Nov" and "2 Nov", where both
/// would have been "Week…". (No "…" before them: it took room, and showed on some tabs and not
/// others, as the rest fitted or didn't.) Titles that already look different where they're cut
/// are only cut at their ends. The tooltip has the whole title.
@MainActor
enum TabLabels {
    /// `rooms` holds the room for each title's text, or nil for a tab not shown.
    static func fit(_ titles: [String], rooms: [CGFloat?]) -> [String] {
        let dated = titles.indices.map { i in
            guard let room = rooms[i], TabLayout.textWidth(titles[i]) > room else { return titles[i] }
            return shortenDates(titles[i])
        }
        // What each shown tab would say, cut at its end.
        let seen = titles.indices.map { i in rooms[i].map { visible(dated[i], in: $0) } }
        let words = dated.map { $0.split(separator: " ").map(String.init) }
        return titles.indices.map { i in
            guard rooms[i] != nil, let mine = seen[i], mine != dated[i] else { return dated[i] }
            // The tabs this one would look like: one's start is the other's whole.
            let twins = titles.indices.filter { j in
                guard j != i, let theirs = seen[j] else { return false }
                return theirs.hasPrefix(mine) || mine.hasPrefix(theirs)
            }
            var shared = 0
            for j in twins {
                var same = 0
                while same < words[i].count - 1, same < words[j].count, words[i][same] == words[j][same] {
                    same += 1
                }
                shared = max(shared, same)
            }
            guard shared > 0 else { return dated[i] }
            let rest = words[i][shared...].joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: "-–—·:,|").union(.whitespaces))
            return rest.isEmpty ? dated[i] : rest
        }
    }

    /// What of `text` shows in `room`, cut at its end (without the "…").
    static func visible(_ text: String, in room: CGFloat) -> String {
        guard TabLayout.textWidth(text) > room else { return text }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if TabLayout.textWidth(String(characters[..<middle]) + "…") <= room { low = middle } else { high = middle - 1 }
        }
        return String(characters[..<low]).trimmingCharacters(in: .whitespaces)
    }

    /// "2026-10-30" as "30 Oct".
    static func shortenDates(_ title: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#) else { return title }
        var result = title
        for match in regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).reversed() {
            guard let range = Range(match.range, in: result),
                  let date = parser.date(from: String(result[range])) else { continue }
            result.replaceSubrange(range, with: formatter.string(from: date))
        }
        return result
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

/// At the end of the row, inside the tabs' capsule, for the tabs that don't fit: a double
/// chevron and how many, opening a menu of them. Choosing one makes it current, which brings
/// it into the row.
private struct TabOverflowButton: View {
    let titles: [String]
    let select: (Int) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 9, weight: .semibold))
            Text("\(titles.count)")
                .font(.system(size: 12).monospacedDigit())
        }
        .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(width: TabLayout.overflowWidth, height: PaneTab.height)
        .background {
            Capsule().fill(isHovering ? TopBar.hoverColor : .clear)
        }
        .allowsHitTesting(false)
        .background(MenuArea(help: titles.count == 1 ? "1 more tab" : "\(titles.count) more tabs") {
            let menu = NSMenu()
            for (index, title) in titles.enumerated() {
                menu.addItem(BlockMenuItem(title) { select(index) })
            }
            return menu
        })
        .onHover { isHovering = $0 }
    }
}

/// The current tab's raised capsule: glass from macOS 26.
private struct RaisedTab: View {
    let color: Color

    var body: some View {
        let capsule = Capsule().fill(color)
        if #available(macOS 26, *) {
            capsule.glassEffect(.regular, in: Capsule())
        } else {
            capsule
        }
    }
}

private struct PaneTab: View {
    @Environment(\.colorScheme) private var colorScheme
    let id: VaultModel.NoteTab.ID
    let title: String
    let help: String
    let isCurrent: Bool
    /// False on the side of a split not being worked on, whose current tab is less raised.
    let isActiveSide: Bool
    /// Whether to draw the line after this tab.
    let showsLine: Bool
    let width: CGFloat
    let select: () -> Void
    let close: () -> Void
    let menu: () -> NSMenu
    @State private var isHovering = false

    static let height: CGFloat = 32
    static let fontSize: CGFloat = 13
    /// Either side of the title: room for the close button, and to balance it.
    static let padding: CGFloat = 20

    /// The raised capsule of the current tab: lighter than what's around it.
    private var raisedColor: Color {
        colorScheme == .dark ? .white.opacity(isActiveSide ? 0.16 : 0.08) : .white.opacity(isActiveSide ? 0.95 : 0.55)
    }

    var body: some View {
        Text(title)
            .font(.system(size: Self.fontSize))
            .foregroundStyle((isCurrent && isActiveSide) || isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .padding(.horizontal, Self.padding)
            .frame(width: width, height: Self.height)
            .overlay(alignment: .leading) {
                // Clicked through the tab's mouse area, which knows where it is.
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.padding, height: Self.height)
                    .opacity(isHovering ? 1 : 0)
            }
            .overlay(alignment: .trailing) {
                if showsLine {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1, height: 14)
                        .offset(x: 1.5)
                }
            }
            .background {
                if isCurrent {
                    RaisedTab(color: raisedColor)
                        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(isActiveSide ? 0.1 : 0), radius: 2, y: 1)
                }
                // Hovering shows only the close button and darker text: no shape behind.
            }
            .allowsHitTesting(false) // Clicks go to the tab's mouse area, below.
            // Clicks, drags, hover and the menu are handled in AppKit: the tabs sit where a
            // title bar would, and there the window takes any drag not claimed first.
            .background(TabMouseArea(id: id, title: title, select: select, close: close, closeEdge: .leading,
                                     closeWidth: Self.padding, selectsOnPress: true,
                                     menu: menu, isHovering: $isHovering))
            .help(help)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select() }
            .accessibilityAction(named: "Close tab") { close() }
    }
}

/// A tab dropped on another tab goes before or after it, whichever half it's over.
private struct TabDropTarget: ViewModifier {
    @EnvironmentObject private var model: VaultModel
    let paneIndex: Int
    let index: Int
    @State private var edge: HorizontalEdge?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                if edge != nil {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                        .offset(x: edge == .leading ? -2 : 2)
                }
            }
            .background(TabDropArea { id, point, size in
                edge = id.flatMap { model.location(ofTab: $0) } == nil ? nil : (point.x < size.width / 2 ? .leading : .trailing)
                return edge != nil
            } drop: { id, point, size in
                edge = nil
                guard model.location(ofTab: id) != nil else { return false }
                model.moveTab(id, toPane: paneIndex, at: point.x < size.width / 2 ? index : index + 1)
                return true
            })
    }
}

// MARK: The tab's menu

@MainActor
enum TabMenu {
    /// A tab's right-click menu.
    static func menu(for index: Int, tab: VaultModel.NoteTab, inPane p: Int, model: VaultModel) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(BlockMenuItem("Close Tab") { model.closeTab(index, inPane: p) })
        menu.addItem(BlockMenuItem("Close Other Tabs") { model.closeOtherTabs(index, inPane: p) })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(model.isSplit ? "Move to Other Side" : "Move to New Split") {
            model.moveTabToOtherSide(index, inPane: p)
        })
        if model.isSplit {
            menu.addItem(BlockMenuItem("Merge Both Sides into Tabs") { model.mergeIntoTabs() })
        }
        if let id = tab.noteID {
            menu.addItem(BlockMenuItem("Open in New Window") {
                model.closeTab(index, inPane: p)
                model.openWindowHandler?(id)
            })
        }
        return menu
    }
}

/// Back and forward through the side's current tab's history, joined in one glass capsule (from
/// macOS 26) at the start of the side's bar, as tall as the round bar buttons. As in the
/// system's grouped toolbar buttons, each is a circle nearly as tall as the capsule, shaded on
/// hover.
private struct BackForwardButtons: View {
    @EnvironmentObject private var model: VaultModel
    let paneIndex: Int
    /// In a narrow bar, closer together: the thin chevrons looked far apart in 32-point circles.
    var isNarrow = false

    /// Each button's width in a narrow bar.
    private static let narrowWidth: CGFloat = 26

    var body: some View {
        let width = isNarrow ? Self.narrowWidth : nil
        let row = HStack(spacing: 0) {
            BarIcon(symbol: "chevron.left", label: "Back", help: "Back (⌘[)", enabled: model.canTravel(back: true, inPane: paneIndex), width: width) {
                model.travel(back: true, inPane: paneIndex)
            }
            BarIcon(symbol: "chevron.right", label: "Forward", help: "Forward (⌘])", enabled: model.canTravel(back: false, inPane: paneIndex), width: width) {
                model.travel(back: false, inPane: paneIndex)
            }
        }
        if #available(macOS 26, *) {
            row
                .padding(2)
                .glassEffect(.regular, in: Capsule())
        } else {
            row
        }
    }
}

/// The side's one menu, at the end of its bar: what can be done with its note, then the split
/// (opening it, or closing it, which keeps both sides' notes as tabs).
private struct PaneMenuButton: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    /// Back and forward first, when they're not in the bar.
    var includesHistory = false
    var paneIndex = 0

    private func menu() -> NSMenu {
        let menu = NSMenu()
        // Items are enabled as set here (Save Web Images to Vault isn't always).
        menu.autoenablesItems = false
        if includesHistory {
            let back = BlockMenuItem("Back") { model.travel(back: true, inPane: paneIndex) }
            back.isEnabled = model.canTravel(back: true, inPane: paneIndex)
            back.keyEquivalent = "["
            menu.addItem(back)
            let forward = BlockMenuItem("Forward") { model.travel(back: false, inPane: paneIndex) }
            forward.isEnabled = model.canTravel(back: false, inPane: paneIndex)
            forward.keyEquivalent = "]"
            menu.addItem(forward)
            menu.addItem(.separator())
        }
        let note = model.note(pane.tab.noteID)
        if let note {
            let bookmark = BlockMenuItem("Bookmark") { model.toggleBookmark(note.id) }
            bookmark.state = model.isBookmarked(note.id) ? .on : .off
            menu.addItem(bookmark)
            menu.addItem(BlockMenuItem("Move File…") { model.moving = note })
            // As File › Save Web Images to Vault: only where the note has pictures from the web.
            let saving = WebImageNotes.shared.saving.contains(note.id)
            let webImages = BlockMenuItem(saving ? "Saving Web Images…" : "Save Web Images to Vault") { model.store.saveWebImages(in: note) }
            webImages.isEnabled = WebImageNotes.shared.canSave(note.id)
            menu.addItem(webImages)
            let markdown = BlockMenuItem("Show Markdown") { model.toggleMarkdown(inPane: pane.id) }
            markdown.state = model.showsMarkdown(inPane: pane.id) ? .on : .off
            menu.addItem(markdown)
            menu.addItem(BlockMenuItem("Reveal in Finder") { model.showInFinder(note) })
            menu.addItem(.separator())
        }
        if model.isSplit {
            menu.addItem(BlockMenuItem("Close Split") { model.mergeIntoTabs() })
        } else {
            menu.addItem(BlockMenuItem("Split") { model.toggleSplit() })
        }
        if let note {
            menu.addItem(.separator())
            menu.addItem(BlockMenuItem("Delete File") { model.moveToTrash(note) })
        }
        return menu
    }

    var body: some View {
        BarMenu("Note options", systemImage: "ellipsis", help: "Note options", menu: menu)
    }
}

/// How the notes are sorted, in the two-column note list's top bar.
struct SortButton: View {
    @EnvironmentObject private var model: VaultModel
    /// At a list's foot, the menu opens above it.
    var opensUpward = false

    private func menu() -> NSMenu {
        let menu = NSMenu()
        for (title, sort) in [("Date Edited", NoteSort.modified), ("Date Created", .created), ("Title", .title)] {
            let item = BlockMenuItem(title) { model.sort = sort }
            item.state = model.sort == sort ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    var body: some View {
        BarMenu("Sort", systemImage: "arrow.up.arrow.down", help: "How notes are sorted", opensUpward: opensUpward, menu: menu)
    }
}

/// A plain icon in a bar, in a circle shaded on hover. Clicks are taken by an AppKit view under
/// it: in the title bar's area, the window takes a click on a SwiftUI button and moves itself
/// instead.
struct BarIcon: View {
    let symbol: String
    let label: String
    let help: String
    var enabled = true
    /// Narrower than it is tall, in a narrow bar (its hover shape a capsule, not a circle).
    var width: CGFloat?
    let action: () -> Void
    @State private var isHovering = false

    /// 32 points: in the back and forward capsule, 2 points in from its edge.
    private static let size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: width ?? Self.size, height: Self.size)
            .background {
                Capsule().fill(isHovering && enabled ? TopBar.hoverColor : .clear)
            }
            .allowsHitTesting(false) // The click area below takes the clicks.
            .background(ClickArea(enabled: enabled, help: help, action: action))
            .onHover { isHovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }
}

/// A place that takes clicks in AppKit, behind something drawn in SwiftUI: needed in the
/// top bars, where the window would otherwise take the click and move itself.
struct ClickArea: NSViewRepresentable {
    var enabled = true
    var help: String?
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        view.isEnabled = enabled
        view.action = action
        view.toolTip = help
    }

    final class ClickView: NSView {
        var isEnabled = true
        var action: () -> Void = {}
        private var isPressed = false

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { isPressed = isEnabled }

        override func mouseUp(with event: NSEvent) {
            defer { isPressed = false }
            // Only if the pointer is still over it, as with any button.
            guard isPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action()
        }
    }
}

/// Like `ClickArea`, for a menu: shows it below itself as the mouse goes down.
struct MenuArea: NSViewRepresentable {
    let help: String
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> MenuView { MenuView() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.makeMenu = menu
        view.toolTip = help
    }

    final class MenuView: NSView {
        var makeMenu: () -> NSMenu = { NSMenu() }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func show() {
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
        }

        override func mouseDown(with event: NSEvent) { show() }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { toolTip }

        override func accessibilityPerformPress() -> Bool {
            show()
            return true
        }
    }
}

/// An icon button like a toolbar's.
struct BarButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    init(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        if #available(macOS 26, *) {
            // A round glass button, as in a toolbar: 36 points, as tall as the back and
            // forward capsule and the system's sidebar button.
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .focusEffectDisabled() // No focus ring when the window opens.
            .help(help)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(help)
        }
    }
}

/// A `BarButton` that opens a menu below itself. (A SwiftUI menu drawn as glass wasn't the
/// bar buttons' glass.)
struct BarMenu: View {
    let title: String
    let systemImage: String
    let help: String
    var opensUpward = false
    let menu: () -> NSMenu
    @State private var anchor = MenuAnchor.Holder()

    init(_ title: String, systemImage: String, help: String, opensUpward: Bool = false, menu: @escaping () -> NSMenu) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.opensUpward = opensUpward
        self.menu = menu
    }

    var body: some View {
        if #available(macOS 26, *) {
            // Drawn as the other bar buttons are; over it, an invisible system pull-down takes
            // the click, so macOS places the menu and opens it from the button. (The pull-down's
            // own glass bezel isn't the bar buttons' glass: it drew as a flat grey circle.)
            BarButton(title, systemImage: systemImage, help: help) {}
                .allowsHitTesting(false)
                .overlay {
                    GlassPullDown(title: title, systemImage: systemImage, help: help, opensUpward: opensUpward, menu: menu)
                }
        } else {
            popUpButton
        }
    }

    /// Before macOS 26: a bar button that shows the menu below (or above) itself.
    private var popUpButton: some View {
        BarButton(title, systemImage: systemImage, help: help) {
            guard let view = anchor.view else { return }
            let menu = menu()
            // The point is the menu's top left: above, it's the menu's height up from the button.
            let y = opensUpward ? view.bounds.height + 6 + menu.size.height : -6
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
        }
        .background(MenuAnchor(holder: anchor))
    }
}

/// An invisible pull-down button (`NSPopUpButton`) over a bar button's face, its menu made
/// afresh each time it opens.
@available(macOS 26, *)
private struct GlassPullDown: NSViewRepresentable {
    let title: String
    let systemImage: String
    let help: String
    let opensUpward: Bool
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> Button {
        let button = Button(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.isTransparent = true
        button.imagePosition = .noImage
        button.setAccessibilityLabel(title)
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.focusRingType = .none
        return button
    }

    func updateNSView(_ button: Button, context: Context) {
        button.makeMenu = menu
        button.toolTip = help
        button.preferredEdge = opensUpward ? .maxY : .minY
        button.refreshMenu()
    }

    final class Button: NSPopUpButton {
        var makeMenu: () -> NSMenu = { NSMenu() }

        // In the title bar's area the window would take the click and move itself.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// A pull-down shows its first item as the button and leaves it out of the menu: an
        /// empty one goes there (the face is drawn beneath), and the real items after it.
        func refreshMenu() {
            let menu = makeMenu()
            let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.insertItem(face, at: 0)
            self.menu = menu
        }

        // Made afresh as it opens, so ticks (the sort, Show Markdown) are current.
        override func mouseDown(with event: NSEvent) {
            refreshMenu()
            super.mouseDown(with: event)
        }

        override func accessibilityPerformPress() -> Bool {
            refreshMenu()
            return super.accessibilityPerformPress()
        }
    }
}

/// An AppKit view behind a button, for a menu to open from; it takes no clicks itself.
struct MenuAnchor: NSViewRepresentable {
    final class Holder { weak var view: NSView? }
    let holder: Holder

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        holder.view = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) { holder.view = view }
}

/// A tab's or a tab list row's mouse handling: a click selects it, a drag picks it up, a
/// right-click shows its menu. Dropped outside the list, the list closes.
private struct TabMouseArea: NSViewRepresentable {
    let id: VaultModel.NoteTab.ID
    let title: String
    let select: () -> Void
    /// A click this close to the edge with the close button closes the tab.
    let close: () -> Void
    var closeEdge = HorizontalEdge.trailing
    let closeWidth: CGFloat
    /// Selects as the mouse goes down, as a tab does, rather than as it comes up, as a menu
    /// row does (so a row can be dragged without going to its tab).
    var selectsOnPress = false
    let menu: () -> NSMenu
    var draggedOut: () -> Void = {}
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TabMouseView { TabMouseView() }

    func updateNSView(_ view: TabMouseView, context: Context) {
        view.tabID = id
        view.title = title
        view.select = select
        view.close = close
        view.closeEdge = closeEdge
        view.closeWidth = closeWidth
        view.selectsOnPress = selectsOnPress
        view.makeMenu = menu
        view.draggedOut = draggedOut
        view.onHover = { isHovering = $0 }
    }

    final class TabMouseView: NSView, NSDraggingSource {
        var tabID: VaultModel.NoteTab.ID?
        var title = ""
        var select: () -> Void = {}
        var close: () -> Void = {}
        var closeEdge = HorizontalEdge.trailing
        var closeWidth: CGFloat = 0
        var selectsOnPress = false
        var makeMenu: () -> NSMenu = { NSMenu() }
        var draggedOut: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        private var mouseDownAt: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func isOverClose(_ point: NSPoint) -> Bool {
            closeEdge == .leading ? point.x < closeWidth : point.x > bounds.maxX - closeWidth
        }

        /// Whether the pointer is over the tab, as last told to SwiftUI.
        private var isInside = false

        /// Checks where the pointer actually is. Entered and exited events alone leave a tab
        /// shaded when it moves out from under a still pointer (a tab closed or moved, the
        /// row scrolled) and miss the tab that moves in. `always` tells SwiftUI even if nothing
        /// seems to have changed: a row moved by a drag can get a fresh view, whose own record
        /// differs from the row's.
        private func syncHover(leaving: Bool = false, always: Bool = false) {
            var inside = false
            if !leaving, let window, !isHiddenOrHasHiddenAncestor {
                // Its bounds as well as what's visible: in a scrolling list, the visible rect
                // can come back as the whole list's.
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                inside = bounds.contains(point) && visibleRect.contains(point)
            }
            guard always || inside != isInside else { return }
            isInside = inside
            // Not in the middle of SwiftUI laying out the row, which this can be called from.
            DispatchQueue.main.async { [weak self] in
                guard let self, isInside == inside else { return }
                onHover(inside)
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
            syncHover()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncHover()
            NotificationCenter.default.removeObserver(self, name: Self.dragEnded, object: nil)
            if window != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(otherDragEnded), name: Self.dragEnded, object: nil)
            }
        }

        /// A row was dragged: the rows it passed over missed the pointer leaving them (a drag
        /// takes the mouse events), so all of them look again.
        private static let dragEnded = Notification.Name("org.mikegallagher.point.tabRowDragEnded")

        @objc private func otherDragEnded() { syncHover(always: true) }

        override func mouseEntered(with event: NSEvent) { syncHover() }
        override func mouseMoved(with event: NSEvent) { syncHover() }
        override func mouseExited(with event: NSEvent) { syncHover(leaving: true) }

        override func mouseDown(with event: NSEvent) {
            mouseDownAt = event.locationInWindow
            if selectsOnPress, !isOverClose(convert(event.locationInWindow, from: nil)) { select() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownAt, let tabID else { return }
            let point = event.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
            mouseDownAt = nil
            Trace.mark("tab drag began: \(title)")
            let item = NSPasteboardItem()
            item.setString(tabID.uuidString, forType: TabDrag.pasteboardType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            dragging.setDraggingFrame(bounds, contents: snapshot())
            let session = beginDraggingSession(with: [dragging], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            guard mouseDownAt != nil else { return }
            mouseDownAt = nil
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            if isOverClose(point) { close() } else if !selectsOnPress { select() }
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            // After the drop has rearranged the rows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NotificationCenter.default.post(name: Self.dragEnded, object: nil) }
            // Taken somewhere outside the list (the page, the other side's bar): close it.
            if operation != [], let window, !window.frame.contains(screenPoint) { draggedOut() }
        }

        /// The tab as drawn, to drag.
        private func snapshot() -> NSImage {
            guard let root = window?.contentView else { return NSImage(size: bounds.size) }
            let rect = convert(bounds, to: root)
            guard let rep = root.bitmapImageRepForCachingDisplay(in: rect) else { return NSImage(size: bounds.size) }
            root.cacheDisplay(in: rect, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }
    }
}

// MARK: Dragging tabs

/// A dragged tab, on the drag's pasteboard by its ID, which is looked up in the window it's
/// dropped in (a tab from another window isn't found there, so isn't taken).
enum TabDrag {
    static let pasteboardType = NSPasteboard.PasteboardType("org.mikegallagher.point.tab")

    static func tab(on pasteboard: NSPasteboard) -> VaultModel.NoteTab.ID? {
        pasteboard.string(forType: pasteboardType).flatMap(UUID.init(uuidString:))
    }
}

/// Somewhere a dragged tab can be dropped. In AppKit, because SwiftUI's drop targets never
/// see a drag started in AppKit (as tabs' are). Put it behind the content: it takes no
/// clicks, and a drag finds it through the views in front.
struct TabDropArea: NSViewRepresentable {
    /// As a tab moves over the area: whether it would be taken, given the tab, where it is
    /// (from the area's top left) and the area's size. The tab is nil when the drag leaves.
    let hover: @MainActor (VaultModel.NoteTab.ID?, CGPoint, CGSize) -> Bool
    let drop: @MainActor (VaultModel.NoteTab.ID, CGPoint, CGSize) -> Bool

    func makeNSView(context: Context) -> DropView { DropView() }

    func updateNSView(_ view: DropView, context: Context) {
        view.hover = hover
        view.drop = drop
    }

    final class DropView: NSView {
        var hover: @MainActor (VaultModel.NoteTab.ID?, CGPoint, CGSize) -> Bool = { _, _, _ in false }
        var drop: @MainActor (VaultModel.NoteTab.ID, CGPoint, CGSize) -> Bool = { _, _, _ in false }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([TabDrag.pasteboardType])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func location(_ info: NSDraggingInfo) -> CGPoint { convert(info.draggingLocation, from: nil) }

        private func operation(_ info: NSDraggingInfo) -> NSDragOperation {
            guard let id = TabDrag.tab(on: info.draggingPasteboard) else { return [] }
            return hover(id, location(info), bounds.size) ? .move : []
        }

        override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
            let operation = operation(info)
            Trace.mark("tab drag entered a drop area: \(operation == .move ? "taken" : "refused")")
            return operation
        }

        override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { operation(info) }

        override func draggingExited(_ info: NSDraggingInfo?) { _ = hover(nil, .zero, bounds.size) }

        override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
            guard let id = TabDrag.tab(on: info.draggingPasteboard) else { return false }
            let point = location(info)
            _ = hover(nil, .zero, bounds.size)
            let taken = drop(id, point, bounds.size)
            Trace.mark("tab dropped: \(taken ? "taken" : "refused")")
            return taken
        }

        override func draggingEnded(_ info: NSDraggingInfo) { _ = hover(nil, .zero, bounds.size) }
    }
}

/// Where on a side's page a dragged tab would go.
enum PaneDropZone {
    /// One half of an unsplit window: a new side, there.
    case leading, trailing
    /// The other side of a split: into its tabs.
    case whole

    /// Where a tab dropped at `x` on a side's page `width` wide would go, if anywhere.
    @MainActor init?(tab id: VaultModel.NoteTab.ID, overPane paneIndex: Int, x: CGFloat, width: CGFloat, in model: VaultModel) {
        guard let source = model.location(ofTab: id) else { return nil }
        if model.isSplit {
            guard source.pane != paneIndex else { return nil }
            self = .whole
        } else {
            guard model.canSplit(withTab: id) else { return nil }
            self = x < width / 2 ? .leading : .trailing
        }
    }

    /// Splits the window or moves the tab to the other side.
    @MainActor func drop(_ id: VaultModel.NoteTab.ID, onPane paneIndex: Int, in model: VaultModel) {
        switch self {
        case .leading: model.split(withTab: id, onLeading: true)
        case .trailing: model.split(withTab: id, onLeading: false)
        case .whole: model.moveTab(id, intoPane: paneIndex)
        }
    }
}

/// Shades the part of a page a dragged tab would go to.
struct PaneDropHighlight: View {
    let zone: PaneDropZone?

    var body: some View {
        GeometryReader { geometry in
            if let zone {
                let half = geometry.size.width / 2
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                    }
                    .padding(6)
                    .frame(width: zone == .whole ? geometry.size.width : half)
                    .offset(x: zone == .trailing ? half : 0)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: zone)
    }
}

/// A menu item that runs a closure.
final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void

    init(_ title: String, block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { block() }
}

/// Empty space in a top bar that moves the window when dragged and zooms it when
/// double-clicked, as a title bar does.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
