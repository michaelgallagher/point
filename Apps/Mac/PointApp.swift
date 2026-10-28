import AppKit
import SwiftUI
import VaultKit

@main
struct PointApp: App {
    /// The vault, shared by every window and tab.
    @StateObject private var store = VaultStore()

    init() {
        // Point has its own tabs, inside each side of a window; no window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async { AppIcon.applyChosen() }
    }

    var body: some Scene {
        // Each window has its own notes (in panes and tabs), folder, search and history.
        WindowGroup(id: "main", for: TabRequest.self) { $request in
            WindowRoot(store: store, request: request)
        } defaultValue: {
            TabRequest()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(store: store)
            FormatCommands()
        }
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

/// What a new window should show. Unique each time, so asking for a note in a new window
/// always opens one rather than finding an older window that once showed it.
struct TabRequest: Codable, Hashable {
    var id = UUID()
    var noteID: String?
}

/// One window: its own model, over the shared store.
struct WindowRoot: View {
    let store: VaultStore
    let request: TabRequest
    @StateObject private var model: VaultModel
    @Environment(\.openWindow) private var openWindow

    init(store: VaultStore, request: TabRequest) {
        self.store = store
        self.request = request
        _model = StateObject(wrappedValue: VaultModel(store: store))
    }

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(store)
            .focusedSceneObject(model)
            .background(WindowTabbing(
                onAttach: { [weak model] window in model?.window = window },
                onBecomeKey: { [weak store, weak model] in store?.activeWindow = model }
            ))
            .onAppear {
                model.openWindowHandler = { noteID in openWindow(id: "main", value: TabRequest(noteID: noteID)) }
                #if DEBUG
                DebugSnapshots.runIfAsked(for: model)
                #endif
                if let noteID = request.noteID, model.selection == nil {
                    model.selection = noteID
                } else if request.noteID == nil, store.claimWindowRestore() {
                    model.restoreWindowState()
                }
            }
    }
}

/// Reports the window, and when it comes to the front. Point keeps its own tabs, inside
/// each side of a window, so macOS's window tabs are turned off.
private struct WindowTabbing: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void
    let onBecomeKey: () -> Void

    func makeNSView(context: Context) -> TabbingView {
        let view = TabbingView()
        view.onAttach = onAttach
        view.onBecomeKey = onBecomeKey
        return view
    }

    func updateNSView(_ view: TabbingView, context: Context) {
        view.onAttach = onAttach
        view.onBecomeKey = onBecomeKey
    }

    final class TabbingView: NSView {
        var onAttach: ((NSWindow) -> Void)?
        var onBecomeKey: (() -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onAttach?(window)
            window.tabbingMode = .disallowed
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onBecomeKey?()
                }
            }
            if window.isKeyWindow { onBecomeKey?() }
        }
    }
}

/// The app's menus. Note and window commands act on the window in front.
struct AppCommands: Commands {
    @ObservedObject var store: VaultStore
    @FocusedObject private var model: VaultModel?
    @Environment(\.openWindow) private var openWindow
    /// Each command's shortcut, as set in Settings (or its default).
    @ObservedObject private var shortcuts = ShortcutStore.shared

