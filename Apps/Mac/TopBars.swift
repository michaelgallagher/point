import AppKit
import IndexKit
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

    /// Where the sidebar button's square starts past the window buttons: its symbol as far
    /// from the zoom button as the close button is from the window's edge. Measured from the
    /// window.
    @MainActor static func windowButtonsInset(for window: NSWindow?) -> CGFloat? {
        guard let window, let zoom = window.standardWindowButton(.zoomButton),
              let close = window.standardWindowButton(.closeButton) else { return nil }
        let edgeGap = close.convert(close.bounds, to: nil).minX
        return (zoom.convert(zoom.bounds, to: nil).maxX + edgeGap - sidebarSymbolInset).rounded()
    }

    /// How far the bar starts past the window buttons while the sidebar is hidden: the sidebar
    /// button (see `SidebarSplitController`), then the gap.
    static let sidebarButtonWidth: CGFloat = iconSize + buttonSpacing
    /// A side narrower than this can't spare the room for its bar's buttons. The sidebar
    /// button goes while the sidebar's hidden (⌘S, the View menu and a swipe still show it),
    /// and the split button goes into the side's "…" menu. In a split, each side by its own
    /// width.
    static let sidebarButtonHidingWidth: CGFloat = 580
    /// The gap between buttons in a bar (the HStack's spacing): small, since the icons have no
    /// bezels and their own squares hold some space around each symbol.
    static let buttonSpacing: CGFloat = 4
    /// How far a side's bar starts past the sidebar's edge or the divider, and ends before the
    /// window's edge, so its buttons never touch either.
    static let edgeInset: CGFloat = 6
    /// How far the nearest drawn part of a button is from the divider beside it: the sidebar
    /// button's symbol on the sidebar's side, the back arrow on the notes' side. Measured from
    /// the symbols, not their squares, as the sidebar symbol nearly fills its square and the
    /// chevron is thin in the middle of its own.
    static let dividerGap: CGFloat = 16
    private static let sidebarSymbolWidth: CGFloat = 20
    /// How far the sidebar symbol is inside its square.
    static let sidebarSymbolInset: CGFloat = (iconSize - sidebarSymbolWidth) / 2
    private static let chevronWidth: CGFloat = 8
    /// The sidebar button's square from the sidebar's edge.
    static let sidebarButtonInset: CGFloat = dividerGap - (iconSize - sidebarSymbolWidth) / 2
    /// Back's square from the divider, at its width.
    static func arrowInset(width: CGFloat) -> CGFloat { max(dividerGap - (width - chevronWidth) / 2, 0) }

    /// The top bar's background, in every layout: the page's own colour.
    static let barColor = Color(nsColor: .textBackgroundColor)
    /// Shading under something hovered in a bar: a little darker than the bar.
    static let selectedTabColor = Color.primary.opacity(0.07)
    /// Shading under a hovered button on glass, a little stronger to show on the lighter glass.
    static let hoverColor = Color.primary.opacity(0.1)

    /// A bar's icons: the symbol alone, in a square this size, shaded on hover.
    static let iconSize: CGFloat = 28
    static let iconFontSize: CGFloat = 15
    /// The sidebar button's symbol, a wide box of thin lines, reads small at 15 points beside
    /// the window buttons; a little larger, it's nearer the system's own sidebar button.
    static let sidebarIconFontSize: CGFloat = 17
    /// Back and forward's width each in a narrow bar: the chevrons are thin, and at the full
    /// square they look far apart.
    static let narrowArrowWidth: CGFloat = 22
    static let iconCornerRadius: CGFloat = 7

    /// How much of a side the top bar covers: the title bar's row alone.
    @MainActor static func cover(for pane: VaultModel.NotePane, in model: VaultModel) -> CGFloat {
        model.topBarHeight
    }

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
                        // Just left of the sidebar button (see `TopBar.sidebarButtonInset`).
                        .padding(.trailing, TopBar.sidebarButtonInset + TopBar.sidebarButtonWidth)
                }
            }
    }
}

/// The two-column note list's top bar: the folder or tag's name (and, in the trash, emptying
/// it), and under the name how many notes there are; then sort and the filter tools' button,
/// clear of the sidebar button at its end. See-through, like a
/// side's bar: the list scrolls up beneath it and blurs (see `BarEdgeScrollView`). Its empty
/// space drags the window.
struct NoteListTopBar: View {
    @EnvironmentObject private var model: VaultModel
    @ObservedObject var filterTools: FilterToolsState
    @ObservedObject var listCount: ListCountState

    /// How the notes are sorted: not in the trash, nor Recent (in the order opened).
    private var showsSort: Bool { model.place != .trash && model.place != .recent }

    var body: some View {
        HStack(spacing: TopBar.buttonSpacing) {
            // The name, and under it how many notes there are (how many the filter leaves, while
            // anything filters).
            VStack(alignment: .leading, spacing: 1) {
                Text(model.place == .allNotes ? (model.root?.lastPathComponent ?? "Notes") : model.title(for: model.place))
                    .font(.headline)
                    .lineLimit(1)
                Text(model.listCountLabel(shown: listCount.shown))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.place == .trash { EmptyTrashButton() }
            if showsSort { SortButton() }
            if model.place != .trash {
                // Shows or hides the filter tools under the bar; coloured while anything
                // filters the list, so it shows even with the tools away.
                let filtering = model.isFiltering || model.showsOnlyUnread
                BarIcon(symbol: "line.3.horizontal.decrease", label: "Filter",
                        help: filterTools.isShown ? "Hide filter" : "Filter these notes (⇧⌘F)",
                        tint: filtering ? .accentColor : nil, isSelected: filterTools.isShown) {
                    model.setFilterTools(shown: !filterTools.isShown)
                }
                .accessibilityAddTraits(filterTools.isShown ? .isSelected : [])
            }
        }
        // In line with the list's text: its date headings, and its notes when not grouped
        // (the source list's row inset, then the row's own padding).
        .padding(.leading, 24)
        // The filter button just left of the sidebar button.
        .padding(.trailing, TopBar.sidebarButtonInset + TopBar.sidebarButtonWidth)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
    }
}

extension VaultModel {
    /// How much is here, as the sidebar counts it: notes, or for the lists of tags and types,
    /// how many there are. While anything filters the notes, how many it leaves of them all
    /// ("12 of 340 notes"), `shown` being how many the list shows.
    func listCountLabel(shown: Int?) -> String {
        let count = noteCount(of: place)
        let noun = switch place {
        case .trash: count == 1 ? "item" : "items"
        case .types: count == 1 ? "type" : "types"
        case .tags: count == 1 ? "tag" : "tags"
        default: count == 1 ? "note" : "notes"
        }
        if let shown, isFiltering || showsOnlyUnread, place != .types, place != .tags {
            return "\(shown.formatted()) of \(count.formatted()) \(noun)"
        }
        return "\(count.formatted()) \(noun)"
    }
}

/// One side's top bar, in one row in the title bar: back and forward, its tabs (always, even
/// just one), and its menu, which on the last side ends with Split. (Where the note is, is on
/// the page, above its title: see `PanePath`.) Its empty space moves the window. Narrower than
/// `TopBar.sidebarButtonHidingWidth`, the sidebar button and the arrows give their room to
/// the tabs.
struct PaneTabBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// With the sidebar hidden, the first side's tabs start past the window buttons and the
    /// sidebar button.
    private var startsAtWindowEdge: Bool { paneIndex == 0 && !model.showsNoteList }

