#if DEBUG
import AppKit
import SwiftUI
import VaultKit

/// Debug builds only: `-PointSnapshots <folder>` opens a few notes in tabs, then saves
/// pictures of the window in a few states (a start page, a note, a new note), so the layout
/// can be checked without anyone at the screen. Add `-showsNoteList NO` to start with the
/// sidebar hidden.
@MainActor
enum DebugSnapshots {
    static func runIfAsked(for model: VaultModel) {
        scrollNoteIfAsked(for: model)
        clickBackIfAsked(for: model)
        clickTreeIfAsked(for: model)
        cycleSidebarIfAsked(for: model)
        closeSplitIfAsked(for: model)
        openSplitIfAsked(for: model)
        probeCursorIfAsked(for: model)
        if let spec = UserDefaults.standard.string(forKey: "PointRevealAt"), let bar = spec.firstIndex(of: "|") {
            // `-PointRevealAt "note id|text"`: opens the note at the first place the text is.
            let id = String(spec[..<bar]), target = String(spec[spec.index(after: bar)...])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let note = model.note(id), let text = try? NoteReader.read(contentsOf: note.url) else { return }
                model.open(id, revealing: (text as NSString).range(of: target))
            }
        }
        if let key = UserDefaults.standard.string(forKey: "PointBrowse"), let place = SidebarPlace(key: key) {
            // `-PointBrowse <place key>`: shows that place in the sidebar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.browse(place) }
        }
        trashIfAsked(for: model)
        formatIfAsked(for: model)
        guard let folder = UserDefaults.standard.string(forKey: "PointSnapshots") else { return }
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
                window.isReleasedWhenClosed = false // Closed by hand below, and kept by this code.
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
                window.isReleasedWhenClosed = false // Closed by hand below, and kept by this code.
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

    /// `-PointScrollNote <note ID>`: opens that note and scrolls it partway down (by
    /// `-PointScrollBy`, 120 points unless given), to see what's under the top bar. For a
    /// screen capture of the window: the bar's effects don't show in a snapshot.
    private static func scrollNoteIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointScrollNote") else { return }
        let amount = UserDefaults.standard.object(forKey: "PointScrollBy") == nil ? 120 : UserDefaults.standard.double(forKey: "PointScrollBy")
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

