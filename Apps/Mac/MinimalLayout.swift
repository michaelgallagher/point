import AppKit
import SwiftUI
import VaultKit

/// The Minimal layout: no explorer panel, one note at a time, the window's tabs down the
/// side, and a start page (search and browse) in every empty tab. Finding things happens in
/// the start page and the ⌘E palette.
struct MinimalLayout: View {
    @EnvironmentObject private var model: VaultModel

    private var pane: VaultModel.NotePane { model.panes[0] }

    /// The tab list shows itself once there's more than one tab; ⌘S or a swipe hides it.
    private var showsTabList: Bool {
        pane.tabs.count > 1 && model.showsNoteList && !model.isFocused
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsTabList {
                TabList(pane: pane)
                    .frame(width: 220)
                    .transition(.move(edge: .leading))
                Divider()
            }
            VStack(spacing: 0) {
                if !model.isFocused {
                    MinimalTopBar(holdsWindowButtons: !showsTabList, tabCount: pane.tabs.count)
                }
                if let note = model.note(pane.tab.noteID) {
                    NoteEditor(note: note, model: model, paneID: pane.id, offersTemplates: note.id == model.freshNoteID)
                        .id(pane.id.uuidString + note.id)
                } else {
                    // The start page: the explorer, as the tab itself.
                    CommandPalette(isPage: true)
                        .id(pane.tab.id) // A fresh page for each tab.
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .animation(.easeOut(duration: 0.15), value: showsTabList)
        .ignoresSafeArea(.container, edges: .top)
        // Minimal has one side: a split from another layout becomes tabs.
        .onAppear { if model.isSplit { model.mergeIntoTabs() } }
    }
}

/// The top row: the window buttons (unless the tab list holds them), the button for the
/// tab list, and the note's title. Everything else is in the palette.
private struct MinimalTopBar: View {
    @EnvironmentObject private var model: VaultModel
    let holdsWindowButtons: Bool
    let tabCount: Int

    var body: some View {
        ZStack {
            Text(model.selectedNote?.title ?? "New Tab")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 120)
            HStack(spacing: 2) {
                if tabCount > 1 {
                    BarButton(model.showsNoteList ? "Hide Tabs" : "Show Tabs", systemImage: "sidebar.left",
                              help: model.showsNoteList ? "Hide Tabs (⌘S)" : "Show Tabs (⌘S)") {
                        model.showsNoteList.toggle()
                    }
                }
                Spacer()
            }
            .padding(.leading, holdsWindowButtons ? TopBar.windowButtonsWidth : 10)
            .padding(.trailing, 10)
        }
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
    }
}

/// The window's tabs as a native sidebar list, with + for a new tab.
private struct TabList: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane

    private var selection: Binding<UUID?> {
        Binding(
            get: { pane.tab.id },
            set: { id in
                if let index = pane.tabs.firstIndex(where: { $0.id == id }) { model.selectTab(index, inPane: 0) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                BarButton("New Tab", systemImage: "plus", help: "New Tab (⌘T)") { model.newTab() }
            }
            .padding(.leading, TopBar.windowButtonsWidth)
            .padding(.trailing, 10)
            .frame(height: model.topBarHeight)
            .background(WindowDragArea())
            List(selection: selection) {
                ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabRow(title: model.note(tab.noteID)?.title ?? "New Tab", isBlank: tab.noteID == nil) {
                        model.closeTab(index, inPane: 0)
                    }
                    .tag(tab.id)
                    .contextMenu {
                        Button("Close Tab") { model.closeTab(index, inPane: 0) }
                        Button("Close Other Tabs") { model.closeOtherTabs(index, inPane: 0) }
                            .disabled(pane.tabs.count < 2)
                        if let id = tab.noteID {
                            Divider()
                            Button("Open in New Window") {
                                model.closeTab(index, inPane: 0)
                                model.openWindowHandler?(id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(SidebarMaterial())
    }
}

private struct TabRow: View {
    let title: String
    let isBlank: Bool
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isBlank ? "magnifyingglass" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
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
        }
        .onHover { isHovering = $0 }
    }
}

/// The sidebar's translucent material, for a panel outside a split view.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
