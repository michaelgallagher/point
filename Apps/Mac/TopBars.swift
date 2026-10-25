import AppKit
import SwiftUI
import VaultKit

/// The window has no title bar or toolbar of its own: the sidebar and each side of the split
/// have their own bar along the top edge, so a split runs the full height of the window.
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

    /// The system's sidebar button: the round glass platter the window's toolbar draws it in
    /// (the toolbar holds nothing else). Found by class name, so nil if AppKit changes it.
    @MainActor static func sidebarButton(in window: NSWindow?) -> NSView? {
        guard let root = window?.contentView?.superview else { return nil }
        func find(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "NSToolbarPlatterView" { return view }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        return find(root)
    }

    /// The right edge of the system's sidebar button, in the window. Where the system puts it
    /// varies with the window, so the first side's bar starts from it while the sidebar is
    /// hidden.
    @MainActor static func sidebarButtonEnd(for window: NSWindow?) -> CGFloat? {
        guard let button = sidebarButton(in: window), !button.isHiddenOrHasHiddenAncestor else { return nil }
        return button.convert(button.bounds, to: nil).maxX
    }

    /// How far the bar starts past the window buttons while the sidebar is hidden, if the
    /// sidebar button can't be found: room for it, then the gap.
    static let sidebarButtonWidth: CGFloat = 45
    /// The gap between buttons in a bar (the HStack's spacing), and how far a side's bar
    /// starts past the sidebar's edge or the divider, so its buttons never touch either.
    static let buttonSpacing: CGFloat = 8

    /// The top bar's background, in every layout: the page's own colour.
    static let barColor = Color(nsColor: .textBackgroundColor)
    /// Shading under something hovered in a bar or the tab list: a little darker than the bar.
    static let selectedTabColor = Color.primary.opacity(0.07)

}

/// The sidebar's top bar: room for the window buttons and the system's sidebar button,
/// which sits at its trailing edge. Its empty space drags the window.
struct SidebarTopBar: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        Color.clear
            .frame(height: model.topBarHeight)
            .frame(maxWidth: .infinity)
            .background(WindowDragArea())
    }
}

/// One side's top bar: back and forward, where the side's note is ("Projects / Point / Tabs
/// idea"), then a button listing the side's tabs and a button for the split. Tabs aren't
/// shown as tabs: they're reached from that list, the palette (⌃Tab) and ⇧⌘[ / ⇧⌘].
struct PaneTopBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// With the sidebar hidden, the first side starts past the window buttons and the
    /// system's sidebar button.
    private var startsAtWindowEdge: Bool { paneIndex == 0 && (!model.showsNoteList || model.isFocused) }

    /// Past the window buttons and the sidebar button when the sidebar is hidden; otherwise
    /// just past the sidebar's edge or the divider.
    private var leadingInset: CGFloat {
        guard startsAtWindowEdge else { return TopBar.buttonSpacing }
        return model.sidebarButtonEnd.map { $0 + TopBar.buttonSpacing } ?? model.windowButtonsInset + TopBar.sidebarButtonWidth
    }

    var body: some View {
        HStack(spacing: TopBar.buttonSpacing) {
            BackForwardButtons(pane: pane, paneIndex: paneIndex)
            PanePath(pane: pane, paneIndex: paneIndex)
                .padding(.horizontal, 4)
            TabListButton(pane: pane)
            if model.isSplit {
                BarButton("Close This Side", systemImage: "xmark", help: "Close This Side") { model.closePane(paneIndex) }
            } else {
                BarButton("Split", systemImage: "rectangle.split.2x1", help: "Split (⇧⌘S)") { model.toggleSplit() }
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, TopBar.buttonSpacing)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        // A tab (dragged from a tab list) dropped on the bar goes at the end of this side's tabs.
        .background(TabDropArea { id, _, _ in
            id.map { model.location(ofTab: $0) != nil } ?? false
        } drop: { id, _, _ in
            guard model.location(ofTab: id) != nil, model.panes.indices.contains(paneIndex) else { return false }
            model.moveTab(id, toPane: paneIndex, at: model.panes[paneIndex].tabs.count)
            return true
        })
        .background { barBackground }
    }

    /// Before macOS 26, the page's colour with a hairline under it. From 26, nothing: the
    /// system's hard scroll edge effect blurs the note scrolling beneath, with its own edge.
    @ViewBuilder private var barBackground: some View {
        if #available(macOS 26, *) {
            Color.clear
        } else {
            TopBar.barColor
                .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        }
    }
}

