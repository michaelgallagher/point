import AppKit
import SwiftUI
import VaultKit

/// The palette's explorer, in two columns like the two-column sidebar: pinned places, folders
/// and tags on the left; the notes in the highlighted one on the right. Driven entirely from
/// the palette's text field: ↑↓ move, → (or Return) goes into the notes, ← back to places,
/// and typing filters whichever column has the keyboard.
@MainActor
final class ExplorerState: ObservableObject {
    struct Place: Identifiable, Equatable {
        let id: String
        let place: SidebarPlace
        let title: String
        let depth: Int
        let count: Int
        /// "Pinned", "Folders" or "Tags": a heading shows above each section's first row.
        let section: String
    }

    @Published private(set) var places: [Place] = []
    @Published private(set) var placeIndex = 0
    @Published private(set) var notes: [Note] = []
    @Published private(set) var noteIndex = 0
    /// Whether the keyboard is in the notes column.
    @Published private(set) var inNotes = false

    private var allPlaces: [Place] = []
    private var placeNotes: [Note] = []
    private var filter = ""
    private weak var model: VaultModel?

    var currentPlace: Place? { places.indices.contains(placeIndex) ? places[placeIndex] : nil }
    var currentNote: Note? { notes.indices.contains(noteIndex) ? notes[noteIndex] : nil }

    /// Lists the vault's places, and returns to where the explorer was last left.
    func load(_ model: VaultModel) {
        self.model = model
        var rows: [Place] = model.pins.map {
            Place(id: "pin:" + $0.key, place: $0, title: $0.title, depth: 0, count: model.noteCount(of: $0), section: "Pinned")
        }
        func add(_ nodes: [VaultModel.PlaceNode], depth: Int, section: String) {
            for node in nodes {
                // Nested tags by their own name ("imprint" under "#work"); the vault's count is
                // its top-level notes, which is what its column lists.
                let title = depth > 0 && node.place.isTag ? node.place.shortName : node.name
                let count = node.place == .allNotes ? model.notes(in: .allNotes).count : model.noteCount(of: node.place)
                rows.append(Place(id: section + ":" + node.place.key, place: node.place, title: title, depth: depth,
                                  count: count, section: section))
                add(node.children ?? [], depth: depth + 1, section: section)
            }
        }
        add(model.folderNodes, depth: 0, section: "Folders")
        add(model.tagNodes, depth: 0, section: "Tags")
        allPlaces = rows
        filter = ""
        places = rows
        placeIndex = rows.firstIndex { $0.place == model.explorerPlace && $0.section != "Pinned" }
            ?? rows.firstIndex { $0.place == model.explorerPlace } ?? 0
        loadNotes()
        if model.explorerInNotes, !notes.isEmpty {
            inNotes = true
            noteIndex = notes.firstIndex { $0.id == model.explorerNote } ?? 0
        } else {
            inNotes = false
        }
    }

    /// Filters the column with the keyboard.
    func setFilter(_ text: String) {
        filter = text.trimmingCharacters(in: .whitespaces)
        if inNotes {
            notes = filtered(placeNotes, by: \.title)
            noteIndex = 0
        } else {
            let current = currentPlace?.id
            places = filtered(allPlaces, by: \.title)
            placeIndex = places.firstIndex { $0.id == current } ?? 0
            loadNotes()
        }
    }

    private func filtered<T>(_ things: [T], by name: KeyPath<T, String>) -> [T] {
        filter.isEmpty ? things : CommandPalette.rank(things, by: filter, name: name)
    }

    func move(_ step: Int) {
        if inNotes {
            guard !notes.isEmpty else { return }
            noteIndex = min(max(noteIndex + step, 0), notes.count - 1)
        } else {
            guard !places.isEmpty else { return }
            placeIndex = min(max(placeIndex + step, 0), places.count - 1)
            loadNotes()
        }
        remember()
    }

    func selectPlace(_ index: Int) {
        guard places.indices.contains(index) else { return }
        inNotes = false
        placeIndex = index
        loadNotes()
        remember()
    }

    /// Into the notes column. Returns false if there are none.
    @discardableResult func enterNotes() -> Bool {
        guard !inNotes, !notes.isEmpty else { return false }
        inNotes = true
        noteIndex = 0
        remember()
        return true
    }

    /// Back to the places column. Returns false if already there.
    @discardableResult func leaveNotes() -> Bool {
        guard inNotes else { return false }
        inNotes = false
        notes = placeNotes
        remember()
        return true
    }

    private func loadNotes() {
        guard let model, let place = currentPlace?.place else {
            placeNotes = []
            notes = []
            return
        }
        placeNotes = model.notes(in: place).sorted(by: model.sort)
        notes = placeNotes
        noteIndex = 0
    }

