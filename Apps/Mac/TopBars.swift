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

    /// The system's sidebar button, just past the window buttons while the sidebar is hidden.
    static let sidebarButtonWidth: CGFloat = 48

    /// The top bar's background, in every layout: the page's own colour.
    static let barColor = Color(nsColor: .textBackgroundColor)
    /// The selected tab: a little darker than the bar.
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

/// One side's top bar: its tabs, and a button for the split.
struct PaneTopBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// With the sidebar hidden, the first side starts past the window buttons and the
    /// system's sidebar button.
    private var startsAtWindowEdge: Bool { paneIndex == 0 && (!model.showsNoteList || model.isFocused) }

    /// A tab dragged over the bar's empty space, which would go at the end.
    @State private var isAppendTarget = false

    var body: some View {
        HStack(spacing: 8) {
            // Always tabs, even just one: the note's path is above its title, in the page.
            NoteTabs(pane: pane, paneIndex: paneIndex, isAppendTarget: isAppendTarget)
            Spacer(minLength: 0)
            if model.isSplit {
                BarButton("Close This Side", systemImage: "xmark", help: "Close This Side") { model.closePane(paneIndex) }
            } else {
                BarButton("Split", systemImage: "rectangle.split.2x1", help: "Split (⇧⌘S)") { model.toggleSplit() }
            }
        }
        // Less the tab row's own inset (room for the drop marker at its ends).
        .padding(.leading, (startsAtWindowEdge ? model.windowButtonsInset + TopBar.sidebarButtonWidth : 16) - NoteTabs.inset)
        .padding(.trailing, 8)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        // A tab dropped past the last one goes at the end.
        .background(TabDropArea { id, _, _ in
            isAppendTarget = id.map { model.location(ofTab: $0) != nil } ?? false
            return isAppendTarget
        } drop: { id, _, _ in
            isAppendTarget = false
            guard model.location(ofTab: id) != nil, model.panes.indices.contains(paneIndex) else { return false }
            model.moveTab(id, toPane: paneIndex, at: model.panes[paneIndex].tabs.count)
            return true
        })
        .background(TopBar.barColor)
        // A hairline, like the one under the properties.
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
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
            // A round glass button, as in a toolbar.
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .frame(width: 20, height: 20)
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

/// A side's tabs, drawn by Imprint: the current tab a raised, page-coloured tab (it is the
/// page below), the others plain titles that shade on hover, each with a close button on
/// hover, at its leading edge as in Safari and Finder. Right-click a tab for its menu.
struct NoteTabs: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int
    /// Shows where a tab dropped past the last one would go.
    var isAppendTarget = false

    /// Tab widths: a tab is as wide as its title, between these.
    static let narrowest: CGFloat = 80
    static let widest: CGFloat = 240
    /// When they don't all fit, the others shrink to this (or their own width, if less)
    /// before the row scrolls.
    static let squeezed: CGFloat = 120
    static let spacing: CGFloat = 2
    /// Room at each end of the row, for the drop marker.
    static let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let titles = pane.tabs.map { model.note($0.noteID)?.title ?? "New Tab" }
            let widths = Self.widths(for: titles, current: pane.current, in: geometry.size.width - Self.inset * 2)
            let rowWidth = widths.reduce(0, +) + Self.spacing * CGFloat(max(widths.count - 1, 0)) + Self.inset * 2
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.spacing) {
                        ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                            NoteTab(
                                id: tab.id,
                                title: titles[index],
                                isCurrent: index == pane.current,
                                width: widths[index],
                                select: { model.selectTab(index, inPane: paneIndex) },
                                close: { model.closeTab(index, inPane: paneIndex) },
                                menu: { menu(for: index, tab: tab) }
                            )
                            // Drag a tab along the bar, to the other side's bar or page, or to
                            // one half of the page to split the window.
                            .modifier(TabDropTarget(paneIndex: paneIndex, index: index))
                            .id(tab.id)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isAppendTarget { DropMarker().offset(x: 2) }
                    }
                    .padding(.horizontal, Self.inset)
                    .frame(height: geometry.size.height)
                }
                // Only as wide as the tabs, so the bar's empty space still moves the window.
                .frame(width: min(rowWidth, geometry.size.width))
                // The current tab always in view.
                .onAppear { proxy.scrollTo(pane.tab.id) }
                .onChange(of: pane.tab.id) { id in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
                .onChange(of: geometry.size.width) { _ in proxy.scrollTo(pane.tab.id) }
            }
        }
    }

    /// Each tab as wide as its title, while they all fit. When they don't, the current tab
    /// keeps its width and the others share what's left, each down to `squeezed`; past that,
    /// the row scrolls.
    static func widths(for titles: [String], current: Int, in available: CGFloat) -> [CGFloat] {
        let natural = titles.map { min(max(titleWidth($0) + chrome, narrowest), widest) }
        let gaps = spacing * CGFloat(max(titles.count - 1, 0))
        guard natural.reduce(0, +) + gaps > available, natural.indices.contains(current) else { return natural }
        var widths = natural
        var room = available - gaps - natural[current]
        var sharing = natural.indices.filter { $0 != current }
        // Tabs narrower than an equal share keep their own width; the rest share equally.
        while !sharing.isEmpty {
            let share = room / CGFloat(sharing.count)
            let fitting = sharing.filter { natural[$0] <= share }
            if fitting.isEmpty {
                for i in sharing { widths[i] = max(share, min(natural[i], squeezed)) }
                break
            }
            for i in fitting { room -= natural[i] }
            sharing.removeAll { fitting.contains($0) }
        }
        return widths
    }

    /// The close button, its balance on the other side, and padding.
    private static let chrome: CGFloat = 6 * 2 + 16 * 2 + 2 * 2

    private static func titleWidth(_ title: String) -> CGFloat {
        // The current tab's weight, so a tab doesn't change width when picked.
        let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
        let font = NSFont.systemFont(ofSize: size, weight: .medium)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The tab's right-click menu.
    private func menu(for index: Int, tab: VaultModel.NoteTab) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(BlockMenuItem("Close Tab") { model.closeTab(index, inPane: paneIndex) })
        menu.addItem(BlockMenuItem("Close Other Tabs") { model.closeOtherTabs(index, inPane: paneIndex) })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(model.isSplit ? "Move to Other Side" : "Move to New Split") {
            model.moveTabToOtherSide(index, inPane: paneIndex)
        })
        if model.isSplit {
            menu.addItem(BlockMenuItem("Merge Both Sides into Tabs") { model.mergeIntoTabs() })
        }
        if let id = tab.noteID {
            menu.addItem(BlockMenuItem("Open in New Window") {
                model.closeTab(index, inPane: paneIndex)
                model.openWindowHandler?(id)
            })
        }
        return menu
    }
}