// MARK: The path

/// Where a side's note is in the vault, then its name: "Projects / Point / Tabs idea". The
/// folders are dimmed, and clicking one shows it (in the sidebar, or the explorer); clicking
/// the name renames the note. When it doesn't fit, the folders after the first fold into "…"
/// one at a time; only then is the name cut, in its middle. With a split, the side not being
/// worked on is dimmed.
struct PanePath: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int
    @State private var isRenaming = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if let note = model.note(pane.tab.noteID) {
                    let parts = Self.parts(of: note, toFit: geometry.size.width)
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        segment(part, note: note)
                    }
                } else {
                    Text("New Tab")
                        .font(Self.font(.name))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, Self.padding)
                }
            }
            .frame(maxHeight: .infinity)
            .help(model.note(pane.tab.noteID)?.id ?? "")
        }
        .opacity(model.isSplit && paneIndex != model.activePane ? 0.55 : 1)
        .onChange(of: pane.tab.noteID) { _ in isRenaming = false }
    }

    /// A piece of the path, as laid out.
    enum Part: Equatable {
        case folder(name: String, path: String)
        /// Folders folded away, by path.
        case folded([String])
        case separator
        /// The note's name, cut in its middle if `fits` is false.
        case name(String, fits: Bool)
    }

    @ViewBuilder private func segment(_ part: Part, note: Note) -> some View {
        switch part {
        case .folder(let name, let path):
            PathButton(text: name, style: .folder, help: "Show “\(name)”") { model.reveal(folder: path) }
        case .folded(let paths):
            Text("…")
                .font(Self.font(.folder))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Self.padding)
                .help(paths.joined(separator: "\n"))
        case .separator:
            Text("/")
                .font(Self.font(.folder))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Self.separatorPadding)
        case .name(let name, let fits):
            if isRenaming {
                PathRenameField(note: note, isRenaming: $isRenaming)
            } else {
                PathButton(text: name, style: .name, cutsInMiddle: !fits, help: "Rename") { isRenaming = true }
            }
        }
    }

    // MARK: Fitting

    enum Style { case folder, name }

    static func font(_ style: Style) -> Font {
        style == .name ? .system(size: nsFontSize, weight: .medium) : .system(size: nsFontSize)
    }

    private static let nsFontSize: CGFloat = 13
    /// Around each folder and the name: room for the shading on hover.
    static let padding: CGFloat = 5
    static let separatorPadding: CGFloat = 1

    private static func width(_ text: String, _ style: Style) -> CGFloat {
        let font = NSFont.systemFont(ofSize: nsFontSize, weight: style == .name ? .medium : .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func width(of part: Part) -> CGFloat {
        switch part {
        case .folder(let name, _): width(name, .folder) + padding * 2
        case .folded: width("…", .folder) + padding * 2
        case .separator: width("/", .folder) + separatorPadding * 2
        case .name(let name, _): width(name, .name) + padding * 2
        }
    }

    /// The longest form of the path that fits: every folder; then the first folder, "…" and
    /// fewer and fewer of the rest; then the first folder, "…" and the name, cut to fit.
    static func parts(of note: Note, toFit available: CGFloat) -> [Part] {
        let names = note.id.split(separator: "/").dropLast().map(String.init)
        let paths = names.indices.map { names[...$0].joined(separator: "/") }
        let folders = zip(names, paths).map { Part.folder(name: $0, path: $1) }
        let name = Part.name(note.title, fits: true)

        func joined(_ pieces: [Part]) -> [Part] {
            pieces.enumerated().flatMap { index, piece in index == 0 ? [piece] : [.separator, piece] }
        }
        func fits(_ parts: [Part]) -> Bool { parts.map(width(of:)).reduce(0, +) <= available }

        let whole = joined(folders + [name])
        if fits(whole) || folders.isEmpty { return fits(whole) ? whole : [.name(note.title, fits: false)] }
        // Fold the folders after the first, one more each time, from the second on.
        if folders.count > 1 {
            for hidden in 1..<folders.count {
                let kept = folders.dropFirst(1 + hidden)
                let parts = joined([folders[0], .folded(Array(paths[1...hidden]))] + kept + [name])
                if fits(parts) { return parts }
            }
        }
        let first = folders.count > 1 ? [folders[0], .folded(Array(paths[1...]))] : [folders[0]]
        return joined(first + [.name(note.title, fits: false)])
    }
}

/// A folder or the note's name in a side's path, taking clicks in AppKit (as the bar's other
/// controls do), shaded on hover.
private struct PathButton: View {
    let text: String
    let style: PanePath.Style
    var cutsInMiddle = false
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(text)
            .font(PanePath.font(style))
            .foregroundStyle(style == .name ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .fixedSize(horizontal: !cutsInMiddle, vertical: false)
            .padding(.horizontal, PanePath.padding)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? TopBar.selectedTabColor : .clear)
            }
            .layoutPriority(style == .name ? 0 : 1) // The name is what's cut.
            .allowsHitTesting(false)
            .background(ClickArea(help: help, action: action))
            .onHover { isHovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// The note's name in a side's path, being renamed: Return or clicking away renames the note
/// (and its file, updating links), Escape puts it back, as with the title on the page.
private struct PathRenameField: View {
    @EnvironmentObject private var model: VaultModel
    let note: Note
    @Binding var isRenaming: Bool
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .font(PanePath.font(.name))
            .padding(.horizontal, PanePath.padding)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(TopBar.selectedTabColor))
            .frame(minWidth: 120, maxWidth: 360)
            .focused($isFocused)
            .onSubmit { commit() }
            .onExitCommand { isRenaming = false }
            .onChange(of: isFocused) { focused in
                if !focused, isRenaming { commit() }
            }
            .onAppear {
                draft = note.title
                DispatchQueue.main.async { isFocused = true }
            }
    }

    private func commit() {
        isRenaming = false
        let title = NoteFiles.sanitizedTitle(draft)
        guard !title.isEmpty, title != note.title else { return }
        model.rename(note, to: title)
    }
}

