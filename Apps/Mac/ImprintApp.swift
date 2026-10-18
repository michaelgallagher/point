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
            CommandGroup(replacing: .newItem) {
                Button("New Note") { model.createNote() }
                    .keyboardShortcut("n")
                    .disabled(model.root == nil)
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
                Button("Reload Notes") { Task { await model.reload() } }
                    .keyboardShortcut("r")
                    .disabled(model.root == nil)
                Divider()
            }
        }
    }
}
