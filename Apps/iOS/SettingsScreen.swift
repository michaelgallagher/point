import SwiftUI

/// Settings, from home's top right: where the notes are, and how many, and forgetting what
/// search has learned.
struct SettingsScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Notes", value: "\(store.notes.count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Notes are kept in Point’s folder on this iPhone, which the Files app shows. They don’t sync yet.")
                }
                Section {
                    Button("Forget What Search Has Learned", role: .destructive) { confirmsForget = true }
                        .disabled(store.history.isEmpty)
                } footer: {
                    Text("Search puts the notes you open and pick most first. What it learns stays on this iPhone.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .confirmationDialog("Forget what search has learned?", isPresented: $confirmsForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { store.forgetSearchHistory() }
            } message: {
                Text("Your notes aren’t changed.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
