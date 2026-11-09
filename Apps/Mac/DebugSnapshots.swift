#if DEBUG
import AppKit
import IndexKit
import UniformTypeIdentifiers
import EditorKit
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
        scrollTestIfAsked(for: model)
        typeTestIfAsked(for: model)
        markerClickTestIfAsked(for: model)
        focusFieldIfAsked(for: model)
        clickBackIfAsked(for: model)
        clickTreeIfAsked(for: model)
        cycleSidebarIfAsked(for: model)
        closeSplitIfAsked(for: model)
        openSplitIfAsked(for: model)
        probeCursorIfAsked(for: model)
        conflictIfAsked(for: model)
        safetyIfAsked(for: model)
        shortcutTestIfAsked(for: model)
        tabTestIfAsked(for: model)
        tabTimingIfAsked(for: model)
        tabBarIfAsked(for: model)
        scanIfAsked(for: model)
        // `-PointOpenSettings YES`: opens Settings (at `-settingsPage`), for checking it.
        if UserDefaults.standard.bool(forKey: "PointOpenSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // As the app menu's Settings item does.
                if let menu = NSApp.mainMenu?.items.first?.submenu,
                   let index = menu.items.firstIndex(where: { $0.title.hasPrefix("Settings") }) {
                    menu.performActionForItem(at: index)
                }
            }
            // With `-PointWindowSnapshot`, the picture is of Settings.
            if let path = UserDefaults.standard.string(forKey: "PointWindowSnapshot") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Trace.mark("settings test: windows \(NSApp.windows.map { "\($0.title) \($0.frame) \($0.isVisible)" })")
                    save(NSApp.windows.first { $0 !== model.window && $0.isVisible && $0.contentView != nil && $0.frame.width > 600 },
                         to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if let path = UserDefaults.standard.string(forKey: "PointWindowSnapshot") {
            // `-PointWindowSnapshot <file.png>`: a picture of the window, drawn by the app (so
            // it works with the screen locked), after `-PointSnapshotDelay` seconds (5); then quits.
            let delay = UserDefaults.standard.double(forKey: "PointSnapshotDelay")
            DispatchQueue.main.asyncAfter(deadline: .now() + (delay > 0 ? delay : 5)) {
                save(model.window, to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        if let line = UserDefaults.standard.string(forKey: "PointUntitledTest") {
            // `-PointUntitledTest "first line"`: makes a note, types the line, then goes to a
            // note open in another tab, as a click in the list does.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                model.createNote()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard let id = model.selection else { return }
                    NotificationCenter.default.post(name: .pointInsertText, object: model, userInfo: ["text": line, "noteID": id])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let other = model.panes.flatMap(\.tabs).compactMap(\.noteID).first { $0 != id }
                        Trace.mark("untitled test: \(id) → \(other ?? "none")")
                        if let other { model.selectFromList(other) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            Trace.mark("untitled test: tabs now \(model.panes.flatMap(\.tabs).compactMap(\.noteID))")
                        }
                    }
                }
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "PointRetitle"), let bar = spec.firstIndex(of: "|") {
            // `-PointRetitle "note.md|New title"`: renames the note, as its title field does.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let note = model.note(String(spec[..<bar])) else { return Trace.mark("retitle: no note") }
                model.rename(note, to: String(spec[spec.index(after: bar)...]))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    Trace.mark("retitle: notes now \(model.notes.map { "\($0.id)=\($0.title)" })")
                    NSApp.terminate(nil)
                }
            }
        }
        if let id = UserDefaults.standard.string(forKey: "PointTypeTiming") {
            // `-PointTypeTiming <note ID>`: types 30 letters at the note's middle, each with its
            // layout and the views over the text brought up to date, and notes the slowest.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                model.selection = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let content = model.window?.contentView,
                          let view = scrollViews(in: content).lazy.compactMap({ $0.documentView as? MarkdownTextView }).first,
                          let layoutManager = view.layoutManager, let container = view.textContainer else { return Trace.mark("type timing: no editor") }
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length / 2, length: 0))
                    var times: [Double] = []
                    for _ in 0..<30 {
                        let start = DispatchTime.now().uptimeNanoseconds
                        view.insertText("a", replacementRange: view.selectedRange())
                        layoutManager.ensureLayout(for: container)
                        RunLoop.main.run(until: Date()) // The views over the text, brought up to date.
                        view.displayIfNeeded()
                        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    }
                    let sorted = times.sorted()
                    Trace.mark(String(format: "type timing: median %.2f ms, slowest %.2f ms, %d image views", sorted[15], sorted.last!, view.subviews.count))
                    NSApp.terminate(nil)
                }
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "PointFollowLink"), let bar = spec.firstIndex(of: "|") {
            // `-PointFollowLink "note.md|target"`: follows a wikilink in that note, as a click does.
            let id = String(spec[..<bar]), target = String(spec[spec.index(after: bar)...])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let before = model.notes.count
                model.selection = id
                model.open(.note(target), from: id, inPane: model.panes[model.activePane].id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    Trace.mark("follow link: tab shows \(model.selection ?? "nothing"), notes \(before) → \(model.notes.count)")
                    NSApp.terminate(nil)
                }
            }
        }
        if let path = UserDefaults.standard.string(forKey: "PointOpenImage") {
            // `-PointOpenImage <path>`: opens the image at that path from the vault's root in the tab.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                Trace.mark("open image: \(model.store.image(path) == nil ? "not found" : "found")")
                model.selection = path
                // With `-PointRenameImageTo <name>`: renames it, as the viewer's Rename does.
                if let name = UserDefaults.standard.string(forKey: "PointRenameImageTo"), let image = model.store.image(path) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let renamed = model.store.renameImage(image, to: name)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            Trace.mark("rename image: now \(renamed?.path ?? "not renamed"), tab shows \(model.selection ?? "nothing")")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
        if UserDefaults.standard.bool(forKey: "PointUnusedImages") {
            // `-PointUnusedImages YES`: notes the images no note shows, once the index is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Task {
                    let unused = await model.store.unusedImages()
                    Trace.mark("unused images: \(unused.map(\.path)) of \(model.store.images.map(\.path).sorted())")
                    NSApp.terminate(nil)
                }
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "PointImagePaste"), let bar = spec.firstIndex(of: "|") {
            // `-PointImagePaste "note.md|image file"`: puts the image into the note at its end, as
            // pasting it would (without touching the pasteboard), then saves.
            let id = String(spec[..<bar]), file = URL(fileURLWithPath: String(spec[spec.index(after: bar)...]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                model.selection = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let content = model.window?.contentView,
                          let view = scrollViews(in: content).lazy.compactMap({ $0.documentView as? MarkdownTextView }).first,
                          let data = try? Data(contentsOf: file) else { return Trace.mark("image paste: no editor or image") }
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                    let pasted = view.insertImages([(data, UTType(filenameExtension: file.pathExtension))])
                    Trace.mark("image paste: \(pasted ? "pasted" : "not pasted")")
                    NotificationCenter.default.post(name: .pointSaveNow, object: nil)
                }
            }
        }
        if UserDefaults.standard.bool(forKey: "PointNewNote") {
            // `-PointNewNote YES`: makes a new note (as ⌘N does), three seconds in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Trace.mark("new note")
                model.createNote()
            }
        }
        if let which = UserDefaults.standard.string(forKey: "PointTemplateSheet") {
            // `-PointTemplateSheet apply|new`: shows the template sheet, for checking it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if which == "new" { model.isCreatingFromTemplate = true } else { model.applyTemplateInPalette() }
            }
        }
        if let name = UserDefaults.standard.string(forKey: "PointTemplateTest") {
            // `-PointTemplateTest <template name>`: applies that template to the note open,
            // then starts a note from it, named "From <name>".
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let template = model.templates.first(where: { $0.name == name }) else { return Trace.mark("template test: no template \(name)") }
                model.applyTemplate(at: template.url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if UserDefaults.standard.bool(forKey: "PointTemplateUndo") {
                        // With `-PointTemplateUndo YES`: one undo instead, which should take it all back.
                        model.window?.firstResponder?.undoManager?.undo()
                    } else {
                        model.createNote(fromTemplate: template.url, titled: "From \(name)")
                    }
                }
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "PointListSheet"), let bar = spec.firstIndex(of: "|"),
           let path = UserDefaults.standard.string(forKey: "PointSheetSnapshot") {
            // `-PointListSheet "note id|new"` (or `|condition:1`) with `-PointSheetSnapshot <file.png>`:
            // opens a list, then its filter window, and saves a picture of the window; then quits.
            let id = String(spec[..<bar]), target = String(spec[spec.index(after: bar)...])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { model.selection = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                NotificationCenter.default.post(name: .pointOpenListFilter, object: nil, userInfo: ["target": target])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                Trace.mark("list sheet: attached \(model.window?.attachedSheet != nil), windows \(NSApp.windows.map { "\(type(of: $0)) \($0.frame.size)" })")
                save(model.window?.attachedSheet ?? NSApp.windows.first { "\(type(of: $0))".contains("Sheet") }, to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "PointListTest") {
            // `-PointListTest "note id"`: opens a list and changes it as its menus do, in steps,
            // tracing the note's properties after each; then undoes them all.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                model.selection = spec
                guard let note = model.note(spec) else { return }
                func list() -> ListDefinition? {
                    (try? NoteReader.read(contentsOf: note.url)).flatMap { ListDefinition(frontmatter: Frontmatter.parse($0)) }
                }
                let steps: [(String, (inout ListDefinition) -> Void)] = [
                    ("add condition", { $0.conditions.append(ListCondition("rating", .greater, "3")) }),
                    ("match any", { $0.matchesAny = true }),
                    ("remove folder and tags", { $0.folders = []; $0.tags = [] }),
                    ("sort by title", { $0.sort = [NoteQuery.Sort(.field(.title))] }),
                    ("remove columns", { $0.columns = [] }),
                    ("remove all conditions", { $0.conditions = []; $0.matchesAny = false }),
                    ("add folder", { $0.folders = ["Elsewhere"] }),
                ]
                for (index, step) in steps.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * 2.5) {
                        guard var current = list() else { return Trace.mark("list test: not a list before \(step.0)") }
                        step.1(&current)
                        NotificationCenter.default.post(name: .pointWriteList, object: nil, userInfo: ["noteID": spec, "list": current])
                        NotificationCenter.default.post(name: .pointSaveNow, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            let text = (try? NoteReader.read(contentsOf: note.url)) ?? ""
                            Trace.mark("list test: \(step.0)\n\(Frontmatter.parse(text).map { (text as NSString).substring(with: $0.range) } ?? "none")")
                        }
                    }
                }
            }
        }
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
            // With `-PointTrace`, the rows the sidebar shows there, as text (pictures the app
            // draws of itself leave out the sidebar's table), once the index has answered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                for row in model.sidebarRows(collapsed: []) {
                    switch row {
                    case .header(let section): Trace.mark("row: [\(section.title)]")
                    case .place(let place, let depth):
                        Trace.mark("row: \(String(repeating: "  ", count: depth))\(model.symbol(for: place)) \(place.title) \(model.noteCount(of: place))")
                    case .note(let id): Trace.mark("row: note \(id)")
                    case .divider: Trace.mark("row: ---")
                    default: Trace.mark("row: \(row)")
                    }
                }
            }
        }
        // `-PointRenameTest "tag:work|job"` (or `property:name|new`, `value:name|value|new`): renames
        // across the vault, traces each note's text, undoes, and traces them again.
        if let spec = UserDefaults.standard.string(forKey: "PointRenameTest") {
            let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let kind = parts[0].split(separator: ":", maxSplits: 1).map(String.init)
            let rename: VaultStore.VaultRename? = switch kind.first {
            case "tag": .tag(kind[1])
            case "property": .property(kind[1])
            case "value": .value(property: kind[1], value: parts[1])
            default: nil
            }
            func dump(_ label: String) {
                for note in model.notes.sorted(by: { $0.id < $1.id }) {
                    let text = (try? NoteReader.read(contentsOf: note.url)) ?? "?"
                    Trace.mark("\(label) \(note.id): \(text.replacingOccurrences(of: "\n", with: "⏎"))")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let rename, let new = parts.last else { return }
                model.store.rename(rename, to: new)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dump("after")
                    Trace.mark("notice: \(model.store.vaultChangeNotice?.text ?? "none")")
                    model.store.undoLastVaultChange()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dump("undone")
                        Trace.mark("notice: \(model.store.vaultChangeNotice?.text ?? "none")")
                        NSApp.terminate(nil)
                    }
                }
            }
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

    /// `-PointTypeTest <note ID>`: opens that note, scrolls it by `-PointScrollBy` (300),
    /// puts the cursor on the line in the middle of the view, then types `-PointTypeText`
    /// ("abc" and Return unless given) a key at a time through the window, tracing where the
    /// note is scrolled to after each key. A note that jumps while typing shows as a change.
    private static func typeTestIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointTypeTest") else { return }
        let amount = UserDefaults.standard.object(forKey: "PointScrollBy") == nil ? 300 : UserDefaults.standard.double(forKey: "PointScrollBy")
        let text = UserDefaults.standard.string(forKey: "PointTypeText") ?? "abc\rdef\r"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.selection = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let window = model.window, let content = window.contentView,
                      let view = scrollViews(in: content).lazy.compactMap({ $0.documentView as? MarkdownTextView }).first,
                      let scrollView = view.enclosingScrollView, let layoutManager = view.layoutManager, let container = view.textContainer else {
                    Trace.mark("type test: no editor"); return
                }
                let clip = scrollView.contentView
                clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y + amount))
                scrollView.reflectScrolledClipView(clip)
                let fraction = UserDefaults.standard.object(forKey: "PointTypeAt") == nil ? 0.5 : UserDefaults.standard.double(forKey: "PointTypeAt")
                let visibleTop = clip.bounds.minY + scrollView.contentInsets.top
                let y = visibleTop + (clip.bounds.maxY - visibleTop) * fraction
                let middle = NSPoint(x: container.lineFragmentPadding + 2, y: y - view.textContainerOrigin.y)
                var index = layoutManager.characterIndexForGlyph(at: layoutManager.glyphIndex(for: middle, in: container))
                // `-PointTypeIn <text>`: in the first place after there that has it (a table's cell, say).
                if let marker = UserDefaults.standard.string(forKey: "PointTypeIn") {
                    let found = (view.string as NSString).range(of: marker, range: NSRange(location: index, length: (view.string as NSString).length - index))
                    if found.location != NSNotFound { index = NSMaxRange(found) }
                }
                window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: index, length: 0))
                Trace.mark("type test: scrolled \(clip.bounds.minY) inset \(scrollView.contentInsets.top) header \(view.headerHeight) cursor \(index)")
                func next(_ keys: [Character]) {
                    guard let first = keys.first else {
                        for t in 1...8 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(t)) { Trace.mark("type test: +\(t)s \(clip.bounds.minY) header \(view.headerHeight)") }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                            Trace.mark("type test: settled \(clip.bounds.minY) header \(view.headerHeight)")
                            NSApp.terminate(nil)
                        }
                        return
                    }
                    let key = String(first)
                    let before = clip.bounds.minY
                    let window = view.window ?? window
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key,
                                                        isARepeat: false, keyCode: key == "\r" ? 36 : 0) {
                            window.sendEvent(event)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        let after = clip.bounds.minY
                        Trace.mark("type test: \(key == "\r" ? "⏎" : key) \(before) → \(after)\(abs(after - before) > 0.5 ? " JUMP \(after - before)" : "") header \(view.headerHeight) insets \(scrollView.contentInsets.top)/\(scrollView.contentInsets.bottom) clip \(clip.bounds.height) caret \(view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil).minY) responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "-")")
                        next(Array(keys.dropFirst()))
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next(Array(text)) }
            }
        }
    }

    /// `-PointScrollTest <note ID>`: opens that (long) note and traces, as PASS or FAIL:
    /// whether a scroll to the end just after the width changes reaches the last line (the
    /// note's height not a guess); whether the line at the top stays there as the window
    /// narrows and widens and the sidebar hides and shows; and whether going to another tab
    /// and back comes back to the same place.
    private static func scrollTestIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointScrollTest") else { return }
        func textView() -> MarkdownTextView? {
            guard let content = model.window?.contentView else { return nil }
            return scrollViews(in: content).lazy.compactMap { $0.documentView as? MarkdownTextView }.first
        }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("scroll test: \(ok ? "PASS" : "FAIL") \(name) \(detail)")
        }
        /// The character at the top, below the bars.
        func top() -> Int {
            guard let view = textView(), let scrollView = view.enclosingScrollView, let layoutManager = view.layoutManager,
                  let container = view.textContainer else { return -1 }
            let y = scrollView.contentView.bounds.minY + scrollView.contentInsets.top - view.textContainerOrigin.y
            return layoutManager.characterIndexForGlyph(at: layoutManager.glyphIndex(for: NSPoint(x: 5, y: y), in: container))
        }
        func scroll(toFraction fraction: CGFloat) {
            guard let view = textView(), let scrollView = view.enclosingScrollView else { return }
            let clip = scrollView.contentView
            let y = fraction >= 1 ? view.frame.height - clip.bounds.height : view.frame.height * fraction
            clip.scroll(to: NSPoint(x: 0, y: max(-scrollView.contentInsets.top, y)))
            scrollView.reflectScrolledClipView(clip)
        }
        /// Whether the note's last character is in sight.
        func endInSight() -> Bool {
            guard let view = textView(), let layoutManager = view.layoutManager, let container = view.textContainer else { return false }
            let length = (view.string as NSString).length
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: max(0, length - 1), length: 1), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.y += view.textContainerOrigin.y
            return view.visibleRect.intersects(rect)
        }
        func resize(by amount: CGFloat) {
            guard let window = model.window else { return }
            var frame = window.frame
            frame.size.width += amount
            window.setFrame(frame, display: true)
        }
        var steps: [(Double, () -> Void)] = []
        var before = -1
        steps.append((2.5, {
            model.window?.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 800), display: true)
            model.selection = id
        }))
        // Scrolling to the end soon after the width changes.
        for (index, amount) in [-180.0, 180, -260, 260].enumerated() {
            steps.append((1.5, {
                // From the top, so nothing else lays out the whole note.
                scroll(toFraction: 0)
                resize(by: amount)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // The height a fast scroll would stop at, then the real one, all laid out.
                    guard let view = textView(), let layoutManager = view.layoutManager else { return }
                    let shown = view.frame.height
                    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (view.string as NSString).length))
                    view.sizeToFit()
                    scroll(toFraction: 1)
                    check("height real soon after resize \(index + 1)", abs(view.frame.height - shown) < 2 && endInSight(),
                          "height was \(Int(shown)), really \(Int(view.frame.height))")
                }
            }))
        }
        // The line at the top, through resizes and the sidebar.
        steps.append((1.2, { scroll(toFraction: 0.45) }))
        steps.append((0.5, { before = top() }))
        for (name, change) in [("narrower", { resize(by: -240) }), ("wider", { resize(by: 240) }),
                               ("sidebar toggled", { model.showsNoteList.toggle() }), ("sidebar toggled back", { model.showsNoteList.toggle() })] {
            steps.append((0.1, change))
            steps.append((1.0, {
                let now = top()
                check("top line kept, \(name)", abs(now - before) < 80, "was \(before), now \(now)")
            }))
        }
        // Another tab and back.
        var selection = NSRange()
        steps.append((0.5, {
            textView()?.setSelectedRange(NSRange(location: max(0, before + 5), length: 0))
            selection = textView()?.selectedRange() ?? NSRange()
            before = top()
            let other = model.notes.first { $0.id != id }?.id
            model.newTab(noteID: other)
        }))
        steps.append((1.5, { model.selection = id }))
        steps.append((1.5, {
            let now = top()
            check("place kept across tabs", abs(now - before) < 80, "was \(before), now \(now)")
            check("cursor kept across tabs", textView()?.selectedRange() == selection, "was \(selection), now \(textView()?.selectedRange() ?? NSRange())")
            Trace.mark("scroll test: done")
            NSApp.terminate(nil)
        }))
        var delay = 0.0
        for (wait, step) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
    }

    /// `-PointMarkerClickTest <note ID>`: opens that note and ⌘-clicks across the start of
    /// each of its list items (where the bullet or checkbox is), tracing which ones open the
    /// highlight colours (closing the menu again), then plainly clicks the same places, tracing
    /// whether the text changed (a checkbox ticked).
    private static func markerClickTestIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointMarkerClickTest") else { return }
        var opened: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            opened.append(menu.items.map(\.title).joined(separator: "/"))
            RunLoop.main.perform(inModes: [.eventTracking, .default, .modalPanel]) { menu.cancelTrackingWithoutAnimation() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            model.window?.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 800), display: true)
            model.selection = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            guard let content = model.window?.contentView,
                  let view = scrollViews(in: content).lazy.compactMap({ $0.documentView as? MarkdownTextView }).first,
                  let layoutManager = view.layoutManager, let window = view.window else { return }
            func click(_ point: NSPoint, command: Bool) {
                let location = view.convert(point, to: nil)
                if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: command ? .command : [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                   let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: command ? .command : [],
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(up, atStart: false) // For the text view's own tracking of the click.
                    view.mouseDown(with: event)
                }
            }
            let text = view.string as NSString
            var start = 0
            while start < text.length {
                let line = text.lineRange(for: NSRange(location: start, length: 0))
                let content = text.substring(with: line).trimmingCharacters(in: .newlines)
                start = NSMaxRange(line)
                guard content.hasPrefix("- ") || content.hasPrefix("1. ") else { continue }
                let rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: line.location), effectiveRange: nil)
                let y = rect.midY + view.textContainerOrigin.y
                opened = []
                var hits: [Int] = []
                for dx in stride(from: 0, through: 40, by: 2) {
                    let before = opened.count
                    click(NSPoint(x: view.textContainerOrigin.x + CGFloat(dx), y: y), command: true)
                    if opened.count > before { hits.append(dx) }
                }
                let menu = opened.first ?? "none"
                var ticked: [Int] = []
                for dx in stride(from: 0, through: 40, by: 2) {
                    let before = view.string
                    click(NSPoint(x: view.textContainerOrigin.x + CGFloat(dx), y: y), command: false)
                    if view.string != before {
                        ticked.append(dx)
                        view.undoManager?.undo()
                    }
                }
                Trace.mark("marker test: \(content) ⌘-click menu at \(hits.first ?? -1)…\(hits.last ?? -1): \(menu); plain click changed text at \(ticked.first ?? -1)…\(ticked.last ?? -1)")
            }
            NotificationCenter.default.removeObserver(observer)
            NSApp.terminate(nil)
        }
    }

    /// `-PointFocusField <n>`: four seconds in (after `-PointScrollNote` has opened a note),
    /// saves pictures of the window before the nth text field in it has the keyboard, with
    /// it, and after, to `-PointWindowSnapshot`'s path with -1, -2 and -3 added; then quits.
    /// `-PointFocusType <text>` types that into it first (`«` for `[`), and `-PointFocusTab YES`
    /// then presses Tab; the note's file is traced at the end.
    private static func focusFieldIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.object(forKey: "PointFocusField") != nil,
              let path = UserDefaults.standard.string(forKey: "PointWindowSnapshot") else { return }
        let index = UserDefaults.standard.integer(forKey: "PointFocusField")
        func shot(_ n: Int) { save(model.window, to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(n).png"))) }
        // Longer for a big vault (`-PointFocusDelay`), which takes a while to open.
        let delay = UserDefaults.standard.object(forKey: "PointFocusDelay") != nil ? UserDefaults.standard.double(forKey: "PointFocusDelay") : 4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = model.window else { return }
            // Top to bottom: they're found in no fixed order.
            let fields = views(of: NSTextField.self, in: window.contentView).filter { $0.isEditable }
                .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
            Trace.mark("focus test: fields \(fields.map { "\($0.placeholderString ?? "") \($0.convert($0.bounds, to: nil))" })")
            guard fields.indices.contains(index) else { return }
            shot(1)
            // A click on the field, through the window, as a person's would go.
            func click(at point: NSPoint) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        if type == .leftMouseUp { NSApp.postEvent(event, atStart: false) } else { window.sendEvent(event) }
                    }
                }
            }
            let frame = fields[index].convert(fields[index].bounds, to: nil)
            click(at: NSPoint(x: frame.minX + 20, y: frame.midY))
            // `-PointFocusTypeSlow "text"`: typed a character at a time, tracing how long each
            // one keeps the app busy (until the next turn of the run loop after it's drawn).
            if let typed = UserDefaults.standard.string(forKey: "PointFocusTypeSlow")?.replacingOccurrences(of: "«", with: "[") {
                // `-PointFocusTypeGap`: seconds between characters (0.15 if not given).
                let gap = UserDefaults.standard.object(forKey: "PointFocusTypeGap") != nil ? UserDefaults.standard.double(forKey: "PointFocusTypeGap") : 0.15
                @MainActor func type(_ characters: ArraySlice<Character>) {
                    guard let first = characters.first, let editor = window.firstResponder as? NSTextView else { return }
                    let character = String(first)
                    let start = CACurrentMediaTime()
                    // As key presses through the window, as a person's come ("⌫" deletes back).
                    _ = editor
                    let isDelete = character == "⌫"
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil,
                                                        characters: isDelete ? "\u{7F}" : character, charactersIgnoringModifiers: isDelete ? "\u{7F}" : character,
                                                        isARepeat: false, keyCode: isDelete ? 51 : 0) {
                            window.sendEvent(event)
                        }
                    }
                    DispatchQueue.main.async {
                        window.displayIfNeeded()
                        CATransaction.flush()
                        DispatchQueue.main.async {
                            Trace.mark("slow type: \(character) took \(Int((CACurrentMediaTime() - start) * 1000)) ms")
                            DispatchQueue.main.asyncAfter(deadline: .now() + gap) { type(characters.dropFirst()) }
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { type(Array(typed)[...]) }
            }
            if let typed = UserDefaults.standard.string(forKey: "PointFocusType")?.replacingOccurrences(of: "«", with: "[") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    (window.firstResponder as? NSTextView)?.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Trace.mark("focus test: first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
                shot(2)
                // `-PointFocusClick "left down"`: then a click that far left of the field's bottom
                // left corner and below it, such as on a suggestion, tracing the view it hits.
                if let text = UserDefaults.standard.string(forKey: "PointFocusClick") {
                    // ("up" before the second number goes above the field's bottom instead.)
                    let parts = text.replacingOccurrences(of: "up", with: "-").split(separator: " ").compactMap { Double($0) }
                    if parts.count == 2 {
                        let point = NSPoint(x: frame.minX - parts[0], y: frame.minY - parts[1])
                        let hit = window.contentView?.superview?.hitTest(point)
                        Trace.mark("focus test: click at \(point) hits \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                        // Both queued: sent at once, a button's mouse down tracks the mouse
                        // until a mouse up that, queued after it, never came. (SwiftUI's tap
                        // gestures don't take these clicks; buttons and fields do.)
                        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                                NSApp.postEvent(event, atStart: false)
                            }
                        }
                        Trace.mark("focus test: click queued")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Trace.mark("focus test: after the click, \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") holds \((window.firstResponder as? NSTextView)?.string ?? "-")")
                            shot(4)
                        }
                    }
                }
                if UserDefaults.standard.bool(forKey: "PointFocusTab"),
                   let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
                                              isARepeat: false, keyCode: 48) {
                    window.sendEvent(tab)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        Trace.mark("focus test: after Tab, field holds \((window.firstResponder as? NSTextView)?.string ?? "-")")
                    }
                }
                // Away again, after Tab has had its effect (not while typing slowly).
                if UserDefaults.standard.string(forKey: "PointFocusTypeSlow") == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { window.makeFirstResponder(nil) }
                }
                let slow = UserDefaults.standard.string(forKey: "PointFocusTypeSlow") != nil
                DispatchQueue.main.asyncAfter(deadline: .now() + (slow ? 12 : 3.5)) {
                    shot(3)
                    if let note = model.note(model.selection) {
                        Trace.mark("focus test: file now\n" + ((try? String(contentsOf: note.url, encoding: .utf8)) ?? "?"))
                    }
                    NSApp.terminate(nil)
                }
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
            if UserDefaults.standard.bool(forKey: "PointFrameLog") {
                FrameLog.shared.start(in: model.window)
                if UserDefaults.standard.bool(forKey: "PointFrameProbe") {
                    FrameLog.shared.probe = {
                        guard let window = model.window, let content = window.contentView else { return "" }
                        func place(_ view: NSView?) -> String {
                            guard let view, view.window != nil else { return "-" }
                            let frame = view.convert(view.bounds, to: nil)
                            return "\(Int(frame.minX))+\(Int(frame.width))"
                        }
                        let tables = views(of: SidebarTableView.self, in: content)
                        let cells = tables.map { table in table.rows(in: table.visibleRect).length > 0 ? table.view(atColumn: 0, row: table.rows(in: table.visibleRect).location, makeIfNecessary: false) : nil }
                        let split = model.sidebarSplit.splitView
                        let button = views(of: NSHostingView<SidebarButton>.self, in: window.contentView?.superview).first
                        return "button \(place(button)) window \(Int(window.frame.width)) sidebar \(place(split.arrangedSubviews.first)) host \(place(split.arrangedSubviews.first?.subviews.first)) tables \(tables.map(place)) firstCells \(cells.map(place)) notes \(place(split.arrangedSubviews.last))"
                    }
                }
                // How many views each part of the window has: the window's layout visits them all.
                func count(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + count($1) } }
                if let split = model.sidebarSplit.isViewLoaded ? model.sidebarSplit.splitView : nil {
                    Trace.mark("views: window \(model.window?.contentView?.superview.map(count) ?? 0), sidebar \(split.arrangedSubviews.first.map(count) ?? 0), notes \(split.arrangedSubviews.last.map(count) ?? 0), tree \(views(of: NSOutlineView.self, in: split).first.map(count) ?? 0)")
                }
            }
            report("start")
            // `-PointSidebarZoom YES`: the window fills the screen (zoomed) after the first hide,
            // so the sidebar shows again in place rather than widening the window.
            let zooms = UserDefaults.standard.bool(forKey: "PointSidebarZoom")
            for step in 0..<(count * 2) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(step) * (zooms ? 1.5 : 0.6)) {
                    if zooms, step == 1, let window = model.window, !window.isZoomed {
                        window.zoom(nil)
                        // `-PointSidebarSwitch YES`: and the sidebar changes to two columns while hidden.
                        if UserDefaults.standard.bool(forKey: "PointSidebarSwitch") { model.browsingStyle = .twoColumns }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { report("zoomed") }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            model.showsNoteList.toggle()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { report("\(step + 1)") }
                        }
                        return
                    }
                    if UserDefaults.standard.bool(forKey: "PointSidebarButton") {
                        // As the system's sidebar button does.
                        let split = views(of: NSSplitView.self, in: model.window?.contentView).first { ($0.delegate as? NSSplitViewController) != nil }
                        (split?.delegate as? NSSplitViewController)?.toggleSidebar(nil)
                    } else {
                        model.showsNoteList.toggle()
                    }
                    FrameLog.shared.mark()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        report("\(step + 1)")
                        FrameLog.shared.report("\(step + 1) \(model.showsNoteList ? "show" : "hide")")
                    }
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

    /// `-PointTabBar <tabs> [split]`: opens that many notes in tabs (with `split`, the last on
    /// the other side) and scrolls them under the bars, for pictures of the tab row.
    private static func tabBarIfAsked(for model: VaultModel) {
        guard let spec = UserDefaults.standard.string(forKey: "PointTabBar") else { return }
        let words = spec.split(separator: " ")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for note in model.notes.prefix(Int(words.first ?? "") ?? 3) { model.newTab(noteID: note.id) }
            model.closeTab(0, inPane: 0)
            if words.contains("split") { model.moveTabToOtherSide() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard UserDefaults.standard.object(forKey: "PointScrollBy") != nil, let content = model.window?.contentView else { return }
                for scrollView in scrollViews(in: content) where scrollView.documentView is NSTextView {
                    let clip = scrollView.contentView
                    clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y + UserDefaults.standard.double(forKey: "PointScrollBy")))
                    scrollView.reflectScrolledClipView(clip)
                }
            }
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
        // `-PointSplitLinks YES`: and the links panel opens on the left side only.
        if UserDefaults.standard.bool(forKey: "PointSplitLinks") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
                guard let first = model.panes.first else { return }
                for pane in model.panes { model.setLinksPanelOpen(pane.id == first.id, for: pane.id) }
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
            let imagesBefore = model.store.images.map(\.path).sorted()
            model.moveToTrash(note)
            check("gone from the notes", model.note(id) == nil)
            check("listed in the trash", model.trashedNotes.contains { $0.title == note.title })
            model.browse(.trash)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // The images only it showed went with it.
                Trace.mark("trash test: images before \(imagesBefore), in the trash with it \(Set(imagesBefore).subtracting(model.store.images.map(\.path)).sorted())")
                guard let item = model.trashedNotes.first(where: { $0.title == note.title }) else { return check("still listed", false) }
                model.store.restore(item)
                check("gone from the trash", !model.trashedNotes.contains { $0.title == note.title })
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    check("back where it was", model.note(id) != nil)
                    Task {
                        await model.store.reload()
                        check("its images back", model.store.images.map(\.path).sorted() == imagesBefore)
                    }
                }
            }
        }
    }

    /// `-PointConflictTest "<note ID>|keep|theirs|leave|rename"`, with `-PointSaveDelay 60` so
    /// typing stays unsaved: opens the note, types a line, then changes the file as another app
    /// would, and checks the banner shows and nothing is overwritten. Then Keep Mine, Use
    /// Theirs, or leaving the note (a conflict copy). `rename` instead renames the note the
    /// open one links to first (`[[Conflict target]]`), and checks the typing and the new link
    /// both end up in the file. Each step is noted in the trace.
    private static func conflictIfAsked(for model: VaultModel) {
        guard let spec = UserDefaults.standard.string(forKey: "PointConflictTest"), let bar = spec.lastIndex(of: "|") else { return }
        let id = String(spec[..<bar]), mode = String(spec[spec.index(after: bar)...])
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("conflict test (\(mode)): \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        func session() -> EditorSession? { EditorSession.live.allObjects.first { $0.note.id == id && $0.debugText != nil } }
        func start(tries: Int) {
            guard let note = model.note(id) else {
                if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { start(tries: tries - 1) } }
                else { check("note found", false, model.store.root?.path ?? "no vault") }
                return
            }
            run(note)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { start(tries: 20) }
        func run(_ note: Note) {
            model.selectFromList(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let session = session(), let original = try? String(contentsOf: note.url, encoding: .utf8) else {
                    return check("note open", false)
                }
                NotificationCenter.default.post(name: .pointInsertText, object: model, userInfo: ["text": "Mine\n", "noteID": id])
                let mine = session.debugText ?? ""
                check("typing unsaved", mine.contains("Mine") && (try? String(contentsOf: note.url, encoding: .utf8)) == original)
                if mode == "rename" {
                    guard let target = model.note("Conflict target.md") else { return check("target found", false) }
                    model.store.rename(target, to: "Conflict target renamed")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        let file = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
                        check("typing saved", file.contains("Mine"))
                        check("link updated in the file", file.contains("[[Conflict target renamed]]"), file)
                        check("editor shows both", (session.debugText ?? "").contains("Mine") && (session.debugText ?? "").contains("[[Conflict target renamed]]"))
                        check("no banner", session.conflict == nil)
                    }
                    return
                }
                // Another app adds a line, writing in place as Obsidian does.
                let theirs = original + "Theirs\n"
                try? Data(theirs.utf8).write(to: note.url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if case .changedElsewhere? = session.conflict { check("banner shows", true) } else { check("banner shows", false) }
                    NotificationCenter.default.post(name: .pointSaveNow, object: nil) // As switching apps does.
                    check("their text not overwritten", (try? String(contentsOf: note.url, encoding: .utf8)) == theirs)
                    check("my typing still showing", session.debugText == mine)
                    let folder = note.url.deletingLastPathComponent()
                    let copiesBefore = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.contains("(conflict ") } ?? []
                    switch mode {
                    case "keep":
                        session.keepMine()
                        check("file has mine", (try? String(contentsOf: note.url, encoding: .utf8)) == mine)
                        check("banner gone", session.conflict == nil)
                    case "theirs":
                        session.useTheirs()
                        check("editor shows theirs", session.debugText == theirs)
                        check("file has theirs", (try? String(contentsOf: note.url, encoding: .utf8)) == theirs)
                        check("banner gone", session.conflict == nil)
                    default:
                        let other = model.notes.first { $0.id != id && !$0.id.hasPrefix("Conflict") }
                        if let other { model.selectFromList(other.id) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            let copies = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.contains("(conflict ") && !copiesBefore.contains($0) } ?? []
                            check("file still theirs", (try? String(contentsOf: note.url, encoding: .utf8)) == theirs)
                            let copy = copies.first.flatMap { try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
                            check("conflict copy has mine", copy == mine, copies.joined(separator: ", "))
                        }
                    }
                }
            }
        }
    }

    /// `-PointSafetyTest YES`, with `-PointSaveDelay 60` and `-PointNoAlerts YES`, on a vault
    /// holding `Safe.md`, `Taken.md`, `Other.md` and `Gone.md`: the failures from the review of
    /// 27 October. A rename to a name that's taken, a save that fails (the file made read-only),
    /// a rename and a trash move while edits can't be saved, a trash move that fails, a kept
    /// draft offered when a note opens, a note deleted elsewhere, and an untitled note whose
    /// edits can't be saved. Each step is noted in the trace.
    private static func safetyIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "PointSafetyTest") else { return }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("safety test: \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        func session(_ id: Note.ID) -> EditorSession? { EditorSession.live.allObjects.first { $0.note.id == id && $0.debugText != nil } }
        func type(_ text: String, in id: Note.ID) {
            NotificationCenter.default.post(name: .pointInsertText, object: model, userInfo: ["text": text, "noteID": id])
        }
        func file(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "<none>" }
        func setWritable(_ url: URL, _ writable: Bool) {
            try? FileManager.default.setAttributes([.posixPermissions: writable ? 0o644 : 0o444], ofItemAtPath: url.path)
        }
        func showing(_ id: Note.ID) -> Bool { model.panes.contains { $0.tab.noteID == id } }
        // Steps a second and a half apart, each after the last.
        var steps: [() -> Void] = []
        func run(_ index: Int = 0) {
            guard index < steps.count else { return Trace.mark("safety test: done") }
            steps[index]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { run(index + 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let root = model.store.root, let note = model.note("Safe.md") else { return check("vault", false) }
            let url = note.url, taken = root.appendingPathComponent("Taken.md")
            let takenBefore = file(taken)
            steps = [
                { model.selectFromList("Safe.md") },
                {
                    // A rename to a name that's taken: refused, and the note goes on saving.
                    type("One\n", in: "Safe.md")
                    model.store.rename(note, to: "Taken")
                    check("rename to a taken name refused", file(url).contains("One") && file(taken) == takenBefore)
                    type("Two\n", in: "Safe.md")
                    check("still saves after", session("Safe.md")?.save() == true && file(url).contains("Two"), file(url))
                },
                {
                    // A save that fails: said so, and the edits kept as a draft.
                    setWritable(url, false)
                    type("Three\n", in: "Safe.md")
                    let session = session("Safe.md")
                    check("failed save reported", session?.save() == false && session?.saveProblem != nil, session?.saveProblem ?? "")
                    check("edits kept as a draft", model.store.drafts?.draft(for: "Safe.md")?.text.contains("Three") == true)
                    // Nothing moved while its edits can't be saved.
                    model.store.rename(note, to: "Renamed")
                    check("not renamed while unsaved", FileManager.default.fileExists(atPath: url.path)
                          && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed.md").path))
                    model.moveToTrash(note)
                    check("not trashed while unsaved", FileManager.default.fileExists(atPath: url.path) && showing("Safe.md"))
                },
                {
                    setWritable(url, true)
                    let session = session("Safe.md")
                    session?.retrySave()
                    check("saved once it can be", file(url).contains("Three") && session?.saveProblem == nil, file(url))
                    check("draft gone once saved", model.store.drafts?.draft(for: "Safe.md") == nil)
                },
                {
                    // A trash move that fails (the trash is a file, not a folder): the note stays open.
                    let trash = root.appendingPathComponent(".trash")
                    try? FileManager.default.removeItem(at: trash)
                    try? Data().write(to: trash)
                    model.moveToTrash(note)
                    check("failed trash move leaves it open", FileManager.default.fileExists(atPath: url.path) && showing("Safe.md"))
                    try? FileManager.default.removeItem(at: trash)
                    type("Four\n", in: "Safe.md")
                    check("and still saving", session("Safe.md")?.save() == true && file(url).contains("Four"))
                },
                {
                    // A draft kept from before, offered as the note opens.
                    try? model.store.drafts?.keep("Recovered\n", for: "Other.md")
                    model.selectFromList("Other.md")
                },
                {
                    let session = session("Other.md")
                    check("draft offered", session?.recoveredDraft?.text == "Recovered\n")
                    session?.restoreDraft()
                    check("draft restored and saved", file(root.appendingPathComponent("Other.md")) == "Recovered\n")
                    check("draft gone", model.store.drafts?.draft(for: "Other.md") == nil)
                },
                { model.selectFromList("Gone.md") },
                {
                    // Deleted in another app with edits unsaved: not written again unasked.
                    guard let gone = model.note("Gone.md"), let session = session("Gone.md") else { return check("Gone.md open", false) }
                    type("Edit\n", in: "Gone.md")
                    try? FileManager.default.removeItem(at: gone.url)
                    check("deleted note not recreated", session.save() == false && session.fileIsMissing
                          && !FileManager.default.fileExists(atPath: gone.url.path))
                    check("its edits kept", model.store.drafts?.draft(for: "Gone.md")?.text.contains("Edit") == true)
                    session.recreateFile()
                    check("written again when asked", file(gone.url).contains("Edit") && session.saveProblem == nil)
                },
                { model.createNote() },
                {
                    // An untitled note whose edits can't be saved isn't treated as empty.
                    guard let id = model.selection, model.store.isUntitled(id), let untitled = model.note(id) else {
                        return check("untitled note", false)
                    }
                    type("Hello untitled", in: id)
                    setWritable(untitled.url, false)
                    model.store.finishUntitledNote(id)
                    check("unsaved untitled note kept", FileManager.default.fileExists(atPath: untitled.url.path) && model.store.isUntitled(id))
                    setWritable(untitled.url, true)
                    model.store.finishUntitledNote(id)
                    check("named once saved", FileManager.default.fileExists(atPath: root.appendingPathComponent("Hello untitled.md").path)
                          && !FileManager.default.fileExists(atPath: untitled.url.path))
                },
            ]
            run()
        }
    }

    /// `-PointScanTest <other vault>`: the overlapping scans from the review of 27 October. A
    /// burst of 20 reloads (as a burst of changes from iCloud starts) runs one scan and one
    /// more, not 20; a note added during a burst is shown; and opening the other vault while
    /// this one's being scanned shows only the other vault's notes.
    private static func scanIfAsked(for model: VaultModel) {
        guard let other = UserDefaults.standard.string(forKey: "PointScanTest") else { return }
        let store = model.store
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("scan test: \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard let root = store.root else { return check("vault", false) }
            let before = store.debugScans.started
            let added = root.appendingPathComponent("Added during burst \(UUID().uuidString.prefix(4)).md")
            for index in 0..<20 {
                if index == 10 { try? Data("New".utf8).write(to: added) }
                Task { await store.reload() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let scans = store.debugScans.started - before
                check("a burst of 20 reloads coalesced", scans <= 3, "\(scans) scans")
                check("a note added during the burst is shown", store.notes.contains { $0.url.lastPathComponent == added.lastPathComponent })
                try? FileManager.default.removeItem(at: added)
                // Another vault opened while this one's being scanned.
                Task { await store.reload() }
                let otherURL = URL(fileURLWithPath: other)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    store.debugOpen(otherURL)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        let expected = (try? VaultScanner.scan(otherURL).count) ?? -1
                        let strays = store.notes.filter { !$0.url.path.hasPrefix(otherURL.path) }
                        check("only the other vault's notes", strays.isEmpty && store.notes.count == expected,
                              "\(store.notes.count) notes, \(strays.count) from the first vault, expected \(expected)")
                        Trace.mark("scan test: done")
                    }
                }
            }
        }
    }

    /// `-PointTabTest YES`, on a vault of at least four notes: opens four tabs, then checks
    /// their numbers, ⌥⌘1 to ⌥⌘9, and ⌃Tab: a quick one, one held until the palette shows, and
    /// one pressed twice. (Letting go of ⌃ is called directly: it can't be pressed from here.)
    /// `-PointTabTiming "a.md,b.md,c.md,d.md"`: opens those notes in tabs, then goes from tab
    /// to tab, tracing how long each switch keeps the app busy and how long until the new
    /// note's text shows (its editor is hidden until its header is measured).
    private static func tabTimingIfAsked(for model: VaultModel) {
        guard let spec = UserDefaults.standard.string(forKey: "PointTabTiming") else { return }
        let ids = spec.split(separator: ",").map(String.init)
        // Not napping: in the background, macOS held back the app's timers for seconds.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Timing tab switches")
        _ = Unmanaged.passRetained(activity as AnyObject)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard let window = model.window else { return }
            while model.numberedTabs.count > 1 { model.closeTab() }
            model.selection = ids[0]
            ids.dropFirst().forEach { model.newTab(noteID: $0) }
            let order = [0, 1, 2, 3, 0, 2, 1, 3, 0, 1, 2, 3, 2, 0, 3, 1]
            final class Times { var busy: Double? }
            @MainActor func step(_ n: Int) {
                guard n < order.count else { return NSApp.terminate(nil) }
                guard let note = model.note(ids[order[n]]), let contents = try? String(contentsOf: note.url, encoding: .utf8) else { return }
                let marker = String(contents.prefix(120))
                let start = CACurrentMediaTime()
                let times = Times()
                model.selectTab(order[n], inPane: 0)
                Trace.mark("tab timing: selectTab returned after \(Int((CACurrentMediaTime() - start) * 1000)) ms; window \(window.title) visible \(window.isVisible)")
                DispatchQueue.main.async {
                    Trace.mark("tab timing: first turn")
                    window.displayIfNeeded()
                    DispatchQueue.main.async { times.busy = CACurrentMediaTime() - start }
                }
                // Until a text view showing the note shows, checked each millisecond.
                @MainActor func poll() {
                    let shown = views(of: MarkdownTextView.self, in: window.contentView).filter {
                        $0.alphaValue > 0 && !$0.isHiddenOrHasHiddenAncestor && $0.window != nil && $0.string.hasPrefix(marker)
                    }
                    let elapsed = CACurrentMediaTime() - start
                    if elapsed > 1.9 {
                        Trace.mark("tab timing: views \(views(of: MarkdownTextView.self, in: window.contentView).map { "\($0.alphaValue) \($0.isHiddenOrHasHiddenAncestor) \($0.string.prefix(40).debugDescription)" }) want \(marker.prefix(40).debugDescription) selection \(model.selection ?? "-")")
                    }
                    if !shown.isEmpty || elapsed > 2 {
                        Trace.mark("tab timing: to tab \(order[n]) busy \(times.busy.map { Int($0 * 1000) } ?? -1) ms, shown \(shown.isEmpty ? "never" : "\(Int(elapsed * 1000)) ms")")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { step(n + 1) }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { poll() }
                    }
                }
                poll()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { step(0) }
        }
    }

    private static func tabTestIfAsked(for model: VaultModel) {
        guard UserDefaults.standard.bool(forKey: "PointTabTest") else { return }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("tab test: \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let ids = Array(model.notes.prefix(4).map(\.id))
            guard ids.count == 4 else { return check("four notes", false) }
            // From one tab, whatever the last run left open.
            while model.numberedTabs.count > 1 { model.closeTab() }
            model.selection = ids[0]
            ids.dropFirst().forEach { model.newTab(noteID: $0) }
            @MainActor func at() -> Int { model.selection.flatMap(model.tabNumber(of:)) ?? 0 }
            func go(_ number: Int?) -> @MainActor () -> Void { { model.goToTab(number: number) } }
            let steps: [(Double, @MainActor () -> Void)] = [
                (0.2, { check("numbers follow tab order", ids.map(model.tabNumber(of:)) == [1, 2, 3, 4]) }),
                (0.2, {
                    let menu = NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu?.items.first { $0.title == "Go to Tab" }?.submenu
                    let keys = (menu?.items ?? []).map { "\($0.title) \($0.keyEquivalent) \($0.keyEquivalentModifierMask == [.command, .option])" }
                    check("the menu has ⌥⌘1 to ⌥⌘9", keys.count == 9 && keys[2] == "Tab 3 3 true" && keys[8] == "Last Tab 9 true", "\(keys)")
                }),
                (0.2, go(2)), (0.2, { check("⌥⌘2 goes to tab 2", at() == 2, "\(at())") }),
                (0.2, go(nil)), (0.2, { check("⌥⌘9 goes to the last", at() == 4, "\(at())") }),
                (0.2, go(9)), (0.2, { check("past the end stays put", at() == 4, "\(at())") }),
                // Tab 2, then 4: a quick ⌃Tab goes back to 2, with no palette.
                (0.2, { model.beginTabSwitch(holding: .control); model.tabSwitchKeysChanged([]) }),
                (0.3, { check("quick ⌃Tab flips", at() == 2 && !model.isPaletteShown, "tab \(at()), palette \(model.isPaletteShown)") }),
                // Held until the palette shows: letting go goes to the tab before, 4.
                (0.2, { model.beginTabSwitch(holding: .control) }),
                (0.6, { check("held ⌃Tab shows the palette", model.isPaletteShown && model.paletteMode == .tabs) }),
                (0.2, { model.tabSwitchKeysChanged([.control, .shift]) }),
                (0.2, { check("another key held keeps it open", model.isPaletteShown) }),
                (0.2, { model.tabSwitchKeysChanged([]) }),
                (0.4, { check("letting go goes to the tab before", at() == 4 && !model.isPaletteShown, "tab \(at())") }),
                // Twice before it shows: one down from the tab before (2), which is 3.
                (0.2, { model.beginTabSwitch(holding: .control); model.togglePalette(.tabs) }),
                (0.6, { model.tabSwitchKeysChanged([]) }),
                (0.4, { check("⌃Tab twice moves down", at() == 3 && !model.isPaletteShown, "tab \(at())") }),
                (0.2, go(1)),
                (0.2, { model.moveTabToOtherSide() }),
                (0.4, { check("the left side's come first", model.tabNumber(of: ids[1]) == 1 && model.tabNumber(of: ids[0]) == 4,
                              "\(ids.map(model.tabNumber(of:)))") }),
                (0.2, { Trace.mark("tab test: done"); NSApp.terminate(nil) }),
            ]
            var delay = 0.5
            for (wait, step) in steps {
                delay += wait
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { step() } }
            }
        }
    }

    /// `-PointShortcutTest <note ID>`, on a note whose first line is a list item: presses ⇧⌘1 and
    /// ⇧⌘2 through the menus (orange and red highlights), gives orange ⌃⌘J and presses that, then
    /// ⌘F and ⌘E (Search Vault and Explorer). Puts the shortcuts back as they were after.
    private static func shortcutTestIfAsked(for model: VaultModel) {
        guard let id = UserDefaults.standard.string(forKey: "PointShortcutTest") else { return }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            Trace.mark("shortcut test: \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        @MainActor func press(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags, unmodified: String) -> Bool {
            guard let window = model.window,
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: unmodified, isARepeat: false, keyCode: keyCode) else { return false }
            return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
        }
        @MainActor func session() -> EditorSession? { EditorSession.live.allObjects.first { $0.note.id == id && $0.debugText != nil } }
        let store = ShortcutStore.shared
        let saved = UserDefaults.standard.dictionary(forKey: "shortcuts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            model.selectFromList(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let text = session()?.debugText else { return check("note open", false) }
                // In front, as when the keys are pressed for real: menu commands go to the key
                // window, and the menus update for an app that's active.
                NSApp.activate(ignoringOtherApps: true)
                model.window?.makeKeyAndOrderFront(nil)
                model.window?.makeFirstResponder(nil)
                if let editor = Self.views(of: MarkdownTextView.self, in: model.window?.contentView).first {
                    model.window?.makeFirstResponder(editor)
                    editor.setSelectedRange(NSRange(location: 3, length: 0))
                }
                @MainActor func menuKey(_ title: String) -> String {
                    func find(_ menu: NSMenu?) -> NSMenuItem? {
                        for item in menu?.items ?? [] {
                            if item.title == title { return item }
                            if let found = find(item.submenu) { return found }
                        }
                        return nil
                    }
                    guard let item = find(NSApp.mainMenu?.items.first { $0.title == "Format" }?.submenu) else { return "none" }
                    return "\(item.keyEquivalent) \(item.keyEquivalentModifierMask.rawValue)"
                }
                @MainActor func line() -> String { String((session()?.debugText ?? "").prefix(12)) }
                // Steps a little apart: a menu command's action runs just after its key is matched.
                @MainActor func menuItem(_ path: [String]) -> (NSMenu, Int)? {
                    var menu = NSApp.mainMenu
                    for title in path.dropLast() { menu = menu?.items.first { $0.title == title }?.submenu }
                    guard let menu, let index = menu.items.firstIndex(where: { $0.title == path.last }) else { return nil }
                    return (menu, index)
                }
                let editor = Self.views(of: MarkdownTextView.self, in: model.window?.contentView).first
                // An app in the background has no key window, so a menu command that goes to the
                // first responder finds no editor: the editor's command is sent to it directly, and
                // the menus are checked for their keys (their actions, which need the window in
                // front, can't be run here).
                let steps: [@MainActor () -> Void] = [
                    { check("editor takes the command", NSApp.sendAction(#selector(MarkdownTextView.highlightListItems(_:)), to: editor, from: MarkdownTextView.ListHighlightRequest(colour: "Orange"))) },
                    { check("it highlights orange", line().hasPrefix("- ? "), line())
                      NSApp.sendAction(#selector(MarkdownTextView.highlightListItems(_:)), to: editor, from: MarkdownTextView.ListHighlightRequest(colour: "Red")) },
                    { check("then red", line().hasPrefix("- ! "), line())
                      NSApp.sendAction(#selector(MarkdownTextView.highlightListItems(_:)), to: editor, from: MarkdownTextView.ListHighlightRequest(colour: nil)) },
                    { check("then none", line().hasPrefix("- one"), line())
                      check("⇧⌘1 is a menu key", press("!", keyCode: 18, [.command, .shift], unmodified: "1"))
                      check("⇧⌘2 is a menu key", press("@", keyCode: 19, [.command, .shift], unmodified: "2"))
                      Trace.mark("shortcut test: Orange's key before \(menuKey("Orange"))")
                      store.set(Shortcut("j", control: true), for: .highlightOrange) },
                    { Trace.mark("shortcut test: Orange's key 0.6 s after \(menuKey("Orange"))") },
                    { Trace.mark("shortcut test: Orange's key 1.2 s after \(menuKey("Orange"))")
                      check("⌃⌘J is a menu key once set", press("\u{0A}", keyCode: 38, [.command, .control], unmodified: "j"))
                      check("palette label follows", store.label(for: .highlightOrange) == "⌃⌘J")
                      check("⌘E is a menu key", press("e", keyCode: 14, .command, unmodified: "e"))
                      check("⌘F is a menu key", press("f", keyCode: 3, .command, unmodified: "f"))
                      check("⌘F is Edit › Search Vault", menuItem(["Edit", "Search Vault"]).map { $0.0.items[$0.1].keyEquivalent } == "f")
                      check("⌘E is Edit › Explorer", menuItem(["Edit", "Explorer"]).map { $0.0.items[$0.1].keyEquivalent } == "e") },
                ]
                for (index, step) in steps.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.6) { MainActor.assumeIsolated { step() } }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps.count) * 0.6) {
                    do {
                        // Back as they were, and the note too.
                        store.resetAll()
                        UserDefaults.standard.set(saved, forKey: "shortcuts")
                        if let editor = Self.views(of: MarkdownTextView.self, in: model.window?.contentView).first {
                            editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
                            editor.insertText(text, replacementRange: editor.selectedRange())
                        }
                        Trace.mark("shortcut test: done")
                    }
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
/// `-PointFrameLog YES`, with `-PointSidebarCycle`: the time between the frames drawn while
/// the sidebar slides, from a display link, so a stutter shows as a long one.
@MainActor
final class FrameLog: NSObject {
    static let shared = FrameLog()
    private var link: AnyObject?
    private var times: [CFTimeInterval] = []
    private var since: CFTimeInterval = 0

    func start(in window: NSWindow?) {
        guard #available(macOS 14, *), let view = window?.contentView, link == nil else { return }
        // A watchdog: notes when the main thread doesn't answer for 100 ms.
        Thread.detachNewThread {
            while true {
                let asked = CACurrentMediaTime()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 0.1) == .timedOut {
                    answered.wait()
                    Trace.mark("main thread blocked \(Int((CACurrentMediaTime() - asked) * 1000)) ms")
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @available(macOS 14, *)
    @objc private func tick(_ link: CADisplayLink) {
        times.append(link.timestamp)
        if let probe, CACurrentMediaTime() - since < 0.4 { Trace.mark("probe \(probe())") }
    }

    /// With `-PointFrameProbe YES`: where things are in the window, traced every frame of a slide.
    var probe: (() -> String)?

    func mark() { since = CACurrentMediaTime() }

    func report(_ label: String) {
        guard link != nil else { return }
        let frames = times.filter { $0 >= since }
        let gaps = zip(frames.dropFirst(), frames).map { ($0 - $1) * 1000 }
        let long = gaps.filter { $0 > 20 }
        Trace.mark("frames \(label): \(frames.count) frames, longest \(String(format: "%.0f", gaps.max() ?? 0)) ms, over 20 ms: \(long.map { String(format: "%.0f", $0) }), all: \(gaps.map { String(format: "%.0f", $0) }.joined(separator: " "))")
    }
}
#endif