// MARK: The tab list

/// Lists the side's tabs in a small menu. Dimmed with only one tab, rather than hidden, so
/// the bar doesn't shift.
private struct TabListButton: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    /// When the menu last closed, so the click outside that closes it, if it lands on this
    /// button, doesn't open it straight away again.
    @State private var closedAt = Date.distantPast

    var body: some View {
        let isShown = Binding(
            get: { model.tabMenuPane == pane.id },
            set: { shown in
                if shown {
                    model.tabMenuPane = pane.id
                } else if model.tabMenuPane == pane.id {
                    model.tabMenuPane = nil
                    closedAt = Date()
                }
            })
        BarButton("Tabs", systemImage: "square.stack", help: "Show Tab List (⇧⌘T)") {
            guard Date().timeIntervalSince(closedAt) > 0.3 else { return }
            isShown.wrappedValue.toggle()
        }
        .disabled(pane.tabs.count < 2)
        // How many tabs this side has open, once there's more than one.
        .overlay(alignment: .topTrailing) {
            if pane.tabs.count > 1 {
                Text("\(pane.tabs.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 4, y: -2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue("\(pane.tabs.count) tabs")
        .popover(isPresented: isShown, arrowEdge: .bottom) {
            TabMenu(paneID: pane.id)
                .environmentObject(model)
        }
    }
}

/// A side's tabs, in order, the current one ticked. Click one to go to it; hover for its
/// close button, right-click for more. Drag a row up or down to reorder, onto the page to
/// split the window or onto the other side. Keys: ↑↓ move, Return goes to the tab, ⌫ or ⌘W
/// closes it, Escape closes the menu.
struct TabMenu: View {
    @EnvironmentObject private var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    /// The row picked with the arrow keys, by tab.
    @State private var highlighted: VaultModel.NoteTab.ID?

    static let rowHeight: CGFloat = 28
    static let width: CGFloat = 280

    var body: some View {
        if let p = model.paneIndex(paneID) {
            let pane = model.panes[p]
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabMenuRow(
                                id: tab.id,
                                title: model.note(tab.noteID)?.title ?? "New Tab",
                                isCurrent: index == pane.current,
                                isHighlighted: highlighted == tab.id,
                                select: { go(to: index, inPane: p) },
                                close: { model.closeTab(index, inPane: p) },
                                menu: { menu(for: index, tab: tab, inPane: p) },
                                draggedOut: { model.tabMenuPane = nil }
                            )
                            .modifier(TabMenuDropTarget(paneIndex: p, index: index))
                        }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(pane.tabs.count) * Self.rowHeight + 12, 360))
                Divider()
                NewTabRow { model.tabMenuPane = nil; model.newTab(inPane: p) }
                    .padding(6)
            }
            .frame(width: Self.width)
            .background(TabMenuKeys(
                move: { step in move(step, in: pane) },
                choose: {
                    guard let index = highlightedIndex(in: pane) else { return }
                    go(to: index, inPane: p)
                },
                close: {
                    guard let index = highlightedIndex(in: pane) else { return }
                    // Highlight its neighbour, so ⌫ can be pressed again.
                    let next = pane.tabs.indices.contains(index + 1) ? index + 1 : index - 1
                    highlighted = pane.tabs.indices.contains(next) ? pane.tabs[next].id : nil
                    model.closeTab(index, inPane: p)
                },
                dismiss: { model.tabMenuPane = nil }
            ))
            // Down to one tab, there's nothing to switch to, and ⌫ again would close the
            // window's last tab (and the window).
            .onChange(of: pane.tabs.count) { count in
                if count < 2 { model.tabMenuPane = nil }
            }
        }
    }

    private func highlightedIndex(in pane: VaultModel.NotePane) -> Int? {
        pane.tabs.firstIndex { $0.id == highlighted }
    }

    /// The first arrow press starts from the current tab.
    private func move(_ step: Int, in pane: VaultModel.NotePane) {
        let from = highlightedIndex(in: pane) ?? pane.current
        let to = highlighted == nil ? pane.current + step : from + step
        highlighted = pane.tabs[max(0, min(to, pane.tabs.count - 1))].id
    }

    private func go(to index: Int, inPane p: Int) {
        model.tabMenuPane = nil
        model.selectTab(index, inPane: p)
    }

    /// A row's right-click menu: what a tab's menu used to offer.
    private func menu(for index: Int, tab: VaultModel.NoteTab, inPane p: Int) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(BlockMenuItem("Close Tab") { model.closeTab(index, inPane: p) })
        menu.addItem(BlockMenuItem("Close Other Tabs") { model.closeOtherTabs(index, inPane: p) })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(model.isSplit ? "Move to Other Side" : "Move to New Split") {
            model.tabMenuPane = nil
            model.moveTabToOtherSide(index, inPane: p)
        })
        if model.isSplit {
            menu.addItem(BlockMenuItem("Merge Both Sides into Tabs") {
                model.tabMenuPane = nil
                model.mergeIntoTabs()
            })
        }
        if let id = tab.noteID {
            menu.addItem(BlockMenuItem("Open in New Window") {
                model.tabMenuPane = nil
                model.closeTab(index, inPane: p)
                model.openWindowHandler?(id)
            })
        }
        return menu
    }
}