    /// A binding to a property of the front window's model.
    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<VaultModel, Value>, _ fallback: Value) -> Binding<Value> {
        Binding(get: { model?[keyPath: keyPath] ?? fallback }, set: { model?[keyPath: keyPath] = $0 })
    }

    var body: some Commands {
        // Undo reopens a tab when closing it was the last thing done; otherwise it undoes as
        // usual, in whatever has the keyboard.
        CommandGroup(replacing: .undoRedo) {
            Button((model?.canReopenClosedTab ?? false) ? "Undo Close Tab" : "Undo") {
                if model?.reopenClosedTab() != true {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .newItem) {
            Button("New Note") { model?.createNote() }
                .shortcut(.newNote, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("New Note from Template…") { model?.isCreatingFromTemplate = true }
                .shortcut(.newNoteFromTemplate, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("New Folder…") { model?.newFolder() }
                .shortcut(.newFolder, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("New Tab") { model?.newTab() }
                .shortcut(.newTab, in: shortcuts)
                .disabled(model == nil)
            Button("New Tab on Other Side") { model?.newTabOnOtherSide() }
                .shortcut(.newTabOnOtherSide, in: shortcuts)
                .disabled(model == nil)
            Button("New Window") { openWindow(id: "main", value: TabRequest()) }
                .shortcut(.newWindow, in: shortcuts)
            // No shortcut for now: ⇧⌘T shows the tab list.
            Button("Today's Note") { model?.openTodaysNote() }
                .shortcut(.todaysNote, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("Apply Template…") { model?.applyTemplateInPalette() }
                .shortcut(.applyTemplate, in: shortcuts)
                .disabled(model?.selectedNote == nil)
            Button("Open Vault…") { store.chooseVault() }
                .shortcut(.openVault, in: shortcuts)
            Divider()
            // In a note window, closes a tab; in any other window (Settings), closes that.
            Button("Close Tab") {
                if let model, NSApp.keyWindow == nil || NSApp.keyWindow === model.window {
                    model.closeTab()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .shortcut(.closeTab, in: shortcuts)
            Divider()
            Button("Rename Note…") { model?.renaming = model?.selectedNote }
                .shortcut(.renameNote, in: shortcuts)
                .disabled(model?.selectedNote == nil)
            Button("Move to Folder…") { model?.moving = model?.selectedNote }
                .shortcut(.moveToFolder, in: shortcuts)
                .disabled(model?.selectedNote == nil)
            Button("Add Tag…") { model?.tagging = model?.selectedNote }
                .shortcut(.addTag, in: shortcuts)
                .disabled(model?.selectedNote == nil)
            Button(model.flatMap { m in m.selection.map(m.isBookmarked) } == true ? "Remove Bookmark" : "Add Bookmark") {
                if let model, let id = model.selection { model.toggleBookmark(id) }
            }
            .shortcut(.toggleBookmark, in: shortcuts)
            .disabled(model?.selectedNote == nil)
            Button("Show in Finder") { if let model, let note = model.selectedNote { model.showInFinder(note) } }
                .shortcut(.showInFinder, in: shortcuts)
                .disabled(model?.selectedNote == nil)
            Button("Move to Trash") { if let model, let note = model.selectedNote { model.moveToTrash(note) } }
                .shortcut(.moveToTrash, in: shortcuts)
                .disabled(model?.selectedNote == nil)
        }
        // No divider first: the menu already has one between groups, and two showed a gap.
        CommandGroup(after: .textEditing) {
            // The same in every layout, both in the palette: ⌘E, Explorer, to search, open notes
            // and run commands; ⌘F, Search Vault, to browse folders and tags in two columns.
            Button("Explorer") { model?.togglePalette(.search) }
                .shortcut(.explorer, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("Search Vault") { model?.togglePalette(.explorer) }
                .shortcut(.searchVault, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            // The sidebar's own search field (there's no sidebar in Minimal).
            Button("Search in List") { model?.focusSearch() }
                .shortcut(.searchInList, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Button("Find in Note") { FindInNote.show() }
                .shortcut(.findInNote, in: shortcuts)
        }
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { model?.isShowingShortcuts = true }
                .shortcut(.keyboardShortcuts, in: shortcuts)
                .disabled(model == nil)
        }
        CommandMenu("Go") {
            Button("Enclosing Folder") { model?.goUp() }
                .shortcut(.enclosingFolder, in: shortcuts)
                .disabled(model == nil || model?.place == .allNotes)
            Button("Top Level") { model?.browse(.allNotes) }
                .shortcut(.topLevel, in: shortcuts)
                .disabled(model == nil)
            Divider()
            Button("Back") { model?.goBack() }
                .shortcut(.back, in: shortcuts)
                .disabled(!(model.map { $0.canTravel(back: true, inPane: $0.activePane) } ?? false))
            Button("Forward") { model?.goForward() }
                .shortcut(.forward, in: shortcuts)
                .disabled(!(model.map { $0.canTravel(back: false, inPane: $0.activePane) } ?? false))
        }
        CommandGroup(after: .toolbar) {
            Picker("Sort Notes By", selection: $store.sort) {
                Text("Date Edited").tag(NoteSort.modified)
                Text("Date Created").tag(NoteSort.created)
                Text("Title").tag(NoteSort.title)
            }
            Picker("Sort Folders and Tags By", selection: $store.tagOrder) {
                Text("Name").tag(VaultModel.TagOrder.name)
                Text("Date Modified").tag(VaultModel.TagOrder.modified)
            }
            Divider()
            Toggle("Show Dates in List", isOn: $store.showsDateInList)
            Picker("List Dates", selection: $store.listDate) {
                Text("Date Edited").tag(VaultModel.ListDate.edited)
                Text("Date Created").tag(VaultModel.ListDate.created)
            }
            .disabled(!store.showsDateInList)
            Toggle("Show Tags in List", isOn: $store.showsTagsInList)
            Divider()
            Button((model?.showsNoteList ?? true) ? "Hide Note List" : "Show Note List") { model?.showsNoteList.toggle() }
                .shortcut(.toggleNoteList, in: shortcuts)
                .disabled(model == nil)
            Button("Bigger Text") { store.makeTextBigger() }
                .shortcut(.biggerText, in: shortcuts)
            Button("Smaller Text") { store.makeTextSmaller() }
                .shortcut(.smallerText, in: shortcuts)
            Button("Actual Size") { store.textScale = 1 }
                .shortcut(.actualSize, in: shortcuts)
            Divider()
            Button((model?.isSplit ?? false) ? "Merge Split into Tabs" : "Split") { model?.toggleSplit() }
                .shortcut(.split, in: shortcuts)
                .disabled(model == nil)
            Button((model?.isSplit ?? false) ? "Move Tab to Other Side" : "Move Tab to New Split") { model?.moveTabToOtherSide() }
                .shortcut(.moveTabToOtherSide, in: shortcuts)
                .disabled(model == nil)
            Button("Show Next Tab") { model?.cycleTab(1) }
                .shortcut(.nextTab, in: shortcuts)
                .disabled(model == nil)
            Button("Show Previous Tab") { model?.cycleTab(-1) }
                .shortcut(.previousTab, in: shortcuts)
                .disabled(model == nil)
            // Tabs aren't shown as tabs: these list them.
            Button("Show Tab List") { model?.toggleTabMenu() }
                .shortcut(.tabList, in: shortcuts)
                .disabled(model == nil)
            Button("Switch to Tab…") { model?.togglePalette(.tabs) }
                .shortcut(.switchToTab, in: shortcuts)
                .disabled(model == nil || store.root == nil)
            Divider()
            Toggle("Show Markdown", isOn: $store.showsMarkdown)
                .shortcut(.showMarkdown, in: shortcuts)
            Toggle("Focus", isOn: bind(\.isFocused, false))
                .shortcut(.focus, in: shortcuts)
                .disabled(model == nil)
            Divider()
            Button("Reload Notes") { Task { await store.reload() } }
                .shortcut(.reloadNotes, in: shortcuts)
                .disabled(store.root == nil)
            Divider()
        }
    }
}

/// Opens the find bar in the note being edited.
enum FindInNote {
    @MainActor static func show() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}
