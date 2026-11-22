import IndexKit
import SwiftUI
import VaultKit

/// Browsing folders in the palette (Browse Folders, ⌘E; or a folder picked in Search Vault):
/// one place at a time, as one list. At the vault's top, its pinned places, types, folders and
/// tags, then the notes at its top level; in a folder, its folders then its notes; in a tag,
/// the tags under it then its notes. Return (or →) goes into a place and opens a note; ← (or ⌫
/// with nothing typed) goes back up. Typing filters the place, finding folders and tags inside
/// it at any depth, so a folder deep down is a few letters away.
@MainActor
enum PaletteBrowse {
    /// The place above `place`: a folder's parent, a nested tag's; nil at the vault's top.
    static func parent(of place: SidebarPlace) -> SidebarPlace? {
        switch place {
        case .allNotes: return nil
        case .folder(let path):
            let parent = FolderTree.parent(of: path)
            return parent.isEmpty ? .allNotes : .folder(parent)
        case .tag(let tag):
            guard let slash = tag.lastIndex(of: "/") else { return .allNotes }
            return .tag(String(tag[..<slash]))
        default: return .allNotes
        }
    }

    /// The places from the top down to `place`, the vault's top first.
    static func trail(to place: SidebarPlace) -> [SidebarPlace] {
        var trail = [place]
        while let parent = parent(of: trail[0]) { trail.insert(parent, at: 0) }
        return trail
    }

    /// What a place is called in the trail: the vault's top by the vault's name.
    static func name(of place: SidebarPlace, model: VaultModel) -> String {
        if place == .allNotes { return model.store.root?.lastPathComponent ?? "Vault" }
        if case .tag = place { return "#" + place.shortName }
        return model.title(for: place)
    }

    /// A place as a row: its name (or, found deeper down, its path from here), its count, and
    /// a symbol.
    static func item(_ place: SidebarPlace, from here: SidebarPlace?, model: VaultModel) -> PaletteItem {
        let count = place == .allNotes ? model.notes(in: .allNotes).count : model.store.sidebarCount(of: place)
        var title = model.title(for: place), path: String?
        switch place {
        case .folder(let folder):
            // Inside the folder it's in, its name; deeper, the folders between, under it.
            let parent = FolderTree.parent(of: folder)
            let base: String? = switch here {
            case .folder(let path): path
            case .allNotes, nil: ""
            default: nil
            }
            if model.store.specialFolder(at: folder) == nil, let base, parent != base {
                path = base.isEmpty ? parent : String(parent.dropFirst(base.count + 1))
            }
        case .tag(let tag):
            title = "#" + (here.map { parent(of: place) == $0 } == true ? place.shortName : tag)
        default: break
        }
        return .place(place, title, count, model.symbol(for: place), path)
    }

    /// The rows for `place`, in labelled sections, filtered by `filter`.
    static func sections(at place: SidebarPlace, filter: String, model: VaultModel) -> [(String, [PaletteItem])] {
        let store = model.store
        let filter = filter.trimmingCharacters(in: .whitespaces)
        var sections: [(String, [PaletteItem])] = []
        func places(_ title: String, _ list: [SidebarPlace]) {
            sections.append((title, list.map { item($0, from: place, model: model) }))
        }

        // The places in it: those directly inside, or with something typed, any inside it.
        switch place {
        case .allNotes:
            if filter.isEmpty {
                places("Pinned", model.pins)
                places("Types", store.shownSidebarKinds.map { .kind(store.kinds.property, $0.name) })
                places("Folders", store.specialFolders.map { .folder($0.path) } + model.subplaces(of: .allNotes))
                if store.showsTagsInSidebar { places("Tags", model.subplaces(of: .tags)) }
            } else {
                places("Types", ranked(store.shownSidebarKinds.map { .kind(store.kinds.property, $0.name) }, by: filter, model: model))
                let folders = store.specialFolders.map { SidebarPlace.folder($0.path) }
                    + store.sortedFolders(Array(model.folderTree.noteCounts.keys)).map(SidebarPlace.folder)
                places("Folders", ranked(folders, by: filter, model: model))
                if store.showsTagsInSidebar {
                    places("Tags", ranked(model.tagTree.entries.map { .tag($0.tag) }, by: filter, model: model))
                }
            }
        case .folder(let path):
            if filter.isEmpty {
                places("Folders", model.subplaces(of: place))
            } else {
                let inside = store.sortedFolders(model.folderTree.noteCounts.keys.filter { $0.hasPrefix(path + "/") })
                places("Folders", ranked(inside.map(SidebarPlace.folder), by: filter, model: model))
            }
        case .tag(let tag):
            if filter.isEmpty {
                places("Tags", model.subplaces(of: place))
            } else {
                let inside = model.tagTree.entries.filter { $0.tag.hasPrefix(tag + "/") }.map { SidebarPlace.tag($0.tag) }
                places("Tags", ranked(inside, by: filter, model: model))
            }
        default: break
        }

        // Then its notes, in the list's order.
        var notes = model.notes(in: place).sorted(by: model.sort)
        if !filter.isEmpty { notes = CommandPalette.rank(notes, by: filter, name: \.title) }
        sections.append(("Notes", notes.map { PaletteItem.note($0.id, $0.title, nil) }))
        return sections.filter { !$0.1.isEmpty }
    }

    /// Places matching what's typed, best first, by their name (a folder's, not its path).
    private static func ranked(_ places: [SidebarPlace], by filter: String, model: VaultModel) -> [SidebarPlace] {
        Array(places.compactMap { place -> (SidebarPlace, Int)? in
            let name: String = if case .tag(let tag) = place { tag } else { model.title(for: place) }
            return Fuzzy.score(query: filter, name: name).map { (place, $0) }
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
        .prefix(30))
    }

    /// Folders matching what's typed in Search Vault, best first, at most `limit`.
    static func folders(matching query: String, limit: Int, model: VaultModel) -> [PaletteItem] {
        let store = model.store
        let folders = store.specialFolders.map { SidebarPlace.folder($0.path) }
            + store.sortedFolders(Array(model.folderTree.noteCounts.keys)).map(SidebarPlace.folder)
        return ranked(folders, by: query, model: model).prefix(limit).map { item($0, from: nil, model: model) }
    }
}

/// The trail above the palette's field while browsing: the vault, then each folder down to the
/// one shown, each a click away.
struct PaletteBrowseTrail: View {
    let place: SidebarPlace
    let model: VaultModel
    let go: (SidebarPlace) -> Void

    var body: some View {
        let trail = PaletteBrowse.trail(to: place)
        HStack(spacing: 4) {
            ForEach(Array(trail.enumerated()), id: \.offset) { offset, step in
                if offset > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                let isLast = offset == trail.count - 1
                Button(PaletteBrowse.name(of: step, model: model)) { go(step) }
                    .buttonStyle(.plain)
                    .foregroundStyle(isLast ? .primary : .secondary)
                    .fontWeight(isLast ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // The vault and the folder shown keep their names; those between give way.
                    .layoutPriority(isLast ? 2 : offset == 0 ? 1 : 0)
                    .disabled(isLast)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
