import AppKit
import SwiftUI
import VaultKit

@main
struct ImprintApp: App {
    @StateObject private var model = VaultModel()

    var body: some Scene {
        Window("Imprint", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            FormatCommands()
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Command Palette") { model.isPaletteShown.toggle() }
                    .keyboardShortcut("e")
                    .disabled(model.root == nil)
                Button("Search Notes") { model.focusSearch() }
                    .keyboardShortcut("f")
                    .disabled(model.root == nil)
                Button("Find in Note") { FindInNote.show() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
            CommandMenu("Go") {
                Button("Enclosing Folder") { model.goUp() }
                    .keyboardShortcut(.upArrow)
                    .disabled(model.place == .allNotes)
                Button("Top Level") { model.browse(.allNotes) }
                Divider()
                Button("Previous Note") { model.selectAdjacentNote(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Next Note") { model.selectAdjacentNote(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[")
                    .disabled(model.backStack.isEmpty)
                Button("Forward") { model.goForward() }
                    .keyboardShortcut("]")
                    .disabled(model.forwardStack.isEmpty)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") { model.createNote() }
                    .keyboardShortcut("n")
                    .disabled(model.root == nil)
                Button("Today's Note") { model.openTodaysNote() }
                    .keyboardShortcut("t")
                    .disabled(model.root == nil)
                Button("Insert Template…") { model.isChoosingTemplate = true }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .disabled(model.selectedNote == nil)
                Button("Open Vault…") { model.chooseVault() }
                    .keyboardShortcut("o")
                Divider()
                Button("Rename Note…") { model.renaming = model.selectedNote }
                    .disabled(model.selectedNote == nil)
                Button("Move to Folder…") { model.moving = model.selectedNote }
                    .disabled(model.selectedNote == nil)
                Button("Add Tag…") { model.tagging = model.selectedNote }
                    .disabled(model.selectedNote == nil)
                Button("Show in Finder") { model.selectedNote.map(model.showInFinder) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(model.selectedNote == nil)
                Button("Move to Trash") { model.selectedNote.map(model.moveToTrash) }
                    .disabled(model.selectedNote == nil)
            }
            CommandGroup(after: .toolbar) {
                Picker("Sort By", selection: $model.sort) {
                    Text("Date Edited").tag(NoteSort.modified)
                    Text("Date Created").tag(NoteSort.created)
                    Text("Title").tag(NoteSort.title)
                }
                Divider()
                Toggle("Show Dates in List", isOn: $model.showsDateInList)
                Picker("List Dates", selection: $model.listDate) {
                    Text("Date Edited").tag(VaultModel.ListDate.edited)
                    Text("Date Created").tag(VaultModel.ListDate.created)
                }
                .disabled(!model.showsDateInList)
                Toggle("Show Tags in List", isOn: $model.showsTagsInList)
                Divider()
                Button(model.showsNoteList ? "Hide Note List" : "Show Note List") { model.showsNoteList.toggle() }
                    .keyboardShortcut("s")
                Button("Bigger Text") { model.makeTextBigger() }
                    .keyboardShortcut("=") // The ⌘+ key, without Shift.
                Button("Smaller Text") { model.makeTextSmaller() }
                    .keyboardShortcut("-")
                Button("Actual Size") { model.textScale = 1 }
                Divider()
                Toggle("Show Markdown", isOn: $model.showsMarkdown)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Toggle("Focus", isOn: $model.isFocused)
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
                Divider()
                Button("Reload Notes") { Task { await model.reload() } }
                    .keyboardShortcut("r")
                    .disabled(model.root == nil)
                Divider()
            }
        }
    }
}

/// Opens the find bar in the note being edited.
enum FindInNote {
    @MainActor static func show() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}
