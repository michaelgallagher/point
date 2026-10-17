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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Pick up changes made elsewhere, such as in Obsidian. Live file watching comes in M2.
            Task { await model.reload() }
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
