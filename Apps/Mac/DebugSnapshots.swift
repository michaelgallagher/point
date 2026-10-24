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

    /// `-ImprintClickBack YES`: opens two notes one after the other, then clicks the bar's
    /// Back arrow with real mouse events sent through the window, as a person's click would
    /// go, and notes which note is in front before and after.
    private static func clickBackIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "ImprintClickBack") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let open = Set(model.openNoteIDs)
            let picks = model.notes.filter { !open.contains($0.id) }.prefix(2).map(\.id)
            guard picks.count == 2 else { return Trace.mark("click test: not enough notes") }
            model.selection = picks[0]
            model.selection = picks[1]
            Trace.mark("click test: showing \(model.selection ?? "nil"), back \(model.backStack.suffix(2))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let window = model.window, let frame = window.contentView?.superview else { return }
                func clickViews(in view: NSView) -> [NSView] {
                    (view is ClickArea.ClickView ? [view] : []) + view.subviews.flatMap(clickViews(in:))
                }
                let areas = clickViews(in: frame).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
                guard let back = areas.first else { return Trace.mark("click test: no click areas") }
                let rect = back.convert(back.bounds, to: nil)
                let point = NSPoint(x: rect.midX, y: rect.midY)
                let hit = frame.hitTest(frame.convert(point, from: nil))
                Trace.mark("click test: \(areas.count) areas, back at \(rect), hit \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        window.sendEvent(event)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Trace.mark("click test: after clicking Back, showing \(model.selection ?? "nil") (expected \(picks[0]))")
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