    /// The tabs' row: past the window buttons and the sidebar button when the sidebar is
    /// hidden; otherwise just past the sidebar's edge or the divider.
    private var leadingInset: CGFloat {
        // Back's chevron as far from the divider as the sidebar button's symbol is on the
        // other side of it (see `TopBar.dividerGap`).
        guard startsAtWindowEdge else { return showsArrows ? TopBar.arrowInset(width: TopBar.narrowArrowWidth) : TopBar.edgeInset }
        return model.windowButtonsInset + (model.hidesSidebarButtonForWidth ? 0 : TopBar.sidebarButtonWidth)
    }

    @State private var sideWidth: CGFloat = 0

    private func sideResized(_ width: CGFloat) {
        sideWidth = width
        if paneIndex == 0 { model.firstSideResized(width) }
    }

    /// The last side's "…" menu ends with Split (or Close Split): the split has no button
    /// of its own.
    private var isLastSide: Bool { paneIndex == model.panes.count - 1 }
    /// Back and forward, unless the side is narrow: then they give their room to the tabs, as
    /// the sidebar button does.
    private var showsArrows: Bool { !model.isNarrow(sideWidth: sideWidth) }

    /// As far from the side's edge as from the top of the bar, so the menu's hover square sits
    /// evenly in the corner.
    private var trailingInset: CGFloat { max((model.topBarHeight - TopBar.iconSize) / 2, TopBar.edgeInset) }

    var body: some View {
        // One row, in the title bar: back and forward, the tabs, and the side's menu. The tabs'
        // row has its own inset around them, so less between: a tab is the same gap from a
        // button as buttons are from each other.
        HStack(spacing: TopBar.buttonSpacing - PaneTabs.inset) {
            if showsArrows {
                BackForwardButtons(paneIndex: paneIndex, isNarrow: true)
                    .transition(.opacity)
            }
            PaneTabs(pane: pane, paneIndex: paneIndex)
            if model.note(pane.tab.noteID) != nil || isLastSide || !showsArrows {
                PaneMenuButton(pane: pane, paneIndex: paneIndex, includesSplit: isLastSide, includesHistory: !showsArrows)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingInset)
        // As the sidebar slides, on the window's own curve and duration, so the bar's contents
        // glide with the notes, staying clear of the window buttons, rather than jumping. (Only
        // an animation moves during the window's animation; nothing is laid out again.)
        .animation(.easeInOut(duration: 0.25), value: startsAtWindowEdge)
        // And as the sidebar button and the arrows fade, so the tabs take or give up their room.
        .animation(.easeInOut(duration: 0.25), value: model.hidesSidebarButtonForWidth)
        .animation(.easeInOut(duration: 0.25), value: showsArrows)
        .padding(.trailing, trailingInset)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        // The side's whole width: the first side's decides whether the sidebar button shows
        // (see `VaultModel.notesAreNarrow`).
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { sideResized(geometry.size.width) }
                .onChange(of: geometry.size.width) { sideResized($0) }
        })
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

/// The folders a note is in, from the vault's top ("Projects / Archive"), above its title on
/// the page, each clickable to show it in the sidebar or the explorer. Empty for a note at the
/// vault's top.
struct PanePath: View {
    @ObservedObject var model: VaultModel
    let note: Note
    /// The room the path had when the sidebar last settled. While it slides, the path keeps the
    /// folding it had (clipped at its end if need be) and folds again once it stops: changing
    /// on the way, its parts crossed over each other as the bar moved.
    @State private var settledWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                do {
                    let width = model.isSidebarSliding && settledWidth > 0 ? settledWidth : geometry.size.width
                    // By what each part is; parts shown or hidden come and go at once.
                    ForEach(Self.identified(Self.parts(of: note, toFit: width)), id: \.id) { item in
                        segment(item.part)
                            .transition(.identity)
                    }
                }
            }
            // While sliding, at its own width, clipped at its end, rather than squeezed into
            // less room (which pushed its parts over each other).
            .fixedSize(horizontal: model.isSidebarSliding, vertical: false)
            // From its leading edge (wider than its room, it would otherwise be centred in it).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .help(note.id)
            .contentTransition(.identity)
            .onAppear { settledWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { width in
                if !model.isSidebarSliding { settledWidth = width }
            }
            .onChange(of: model.isSidebarSliding) { sliding in
                if !sliding { settledWidth = geometry.size.width }
            }
        }
        .clipped()
    }

    /// A piece of the path, as laid out.
    enum Part: Equatable {
        case folder(name: String, path: String)
        /// Folders folded away, by path.
        case folded([String])
        case separator
    }

    /// The parts, each with an identity: a folder by its path, a separator by what comes after it.
    static func identified(_ parts: [Part]) -> [(id: String, part: Part)] {
        func id(_ part: Part) -> String {
            switch part {
            case .folder(_, let path): "folder:" + path
            case .folded: "folded"
            case .separator: "separator"
            }
        }
        return parts.enumerated().map { index, part in
            if case .separator = part, index + 1 < parts.count { return ("before:" + id(parts[index + 1]), part) }
            return (id(part), part)
        }
    }

    @ViewBuilder private func segment(_ part: Part) -> some View {
        switch part {
        case .folder(let name, let path):
            PathButton(text: name, help: "Show “\(name)”") { model.reveal(folder: path) }
        case .folded(let paths):
            Text("…")
                .font(Self.font)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Self.padding)
                .help(paths.joined(separator: "\n"))
        case .separator:
            Text("/")
                .font(Self.font)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Self.separatorPadding)
        }
    }

    // MARK: Fitting

    static let font = Font.system(size: nsFontSize)
    private static let nsFontSize: CGFloat = 13
    /// Around each folder: room for the shading on hover.
    static let padding: CGFloat = 5
    static let separatorPadding: CGFloat = 1

    private static func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: nsFontSize)]).width)
    }

    private static func width(of part: Part) -> CGFloat {
        switch part {
        case .folder(let name, _): width(name) + padding * 2
        case .folded: width("…") + padding * 2
        case .separator: width("/") + separatorPadding * 2
        }
    }

    /// The longest form of the path that fits: every folder; then the first folder, "…" and
    /// fewer and fewer of the rest, ending with the innermost; then "…" and the innermost;
    /// then "…" alone.
    static func parts(of note: Note, toFit available: CGFloat) -> [Part] {
        let names = note.id.split(separator: "/").dropLast().map(String.init)
        guard !names.isEmpty else { return [] }
        let paths = names.indices.map { names[...$0].joined(separator: "/") }
        let folders = zip(names, paths).map { Part.folder(name: $0, path: $1) }

        func joined(_ pieces: [Part]) -> [Part] {
            pieces.enumerated().flatMap { index, piece in index == 0 ? [piece] : [.separator, piece] }
        }
        func fits(_ parts: [Part]) -> Bool { parts.map(width(of:)).reduce(0, +) <= available }

        let whole = joined(folders)
        if fits(whole) { return whole }
        // Fold the folders between the first and the innermost, one more each time.
        if folders.count > 2 {
            for hidden in 1...(folders.count - 2) {
                let parts = joined([folders[0], .folded(Array(paths[1...hidden]))] + folders.dropFirst(1 + hidden))
                if fits(parts) { return parts }
            }
        }
        if folders.count > 1 {
            let parts = joined([.folded(Array(paths.dropLast())), folders[folders.count - 1]])
            if fits(parts) { return parts }
        }
        return [.folded(paths)]
    }
}

