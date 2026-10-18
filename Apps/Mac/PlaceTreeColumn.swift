import SwiftUI
import VaultKit

/// The two-column view's left column: pinned items, then folders (or tags) as a tree.
struct PlaceTreeColumn: View {
    @EnvironmentObject private var model: VaultModel
    /// Whether the current place was chosen from Pinned rather than the tree. A pinned item
    /// is in both lists; this says which copy to highlight, so only one ever is.
    @State private var pickedFromPins = false

    /// Pinned and tree rows get different identities ("pin:…", "tree:…"), even for the
    /// same folder or tag, so the list never treats them as one selection.
    private var selection: Binding<String?> {
        Binding(
            get: {
                let fromPins = pickedFromPins && model.pins.contains(model.place)
                return (fromPins ? "pin:" : "tree:") + model.place.key
            },
            set: { id in
                guard let id, let colon = id.firstIndex(of: ":"),
                      let place = SidebarPlace(key: String(id[id.index(after: colon)...])) else { return }
                pickedFromPins = id.hasPrefix("pin:")
                model.browse(place)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $model.treeKind) {
                Text("Folders").tag(VaultModel.TreeKind.folders)
                Text("Tags").tag(VaultModel.TreeKind.tags)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(selection: selection) {
                if !model.pins.isEmpty {
                    Section("Pinned") {
                        ForEach(model.pins, id: \.self) { place in
                            PlaceLabel(place: place, name: place.title).tag("pin:" + place.key)
                        }
                    }
                }
                Section(model.treeKind == .folders ? "Folders" : "Tags") {
                    OutlineGroup(model.treeKind == .folders ? model.folderNodes : model.tagNodes, children: \.children) { node in
                        PlaceLabel(place: node.place, name: node.name).tag("tree:" + node.place.key)
                    }
                }
            }
            // Sidebar style, without a background of its own, so it sits on the same sidebar
            // material as the note list beside it rather than on white.
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if model.treeKind == .tags {
                Divider()
                Picker("Sort tags by", selection: $model.tagOrder) {
                    Text("Name").tag(VaultModel.TagOrder.name)
                    Text("Date Modified").tag(VaultModel.TagOrder.modified)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }
}

/// A folder or tag in the tree, with its note count. Notes can be dropped on folders.
private struct PlaceLabel: View {
    @EnvironmentObject private var model: VaultModel
    let place: SidebarPlace
    let name: String
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if place != .allNotes {
                Text("\(model.noteCount(of: place))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(isDropTarget ? Color.accentColor.opacity(0.25) : .clear))
        .onDrop(of: [.text], isTargeted: folderPath == nil ? nil : $isDropTarget) { providers in
            guard let path = folderPath, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = object as? String else { return }
                Task { @MainActor in model.move(noteID: id, toFolder: path) }
            }
            return true
        }
        .contextMenu {
            if place != .allNotes {
                Button(model.isPinned(place) ? "Unpin" : "Pin to Sidebar") { model.togglePin(place) }
            }
            if let path = folderPath, let root = model.root {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([path.isEmpty ? root : root.appendingPathComponent(path)])
                }
            }
        }
    }

    /// The folder's path ("" for the vault's top level), or nil for a tag.
    private var folderPath: String? {
        switch place {
        case .allNotes: ""
        case .folder(let path): path
        case .tag: nil
        }
    }

    private var icon: String {
        switch place {
        case .allNotes: "tray"
        case .folder: "folder"
        case .tag: "number"
        }
    }
}
