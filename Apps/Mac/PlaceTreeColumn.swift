import SwiftUI
import VaultKit

/// The two-column view's left column: pinned items, then folders (or tags) as a tree. A folder or tag with others inside unfolds from a chevron after its
/// name, as in the one-column sidebar, so every row lines up with its section's label.
struct PlaceTreeColumn: View {
    @EnvironmentObject private var model: VaultModel
    /// Whether the current place was chosen from Pinned rather than the tree. A pinned item
    /// is in both lists; this says which copy to highlight, so only one ever is.
    @State private var pickedFromPins = false
    /// Folders and tags unfolded, shared with the one-column sidebar (see `SidebarTable`).
    @AppStorage("expandedSidebarFolders") private var expandedFolders = ""

    private var expanded: Set<String> { Set(expandedFolders.split(separator: "\n").map(String.init)) }

    private func toggle(_ place: SidebarPlace) {
        var places = expanded
        let key = VaultModel.expansionKey(place)
        if places.remove(key) == nil { places.insert(key) }
        expandedFolders = places.sorted().joined(separator: "\n")
    }

    /// Gives the tree the keyboard once something's picked in it, so its selection is blue,
    /// as the last thing picked. A click on a row doesn't always do it: the row's own drag
    /// handling (folders can be dragged) can take the click first, leaving the keyboard in
    /// the note list, so the tree's selection stayed grey.
    private func focusTree() {
        DispatchQueue.main.async { [weak model] in
            guard let window = model?.window, let root = window.contentView else { return }
            func tree(in view: NSView) -> NSOutlineView? {
                if let outline = view as? NSOutlineView { return outline }
                for subview in view.subviews { if let found = tree(in: subview) { return found } }
                return nil
            }
            if let tree = tree(in: root), window.firstResponder !== tree { window.makeFirstResponder(tree) }
        }
    }

    /// The tree's rows in order, with the children of each unfolded node beneath it.
    private func rows(_ nodes: [VaultModel.PlaceNode], depth: Int = 0) -> [(node: VaultModel.PlaceNode, depth: Int)] {
        let expanded = expanded
        func walk(_ nodes: [VaultModel.PlaceNode], _ depth: Int) -> [(node: VaultModel.PlaceNode, depth: Int)] {
            nodes.flatMap { node -> [(node: VaultModel.PlaceNode, depth: Int)] in
                let open = node.children != nil && expanded.contains(VaultModel.expansionKey(node.place))
                return [(node, depth)] + (open ? walk(node.children ?? [], depth + 1) : [])
            }
        }
        return walk(nodes, depth)
    }

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
                focusTree()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.treeLayout == .toggle {
                CapsuleToggle(selection: $model.treeKind)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            List(selection: selection) {
                // Special places first, with no heading: every note, and the trash.
                Section {
                    PlaceLabel(place: .everything, name: SidebarPlace.everything.title).tag("tree:" + SidebarPlace.everything.key)
                    PlaceLabel(place: .bookmarks, name: SidebarPlace.bookmarks.title).tag("tree:" + SidebarPlace.bookmarks.key)
                    PlaceLabel(place: .trash, name: SidebarPlace.trash.title).tag("tree:" + SidebarPlace.trash.key)
                }
                if !model.pins.isEmpty {
                    FoldingSection("Pinned") {
                        ForEach(model.pins, id: \.self) { place in
                            PlaceLabel(place: place, name: place.title).tag("pin:" + place.key)
                        }
                    }
                }
                // Stacked (the default): folders, then tags. Otherwise whichever is toggled.
                if model.treeLayout == .stacked || model.treeKind == .folders {
                    FoldingSection("Folders") { treeRows(model.folderNodes) }
                }
                if model.treeLayout == .stacked || model.treeKind == .tags, !model.tagNodes.isEmpty {
                    FoldingSection("Tags") { treeRows(model.tagNodes) }
                }
            }
            // Sidebar style, without a background of its own, so it sits on the same sidebar
            // material as the note list beside it rather than on white.
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // The system's small or medium sidebar rows, which the note list beside it matches.
            .environment(\.sidebarRowSize, model.sidebarDensity == .compact ? .small : .medium)

            SortBar(help: "How folders and tags are sorted", selection: $model.tagOrder,
                    options: [("Folders and Tags by Name", .name), ("Folders and Tags by Date Modified", .modified)])
        }
        .onChange(of: model.treeLayout) { _ in model.matchPlaceToTree() }
        .onAppear { model.matchPlaceToTree() }
    }

    private func treeRows(_ nodes: [VaultModel.PlaceNode]) -> some View {
        let expanded = expanded
        return ForEach(rows(nodes), id: \.node.id) { row in
            PlaceLabel(place: row.node.place, name: row.node.name, depth: row.depth,
                       isExpanded: row.node.children == nil ? nil : expanded.contains(VaultModel.expansionKey(row.node.place)),
                       toggle: { toggle(row.node.place) })
                .tag("tree:" + row.node.place.key)
        }
    }
}