/// A folder in a side's path, taking clicks in AppKit (as the bar's other controls do),
/// shaded on hover.
private struct PathButton: View {
    let text: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(text)
            .font(PanePath.font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, PanePath.padding)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? TopBar.selectedTabColor : .clear)
            }
            .allowsHitTesting(false)
            .background(ClickArea(help: help, action: action))
            .onHover { isHovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

// MARK: The tabs

/// A side's tabs: plain titles, the current one on a soft grey fill. Each tab is as wide as
/// its title, up to `TabLayout.widest`; tabs never shrink to fit. When they don't all fit,
/// the row scrolls sideways, keeping the current tab in view, and fades at an end with tabs
/// scrolled out of sight beyond it. Each tab's close button is after its title. Right-click a
/// tab for its menu;
/// drag it along the row, to the other side's row or page, or to one half of the page to
/// split the window.
struct PaneTabs: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// The rail around the tabs: a tab inside it is as tall as a sidebar row's selection (a
    /// medium sidebar row) and the filter field.
    static let height: CGFloat = PaneTab.height + inset * 2
    static let cornerRadius: CGFloat = 10
    /// Between a tab and the rail around it.
    static let inset: CGFloat = 2
    static let spacing: CGFloat = 2
    /// How far in from an end the tabs fade, where the row's scrolled past them.
    static let fadeWidth: CGFloat = 24

    /// How far the row's scrolled along, and moving it.
    @StateObject private var scroll = TabRowScroll()
    /// Where the scroll view's to go. The view's own state: kept in `scroll`, published, each
    /// move the scroll view reported back laid the row out again, which moved it again.
    @State private var position = ScrollPosition(x: 0)

    /// Where each tab starts along the row.
    private static func starts(_ layout: TabLayout) -> [CGFloat] {
        var x = inset
        return layout.widths.map { width in
            defer { x += width + spacing }
            return x
        }
    }

    /// Where the current tab sits along the row.
    private func current(_ layout: TabLayout) -> TabRowScroll.Span? {
        let index = min(max(pane.current, 0), layout.widths.count - 1)
        guard index >= 0 else { return nil }
        let start = Self.starts(layout)[index]
        return TabRowScroll.Span(start: start, end: start + layout.widths[index])
    }

    var body: some View {
        GeometryReader { geometry in
            let titles = pane.tabs.map { model.note($0.noteID)?.title ?? model.store.image($0.noteID)?.name ?? "New tab" }
            let layout = TabLayout(titles: titles)
            let shown = min(layout.rowWidth, geometry.size.width)
            let _ = scroll.measure(shown: shown, rowWidth: layout.rowWidth)
            let offset = min(max(scroll.offset, 0), max(layout.rowWidth - shown, 0))
            let starts = Self.starts(layout)
            // Fades only at an end with tabs scrolled out of sight beyond it.
            let fadesLeading = offset > 0.5
            let fadesTrailing = offset + shown < layout.rowWidth - 0.5
            // A scroll view, only as wide as the tabs, so the bar's empty space still moves the
            // window. A press on a tab doesn't: the window holds still while the pointer's over
            // one (`WindowMoveGuard`).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                        // The part of the tab in sight, in its own points: only that takes
                        // clicks and drops.
                        let shownPart = (offset - starts[index])...(offset + shown - starts[index])
                        PaneTab(
                            id: tab.id,
                            title: layout.labels[index],
                            help: tab.noteID ?? "",
                            isCurrent: index == pane.current,
                            isActiveSide: paneIndex == model.activePane,
                            showsLine: index + 1 < pane.tabs.count && index != pane.current && index + 1 != pane.current,
                            width: layout.widths[index],
                            shownPart: shownPart,
                            select: { model.selectTab(index, inPane: paneIndex) },
                            close: { model.closeTab(index, inPane: paneIndex) },
                            menu: { TabMenu.menu(for: index, tab: tab, inPane: paneIndex, model: model) }
                        )
                        .modifier(TabDropTarget(paneIndex: paneIndex, index: index, shownPart: shownPart))
                        .id(tab.id)
                    }
                }
                .padding(Self.inset)
                // The gaps between tabs, and around them, take a press and do nothing with it,
                // rather than it going through to the bar, which moves the window.
                .background(HoldsWindowStill(part: .presses))
                .fixedSize(horizontal: true, vertical: false)
                .animation(.easeInOut(duration: 0.2), value: pane.current)
            }
            .scrollDisabled(layout.rowWidth <= shown)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in scroll.scrolled(to: x) }
            // A mouse's wheel, up and down, scrolls it too (the trackpad's sideways swipe is the
            // scroll view's own).
            .background(WheelArea { delta in
                guard layout.rowWidth > shown else { return false }
                scroll.scroll(by: delta)
                return true
            })
            .frame(width: shown, alignment: .leading)
            // While the pointer's anywhere over the row, the window holds still. Tracked here,
            // outside the scroll view: AppKit doesn't move the tracking areas of the views
            // inside as SwiftUI scrolls them, so the row's far end, scrolled into sight, had
            // none, and a press on a tab there dragged the window too.
            .background(HoldsWindowStill(part: .pointer))
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fadesLeading ? Self.fadeWidth : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fadesTrailing ? Self.fadeWidth : 0)
                }
            }
            // The current tab always in view, clear of the fades.
            // The tab's place is passed in as the value that changed: values the closure reads
            // from the view are the ones from before the change, which revealed the tab chosen
            // before this one.
            .onAppear {
                let position = $position
                scroll.move = { x in position.wrappedValue.scrollTo(x: x) }
                scroll.reveal(current(layout), margin: Self.fadeWidth, animated: false)
            }
            .onChange(of: current(layout)) { scroll.reveal($0, margin: Self.fadeWidth, animated: true) }
            .onChange(of: geometry.size.width) { _ in scroll.reveal(current(layout), margin: Self.fadeWidth, animated: false) }
        }
        .frame(height: Self.height)
    }
}