private struct NoteTab: View {
    let id: VaultModel.NoteTab.ID
    let title: String
    let isCurrent: Bool
    let width: CGFloat
    let select: () -> Void
    let close: () -> Void
    let menu: () -> NSMenu
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
            .opacity(isHovering ? 1 : 0)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.callout.weight(isCurrent ? .medium : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false) // Clicks go to the tab's mouse area, below.
            Color.clear.frame(width: 16, height: 16) // Balances the close button.
        }
        .padding(.horizontal, 6)
        .frame(width: width)
        .frame(height: 28)
        .background {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            Group {
                if isCurrent {
                    shape.fill(TopBar.selectedTabColor)
                } else if isHovering {
                    shape.fill(TopBar.selectedTabColor.opacity(0.6))
                }
            }
            .allowsHitTesting(false)
        }
        // Clicks, drags, hover and the menu are handled in AppKit: the tabs sit where a
        // title bar would, and there the window takes any drag SwiftUI doesn't claim
        // first and moves itself.
        .background(TabMouseArea(id: id, title: title, select: select, menu: menu, isHovering: $isHovering))
    }
}

/// A tab's mouse handling: a click selects it, a drag picks it up, a right-click shows its
/// menu. Unlike the bar around it, it never moves the window.
private struct TabMouseArea: NSViewRepresentable {
    let id: VaultModel.NoteTab.ID
    let title: String
    let select: () -> Void
    let menu: () -> NSMenu
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TabMouseView { TabMouseView() }

    func updateNSView(_ view: TabMouseView, context: Context) {
        view.tabID = id
        view.title = title
        view.select = select
        view.makeMenu = menu
        view.onHover = { isHovering = $0 }
    }

    final class TabMouseView: NSView, NSDraggingSource {
        var tabID: VaultModel.NoteTab.ID?
        var title = ""
        var select: () -> Void = {}
        var makeMenu: () -> NSMenu = { NSMenu() }
        var onHover: (Bool) -> Void = { _ in }
        private var mouseDownAt: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        override func mouseDown(with event: NSEvent) {
            mouseDownAt = event.locationInWindow
            select() // On mouse down, as tabs do.
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

        override func mouseUp(with event: NSEvent) { mouseDownAt = nil }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            onHover(false)
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
    static let pasteboardType = NSPasteboard.PasteboardType("org.mikegallagher.imprint.tab")

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

/// The line showing where a dragged tab would go.
private struct DropMarker: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 20)
    }
}

/// A tab dropped on another tab goes before it or after it, whichever half it's over.
private struct TabDropTarget: ViewModifier {
    @EnvironmentObject private var model: VaultModel
    let paneIndex: Int
    let index: Int
    @State private var edge: HorizontalEdge?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                if edge != nil { DropMarker().offset(x: edge == .leading ? -2 : 2) }
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

/// Where a note is in the vault, above its title: the vault, then its folders, in the
/// properties' size and colour ("MG notes › Projects › Archive").
struct NotePath: View {
    let note: Note
    let vault: String

    var body: some View {
        let folders = note.id.split(separator: "/").dropLast().map(String.init)
        Text(([vault] + folders).joined(separator: " › "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .help(note.id)
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
