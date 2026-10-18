import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                NavigationSplitView {
                    NoteList()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    if let note = model.selectedNote {
                        NoteEditor(note: note)
                            .id(note.id)
                    } else {
                        Text("No Note Selected")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle(model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Imprint")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(item: $model.renaming) { note in
            RenameSheet(note: note)
        }
    }
}

private struct OpenVaultView: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Imprint")
                .font(.largeTitle.weight(.semibold))
            Text("Choose the folder that holds your notes.")
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Button("Open Vault…") { model.chooseVault() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteList: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        List(model.notes, selection: $model.selection) { note in
            HStack(spacing: 4) {
                Text(note.title)
                    .lineLimit(1)
                if !note.isDownloaded {
                    Spacer()
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .help("In iCloud, not yet downloaded")
                }
            }
            .help(note.id)
            .contextMenu {
                Button("Rename…") { model.renaming = note }
                Button("Move to Trash") { model.moveToTrash(note) }
            }
        }
        .onDeleteCommand {
            model.selectedNote.map(model.moveToTrash)
        }
        .overlay {
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Note")
                .font(.headline)
            TextField("Name", text: $title)
                .frame(width: 320)
                .onSubmit(rename)
            Text("Links to this note in other notes will be updated.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { title = note.title }
    }

    private func rename() {
        model.rename(note, to: title)
        dismiss()
    }
}
