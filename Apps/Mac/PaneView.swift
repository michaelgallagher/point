import AppKit
import SwiftUI
import VaultKit

/// One side of the window: its top bar (title or tabs) above the current tab's note, or
/// for an empty tab, a start page.
struct PaneView: View {
    @EnvironmentObject private var model: VaultModel
    let paneID: VaultModel.NotePane.ID

    var body: some View {
        if let index = model.paneIndex(paneID) {
            let pane = model.panes[index]
            VStack(spacing: 0) {
                if !model.isFocused {
                    PaneTopBar(pane: pane, paneIndex: index)
                }
                if let note = model.note(pane.tab.noteID) {
                    NoteEditor(note: note, model: model, paneID: paneID, offersTemplates: note.id == model.freshNoteID)
                        .id(paneID.uuidString + note.id)
                } else {
                    // An empty tab is a start page: search, recent notes and the explorer.
                    CommandPalette(isPage: true)
                        .id(pane.tab.id) // A fresh page for each tab.
                }
            }
        }
    }
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
