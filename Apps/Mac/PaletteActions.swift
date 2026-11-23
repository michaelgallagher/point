import AppKit
import SwiftUI
import VaultKit

/// Doing something to a result in the palette, as Raycast's ⌘K and Tuna's subject → action →
/// target do: ⌘K (or Tab) on a note, folder or tag lists what can be done to it; an action
/// that needs more (Move to…, Apply Template…) asks for it next, in the same list.
enum PaletteStep {
    /// What can be done to this.
    case actions(PaletteSubject)
    /// A folder to move this note to.
    case moveTo(Note.ID)
    /// A template to apply to this note.
    case applyTemplate(Note.ID)
}

/// What an action is done to: a note, or a place (a folder, tag or type).
enum PaletteSubject {
    case note(Note.ID)
    case place(SidebarPlace)

    /// The subject of a result, if it can have actions (a note, folder or tag; not a command).
    init?(_ item: PaletteItem) {
        switch item {
        case .note(let id, _, _): self = .note(id)
        case .place(let place, _, _, _, _): self = .place(place)
        case .tag(let tag, _): self = .place(.tag(tag))
        default: return nil
        }
    }

    @MainActor func title(model: VaultModel) -> String {
        switch self {
        case .note(let id): model.note(id)?.title ?? ""
        case .place(let place): PaletteBrowse.name(of: place, model: model)
        }
    }
}

/// One thing to do to a subject: its name (title case, as the palette's commands), its
/// symbol, a key it has elsewhere, and what it does.
struct PaletteAction {
    let name: String
    let symbol: String
    var shortcut: String?
    let perform: Perform

    enum Perform {
        /// Done at once, the palette closing.
        case run(() -> Void)
        /// Asks for something next (a folder, a template).
        case step(PaletteStep)
        /// Goes into a place, in the palette.
        case browse(SidebarPlace)
        /// Done in the palette, which stays open and lists again (Show All Bookmarks).
        case here(() -> Void)
    }

    @MainActor static func all(for subject: PaletteSubject, model: VaultModel) -> [PaletteAction] {
        switch subject {
        case .note(let id): notes(id, model: model)
        case .place(let place): places(place, model: model)
        }
    }

    @MainActor private static func notes(_ id: Note.ID, model: VaultModel) -> [PaletteAction] {
        guard let note = model.note(id) else { return [] }
        var actions = [
            PaletteAction(name: "Open", symbol: "doc.text", shortcut: "↩", perform: .run { model.selection = id }),
            PaletteAction(name: "Open in New Tab", symbol: "plus.square.on.square", shortcut: "⌘↩", perform: .run { model.newTab(noteID: id) }),
            PaletteAction(name: "Open on Other Side", symbol: "rectangle.split.2x1", perform: .run { model.openToTheSide(id) }),
            PaletteAction(name: "Move to…", symbol: "folder", perform: .step(.moveTo(id))),
        ]
        if !model.templates.isEmpty {
            actions.append(PaletteAction(name: "Apply Template…", symbol: "doc.on.doc", perform: .step(.applyTemplate(id))))
        }
        actions += [
            PaletteAction(name: "Add Tag…", symbol: "number", perform: .run { model.tagging = note }),
            PaletteAction(name: model.isBookmarked(id) ? "Remove Bookmark" : "Add Bookmark",
                          symbol: model.isBookmarked(id) ? "bookmark.slash" : "bookmark", perform: .run { model.toggleBookmark(id) }),
        ]
        if model.canMarkRead(id) {
            actions.append(PaletteAction(name: model.isUnread(id) ? "Mark as Read" : "Mark as Unread",
                                         symbol: model.isUnread(id) ? "circle" : "circle.fill", perform: .run { model.toggleRead(id) }))
        }
        actions += [
            PaletteAction(name: "Rename…", symbol: "pencil", perform: .run { model.renaming = note }),
            PaletteAction(name: "Copy Link", symbol: "link", perform: .run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(LinkResolver.linkText(for: note))]]", forType: .string)
            }),
        ]
        // A link to it in the note being viewed, at its cursor.
        if let viewing = model.selection, viewing != id, EditorSession.editing(viewing) != nil {
            actions.append(PaletteAction(name: "Insert Link", symbol: "link.badge.plus", perform: .run {
                NotificationCenter.default.post(name: .pointInsertText, object: model,
                                                userInfo: ["text": "[[\(LinkResolver.linkText(for: note))]]", "noteID": viewing])
            }))
        }
        actions += [
            PaletteAction(name: "Show in Finder", symbol: "finder", perform: .run { model.showInFinder(note) }),
            PaletteAction(name: "Move to Trash", symbol: "trash", perform: .run { model.moveToTrash(note) }),
        ]
        return actions
    }

    @MainActor private static func places(_ place: SidebarPlace, model: VaultModel) -> [PaletteAction] {
        var actions = [
            PaletteAction(name: "Browse", symbol: "folder", shortcut: "↩", perform: .browse(place)),
            PaletteAction(name: "Show in Sidebar", symbol: "sidebar.left", perform: .run {
                model.showsNoteList = true
                model.browse(place)
            }),
        ]
        let folder: String? = switch place {
        case .allNotes: ""
        case .folder(let path): path
        default: nil
        }
        if let folder {
            actions.append(PaletteAction(name: "New Note Here", symbol: "square.and.pencil", perform: .run { model.createNote(inFolder: folder) }))
        }
        actions.append(PaletteAction(name: "New List of These", symbol: "list.bullet.rectangle", perform: .run { model.createList(of: place) }))
        if place != .allNotes {
            let pinned = model.isPinned(place)
            actions.append(PaletteAction(name: pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.slash" : "pin", perform: .run { model.togglePin(place) }))
        }
        if case .tag(let tag) = place {
            actions.append(PaletteAction(name: "Rename Tag…", symbol: "pencil", perform: .run { model.renamingAcrossVault = .tag(tag) }))
        }
        if let folder, let root = model.store.root {
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
            actions.append(PaletteAction(name: "Show in Finder", symbol: "finder", perform: .run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }))
        }
        return actions
    }
}

/// Above an action's list: what it's done to, then each step after (Inbox › Move to), with a
/// way back.
struct PaletteStepTrail: View {
    let titles: [String]
    let back: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: back) {
                Image(systemName: "chevron.backward")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back (←)")
            ForEach(Array(titles.enumerated()), id: \.offset) { offset, title in
                if offset > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .foregroundStyle(offset == titles.count - 1 ? .primary : .secondary)
                    .fontWeight(offset == titles.count - 1 ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(offset == 0 ? 1 : 2)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
