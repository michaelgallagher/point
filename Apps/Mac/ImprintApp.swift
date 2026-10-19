import AppKit
import SwiftUI
import VaultKit

@main
struct ImprintApp: App {
    /// The vault, shared by every window and tab.
    @StateObject private var store = VaultStore()

    init() {
        // Imprint has its own tabs, inside each side of a window; no window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
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
                if let noteID = request.noteID, model.selection == nil { model.selection = noteID }
            }
    }
}

/// Reports the window, and when it comes to the front. Imprint keeps its own tabs, inside
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
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
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

    /// A binding to a property of the front window's model.
    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<VaultModel, Value>, _ fallback: Value) -> Binding<Value> {
        Binding(get: { model?[keyPath: keyPath] ?? fallback }, set: { model?[keyPath: keyPath] = $0 })
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { model?.createNote() }
                .keyboardShortcut("n")
                .disabled(model == nil || store.root == nil)
            Button("New Tab") { model?.newTab() }
                .keyboardShortcut("t")
                .disabled(model == nil)
            Button("New Window") { openWindow(id: "main", value: TabRequest()) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Today's Note") { model?.openTodaysNote() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model == nil || store.root == nil)
            Button("Insert Template…") { model?.isChoosingTemplate = true }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(model?.selectedNote == nil)
            Button("Open Vault…") { store.chooseVault() }
                .keyboardShortcut("o")
            Divider()
            Button("Close Tab") { model?.closeTab() }
                .keyboardShortcut("w")
                .disabled(model == nil)
            Divider()
            Button("Rename Note…") { model?.renaming = model?.selectedNote }
                .disabled(model?.selectedNote == nil)
            Button("Move to Folder…") { model?.moving = model?.selectedNote }
                .disabled(model?.selectedNote == nil)
            Button("Add Tag…") { model?.tagging = model?.selectedNote }
                .disabled(model?.selectedNote == nil)
            Button("Show in Finder") { if let model, let note = model.selectedNote { model.showInFinder(note) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model?.selectedNote == nil)
            Button("Move to Trash") { if let model, let note = model.selectedNote { model.moveToTrash(note) } }
                .disabled(model?.selectedNote == nil)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Command Palette") { model?.togglePalette(.search) }
                .keyboardShortcut("e")
                .disabled(model == nil || store.root == nil)
            Button("Explorer") { model?.togglePalette(.explorer) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil || store.root == nil)
            Button("Search Notes") { model?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(model == nil || store.root == nil)
            Button("Find in Note") { FindInNote.show() }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
        CommandMenu("Go") {
            Button("Enclosing Folder") { model?.goUp() }
                .keyboardShortcut(.upArrow)
                .disabled(model == nil || model?.place == .allNotes)
            Button("Top Level") { model?.browse(.allNotes) }
                .disabled(model == nil)
            Divider()
            Button("Previous Note") { model?.selectAdjacentNote(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model == nil)
            Button("Next Note") { model?.selectAdjacentNote(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model == nil)
            Divider()
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(model?.backStack.isEmpty ?? true)
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
                .disabled(model?.forwardStack.isEmpty ?? true)
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
                .keyboardShortcut("s")
                .disabled(model == nil)
            Button("Bigger Text") { store.makeTextBigger() }
                .keyboardShortcut("=") // The ⌘+ key, without Shift.
            Button("Smaller Text") { store.makeTextSmaller() }
                .keyboardShortcut("-")
            Button("Actual Size") { store.textScale = 1 }
            Divider()
            Button((model?.isSplit ?? false) ? "Merge Split into Tabs" : "Split") { model?.toggleSplit() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button((model?.isSplit ?? false) ? "Move Tab to Other Side" : "Move Tab to New Split") { model?.moveTabToOtherSide() }
                .disabled(model == nil)
            Button("Show Next Tab") { model?.cycleTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Show Previous Tab") { model?.cycleTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Toggle("Show Markdown", isOn: $store.showsMarkdown)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Toggle("Focus", isOn: bind(\.isFocused, false))
                .keyboardShortcut("\\", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Reload Notes") { Task { await store.reload() } }
                .keyboardShortcut("r")
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