private struct TabMenuRow: View {
    let id: VaultModel.NoteTab.ID
    let title: String
    let isCurrent: Bool
    let isHighlighted: Bool
    let select: () -> Void
    let close: () -> Void
    let menu: () -> NSMenu
    let draggedOut: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
                .opacity(isCurrent ? 1 : 0)
                .allowsHitTesting(false)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false) // Clicks go to the row's mouse area, below.
            // Clicked through the row's mouse area, which knows where it is (a SwiftUI button
            // here doesn't reliably get the click before the AppKit view behind it).
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: Self.closeWidth, height: 18)
                .foregroundStyle(isHighlighted ? .white : .secondary)
                .opacity(isHovering || isHighlighted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 8)
        .frame(height: TabMenu.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : isHovering ? TopBar.selectedTabColor : .clear)
                .allowsHitTesting(false)
        }
        .background(TabMouseArea(id: id, title: title, select: select, close: close, closeWidth: Self.closeWidth + 8,
                                 menu: menu, draggedOut: draggedOut, isHovering: $isHovering))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: "Close Tab") { close() }
    }

    static let closeWidth: CGFloat = 18
}

private struct NewTabRow: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text("New Tab")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("⌘T")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: TabMenu.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? TopBar.selectedTabColor : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The tab menu's keys, taken by an AppKit view that holds the keyboard while the menu shows.
private struct TabMenuKeys: NSViewRepresentable {
    let move: (Int) -> Void
    let choose: () -> Void
    let close: () -> Void
    let dismiss: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.move = move
        view.choose = choose
        view.close = close
        view.dismiss = dismiss
    }

    final class KeyView: NSView {
        var move: (Int) -> Void = { _ in }
        var choose: () -> Void = {}
        var close: () -> Void = {}
        var dismiss: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: move(-1) // ↑
            case 125: move(1) // ↓
            case 36, 76: choose() // Return, Enter
            case 51, 117: close() // ⌫, ⌦
            case 53: dismiss() // Escape
            default: super.keyDown(with: event)
            }
        }

        /// ⌘W closes the highlighted tab, rather than reaching the File menu.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w" {
                close()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// A row dropped on another row goes above or below it, whichever half it's over. The tab
