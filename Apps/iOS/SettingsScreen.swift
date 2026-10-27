import SwiftUI

/// Settings, from home's top right. Nothing to set yet: where the notes are, and how many.
struct SettingsScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss

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
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
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
