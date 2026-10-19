import AppKit
import SwiftUI
import VaultKit

/// The Minimal layout: no explorer panel, one note at a time, tabs along the top, and a
/// start page (search, recent notes, and the explorer) in every empty tab. It's meant to be
/// compact, to sit beside other windows; finding things happens in the start page and the
/// palette (⌘F to search, ⌘E to explore), never beside the note.
struct MinimalLayout: View {
    @EnvironmentObject private var model: VaultModel

    private var pane: VaultModel.NotePane { model.panes[0] }

    var body: some View {
        VStack(spacing: 0) {
            if !model.isFocused {
                MinimalTopBar(pane: pane)
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
        .ignoresSafeArea(.container, edges: .top)
        // Minimal has one side: a split from another layout becomes tabs.
        .onAppear { if model.isSplit { model.mergeIntoTabs() } }
    }
}

/// The top row: the window buttons, then the tabs (or with one tab, its title), then + for
/// a new tab. Everything else is in the palette.
private struct MinimalTopBar: View {
    @EnvironmentObject private var model: VaultModel
    let pane: VaultModel.NotePane

    var body: some View {
        HStack(spacing: 8) {
            if pane.tabs.count > 1 {
                NoteTabs(pane: pane, paneIndex: 0)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                NotePath(note: model.selectedNote)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            BarButton("New Tab", systemImage: "plus", help: "New Tab (⌘T)") { model.newTab() }
        }
        .padding(.leading, model.windowButtonsInset)
        .padding(.trailing, 10)
        .frame(height: model.topBarHeight)
        .background(WindowDragArea())
        .background(TopBar.barColor)
    }
}
