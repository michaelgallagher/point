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

    /// The top bar's background, always: a light grey over the page.
    static let barColor = Color.primary.opacity(0.05)
    /// The selected tab: a little darker than the bar.
    static let selectedTabColor = Color.primary.opacity(0.07)

}

/// The sidebar's top bar: the New Note and Hide Sidebar buttons, at its trailing edge.
struct SidebarTopBar: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            SidebarButtons()
        }
        .padding(.leading, model.windowButtonsInset)
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
            if pane.tabs.count > 1 {
                NoteTabs(pane: pane, paneIndex: paneIndex)
            } else {
                NotePath(note: model.note(pane.tab.noteID))
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
        .padding(.leading, holdsSidebarButtons ? model.windowButtonsInset : 16)
        .padding(.trailing, 8)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        .background(TopBar.barColor)
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

/// A side's tabs, drawn by Imprint: the current tab a raised, page-coloured tab (it is the
/// page below), the others plain titles that shade on hover, each with a close button on
/// hover, at its leading edge as in Safari and Finder. Right-click a tab for its menu.
struct NoteTabs: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane
    let paneIndex: Int

    var body: some View {
        // Each tab its natural width while they fit; when they don't, equal shares, with
        // titles truncated.
        ViewThatFits(in: .horizontal) {
            row(natural: true)
            row(natural: false)
        }
    }

    private func row(natural: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                NoteTab(
                    title: model.note(tab.noteID)?.title ?? "New Tab",
                    isCurrent: index == pane.current,
                    natural: natural,
                    select: { model.selectTab(index, inPane: paneIndex) },
                    close: { model.closeTab(index, inPane: paneIndex) }
                )
                .contextMenu { menu(for: index, tab: tab) }
            }
        }
    }

    @ViewBuilder private func menu(for index: Int, tab: VaultModel.NoteTab) -> some View {
        Button("Close Tab") { model.closeTab(index, inPane: paneIndex) }
        Button("Close Other Tabs") { model.closeOtherTabs(index, inPane: paneIndex) }
        if let id = tab.noteID, model.isMinimal {
            Divider()
            Button("Open in New Window") {
                model.closeTab(index, inPane: paneIndex)
                model.openWindowHandler?(id)
            }
        } else if !model.isMinimal {
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

private struct NoteTab: View {
    let title: String
    let isCurrent: Bool
    /// Its natural width, or an equal share of a crowded row.
    let natural: Bool
    let select: () -> Void
    let close: () -> Void
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
                .frame(maxWidth: natural ? nil : .infinity)
            Color.clear.frame(width: 16, height: 16) // Balances the close button.
        }
        .padding(.horizontal, 6)
        .frame(minWidth: natural ? nil : 70, maxWidth: natural ? nil : .infinity)
        .fixedSize(horizontal: natural, vertical: false)
        .frame(height: 28)
        .background {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            if isCurrent {
                shape.fill(TopBar.selectedTabColor)
            } else if isHovering {
                shape.fill(TopBar.selectedTabColor.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}

/// A note's place in the vault, for the top bar: its folders, then its title in bold.
struct NotePath: View {
    let note: Note?

    var body: some View {
        if let note {
            let folders = note.id.split(separator: "/").dropLast().map(String.init)
            (Text(folders.map { $0 + "  ›  " }.joined()).foregroundColor(.secondary)
                + Text(note.title).fontWeight(.semibold))
                .lineLimit(1)
                .truncationMode(.head)
                .help(note.id)
        } else {
            Text("New Tab").fontWeight(.semibold)
        }
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
