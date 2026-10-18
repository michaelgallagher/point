import SwiftUI
import VaultKit

/// Imprint's Settings window (⌘,).
struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        Form {
            Picker("Note list:", selection: $store.browsingStyle) {
                Text("Single column: folders, tags and notes in one list").tag(VaultModel.BrowsingStyle.singleColumn)
                Text("Two columns: folders and tags beside the notes").tag(VaultModel.BrowsingStyle.twoColumns)
            }
            .pickerStyle(.radioGroup)

            Divider()

            Picker("Sort notes by:", selection: $store.sort) {
                Text("Date Edited").tag(NoteSort.modified)
                Text("Date Created").tag(NoteSort.created)
                Text("Title").tag(NoteSort.title)
            }
            .fixedSize()
            Toggle("Show dates in the note list", isOn: $store.showsDateInList)
            Toggle("Show tags in the note list", isOn: $store.showsTagsInList)

            Divider()

            LabeledContent("Text size:") {
                HStack {
                    Text("\(Int((store.textScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Stepper("Text size", onIncrement: store.makeTextBigger, onDecrement: store.makeTextSmaller)
                        .labelsHidden()
                    Button("Reset") { store.textScale = 1 }
                        .disabled(store.textScale == 1)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
