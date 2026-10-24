#if DEBUG
import AppKit
import SwiftUI
import VaultKit

/// Debug builds only: `-ImprintSnapshots <folder>` opens a few notes in tabs, then saves
/// pictures of the window in a few states (a start page, a note, a new note), so the layout
/// can be checked without anyone at the screen. Add `-showsNoteList NO` to start with the
/// sidebar hidden.
@MainActor
enum DebugSnapshots {
    static func runIfAsked(for model: VaultModel) {
        scrollNoteIfAsked(for: model)
        clickBackIfAsked(for: model)
        if let key = UserDefaults.standard.string(forKey: "ImprintBrowse"), let place = SidebarPlace(key: key) {
            // `-ImprintBrowse <place key>`: shows that place in the sidebar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.browse(place) }
        }
        trashIfAsked(for: model)
        guard let folder = UserDefaults.standard.string(forKey: "ImprintSnapshots") else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let steps: [(String, () -> Void)] = [
            ("1-note-with-tabs", {
                for note in model.notes.sorted(by: .modified).prefix(3) { model.newTab(noteID: note.id) }
                model.closeOtherTabs(model.panes[0].tabs.count - 1, inPane: 0)
                for note in model.notes.sorted(by: .modified).prefix(2) { model.newTab(noteID: note.id) }
            }),
            ("0-shortcuts", { model.isShowingShortcuts = true }),
            ("0b-shortcuts-closed", { model.isShowingShortcuts = false }),
            ("0d-add-property", {
                // The Add Property window, drawn offscreen.
                let host = NSHostingView(rootView: AddPropertySheet().environmentObject(model))
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("0d-add-property.png"))
                    window.close()
                }
            }),
            ("0c-settings", {
                // Settings, drawn offscreen (an app in the background can't open its window).
                let host = NSHostingView(rootView: SettingsView().environmentObject(model.store))
                host.frame = NSRect(x: 0, y: 0, width: 760, height: 540)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("0c-settings-window.png"))
                    window.close()
                }
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
            ("9b-tag-in-explorer", {
                // A tag clicked with the sidebar hidden: its notes, in the explorer.
                if case .tag(let tag)? = model.tagNodes.first?.place { model.search(tag: tag) }
            }),
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

    /// `-ImprintScrollNote <note ID>`: opens that note and scrolls it partway down (by
    /// `-ImprintScrollBy`, 120 points unless given), to see what's under the top bar. For a
    /// screen capture of the window: the bar's effects don't show in a snapshot.
    private static func scrollNoteIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "ImprintScrollNote") else { return }
        let amount = UserDefaults.standard.object(forKey: "ImprintScrollBy") == nil ? 120 : UserDefaults.standard.double(forKey: "ImprintScrollBy")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.selection = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let content = model.window?.contentView else { return }
                for scrollView in scrollViews(in: content) where scrollView.documentView is NSTextView {
                    let clip = scrollView.contentView
                    clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y + amount))
                    scrollView.reflectScrolledClipView(clip)
                }
                Trace.mark("scrolled \(id) by \(amount)")
            }
        }
    }

    /// `-ImprintClickBack YES`: tries the back and forward arrows on the first side's bar
    /// with real mouse events sent through the window, as a person's clicks would go, and
    /// notes in the trace whether each step did what it should.
    private static func clickBackIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "ImprintClickBack") else { return }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("click test: \(ok ? "PASS" : "FAIL") \(name) \(detail)")
        }
        func click(back: Bool) {
            guard let window = model.window, let frame = window.contentView?.superview else { return }
            func clickViews(in view: NSView) -> [NSView] {
                (view is ClickArea.ClickView ? [view] : []) + view.subviews.flatMap(clickViews(in:))
            }
            let areas = clickViews(in: frame).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            guard areas.count >= 2 else { return check("arrows found", false) }
            let rect = areas[back ? 0 : 1].convert(areas[back ? 0 : 1].bounds, to: nil)
            let point = NSPoint(x: rect.midX, y: rect.midY)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    window.sendEvent(event)
                }
            }
        }
        var steps: [() -> Void] = []
        var a = "", b = ""
        steps.append {
            // Start from one side, with a fresh tab.
            if model.isSplit { model.mergeIntoTabs() }
            model.newTab()
            let open = Set(model.openNoteIDs)
            let picks = model.notes.filter { !open.contains($0.id) }.prefix(2).map(\.id)
            guard picks.count == 2 else { return check("enough notes", false) }
            (a, b) = (picks[0], picks[1])
            check("a new tab has Back off", !model.canTravel(back: true, inPane: 0))
            model.selection = a
            model.selection = b
            check("after A then B, Back is on", model.canTravel(back: true, inPane: 0))
        }
        steps.append { click(back: true) }
        steps.append {
            check("Back shows A", model.selection == a, "showing \(model.selection ?? "nil")")
            check("then Back is off, Forward on", !model.canTravel(back: true, inPane: 0) && model.canTravel(back: false, inPane: 0))
        }
        steps.append { click(back: false) }
        steps.append {
            check("Forward shows B", model.selection == b, "showing \(model.selection ?? "nil")")
            // A second tab has its own, empty, history; it opens A (not open anywhere now).
            model.newTab()
            check("another tab has its own history", !model.canTravel(back: true, inPane: 0))
            model.selection = a
            check("the other tab shows A", model.selection == a)
            // Back to the first tab, B, and back from there to A, which the other tab has.
            let first = model.panes[0].tabs.firstIndex { $0.noteID == b } ?? 0
            model.selectTab(first, inPane: 0)
        }
        steps.append { click(back: true) }
        steps.append {
            check("Back to a note open in another tab moves it here", model.selection == a, "showing \(model.selection ?? "nil")")
            check("that note is open once", model.openNoteIDs.filter { $0 == a }.count == 1)
            check("the other tab steps back (to a start page)", model.panes[0].tabs.contains { $0.noteID == nil })
        }
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(index) * 0.6, execute: step)
        }
    }

    /// `-ImprintTrashTest <note ID>`: deletes that note, checks it's listed in the trash, puts
    /// it back and checks it's back, noting each step in the trace.
    private static func trashIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "ImprintTrashTest") else { return }
        func check(_ name: String, _ ok: Bool) { Trace.mark("trash test: \(ok ? "PASS" : "FAIL") \(name)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let note = model.note(id) else { return check("note found", false) }
            model.moveToTrash(note)
            check("gone from the notes", model.note(id) == nil)
            check("listed in the trash", model.trashedNotes.contains { $0.title == note.title })
            model.browse(.trash)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let item = model.trashedNotes.first(where: { $0.title == note.title }) else { return check("still listed", false) }
                model.store.restore(item)
                check("gone from the trash", !model.trashedNotes.contains { $0.title == note.title })
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    check("back where it was", model.note(id) != nil)
                }
            }
        }
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
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