/// A sidebar icon: blue (the accent colour), as in Finder's sidebar, or grey; white on a
/// selected row's blue, from macOS 14.
private struct PlaceIcon: View {
    let symbol: String
    let isAccent: Bool

    var body: some View {
        if #available(macOS 14, *) {
            ProminenceAwareIcon(symbol: symbol, isAccent: isAccent)
        } else {
            Image(systemName: symbol)
                .foregroundStyle(isAccent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 16)
        }
    }
}

@available(macOS 14, *)
private struct ProminenceAwareIcon: View {
    let symbol: String
    let isAccent: Bool
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.white)
                             : isAccent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(width: 16)
    }
}

/// A two-way switch the full width of its column, with fully rounded ends.
private struct CapsuleToggle: View {
    @Binding var selection: VaultModel.TreeKind

    var body: some View {
        HStack(spacing: 2) {
            segment("Folders", .folders)
            segment("Tags", .tags)
        }
        .padding(2)
        .background(Capsule().fill(.quaternary))
    }

    private func segment(_ title: String, _ kind: VaultModel.TreeKind) -> some View {
        let isSelected = selection == kind
        return Button { selection = kind } label: {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color(nsColor: .textBackgroundColor) : .clear)
                    .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 1, y: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}

/// A folder or tag in the tree, with its note count. Notes can be dropped on folders.
private struct PlaceLabel: View {
    @EnvironmentObject private var model: VaultModel
    let place: SidebarPlace
    let name: String
    /// How deeply it's nested in the tree.
    var depth = 0
    /// Whether it's unfolded, or nil if there's nothing inside to unfold.
    var isExpanded: Bool?
    var toggle: () -> Void = {}
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            // Blue, as in Finder's sidebar; tags stay grey.
            PlaceIcon(symbol: icon, isAccent: !place.isTag)
            Text(name)
                .font(.body) // The note list's size, even in small (compact) rows.
                .lineLimit(1)
            // Unfolds from after its name, as a section does from after its label.
            if let isExpanded {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Fold" : "Unfold")
                .padding(.leading, -2)
            }
            Spacer(minLength: 4)
            if place != .allNotes {
                Text("\(model.noteCount(of: place))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .background(RoundedRectangle(cornerRadius: 4).fill(isDropTarget ? Color.accentColor.opacity(0.25) : .clear))
        // A folder can be dragged into another (not the vault's top level, which holds them all).
        .modifier(FolderDragSource(path: folderPath.flatMap { $0.isEmpty ? nil : $0 }))
        .onDrop(of: [.text], isTargeted: folderPath == nil ? nil : $isDropTarget) { providers in
            guard let path = folderPath, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = object as? String else { return }
                Task { @MainActor in model.drop(id, onFolder: path) }
            }
            return true
        }
        .contextMenu {
            if place != .allNotes {
                Button(model.isPinned(place) ? "Unpin" : "Pin to Sidebar") { model.togglePin(place) }
            }
            if let path = folderPath, let root = model.root {
                Button("New Folder Inside…") { model.newFolder(in: path) }
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
        case .tag, .everything, .bookmarks, .trash: nil
        }
    }

    private var icon: String {
        switch place {
        case .allNotes: "tray"
        case .folder: "folder"
        case .tag: "number.sign.circle"
        case .everything: "tray.full"
        case .bookmarks: "bookmark"
        case .trash: "trash"
        }
    }
}

/// Lets a folder's row be dragged, carrying its path; other rows aren't.
private struct FolderDragSource: ViewModifier {
    let path: String?

    func body(content: Content) -> some View {
        if let path {
            content.onDrag { NSItemProvider(object: (VaultModel.folderDragPrefix + path) as NSString) }
        } else {
            content
        }
    }
}

/// A section of the tree that folds away, from macOS 14, and stays as it was left.
private struct FoldingSection<Content: View>: View {
    let title: String
    @AppStorage private var isExpanded: Bool
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = AppStorage(wrappedValue: true, "treeSectionExpanded." + title)
        self.content = content()
    }

    var body: some View {
        if #available(macOS 14, *) {
            Section(isExpanded: $isExpanded) { content } header: { Text(title) }
        } else {
            Section(title) { content }
        }
    }
}

/// A sort menu along the bottom of a sidebar column, as wide as the column: a box like the
/// search field's, showing the order chosen, which opens the choices. (The system's pop-up
/// menu sizes itself to its text, whatever room it's given.)
struct SortBar<Value: Hashable>: View {
    let help: String
    @Binding var selection: Value
    let options: [(name: String, value: Value)]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Menu {
                Picker(help, selection: $selection) {
                    ForEach(options, id: \.value) { Text($0.name).tag($0.value) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.value == selection }?.name ?? "")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(help)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}