/// shown doesn't change.
private struct TabMenuDropTarget: ViewModifier {
    @EnvironmentObject private var model: VaultModel
    let paneIndex: Int
    let index: Int
    @State private var edge: VerticalEdge?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if edge != nil {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                        .offset(y: edge == .top ? -1 : 1)
                }
            }
            .background(TabDropArea { id, point, size in
                edge = id.flatMap { model.location(ofTab: $0) } == nil ? nil : (point.y < size.height / 2 ? .top : .bottom)
                return edge != nil
            } drop: { id, point, size in
                edge = nil
                guard model.location(ofTab: id) != nil else { return false }
                model.moveTab(id, toPane: paneIndex, at: point.y < size.height / 2 ? index : index + 1, selects: false)
                return true
            })
    }
}

/// Back and forward through the side's current tab's history, together, before the tabs: a glass
/// capsule from macOS 26. Clicks are taken by AppKit views under the arrows, as the tabs'
/// are: in the title bar's area, the window takes a click on a SwiftUI button and moves
/// itself instead.
private struct BackForwardButtons: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    var body: some View {
        let pair = HStack(spacing: 0) {
            arrow("chevron.left", label: "Back", help: "Back (⌘[)", enabled: model.canTravel(back: true, inPane: paneIndex)) {
                model.travel(back: true, inPane: paneIndex)
            }
            arrow("chevron.right", label: "Forward", help: "Forward (⌘])", enabled: model.canTravel(back: false, inPane: paneIndex)) {
                model.travel(back: false, inPane: paneIndex)
            }
        }
        if #available(macOS 26, *) {
            pair
                .padding(.horizontal, 4)
                .frame(height: 36)
                .glassEffect(.regular, in: Capsule())
        } else {
            pair
        }
    }

    private func arrow(_ symbol: String, label: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(enabled ? .primary : .tertiary)
            .frame(width: 28, height: 28)
            .allowsHitTesting(false) // The click area below takes the clicks.
            .background(ClickArea(enabled: enabled, help: help, action: action))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
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

/// A tab list row's mouse handling: a click selects it, a drag picks it up, a right-click
/// shows its menu. Dropped outside the list, the list closes.
private struct TabMouseArea: NSViewRepresentable {
    let id: VaultModel.NoteTab.ID
    let title: String
    let select: () -> Void
    /// A click this close to the trailing edge, where the close button is, closes the tab.
    let close: () -> Void
    let closeWidth: CGFloat
    let menu: () -> NSMenu
    let draggedOut: () -> Void
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TabMouseView { TabMouseView() }

    func updateNSView(_ view: TabMouseView, context: Context) {
        view.tabID = id
        view.title = title
        view.select = select
        view.close = close
        view.closeWidth = closeWidth
        view.makeMenu = menu
        view.draggedOut = draggedOut
        view.onHover = { isHovering = $0 }
    }

    final class TabMouseView: NSView, NSDraggingSource {
        var tabID: VaultModel.NoteTab.ID?
        var title = ""
        var select: () -> Void = {}
        var close: () -> Void = {}
        var closeWidth: CGFloat = 0
        var makeMenu: () -> NSMenu = { NSMenu() }
        var draggedOut: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        private var mouseDownAt: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

        override func mouseDown(with event: NSEvent) { mouseDownAt = event.locationInWindow }

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

        /// On mouse up, as in a menu, so a row can be dragged without going to its tab.
        override func mouseUp(with event: NSEvent) {
            guard mouseDownAt != nil else { return }
            mouseDownAt = nil
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            if point.x > bounds.maxX - closeWidth { close() } else { select() }
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