/// How far a side's tab row is scrolled along, and scrolling it to show the current tab.
@MainActor
final class TabRowScroll: ObservableObject {
    /// A tab's place along the row.
    struct Span: Equatable {
        var start: CGFloat
        var end: CGFloat
    }

    /// As the scroll view last reported it.
    @Published private(set) var offset: CGFloat = 0
    /// Scrolls the row to a place along it.
    var move: (CGFloat) -> Void = { _ in }
    /// The row's size as last laid out.
    private var shown: CGFloat = 0
    private var rowWidth: CGFloat = 0
    /// Bumped by each reveal, so only the latest, if it has to wait, goes ahead.
    private var request = 0

    private var maxOffset: CGFloat { max(rowWidth - shown, 0) }

    /// Notes the row's size as it's laid out (not something the view draws from).
    func measure(shown: CGFloat, rowWidth: CGFloat) {
        self.shown = shown
        self.rowWidth = rowWidth
    }

    func scrolled(to offset: CGFloat) {
        if abs(offset - self.offset) > 0.25 { self.offset = offset }
    }

    func scroll(by delta: CGFloat) {
        request += 1 // A reveal waiting on the mouse gives way.
        let target = min(max(offset + delta, 0), maxOffset)
        if abs(target - offset) > 0.5 { move(target) }
    }

    /// Shows `span`, `margin` clear of each end, moving the least it can. While the mouse
    /// button is down it waits: the row moving under a click on a half-hidden tab made it jump,
    /// or start dragging the tab.
    func reveal(_ span: Span?, margin: CGFloat, animated: Bool) {
        guard let span else { return }
        request += 1
        attempt(span, margin: margin, animated: animated, request: request)
    }

    private func attempt(_ span: Span, margin: CGFloat, animated: Bool, request: Int) {
        guard request == self.request else { return }
        guard NSEvent.pressedMouseButtons == 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.attempt(span, margin: margin, animated: animated, request: request)
            }
            return
        }
        let now = min(offset, maxOffset)
        var target = now
        if span.start - margin < now { target = span.start - margin } else if span.end + margin > now + shown { target = span.end + margin - shown }
        target = min(max(target, 0), maxOffset)
        guard abs(target - now) > 0.5 else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { move(target) }
        } else {
            move(target)
        }
    }
}

/// Takes a mouse wheel's scrolling, up and down, over it, for a row that scrolls sideways,
/// when `scrolled` says it was used. Takes no clicks. A trackpad's scrolling is left alone.
private struct WheelArea: NSViewRepresentable {
    /// By how much (positive towards the row's end); false if it can't scroll.
    let scrolled: (CGFloat) -> Bool

    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) { view.scrolled = scrolled }

    final class WheelView: NSView {
        var scrolled: (CGFloat) -> Bool = { _ in false }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // Watched for, as the tabs over it take the events.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window === window, !event.hasPreciseScrollingDeltas,
                      event.scrollingDeltaY != 0, event.scrollingDeltaX == 0,
                      bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
                // The wheel up goes back towards the row's start.
                return scrolled(-event.scrollingDeltaY * 10) ? nil : event
            }
        }
    }
}

/// How wide each of a side's tabs is, and what each says: as wide as its whole title, up to
/// `widest`, whatever room there is (the row scrolls when they don't all fit). A longer title
/// is fitted to its tab (see `TabLabels`).
@MainActor
struct TabLayout {
    var labels: [String]
    var widths: [CGFloat]
    var rowWidth: CGFloat

    /// The widest a tab gets: a longer title is cut to fit.
    static let widest: CGFloat = 200

