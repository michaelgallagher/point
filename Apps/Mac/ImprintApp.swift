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
            CommandGroup(after: .newItem) {
                Button("Open Vault…") { model.chooseVault() }
                    .keyboardShortcut("o")
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
