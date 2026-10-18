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
            CommandMenu("Go") {
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