    private static let font = NSFont.systemFont(ofSize: PaneTab.fontSize)

    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    init(titles: [String]) {
        let padding = PaneTab.leadingPadding + PaneTab.closeWidth
        let rooms = titles.map { min(Self.textWidth($0) + padding, Self.widest) }
        labels = TabLabels.fit(titles, rooms: rooms.map { $0 - padding })
        // As wide as what each shows: a title fitted to a tab can come out shorter than the
        // room it had ("9 Nov" for "Weeknote - 2026-11-09"), which left a gap before the ×.
        widths = labels.map { min(Self.textWidth($0) + padding, Self.widest) }
        rowWidth = widths.reduce(0, +) + PaneTabs.spacing * CGFloat(max(titles.count - 1, 0)) + PaneTabs.inset * 2
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

private struct PaneTab: View {
    let id: VaultModel.NoteTab.ID
    let title: String
    let help: String
    let isCurrent: Bool
    /// False on the side of a split not being worked on, whose current tab is less raised.
    let isActiveSide: Bool
    /// Whether to draw the line after this tab: between two tabs neither of which is current.
    let showsLine: Bool
    let width: CGFloat
    /// The part of it in sight, in its own points.
    let shownPart: ClosedRange<CGFloat>
    let select: () -> Void
    let close: () -> Void
    let menu: () -> NSMenu
    @State private var isHovering = false

    /// As tall as a sidebar row's selection, as measured from the window on macOS 26.
    static let height: CGFloat = 32
    static let cornerRadius: CGFloat = PaneTabs.cornerRadius - PaneTabs.inset
    static let fontSize: CGFloat = 13
    /// Before the title.
    static let leadingPadding: CGFloat = 10
    /// The close button's room, after the title, with a little more after it than before. It
    /// always shows, so nothing moves on hover.
    static let closeWidth: CGFloat = closeGap + 20 + closeTrailing
    /// Between the title and the ×.
    static let closeGap: CGFloat = 5
    static let closeTrailing: CGFloat = 4
    /// The title, raised from the middle: centred by its line height, which counts room for
    /// descenders, it looked low.
    static let titleRaise: CGFloat = 1

    /// The current tab: flat, a grey on the bar. Fainter on the side of a split not being
    /// worked on.
    private var selectedColor: Color {
        Color.primary.opacity(isActiveSide ? 0.1 : 0.05)
    }

    var body: some View {
        Text(title)
            .font(.system(size: Self.fontSize))
            .foregroundStyle((isCurrent && isActiveSide) || isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .offset(y: -Self.titleRaise)
            .padding(.leading, Self.leadingPadding)
            .padding(.trailing, Self.closeWidth)
            .frame(width: width, height: Self.height, alignment: .leading)
            .overlay(alignment: .trailing) {
                // On every tab, darker on hover. Clicked through the tab's mouse area, which
                // knows where it is.
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: Self.closeWidth - Self.closeGap - Self.closeTrailing, height: Self.height)
                    .padding(.trailing, Self.closeTrailing)
            }
            .overlay(alignment: .trailing) {
                if showsLine {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1, height: 14)
                        .offset(x: (PaneTabs.spacing + 1) / 2)
                }
            }
            .background {
                // No rail: the current tab a flat grey on the bar.
                if isCurrent {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(selectedColor)
                }
            }
            .allowsHitTesting(false) // Clicks go to the tab's mouse area, below.
            // Clicks, drags, hover and the menu are handled in AppKit: the tabs sit where a
            // title bar would, and there the window takes any drag not claimed first.
            .background(TabMouseArea(id: id, title: title, select: select, close: close, closeEdge: .trailing,
                                     closeWidth: Self.closeWidth - Self.closeGap, selectsOnPress: true, shownPart: shownPart,
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
    /// The part of the tab in sight, in its own points.
    let shownPart: ClosedRange<CGFloat>
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
            .background(TabDropArea(shownPart: shownPart) { id, point, size in
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

/// Back and forward through the side's current tab's history: two plain chevrons, side by side.
private struct BackForwardButtons: View {
    @EnvironmentObject private var model: VaultModel
    let paneIndex: Int
    /// In a narrow bar, closer together (see `TopBar.narrowArrowWidth`).
    var isNarrow = false

    var body: some View {
        let width = isNarrow ? TopBar.narrowArrowWidth : TopBar.iconSize
        HStack(spacing: 0) {
            BarIcon(symbol: "chevron.left", label: "Back", help: "Back (⌘[)", enabled: model.canTravel(back: true, inPane: paneIndex), weight: .medium, width: width) {
                model.travel(back: true, inPane: paneIndex)
            }
            BarIcon(symbol: "chevron.right", label: "Forward", help: "Forward (⌘])", enabled: model.canTravel(back: false, inPane: paneIndex), weight: .medium, width: width) {
                model.travel(back: false, inPane: paneIndex)
            }
        }
    }
}

/// The side's menu, at the end of its second row: what can be done with its note, then deleting
/// it.
private struct PaneMenuButton: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int
    /// Split or Close Split, last, while the split button is hidden.
    var includesSplit = false
    /// Back and Forward, first, while the arrows are hidden (a narrow side).
    var includesHistory = false

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
        // The split has its own button (but see `includesSplit`).
        if let note = model.note(pane.tab.noteID) {
            let bookmark = BlockMenuItem("Bookmark") { model.toggleBookmark(note.id) }
            bookmark.state = model.isBookmarked(note.id) ? .on : .off
            menu.addItem(bookmark)
            menu.addItem(BlockMenuItem("Move File…") { model.moving = .init([note]) })
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
            menu.addItem(BlockMenuItem("Delete File") { model.moveToTrash(note) })
        }
        // Last, when the split button has no room.
        if includesSplit {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            if model.isSplit {
                menu.addItem(BlockMenuItem("Close Split") { model.mergeIntoTabs() })
            } else {
                menu.addItem(BlockMenuItem("Split") { model.toggleSplit() })
            }
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

/// Filters the list from a menu, at its foot: only the unread (kept for the place, where its
/// notes say when they were read, as Mail's filter does), when edited, and the tags and
/// properties' values the notes here have. Each choice is a token in the field, ticked here
/// while it's there; choosing it again takes it away. Filled and coloured while anything
/// filters the list.
struct FilterMenuButton: View {
    @EnvironmentObject private var model: VaultModel
    /// The filter's terms (see `FilterToolsState`): watched here, not through the model.
    @EnvironmentObject private var filterTools: FilterToolsState
    /// At a list's foot, the menu opens above it; at its top, below.
    var opensUpward = true

    /// How many tags and values a submenu lists, most used first.
    private static let listed = 25

    private func menu() -> NSMenu { Self.menu(for: model) }

    static func menu(for model: VaultModel) -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, term: String, count: Int? = nil) -> NSMenuItem {
            let item = BlockMenuItem(title) { model.toggleFilterToken(term) }
            item.state = model.hasFilterToken(term) ? .on : model.hasFilterToken(FilterText.toggled(term)) ? .mixed : .off
            if let count {
                let text = NSMutableAttributedString(string: title + "  ")
                text.append(NSAttributedString(string: count.formatted(), attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                item.attributedTitle = text
            }
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            items.forEach(sub.addItem)
            parent.submenu = sub
            if items.contains(where: { $0.state != .off }) { parent.state = .on }
            return parent
        }
        if model.tracksReading(model.place) {
            let unread = BlockMenuItem("Only Unread") { model.toggleOnlyUnread() }
            unread.state = model.showsOnlyUnread ? .on : .off
            menu.addItem(unread)
            menu.addItem(.separator())
        }
        menu.addItem(submenu("Edited", FilterText.editedTerms.map { item($0.label.capitalized, term: $0.term) }))
        let facets = model.filterFacets ?? FilterFacets()
        if !facets.tags.isEmpty {
            menu.addItem(submenu("Tags", facets.tags.prefix(Self.listed).map { item("#" + $0.value, term: FilterText.term(tag: $0.value), count: $0.count) }))
        }
        let properties = facets.properties.filter { FilterText.canWrite(property: $0.name) }
        if !properties.isEmpty {
            menu.addItem(.separator())
            for property in properties.prefix(12) {
                let name = property.name.lowercased()
                var items: [NSMenuItem] = []
                // Values worth picking: some given by more than one note. (Dates and prose
                // differ note by note.)
                if property.values.contains(where: { $0.count > 1 }) {
                    items += property.values.prefix(Self.listed).map { item($0.value, term: FilterText.term(property: name, value: $0.value), count: $0.count) }
                    items.append(.separator())
                }
                items.append(item("Has Any Value", term: "has:" + name))
                items.append(item("Has No Value", term: "-has:" + name))
                menu.addItem(submenu(property.name.prefix(1).uppercased() + property.name.dropFirst(), items))
            }
        }
        if model.isFiltering || model.showsOnlyUnread {
            menu.addItem(.separator())
            menu.addItem(BlockMenuItem(model.appliedFilterCount > 1 ? "Clear Filters" : "Clear Filter") {
                model.clearAllFilters()
            })
        }
        return menu
    }

    var body: some View {
        let isOn = model.showsOnlyUnread || !model.filterTokens.isEmpty
        // In two columns the bar's filter button has the funnel lines; this menu, beside the
        // field, is the list of filters to pick from.
        let symbol = model.browsingStyle == .twoColumns ? "list.bullet.badge.ellipsis"
            : isOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
        BarMenu("Filter", systemImage: symbol,
                help: "Filter these notes", opensUpward: opensUpward, tint: isOn ? .accentColor : nil, menu: menu)
            .onAppear { _ = model.filterFacets }
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A bar's icon as drawn: just the symbol, no glass or bezel, on a rounded square shaded on
/// hover (as Safari's and Finder's toolbar icons are without Liquid Glass).
struct BarIconFace: View {
    let symbol: String
    var enabled = true
    var isHovering = false
    var weight: Font.Weight = .regular
    var width = TopBar.iconSize
    var fontSize = TopBar.iconFontSize
    /// A colour for an icon that's on (a filter in use), in place of the usual grey.
    var tint: Color?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(!enabled ? AnyShapeStyle(.quaternary) : tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .brightness(isHovering && enabled ? -0.15 : 0)
            .frame(width: width, height: TopBar.iconSize)
            .background {
                RoundedRectangle(cornerRadius: TopBar.iconCornerRadius, style: .continuous)
                    .fill(isHovering && enabled ? TopBar.selectedTabColor : .clear)
            }
    }
}

/// A plain icon in a bar, shaded on hover. Clicks are taken by an AppKit view under it: in the
/// title bar's area, the window takes a click on a SwiftUI button and moves itself instead.
struct BarIcon: View {
    let symbol: String
    let label: String
    let help: String
    var enabled = true
    var weight: Font.Weight = .regular
    var width = TopBar.iconSize
    var fontSize = TopBar.iconFontSize
    var tint: Color?
    /// Shaded as a pressed toggle (the filter tools showing).
    var isSelected = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        BarIconFace(symbol: symbol, enabled: enabled, isHovering: isHovering || isSelected, weight: weight, width: width, fontSize: fontSize, tint: tint)
            .allowsHitTesting(false) // The click area below takes the clicks.
            // Hover from the click area, which checks where the pointer really is: SwiftUI's
            // own missed the pointer leaving as the button moved away from it (the sidebar
            // button, as the sidebar slides), and left it shaded.
            .background(ClickArea(enabled: enabled, help: help, action: action, onHover: { isHovering = $0 }))
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
    /// Whether the pointer is over it.
    var onHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        view.isEnabled = enabled
        view.action = action
        view.toolTip = help
        view.onHover = onHover
    }

    final class ClickView: NSView {
        var isEnabled = true
        var action: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        private var isPressed = false
        /// Whether the pointer is over it, as last told.
        private var isInside = false

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Looks where the pointer is, rather than trusting entered and exited alone, which
        /// miss a button moving out from under a still pointer.
        func syncHover(leaving: Bool = false) {
            var inside = false
            if !leaving, let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                inside = bounds.contains(point) && visibleRect.contains(point)
            }
            guard inside != isInside else { return }
            isInside = inside
            WindowMoveGuard.pointer(isOver: inside, self)
            DispatchQueue.main.async { [weak self] in
                guard let self, isInside == inside else { return }
                onHover(inside)
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            WindowMoveGuard.leaving(self)
            super.viewWillMove(toWindow: newWindow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
            syncHover()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                // The window moving or resizing under a still pointer (the sidebar sliding).
                for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didResignKeyNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
                }
            }
            syncHover()
        }

        @objc private func windowChanged() { syncHover() }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            syncHover()
        }

        override func mouseEntered(with event: NSEvent) { syncHover() }
        override func mouseMoved(with event: NSEvent) { syncHover() }
        override func mouseExited(with event: NSEvent) { syncHover(leaving: true) }

        override func mouseDown(with event: NSEvent) { isPressed = isEnabled }

        override func mouseUp(with event: NSEvent) {
            defer { isPressed = false }
            // Only if the pointer is still over it, as with any button.
            guard isPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action()
            // What the click did may move the button, or what's around it, away from the
            // pointer, without a word: look again once things have settled.
            for delay in [0.05, 0.3, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.syncHover() }
            }
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
        private let moveGuard = WindowMoveGuard.Tracker()

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            moveGuard.track(self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            WindowMoveGuard.leaving(self)
            super.viewWillMove(toWindow: newWindow)
        }

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

/// An icon button in a bar: the icon alone (see `BarIconFace`).
struct BarButton: View {
    let title: String
    let systemImage: String
    let help: String
    var fontSize = TopBar.iconFontSize
    let action: () -> Void

    init(_ title: String, systemImage: String, help: String, fontSize: CGFloat = TopBar.iconFontSize, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.fontSize = fontSize
        self.action = action
    }

    var body: some View {
        BarIcon(symbol: systemImage, label: title, help: help, fontSize: fontSize, action: action)
    }
}

/// A `BarButton` that opens a menu below itself.
struct BarMenu: View {
    let title: String
    let systemImage: String
    let help: String
    var opensUpward = false
    /// A colour for an icon that's on (a filter in use).
    var tint: Color?
    let menu: () -> NSMenu
    @State private var anchor = MenuAnchor.Holder()
    @State private var isHovering = false

    init(_ title: String, systemImage: String, help: String, opensUpward: Bool = false, tint: Color? = nil, menu: @escaping () -> NSMenu) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.opensUpward = opensUpward
        self.tint = tint
        self.menu = menu
    }

    var body: some View {
        if #available(macOS 26, *) {
            // Drawn as the other bar icons are; over it, an invisible system pull-down takes
            // the click, so macOS places the menu and opens it from the button.
            BarIconFace(symbol: systemImage, isHovering: isHovering, tint: tint)
                .overlay {
                    GlassPullDown(title: title, systemImage: systemImage, help: help, opensUpward: opensUpward, menu: menu)
                }
                .onHover { isHovering = $0 }
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
        private let moveGuard = WindowMoveGuard.Tracker()

        // In the title bar's area the window would take the click and move itself.
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            moveGuard.track(self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            WindowMoveGuard.leaving(self)
            super.viewWillMove(toWindow: newWindow)
        }

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
    /// The part of it in sight, across, in its own points, if not all of it: only that takes
    /// clicks and shows hover.
    var shownPart: ClosedRange<CGFloat>? = nil
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
        view.shownPart = shownPart
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
        var shownPart: ClosedRange<CGFloat>? {
            didSet { if shownPart != oldValue { syncHover() } }
        }
        var makeMenu: () -> NSMenu = { NSMenu() }
        var draggedOut: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        private var mouseDownAt: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Whether a point (in its own points) is on the part in sight.
        private func isShown(_ point: NSPoint) -> Bool { shownPart?.contains(point.x) ?? true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview, isShown(convert(point, from: superview)) else { return nil }
            return super.hitTest(point)
        }

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
                inside = bounds.contains(point) && isShown(point)
            }
            guard always || inside != isInside else { return }
            isInside = inside
            WindowMoveGuard.pointer(isOver: inside, self)
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

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            WindowMoveGuard.leaving(self)
            super.viewWillMove(toWindow: newWindow)
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
            Trace.mark("tab drag began: \(title), window at \(window.map { NSStringFromPoint($0.frame.origin) } ?? "none")")
            let item = NSPasteboardItem()
            item.setString(tabID.uuidString, forType: TabDrag.pasteboardType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            dragging.setDraggingFrame(bounds, contents: snapshot())
            let session = beginDraggingSession(with: [dragging], event: event, source: self)
            // Dropped where nothing takes it, it just goes: the drop is found here, not by
            // AppKit, which counts every drop as having missed.
            session.animatesToStartingPositionsOnCancelOrFail = false
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

        /// The drop area the tab is over.
        private weak var dragArea: TabDropArea.DropView?

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            guard let tabID else { return }
            let area = TabDropArea.DropView.area(at: screenPoint)
            if area !== dragArea {
                dragArea?.dragLeft()
                dragArea = area
            }
            area?.dragMoved(tabID, to: screenPoint)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragArea?.dragLeft()
            dragArea = nil
            // Given up with Escape: nothing moves. AppKit can't say so itself, as no view takes
            // the drop the AppKit way, so every drag ends as if it missed.
            let cancelled = NSApp.currentEvent.map { $0.type == .keyDown && $0.keyCode == 53 } ?? false
            let area = cancelled ? nil : TabDropArea.DropView.area(at: screenPoint)
            let taken = tabID.flatMap { id in area?.dropped(id, at: screenPoint) } ?? false
            Trace.mark("tab drag ended: \(taken ? "dropped" : "not dropped"), window at \(window.map { NSStringFromPoint($0.frame.origin) } ?? "none")")
            // After the drop has rearranged the rows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NotificationCenter.default.post(name: Self.dragEnded, object: nil) }
            // Taken in another window: close it here.
            if taken, let window, area?.window !== window { draggedOut() }
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
/// see a drag started in AppKit (as tabs' are). Put it behind the content: it takes no clicks.
/// The dragged tab finds it itself, as the smallest area under the pointer (a tab before the
/// bar it's in, the bar before the page beneath): AppKit's own search for where a drag is
/// over missed areas inside the tabs' scrolling row, and the page under the note.
struct TabDropArea: NSViewRepresentable {
    /// The part of it in sight, across, in its own points, if not all of it.
    var shownPart: ClosedRange<CGFloat>? = nil
    /// Behind something laid over the page in the same window (the palette, the related
    /// notes panel): a tab let go over it goes nowhere, not to the page beneath, which is
    /// otherwise still an area under the pointer.
    var blocks = false
    /// As a tab moves over the area: whether it would be taken, given the tab, where it is
    /// (from the area's top left) and the area's size. The tab is nil when the drag leaves.
    let hover: @MainActor (VaultModel.NoteTab.ID?, CGPoint, CGSize) -> Bool
    let drop: @MainActor (VaultModel.NoteTab.ID, CGPoint, CGSize) -> Bool

    /// An area that takes no tab, and keeps any beneath it from taking one.
    static var blocking: TabDropArea {
        TabDropArea(blocks: true, hover: { _, _, _ in false }, drop: { _, _, _ in false })
    }

    func makeNSView(context: Context) -> DropView { DropView() }

    func updateNSView(_ view: DropView, context: Context) {
        view.hover = hover
        view.drop = drop
        view.shownPart = shownPart
        view.blocks = blocks
    }

    final class DropView: NSView {
        var hover: @MainActor (VaultModel.NoteTab.ID?, CGPoint, CGSize) -> Bool = { _, _, _ in false }
        var drop: @MainActor (VaultModel.NoteTab.ID, CGPoint, CGSize) -> Bool = { _, _, _ in false }
        var shownPart: ClosedRange<CGFloat>?
        var blocks = false

        /// Every area in a window.
        private static let all = NSHashTable<DropView>.weakObjects()

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { Self.all.add(self) } else { Self.all.remove(self) }
        }

        /// The part of it showing, in its window: not a tab scrolled out of sight. From its
        /// bounds, not `visibleRect`, which for a view SwiftUI hosts can be far larger than
        /// the view (the whole row, or the whole window), so every area seemed to be under
        /// the pointer, and the first answered.
        private var shownRect: NSRect {
            var rect = bounds
            if let part = shownPart {
                let minX = max(rect.minX, part.lowerBound), maxX = min(rect.maxX, part.upperBound)
                rect = maxX > minX ? NSRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height) : .zero
            }
            return convert(rect, to: nil)
        }

        /// The area under a point on the screen, in the window in front there; none if
        /// something laid over the page is there.
        static func area(at screenPoint: NSPoint) -> DropView? {
            // The app's own windows, front to back (not the window the drag's image is in).
            guard let front = NSApp.orderedWindows.first(where: { $0.isVisible && $0.frame.contains(screenPoint) }) else { return nil }
            let under = all.allObjects.filter { area in
                guard let window = area.window, window === front, !area.isHiddenOrHasHiddenAncestor else { return false }
                let point = window.convertPoint(fromScreen: screenPoint)
                let rect = area.shownRect
                return !rect.isEmpty && rect.contains(point)
            }
            guard !under.contains(where: \.blocks) else { return nil }
            return under.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }

        private func location(_ screenPoint: NSPoint) -> CGPoint {
            guard let window else { return .zero }
            return convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        }

        func dragMoved(_ id: VaultModel.NoteTab.ID, to screenPoint: NSPoint) {
            _ = hover(id, location(screenPoint), bounds.size)
        }

        func dragLeft() { _ = hover(nil, .zero, bounds.size) }

        func dropped(_ id: VaultModel.NoteTab.ID, at screenPoint: NSPoint) -> Bool {
            dragLeft()
            let taken = drop(id, location(screenPoint), bounds.size)
            Trace.mark("tab dropped: \(taken ? "taken" : "refused") on \(NSStringFromRect(shownRect)) at \(NSStringFromPoint(location(screenPoint)))")
            return taken
        }
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
///
/// The window may be unmovable for a moment, while the pointer is over a tab or a button (see
/// `WindowMoveGuard`), so this lets it move for its own drag whatever.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.performZoom(nil)
            } else {
                let wasMovable = window.isMovable
                window.isMovable = true
                window.performDrag(with: event)
                window.isMovable = wasMovable
            }
        }
    }
}

/// Keeps a press on Point's own controls in the title bar's strip (a tab, a bar button) the
/// control's. macOS decides a press there moves the window as the button goes down, before
/// the view sees it, and doesn't ask the views (`mouseDownCanMoveWindow`), so dragging a tab
/// dragged the window. So while the pointer is over one, its window is unmovable; everywhere
/// else it moves as any window does: by its bars, from Window › Move & Resize and the green
/// button, and to the screen's edges to tile, which an unmovable window can't.
@MainActor
enum WindowMoveGuard {
    /// The controls the pointer is over.
    private static let over = NSHashTable<NSView>.weakObjects()

    /// The pointer came over `view`, or left it.
    static func pointer(isOver inside: Bool, _ view: NSView) {
        guard inside != over.contains(view) else { return }
        if inside { over.add(view) } else { over.remove(view) }
        update(view.window)
    }

    /// `view` is leaving its window (a tab closed under the pointer, say): it no longer holds
    /// the window still. Called while it still has its window.
    static func leaving(_ view: NSView) {
        guard over.contains(view) else { return }
        over.remove(view)
        update(view.window)
    }

    private static func update(_ window: NSWindow?) {
        guard let window else { return }
        let movable = !over.allObjects.contains { $0.window === window }
        if window.isMovable != movable { window.isMovable = movable }
    }

    /// For a control that doesn't follow the pointer itself: its own tracking area, apart from
    /// any the control has (which it may remove).
    @MainActor
    final class Tracker: NSObject {
        private weak var view: NSView?
        private var area: NSTrackingArea?

        func track(_ view: NSView) {
            self.view = view
            if let area { view.removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            view.addTrackingArea(area)
            self.area = area
        }

        // Named for AppKit: as a plain object's methods, Swift would call them
        // `mouseEnteredWith:` and `mouseExitedWith:`, which a tracking area never calls.
        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
            if let view { WindowMoveGuard.pointer(isOver: true, view) }
        }

        @objc(mouseExited:) func mouseExited(with event: NSEvent) {
            if let view { WindowMoveGuard.pointer(isOver: false, view) }
        }
    }
}

/// Keeps the window still over a stretch of the title bar's strip: while the pointer's over it
/// (see `WindowMoveGuard`), or by taking a press there and doing nothing with it. Scrolling
/// goes on up to whatever scrolls.
struct HoldsWindowStill: NSViewRepresentable {
    enum Part { case pointer, presses }
    let part: Part

    func makeNSView(context: Context) -> GuardView { GuardView(part: part) }
    func updateNSView(_ view: GuardView, context: Context) {}

    final class GuardView: NSView {
        private let part: Part
        private let moveGuard = WindowMoveGuard.Tracker()

        init(part: Part) {
            self.part = part
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Not used") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            part == .presses ? super.hitTest(point) : nil
        }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {}

        // AppKit asks a view to update its tracking areas only once it has some.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, part == .pointer { moveGuard.track(self) }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if part == .pointer { moveGuard.track(self) }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            WindowMoveGuard.leaving(self)
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