    /// Lists everything again, after something moved, keeping the explorer where it was.
    func reload() {
        guard let model else { return }
        remember()
        let filter = filter
        load(model)
        if !filter.isEmpty { setFilter(filter) }
    }

    private func remember() {
        model?.explorerPlace = currentPlace?.place ?? .allNotes
        model?.explorerInNotes = inNotes
        model?.explorerNote = inNotes ? currentNote?.id : nil
    }
}

/// The explorer's two columns.
struct ExplorerColumns: View {
    @ObservedObject var state: ExplorerState
    let open: (Note.ID) -> Void
    /// Something dragged (a note's ID, or a folder, as the sidebar carries it) dropped on a
    /// folder ("" for the vault's top level).
    var drop: (String, String) -> Void = { _, _ in }
    /// The folder a drag is over, shaded.
    @State private var dropTarget: String?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                placesColumn
                    .frame(width: min(210, geometry.size.width * 0.42))
                Divider()
                notesColumn
            }
        }
    }

    private var placesColumn: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.places.enumerated()), id: \.element.id) { index, place in
                        if index == 0 || state.places[index - 1].section != place.section {
                            Text(place.section)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 2)
                        }
                        ExplorerRow(
                            icon: place.place.isTag ? "number" : (place.place == .allNotes ? "tray" : "folder"),
                            title: place.title,
                            detail: "\(place.count)",
                            indent: CGFloat(place.depth) * 14,
                            isHighlighted: index == state.placeIndex,
                            isFocused: !state.inNotes,
                            isDropTarget: dropTarget == place.id
                        )
                        .id(place.id)
                        .onTapGesture { state.selectPlace(index) }
                        .modifier(ExplorerFolderDrag(place: place, dropTarget: $dropTarget, drop: drop))
                    }
                }
                .padding(6)
            }
            .onChange(of: state.placeIndex) { _ in
                if let id = state.currentPlace?.id { scroller.scrollTo(id) }
            }
        }
    }

    private var notesColumn: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.notes.enumerated()), id: \.element.id) { index, note in
                        ExplorerRow(icon: "doc.text", title: note.title, detail: nil, indent: 0,
                                    isHighlighted: index == state.noteIndex, isFocused: state.inNotes)
                            .id(note.id)
                            .onTapGesture { open(note.id) }
                            // Drag a note onto a folder on the left to move it there.
                            .onDrag { NSItemProvider(object: note.id as NSString) }
                    }
                }
                .padding(6)
            }
            .overlay {
                if state.notes.isEmpty {
                    Text("No Notes").foregroundStyle(.secondary)
                }
            }
            .onChange(of: state.noteIndex) { _ in
                if let id = state.currentNote?.id { scroller.scrollTo(id) }
            }
        }
    }
}

private struct ExplorerRow: View {
    let icon: String
    let title: String
    let detail: String?
    let indent: CGFloat
    let isHighlighted: Bool
    /// The column with the keyboard shows its highlight in the accent colour.
    let isFocused: Bool
    /// A note or folder dragged over this folder would go into it.
    var isDropTarget = false

    private var isAccented: Bool { isHighlighted && isFocused }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(isAccented ? .white : .secondary)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(isAccented ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isAccented ? .white : .primary)
        .padding(.leading, 8 + indent)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(
            isDropTarget ? Color.accentColor.opacity(0.25)
                : isAccented ? Color.accentColor : (isHighlighted ? Color.primary.opacity(0.1) : .clear)
        ))
        .contentShape(Rectangle())
    }
}

/// A folder in the explorer: dragged into another folder, or taking notes and folders dropped
/// on it. The vault's top level takes drops but can't be dragged; tags do neither.
private struct ExplorerFolderDrag: ViewModifier {
    let place: ExplorerState.Place
    @Binding var dropTarget: String?
    let drop: (String, String) -> Void

    private var folder: String? {
        switch place.place {
        case .allNotes: ""
        case .folder(let path): path
        default: nil
        }
    }

    func body(content: Content) -> some View {
        if let folder {
            content
                .onDrag {
                    NSItemProvider(object: (folder.isEmpty ? "" : VaultModel.folderDragPrefix + folder) as NSString)
                }
                .onDrop(of: [.text], isTargeted: Binding(
                    get: { dropTarget == place.id },
                    set: { targeted in
                        if targeted { dropTarget = place.id } else if dropTarget == place.id { dropTarget = nil }
                    }
                )) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let dragged = object as? String, !dragged.isEmpty else { return }
                        Task { @MainActor in drop(dragged, folder) }
                    }
                    return true
                }
        } else {
            content
        }
    }
}
