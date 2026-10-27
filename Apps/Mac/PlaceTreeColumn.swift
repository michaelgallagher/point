import SwiftUI
import VaultKit

/// The two-column view's left column: the special places, pinned items, then folders (or
/// tags) as a tree. The same AppKit table as the one-column sidebar, showing its top level
/// only: a SwiftUI list here made every frame of the sidebar sliding in or out take twice as
/// long (the window laid it out again each frame), so the slide ran at half speed.
struct PlaceTreeColumn: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        SidebarTable(model: model, content: .places)
            .onChange(of: model.treeLayout) { _ in model.matchPlaceToTree() }
            .onAppear { model.matchPlaceToTree() }
    }
}

/// A two-way switch the full width of its column, with fully rounded ends. In one column it's
/// only drawn: the sidebar's table takes the click (see `SidebarTable`).
struct CapsuleToggle: View {
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

/// A sort menu drawn as a section label's sort label is in one column: the order's name and
/// small up and down arrows, in the label's own type, opening the choices.
struct SortLabel<Value: Hashable>: View {
    let help: String
    @Binding var selection: Value
    let options: [(name: String, value: Value)]

    var body: some View {
        Menu {
            Picker(help, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.name).tag($0.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 2) {
                Text(options.first { $0.value == selection }?.name ?? "")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}
