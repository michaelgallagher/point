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

    /// Room for the close, minimise and zoom buttons at the window's top left.
    static let windowButtonsWidth: CGFloat = 76
}

/// The sidebar's top bar: the New Note and Hide Sidebar buttons, at its trailing edge.
struct SidebarTopBar: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            SidebarButtons()
        }
        .padding(.leading, TopBar.windowButtonsWidth)
        .padding(.trailing, 8)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
    }
}

/// New Note, and the button that hides and shows the sidebar.
struct SidebarButtons: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 2) {
            BarButton("New Note", systemImage: "square.and.pencil", help: "New Note (⌘N)") { model.createNote() }
            BarButton(model.showsNoteList ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left",
                      help: model.showsNoteList ? "Hide Sidebar (⌘S)" : "Show Sidebar (⌘S)") {
                if model.isFocused { model.isFocused = false } else { model.showsNoteList.toggle() }
            }
        }
    }
}

/// One side's top bar: its note's title, or its tabs, and buttons for tabs and the split.
struct PaneTopBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    /// The first side holds the sidebar's buttons while the sidebar is hidden.
    private var holdsSidebarButtons: Bool { paneIndex == 0 && !model.showsNoteList }
    private var isActive: Bool { paneIndex == model.activePane }

    var body: some View {
        HStack(spacing: 8) {
            if holdsSidebarButtons {
                SidebarButtons()
            }
            if pane.tabs.count > 1, #available(macOS 26, *) {
                GlassTabs(pane: pane, paneIndex: paneIndex)
            } else if pane.tabs.count > 1 {
                TabStrip(
                    titles: pane.tabs.map { model.note($0.noteID)?.title ?? "New Tab" },
                    selected: pane.current,
                    select: { model.selectTab($0, inPane: paneIndex) },
                    menu: { tabMenu(for: $0) }
                )
            } else {
                Text(model.note(pane.tab.noteID)?.title ?? "New Tab")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // With two sides, the one being worked on has the stronger title.
                    .foregroundStyle(isActive || !model.isSplit ? .primary : .secondary)
                    .contextMenu { tabMenuItems(for: pane.current) }
            }
            Spacer(minLength: 0)
            BarButton("New Tab", systemImage: "plus", help: "New Tab (⌘T)") { model.newTab(inPane: paneIndex) }
            if model.isSplit {
                BarButton("Close This Side", systemImage: "xmark", help: "Close This Side") { model.closePane(paneIndex) }
            } else {
                BarButton("Split", systemImage: "rectangle.split.2x1", help: "Split (⇧⌘S)") { model.toggleSplit() }
            }
        }
        .padding(.leading, holdsSidebarButtons ? TopBar.windowButtonsWidth : 16)
        .padding(.trailing, 8)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func tabMenuItems(for index: Int) -> some View {
        Button("Close Tab") { model.closeTab(index, inPane: paneIndex) }
        Button(model.isSplit ? "Move to Other Side" : "Move to New Split") { model.moveTabToOtherSide(index, inPane: paneIndex) }
            .disabled(!model.isSplit && pane.tabs.count < 2)
        if model.isSplit {
            Button("Merge Both Sides into Tabs") { model.mergeIntoTabs() }
        }
    }

    /// The right-click menu for a tab in the tab strip.
    private func tabMenu(for index: Int) -> NSMenu {
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
        return menu
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

/// A side's tabs as Liquid Glass capsules: the current one solid glass, the others clear
/// glass, each with a close button on hover. Right-click a tab for its menu.
@available(macOS 26, *)
struct GlassTabs: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                    GlassTab(
                        title: model.note(tab.noteID)?.title ?? "New Tab",
                        isCurrent: index == pane.current,
                        select: { model.selectTab(index, inPane: paneIndex) },
                        close: { model.closeTab(index, inPane: paneIndex) }
                    )
                    .contextMenu {
                        Button("Close Tab") { model.closeTab(index, inPane: paneIndex) }
                        Button("Close Other Tabs") { model.closeOtherTabs(index, inPane: paneIndex) }
                        Divider()
                        Button(model.isSplit ? "Move to Other Side" : "Move to New Split") {
                            model.moveTabToOtherSide(index, inPane: paneIndex)
                        }
                        if model.isSplit {
                            Button("Merge Both Sides into Tabs") { model.mergeIntoTabs() }
                        }
                    }
                }
            }
        }
    }
}

@available(macOS 26, *)
private struct GlassTab: View {
    let title: String
    let isCurrent: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
            .opacity(isHovering ? 1 : 0)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.callout.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 16, height: 16) // Balances the close button.
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 80, maxWidth: 200)
        .frame(height: 32)
        .contentShape(Capsule())
        .glassEffect(isCurrent ? .regular.interactive() : .clear.interactive(), in: .capsule)
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}

/// A pane's tabs, as the system's segmented control. Right-click a tab for its menu.
struct TabStrip: NSViewRepresentable {
    let titles: [String]
    let selected: Int
    let select: (Int) -> Void
    let menu: (Int) -> NSMenu
    /// Each tab's widest, so a few tabs don't stretch across the whole bar.
    private let maxTabWidth: CGFloat = 200

    func makeNSView(context: Context) -> TabSegments {
        let control = TabSegments()
        control.trackingMode = .selectOne
        // The current tab as a light pill, like the system's tabs, not a blue button.
        control.selectedSegmentBezelColor = .controlBackgroundColor
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: TabSegments, context: Context) {
        context.coordinator.select = select
        control.menuForSegment = menu
        if control.segmentCount != titles.count { control.segmentCount = titles.count }
        for (index, title) in titles.enumerated() where control.label(forSegment: index) != title {
            control.setLabel(title, forSegment: index)
            control.setToolTip(title, forSegment: index)
        }
        control.selectedSegment = selected
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TabSegments, context: Context) -> CGSize? {
        let widest = CGFloat(titles.count) * maxTabWidth
        return CGSize(width: min(proposal.width ?? widest, widest), height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var select: ((Int) -> Void)?
        @objc func changed(_ sender: NSSegmentedControl) { select?(sender.selectedSegment) }
    }
}

/// A segmented control whose right-click menu belongs to the segment under the pointer.
final class TabSegments: NSSegmentedControl {
    var menuForSegment: ((Int) -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard segmentCount > 0, let menuForSegment else { return nil }
        let x = convert(event.locationInWindow, from: nil).x
        let index = Int(x / (bounds.width / CGFloat(segmentCount)))
        return menuForSegment(min(max(index, 0), segmentCount - 1))
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
