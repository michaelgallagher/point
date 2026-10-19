import AppKit
import SwiftUI
import VaultKit

/// One side of the window: its top bar (title or tabs) above the current tab's note, or
/// for an empty tab, a start page. From macOS 26 the bar is see-through and the note
/// scrolls up beneath it, behind the system's hard-edged scroll edge effect, which takes
/// the place of a line under the bar.
struct PaneView: View {
    @EnvironmentObject private var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    /// Where a tab dragged over the page would go.
    @State private var dropZone: PaneDropZone?

    var body: some View {
        if let index = model.paneIndex(paneID) {
            let pane = model.panes[index]
            if model.isFocused {
                page(pane, index: index, underBar: 0)
            } else if #available(macOS 26, *) {
                page(pane, index: index, underBar: model.topBarHeight)
                    .safeAreaBar(edge: .top, spacing: 0) { PaneTopBar(pane: pane, paneIndex: index) }
                    .scrollEdgeEffectStyle(.hard, for: .top)
            } else {
                VStack(spacing: 0) {
                    PaneTopBar(pane: pane, paneIndex: index)
                    page(pane, index: index, underBar: 0)
                }
            }
        }
    }

    /// The note or start page. `underBar` is how much of it the top bar covers: the note's
    /// scroll view runs up beneath the bar (and is inset by the window to match), anything
    /// else starts below it.
    private func page(_ pane: VaultModel.NotePane, index: Int, underBar: CGFloat) -> some View {
                Group {
                    if let note = model.note(pane.tab.noteID) {
                        NoteEditor(note: note, model: model, paneID: paneID, offersTemplates: note.id == model.freshNoteID)
                            .environment(\.topBarCover, underBar)
                            .id(paneID.uuidString + note.id)
                    } else {
                        // An empty tab is a start page: search, recent notes and the explorer.
                        CommandPalette(isPage: true)
                            .padding(.top, underBar)
                            .id(pane.tab.id) // A fresh page for each tab.
                    }
                }
                // A tab dragged onto one half of the page splits the window; onto the other
                // side's page, it moves there.
                .overlay { PaneDropHighlight(zone: dropZone) }
                .background(TabDropArea { id, point, size in
                    dropZone = id.flatMap { PaneDropZone(tab: $0, overPane: index, x: point.x, width: size.width, in: model) }
                    return dropZone != nil
                } drop: { id, point, size in
                    dropZone = nil
                    guard let zone = PaneDropZone(tab: id, overPane: index, x: point.x, width: size.width, in: model) else { return false }
                    zone.drop(id, onPane: index, in: model)
                    return true
                })
    }
}

extension EnvironmentValues {
    /// How much of a note's page the see-through top bar covers.
    @Entry var topBarCover: CGFloat = 0
}

/// Two views side by side with a divider to drag between them. Unlike HSplitView, it
/// takes only the width it's offered, so it never squeezes the sidebar.
struct SideBySide<Main: View, Side: View>: View {
    @ViewBuilder let main: Main
    @ViewBuilder let side: Side
    /// How much of the width the left side gets.
    @AppStorage("sideBySideFraction") private var fraction = 0.5
    private let minimumWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                main
                    .frame(width: clamp(width * fraction, in: width))
                Divider()
                    .overlay {
                        // A wider grip than the line itself.
                        Color.clear
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("sideBySide"))
                                .onChanged { value in
                                    guard width > 0 else { return }
                                    fraction = clamp(value.location.x, in: width) / width
                                })
                    }
                side
                    .frame(maxWidth: .infinity)
            }
        }
        .coordinateSpace(name: "sideBySide")
    }

    private func clamp(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        guard width > minimumWidth * 2 else { return width / 2 }
        return min(max(x, minimumWidth), width - minimumWidth)
    }
}