    /// `-PointClickBack YES`: tries the back and forward arrows on the first side's bar
    /// with real mouse events sent through the window, as a person's clicks would go, and
    /// notes in the trace whether each step did what it should.
    /// `-PointSidebarCycle <n>`: hides and shows the sidebar n times (as ⌘S does), tracing the
    /// window's frame and the notes' width after each, to check the window ends where it began.
    /// `-PointWindowFrame "x y w h"` first places the window (to test the screen's edges);
    /// `-PointSidebarButton YES` toggles as the system's sidebar button does, instead of ⌘S.
    private static func cycleSidebarIfAsked(for model: VaultModel) {
        let count = UserDefaults.standard.integer(forKey: "PointSidebarCycle")
        // With a count of 0, only places the window (for screenshots).
        guard count > 0 || UserDefaults.standard.string(forKey: "PointWindowFrame") != nil else { return }
        func notesWidth() -> CGFloat {
            guard let window = model.window else { return 0 }
            return views(of: NSSplitView.self, in: window.contentView).first { ($0.delegate as? NSSplitViewController) != nil }
                .flatMap { $0.arrangedSubviews.last?.frame.width } ?? 0
        }
        func report(_ label: String) {
            guard let window = model.window else { return }
            Trace.mark("sidebar cycle \(label): sidebar \(model.showsNoteList ? "shown" : "hidden"), frame \(window.frame), notes \(notesWidth()), sidebar's view \(model.sidebarSplit.sidebarHost.view.frame), min \(window.minSize) content min \(window.contentMinSize)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let text = UserDefaults.standard.string(forKey: "PointWindowFrame") {
                let parts = text.split(separator: " ").compactMap { Double($0) }
                if parts.count == 4 { model.window?.setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: true) }
            }
            // In sight, without taking the keyboard: a window out of sight doesn't animate.
            model.window?.orderFrontRegardless()
            report("start")
            for step in 0..<(count * 2) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(step) * 0.6) {
                    if UserDefaults.standard.bool(forKey: "PointSidebarButton") {
                        // As the system's sidebar button does.
                        let split = views(of: NSSplitView.self, in: model.window?.contentView).first { ($0.delegate as? NSSplitViewController) != nil }
                        (split?.delegate as? NSSplitViewController)?.toggleSidebar(nil)
                    } else {
                        model.showsNoteList.toggle()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { report("\(step + 1)") }
                }
            }
        }
    }

    /// `-PointCloseSplit <side>`: splits the window if it isn't (opening the first note on the
    /// new side), then closes that side (0 the left, 1 the right), to watch the other slide
    /// across.
    private static func closeSplitIfAsked(for model: VaultModel) {
        guard let text = UserDefaults.standard.string(forKey: "PointCloseSplit"), let side = Int(text) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !model.isSplit {
                model.toggleSplit()
                if let other = model.notes.first(where: { $0.id != model.panes[0].tab.noteID }) { model.selection = other.id }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            Trace.mark("closing split side \(side)")
            model.closePane(side)
        }
    }

    /// `-PointOpenSplit empty|note`: unsplits the window if it's split, then opens a split,
    /// empty (⇧⌘S) or with another note on the new side (⌥⌘-click), to watch it slide in.
    private static func openSplitIfAsked(for model: VaultModel) {
        guard let kind = UserDefaults.standard.string(forKey: "PointOpenSplit") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if model.isSplit { model.mergeIntoTabs() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            Trace.mark("opening split, \(kind)")
            if kind == "note", let other = model.notes.first(where: { !model.openNoteIDs.contains($0.id) }) {
                model.openToTheSide(other.id)
            } else {
                model.toggleSplit()
            }
        }
    }

    /// `-PointCursorProbe YES`: traces the pointer's shape whenever it or the pointer's place
    /// changes, to check where the resize pointer shows.
    private static func probeCursorIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "PointCursorProbe") else { return }
        var last = ""
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let window = model.window else { return }
                let cursor = NSCursor.current
                let name = cursor == .resizeLeftRight ? "resize" : cursor == .iBeam ? "ibeam" : cursor == .arrow ? "arrow" : "other"
                let point = window.mouseLocationOutsideOfEventStream
                let hit = window.contentView?.superview?.hitTest(point)
                var chain = "", view = hit
                for _ in 0..<12 { guard let v = view else { break }; chain += String(describing: type(of: v)).prefix(30) + "\(v.frame.integral) < "; view = v.superview }
                let grips = views(of: ResizeGrip.self, in: window.contentView?.superview).map { "\($0.convert($0.bounds, to: nil).integral) hidden \($0.isHiddenOrHasHiddenAncestor)" }
                let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                let line = "x \(Int(point.x)) \(name) hit \(chain.prefix(40)) grips \(grips.count) responder \(responder)"
                if line != last { last = line; Trace.mark("cursor " + line + " key \(window.isKeyWindow)") }
            }
        }
    }

    private static func views<T: NSView>(of type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        return ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(of: type, in: $0) }
    }

    /// `-PointClickTree YES`: in the two-column view, clicks a note in the list (a real mouse
    /// event), then picks a folder in the tree (by selecting its row, as AppKit does after a
    /// click: synthetic clicks don't reach SwiftUI's rows), tracing where the keyboard goes.
    /// Brings the app to the front.
    private static func clickTreeIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "PointClickTree") else { return }
        func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
        }
        func describe(_ responder: NSResponder?) -> String {
            guard let responder else { return "nil" }
            return String(describing: type(of: responder))
        }
        func click(_ view: NSView, row: Int) {
            guard let window = model.window, let table = view as? NSTableView, row < table.numberOfRows else { return Trace.mark("tree test: no row \(row)") }
            let rect = table.convert(table.rect(ofRow: row), to: nil)
            let point = NSPoint(x: rect.midX, y: rect.midY)
            let hit = window.contentView?.superview?.hitTest(window.contentView!.superview!.convert(point, from: nil))
            Trace.mark("tree test: clicking \(type(of: table)) row \(row) at \(point), hits \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            func event(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            // The mouse-up waits in the queue, for whatever tracks the mouse after the down.
            if let up = event(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
            if let down = event(.leftMouseDown) { window.sendEvent(down) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let root = model.window?.contentView?.superview else { return }
            let lists = views(SidebarTableView.self, in: root)
            let trees = views(NSOutlineView.self, in: root) + views(NSTableView.self, in: root).filter { !($0 is SidebarTableView) && !($0 is NSOutlineView) }
            Trace.mark("tree test: lists \(lists.count) trees \(trees.map { String(describing: type(of: $0)) })")
            guard let list = lists.first, let tree = trees.first else { return }
            NSApp.activate(ignoringOtherApps: true)
            model.window?.makeKeyAndOrderFront(nil)
            click(list, row: 0)
            for delay in [0.2, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Trace.mark("tree test: after note click +\(delay): first responder \(describe(model.window?.firstResponder))") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // As AppKit does after a click on a row (synthetic clicks don't reach SwiftUI's rows).
                (tree as? NSTableView)?.selectRowIndexes([7], byExtendingSelection: false)
                for delay in [0.05, 0.3, 0.8, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Trace.mark("tree test: after tree click +\(delay): first responder \(describe(model.window?.firstResponder)) tree selected row \((tree as? NSTableView)?.selectedRow ?? -9) place \(model.place.key)")
                    }
                }
            }
        }
    }

    private static func clickBackIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "PointClickBack") else { return }
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

    /// `-PointTrashTest <note ID>`: deletes that note, checks it's listed in the trash, puts
    /// it back and checks it's back, noting each step in the trace.
    private static func trashIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointTrashTest") else { return }
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

    /// `-PointFormatTest <note ID>`: opens the note, selects its first word, and runs the
    /// palette's own Bold, then Block Quote, commands, checking the note's text each time.
    private static func formatIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointFormatTest") else { return }
        func check(_ name: String, _ ok: Bool, _ detail: String) { Trace.mark("format test: \(ok ? "PASS" : "FAIL") \(name) \(detail)") }
        func editor() -> NSTextView? {
            func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView, text.isEditable, text.string.count > 3 { return text }
                return view.subviews.lazy.compactMap(find).first
            }
            return model.window?.contentView.flatMap(find)
        }
        func run(_ name: String) { PaletteCommand.all(for: model).first { $0.name == name }?.action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.selection = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let text = editor() else { return check("editor found", false, "") }
                let start = (text.string as NSString).range(of: "Text").location
                guard start != NSNotFound else { return check("word found", false, text.string) }
                text.setSelectedRange(NSRange(location: start, length: 4))
                run("Bold")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    check("Bold", text.string.contains("**Text**"), text.string.replacingOccurrences(of: "\n", with: "⏎"))
                    run("Block Quote")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        check("Block Quote", text.string.contains("> **Text**"), text.string.replacingOccurrences(of: "\n", with: "⏎"))
                        text.undoManager?.undo()
                        text.undoManager?.undo()
                    }
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
