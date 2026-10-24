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

    private func isSelected(_ id: String) -> Bool { selection.wrappedValue == id }

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
                    PlaceLabel(place: .everything, name: SidebarPlace.everything.title, isSelected: isSelected("tree:" + SidebarPlace.everything.key)).tag("tree:" + SidebarPlace.everything.key)
                    PlaceLabel(place: .trash, name: SidebarPlace.trash.title, isSelected: isSelected("tree:" + SidebarPlace.trash.key)).tag("tree:" + SidebarPlace.trash.key)
                }
                if !model.pins.isEmpty {
                    FoldingSection("Pinned") {
                        ForEach(model.pins, id: \.self) { place in
                            PlaceLabel(place: place, name: place.title, isSelected: isSelected("pin:" + place.key)).tag("pin:" + place.key)
                        }
                    }
                }
                // Stacked (the default): folders, then tags. Otherwise whichever is toggled.
                if model.treeLayout == .stacked || model.treeKind == .folders {
                    FoldingSection("Folders") {
                        OutlineGroup(model.folderNodes, children: \.children) { node in
                            PlaceLabel(place: node.place, name: node.name, isSelected: isSelected("tree:" + node.place.key)).tag("tree:" + node.place.key)
                        }
                    }
                }
                if model.treeLayout == .stacked || model.treeKind == .tags, !model.tagNodes.isEmpty {
                    FoldingSection("Tags") {
                        OutlineGroup(model.tagNodes, children: \.children) { node in
                            PlaceLabel(place: node.place, name: node.name, isSelected: isSelected("tree:" + node.place.key)).tag("tree:" + node.place.key)
                        }
                    }
                }
            }
            // Sidebar style, without a background of its own, so it sits on the same sidebar
            // material as the note list beside it rather than on white.
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // The system draws the selected row as a rounded rectangle; each row draws a capsule
            // itself instead, so this turns the system's off.
            .background(SystemSelectionHider())
            // The system's small or medium sidebar rows, which the note list beside it matches.
            .environment(\.sidebarRowSize, model.sidebarDensity == .compact ? .small : .medium)

            SortBar(help: "How folders and tags are sorted", selection: $model.tagOrder,
                    options: [("Folders and Tags by Name", .name), ("Folders and Tags by Date Modified", .modified)])
        }
        .onChange(of: model.treeLayout) { _ in model.matchPlaceToTree() }
        .onAppear { model.matchPlaceToTree() }
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
    let isSelected: Bool
    @Environment(\.controlActiveState) private var activeState
    @State private var isDropTarget = false

    /// Selected while the window is in front: the accent colour, with white text. Otherwise grey.
    private var isOnAccent: Bool { isSelected && activeState != .inactive }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(isOnAccent ? Color.white : Color.secondary)
                .frame(width: 16)
            Text(name)
                .font(.body) // The note list's size, even in small (compact) rows.
                .foregroundStyle(isOnAccent ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if place != .allNotes {
                Text("\(model.noteCount(of: place))")
                    .font(.caption)
                    .foregroundStyle(isOnAccent ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                    .monospacedDigit()
            }
        }
        // Reaching a little past the label, as the system's selection does.
        .background(
            Capsule()
                .fill(isDropTarget ? Color.accentColor.opacity(0.25)
                    : isOnAccent ? Color.accentColor : isSelected ? Color.primary.opacity(0.12) : .clear)
                .padding(.horizontal, -8)
                .padding(.vertical, -2)
        )
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
        case .tag, .everything, .trash: nil
        }
    }

    private var icon: String {
        switch place {
        case .allNotes: "tray"
        case .folder: "folder"
        case .tag: "number"
        case .everything: "tray.full"
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
                .background(Capsule().fill(.quaternary.opacity(0.6)))
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

/// Turns off the system's drawing of the selected row in the List it sits behind, whose
/// table is found among the views around it. The rows draw their own selection (a capsule).
private struct SystemSelectionHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Finder() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Finder)?.hide() }

    final class Finder: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hide()
            // The table can arrive after this view does.
            DispatchQueue.main.async { [weak self] in self?.hide() }
        }

        func hide() {
            var ancestor = superview
            for _ in 0..<8 {
                guard let current = ancestor else { return }
                if let table = Self.table(in: current) {
                    table.selectionHighlightStyle = .none
                    return
                }
                ancestor = current.superview
            }
        }

        /// The first table in a view's subviews that isn't the note list's.
        private static func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, !(table is SidebarTableView) { return table }
            for subview in view.subviews {
                if let found = table(in: subview) { return found }
            }
            return nil
        }
    }
}
