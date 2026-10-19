#if DEBUG
import AppKit
import VaultKit

/// Debug builds only: `-ImprintSnapshots <folder>` opens a few notes in tabs, then saves
/// pictures of the window in a few states (a start page, a note, a new note), so the layout
/// can be checked without anyone at the screen. Add `-showsNoteList NO` to start with the
/// sidebar hidden.
@MainActor
enum DebugSnapshots {
    static func runIfAsked(for model: VaultModel) {
        guard let folder = UserDefaults.standard.string(forKey: "ImprintSnapshots") else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let steps: [(String, () -> Void)] = [
            ("1-note-with-tabs", {
                for note in model.notes.sorted(by: .modified).prefix(3) { model.newTab(noteID: note.id) }
                model.closeOtherTabs(model.panes[0].tabs.count - 1, inPane: 0)
                for note in model.notes.sorted(by: .modified).prefix(2) { model.newTab(noteID: note.id) }
            }),
            ("2-start-page", { model.newTab() }),
            ("3-start-page-explorer", { model.togglePalette(.explorer) }),
            ("3b-start-page-search-again", { model.togglePalette(.search) }),
            ("4-new-note", { model.createNote() }),
            ("5-palette-explorer", {
                model.closeTab() // The new, empty note goes, as an untouched new note does.
                model.togglePalette(.explorer)
            }),
            ("5b-palette-search", { model.togglePalette(.search) }),
            ("6-one-tab", {
                model.isPaletteShown = false
                model.closeOtherTabs(0, inPane: 0)
            }),
            ("8-split", { model.toggleSplit() }),
            ("9-no-list", { model.showsNoteList = false }),
            ("7-note-in-folder", {
                // The deepest note, to show its path in the top bar.
                if let note = model.notes.max(by: { $0.id.filter { $0 == "/" }.count < $1.id.filter { $0 == "/" }.count }) {
                    model.selection = note.id
                }
            }),
        ]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(index) * 2) {
                step.1()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    save(model.window, to: directory.appendingPathComponent(step.0 + ".png"))
                }
            }
        }
    }

    private static func save(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        Trace.mark("snapshot \(url.lastPathComponent)")
    }
}
#endif
