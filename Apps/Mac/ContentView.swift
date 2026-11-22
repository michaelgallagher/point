import IndexKit
import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel
    @EnvironmentObject private var store: VaultStore
    @State private var isAddingProperty = false

    /// The sidebar and the notes, in the window's own split view (see `SidebarSplitController`).
    private var splitView: some View {
        let twoColumns = model.browsingStyle == .twoColumns
        return SidebarSplitView(
            controller: model.sidebarSplit,
            sidebar: AnyView(sidebar.environmentObject(model).environmentObject(store).environmentObject(model.filterTools)),
            detail: AnyView(detail.environmentObject(model).environmentObject(store)),
            // Two columns start at half as wide again as one column, split 40/60 (see `sidebar`).
            widths: twoColumns ? (300, 360, 760) : (180, 240, 400),
            widthKey: twoColumns ? "sidebarWidth.twoColumns" : "sidebarWidth.singleColumn",
            showsSidebar: model.showsNoteList
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    /// One column (folders, tags and notes together) or two (folders and tags beside notes).
    @ViewBuilder private var sidebar: some View {
        Group {
            if model.browsingStyle == .twoColumns {
                // Tree and notes side by side inside one sidebar, so hiding, swiping and
                // resizing work exactly as in the single column.
                // 40/60, the notes wider, kept as the sidebar widens or narrows. (HSplitView
                // gave any extra width to the tree, so it started at half.) The columns, and
                // the divider between them, run to the window's top, under the top bar.
                // Each column has its own top bar; the notes scroll up beneath theirs.
                SideBySide(key: "treeColumnFraction", fraction: 0.4, minimumWidths: (120, 180)) {
                    // Scrolling up under its bar (the window buttons), softly blurred.
                    PlaceTreeColumn()
                        .overlay(alignment: .top) { SidebarTopBar() }
                } side: {
                    NoteList(filterTools: model.filterTools, includesPlaces: false)
                        .overlay(alignment: .top) { NoteListTopBar(filterTools: model.filterTools, listCount: model.listCount) }
                        // The notes in the page's colour, the tree alone in the sidebar's grey,
                        // and a line between the notes and the note (which share a colour).
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(alignment: .trailing) { HStack(spacing: 0) { Divider() } }
                }
            } else {
                VStack(spacing: 0) {
                    SidebarTopBar()
                    NoteList(filterTools: model.filterTools)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The notes: one pane, or two side by side, each with its own tabs.
    private var detail: some View {
        Group {
            // One side or two, in the same view, so the left side's note stays as it is when
            // the right side closes (and can slide to its new place).
            SideBySide(minimumWidths: model.notesSplitMinimums, showsSide: model.isSplit, sideDrawsDivider: true) {
                PaneView(paneID: model.panes[0].id)
            } side: {
                if model.isSplit {
                    SlidingSide(slideOffset: model.sideSlideOffset,
                                content: PaneView(paneID: model.panes[1].id)
                                    .environmentObject(model).environmentObject(store))
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Shows or hides the sidebar. Shown or hidden by hand (⌘S, the sidebar button, a swipe),
    /// the window widens or narrows by the sidebar's width so the notes keep theirs; in focus
    /// mode, when the window's width hid it, or where the window can't resize, the notes take
    /// the space instead.
    private func updateSidebar(resizingWindow: Bool) {
        model.sidebarSplit.setSidebar(shown: model.showsNoteList, resizingWindow: resizingWindow)
    }

    /// The note being worked on (in the active pane), else the vault's name.
    private var windowTitle: String {
        model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Point"
    }

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                Group {
                    splitView
                }
                .navigationTitle(windowTitle)
                // The window's toolbar holds only the system's sidebar button (the split view
                // controller adds it), which gives the top row its standard height and puts the
                // button where macOS does. No other toolbar items: an item, even an invisible
                // one, takes the clicks meant for the bars drawn in that row (the back and forward
                // arrows sat under one). The sidebar and each side draw their own bars there.
                .onChange(of: model.searchFocusRequest) { _ in
                    if !model.showsNoteList { model.showsNoteList = true } // The filter needs the list.
                }
                // Shown or hidden by hand, the window widens or narrows instead of the notes.
                .onChange(of: model.showsNoteList) { _ in
                    updateSidebar(resizingWindow: !model.lastToggleWasAutomatic)
                }
            }
        }
        // Minimal is meant to sit beside other windows, so it can be narrow.
        // With the sidebar hidden, a window is one compact note that can sit beside others.
        .modifier(WindowMinimum(model: model, slide: model.sidebarSlide))
        .onAppear {
            model.startSwipeTracking()
        }
        // After a rename or move: which notes' links were updated, for a moment.
        .overlay(alignment: .bottom) {
            if let update = store.linkUpdate {
                LinkUpdateNotice(update: update)
                    .id(update.id)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: store.linkUpdate)
        // After a change across the vault: what changed, with Undo, for a moment.
        .overlay(alignment: .bottom) {
            if let notice = store.vaultChangeNotice {
                VaultChangeNoticeView(notice: notice)
                    .id(notice.id)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: store.vaultChangeNotice)
        .overlay(alignment: .top) {
            if model.isPaletteShown {
                ZStack(alignment: .top) {
                    // Clicking outside the palette closes it.
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture { model.isPaletteShown = false }
                        // A tab let go over the palette goes nowhere.
                        .background(TabDropArea.blocking)
                    // Over the side a note will open into, when the window's split; inside
                    // the window however narrow that side is.
                    GeometryReader { geometry in
                        let window = geometry.frame(in: .global)
                        let half = min(270, window.width / 2 - 16)
                        let centre = model.targetPaneFrame.map { $0.midX - window.minX } ?? window.width / 2
                        let clamped = min(max(centre, half + 16), window.width - half - 16)
                        CommandPalette()
                            .padding(.top, 80)
                            .frame(maxWidth: .infinity)
                            .offset(x: clamped - window.width / 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $model.renaming) { note in
            RenameSheet(note: note)
        }
        .sheet(item: $model.renamingAcrossVault) { rename in
            RenameAcrossVaultSheet(rename: rename, store: model.store, model: model)
        }
        .sheet(isPresented: $model.isShowingUnusedImages) {
            UnusedImagesSheet()
        }
        .sheet(item: $model.creatingFolder) { request in
            NewFolderSheet(parent: request.parent)
        }
        .sheet(isPresented: $model.isCreatingFromTemplate) {
            TemplatePicker()
        }
        .sheet(isPresented: $model.isShowingShortcuts) {
            ShortcutsSheet()
        }
        .sheet(item: $model.moving) { note in
            MoveSheet(note: note)
        }
        .sheet(item: $model.tagging) { note in
            AddTagSheet(note: note)
        }
        .sheet(isPresented: $isAddingProperty) {
            AddPropertySheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pointAddProperty)) { notification in
            // Only the window that asked.
            guard notification.object as AnyObject? === model, model.selectedNote != nil else { return }
            isAddingProperty = true
        }
    }
}

private struct OpenVaultView: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Point")
                .font(.largeTitle.weight(.semibold))
            Text("Choose the folder that holds your notes.")
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Button("Open vault…") { model.chooseVault() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window's narrowest size: the notes' narrowest, plus the sidebar's width once it shows.
/// Not while it slides in: counted from the start, the window jumped to that width before the
/// slide began (the notes stretched to fill it), and the sidebar snapped to its full width at
/// the end. Only this watches the sliding, so nothing else redraws as it starts and stops.
private struct WindowMinimum: ViewModifier {
    @ObservedObject var model: VaultModel
    @ObservedObject var slide: SidebarSlide

    func body(content: Content) -> some View {
        content.frame(minWidth: slide.isSliding ? SidebarSplitController.minimumNotesWidth : model.minimumWindowWidth,
                      minHeight: 400)
    }
}

private struct NoteList: View {
    @EnvironmentObject private var model: VaultModel
    /// Whether the filter tools show at the top (two columns).
    @ObservedObject var filterTools: FilterToolsState
    @FocusState private var searchFocused: Bool
    /// False in the two-column view, where folders and tags have their own column.
    var includesPlaces = true
    /// The suggestion chosen with the arrow keys, if any.
    @State private var highlighted: Int?
    /// Escape hides the suggestions until the text changes.
    @State private var dismissed = false
    /// The pinned controls' height, chips and all (not the suggestions, which float over the
    /// list): room the list leaves at its top.
    @State private var controlsHeight: CGFloat = topControlsGap + fieldHeight + fieldPadding
    /// Whether the list shows anything but labels, as the table last found (see `browser`).
    @State private var listHasItems = true
    /// Escape, wherever the keyboard is, puts the tools away (see `watchEscape`).
    @State private var escapeMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // In two columns, the name and sort are in the column's top bar (see
            // `NoteListTopBar`).
            if includesPlaces, model.place != .allNotes { PlaceHeader() }
            // In two columns, pinned at the top under the column's bar, with what's filtering
            // as chips below; in one, at the foot, floating over the list's end. Either way the
            // list scrolls on beneath, blurred (drawn by the list's scroll view).
            browser
                .overlay(alignment: filterAtTop ? .top : .bottom) {
                    if filterAtTop { topControls } else { filterField }
                }
        }
        // A turn later: the field may only now be appearing (⇧⌘F with the tools away).
        .onChange(of: model.searchFocusRequest) { _ in DispatchQueue.main.async { searchFocused = true } }
        // Shown, the tools' field takes the keyboard, a turn later, once it's there.
        .onChange(of: filterTools.isShown) { shown in
            if shown { DispatchQueue.main.async { searchFocused = true } }
        }
        .onAppear(perform: watchEscape)
        .onDisappear {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
        }
        .overlay {
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    /// While the tools show, Escape puts them away wherever the keyboard is: in the list, the
    /// tree, or nowhere in particular. Not while typing: in the field, Escape goes step by step
    /// (see `FilterField`), and a note's text or a property being edited keeps its own Escape.
    /// Nor with a sheet up, and anything else Escape stands for (a button's Cancel or Done) is
    /// done first, instead.
    private func watchEscape() {
        guard filterAtTop, escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            guard event.keyCode == 53,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty,
                  model.showsFilterTools, let window = model.window, event.window === window,
                  window.attachedSheet == nil, !(window.firstResponder is NSText) else { return event }
            if window.performKeyEquivalent(with: event) { return nil }
            model.setFilterTools(shown: false)
            return nil
        }
    }

    /// Whether the field, filter and sort are pinned at the list's top (when the bar's filter
    /// button shows them): in two columns, unless `-filterAtTop NO` puts them back at the foot,
    /// always showing (to compare while this is tried).
    private var filterAtTop: Bool {
        !includesPlaces && VaultModel.filtersAtTop
    }

    /// The filter field's height, its corners and the space around it: shaped like the tabs'
    /// rail and a selected sidebar row (see `PaneTabs`).
    /// As tall as a tab, and its corners: a selected row's.
    private static let fieldHeight = PaneTabs.height - PaneTabs.inset * 2
    private static let fieldPadding: CGFloat = 10
    /// How far the sort arrows sit inside their square (measured): taken off the room on
    /// each side of it, so the arrows are as far from the field and the column's edge as the
    /// field is from the other edge.
    private static let sortInset: CGFloat = 6
    /// The bar at the foot: the field, and as much room above it as below.
    private static let footHeight = fieldHeight + fieldPadding * 2
    /// At the top, the room above the field (the bar above has its own) and below it.
    private static let topControlsGap: CGFloat = 2
    private static let topControlsPadding: CGFloat = topControlsGap + 8

    private var suggestions: [VaultModel.FilterSuggestion] {
        searchFocused && !dismissed ? model.filterSuggestions() : []
    }

    private func pick(_ suggestion: VaultModel.FilterSuggestion) {
        model.pickFilterSuggestion(suggestion)
        highlighted = nil
    }

    /// The field, and in two columns the filter and sort buttons beside it.
    private func controlsRow(suggestions: [VaultModel.FilterSuggestion], atTop: Bool) -> some View {
        HStack(alignment: .bottom, spacing: atTop ? TopBar.buttonSpacing : Self.fieldPadding - Self.sortInset) {
            FilterField(isFocused: $searchFocused, height: Self.fieldHeight, suggestions: suggestions,
                        highlighted: $highlighted, dismissed: $dismissed, atTop: atTop, pick: pick) {
                // Return opens the top note.
                if let first = model.sidebarRows(collapsed: [], content: content).lazy.compactMap(\.noteID).first { model.selection = first }
            }
            if showsSort {
                FilterMenuButton(opensUpward: !atTop)
                    .frame(height: Self.fieldHeight)
                // A plain icon, as in the top bars. At the top, it's in the column's bar, beside
                // the filter button (see `NoteListTopBar`).
                if !atTop {
                    SortButton(opensUpward: true)
                        .frame(height: Self.fieldHeight)
                }
            }
        }
        .padding(.leading, Self.fieldPadding)
        // At the top, the filter menu's square under the sidebar button's in the bar above.
        .padding(.trailing, atTop && showsSort ? TopBar.sidebarButtonInset
                 : showsSort ? Self.fieldPadding - Self.sortInset : Self.fieldPadding)
    }

    /// Narrows the list to what's named with what's typed: in one column, the folders, tags
    /// and notes showing; in two, the notes, with how they're sorted on its right (in one
    /// column, that's in the Notes section's label). Searching the whole vault is the explorer's.
    private var filterField: some View {
        controlsRow(suggestions: suggestions, atTop: false)
            // The field's row is the foot's height; suggestions above it make the stack taller,
            // over the list.
            .padding(.vertical, Self.fieldPadding)
    }

    /// The controls pinned at the top: the field and buttons, then what's filtering as chips,
    /// and the suggestions opening down over them and the list. The suggestions are in the
    /// same stack, so it grows to hold them (glass reaching outside its view isn't drawn), but
    /// only the controls and chips are measured for the room the list leaves.
    private var topControls: some View {
        let suggestions = suggestions
        return VStack(spacing: 0) {
            if filterTools.isShown {
                topTools(suggestions: suggestions)
                    // Down out of the bar, and back up into it.
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Clipped at the bar's foot, so they slide from under it rather than over the name.
        .clipped()
        .padding(.top, model.topBarHeight)
    }

    private func topTools(suggestions: [VaultModel.FilterSuggestion]) -> some View {
        ZStack(alignment: .top) {
            let hasChips = !model.filterTokens.isEmpty || model.showsOnlyUnread
            VStack(alignment: .leading, spacing: 0) {
                // Under the last of them, field or chips, as much room as the field has from
                // the column's edge.
                controlsRow(suggestions: suggestions, atTop: true)
                    .padding(.top, Self.topControlsGap)
                    .padding(.bottom, hasChips ? Self.topControlsPadding - Self.topControlsGap : Self.fieldPadding)
                if hasChips {
                    FilterChips()
                        .padding(.horizontal, Self.fieldPadding)
                        .padding(.bottom, Self.fieldPadding)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
            if !suggestions.isEmpty {
                FilterSuggestionList(suggestions: suggestions, highlighted: $highlighted, pick: pick)
                    .padding(.horizontal, Self.fieldPadding)
                    .padding(.top, Self.topControlsGap + Self.fieldHeight + 4)
            }
        }
    }

    private var content: SidebarTable.Content { includesPlaces ? .everything : .notes }

    /// How the notes are sorted, beside the field: in two columns, but not in the trash.
    private var showsSort: Bool { !includesPlaces && model.place != .trash && model.place != .recent }

    /// Whether the list shows places as well as notes: always in one column, and in two for the
    /// lists of tags and types, which are places.
    private var listsPlaces: Bool { includesPlaces || model.place == .types || model.place == .tags }

    /// Pins, folders (or nested tags), tags and notes for the current place.
    private var browser: some View {
        SidebarTable(model: model, content: content, bottomInset: filterAtTop ? 0 : Self.footHeight,
                     topInset: filterAtTop && filterTools.isShown ? controlsHeight : 0,
                     onHasItems: { listHasItems = $0 }, onNoteCount: { [listCount = model.listCount] in listCount.shown = $0 },
                     filter: filterTools.tokens + [filterTools.text])
            .overlay {
                if model.place == .trash ? model.store.trashedNotes.isEmpty : model.notes(in: model.place).isEmpty, model.store.images(in: model.place).isEmpty, !listsPlaces || model.subplaces(of: model.place).isEmpty, model.place != .allNotes {
                    if let message = emptyMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                } else if model.isFiltering || content == .notes && model.showsOnlyUnread, !listHasItems {
                    Text(model.isFiltering ? "No matches" : "No unread notes")
                        .foregroundStyle(.secondary)
                }
            }
    }
}

extension NoteList {
    /// What an empty place says, or nothing while the index is still being asked.
    fileprivate var emptyMessage: String? {
        switch model.place {
        case .tag: return "No notes have this tag."
        case .properties: return "No notes have properties."
        case .types: return "No notes have a type."
        case .tags: return "No notes have tags."
        case .trash: return "The trash is empty."
        case .lists: return "No notes are lists."
        case .property, .propertyValue, .kind:
            guard let query = model.place.query, model.store.noteIDs(matching: query) != nil else { return nil }
            if case .property = model.place { return "No notes have this property." }
            if case .kind = model.place { return "No notes are of this type." }
            return "No notes have this value."
        default: return "This folder has no notes."
        }
    }
}

/// The folder or tag being browsed, with a way back up.
private struct PlaceHeader: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.goUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back (⌘↑)")
            Text(model.title(for: model.place))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if model.place == .lists {
                Button { model.createList() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New list")
            }
            if model.place == .trash {
                EmptyTrashButton()
            } else if model.place != .everything && model.place != .bookmarks {
                Button { model.togglePin(model.place) } label: {
                    Image(systemName: model.isPinned(model.place) ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.isPinned(model.place) ? "Unpin" : "Pin to the top of the sidebar")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

/// Empties the trash, after asking: the notes in it go for good.
struct EmptyTrashButton: View {
    @EnvironmentObject private var model: VaultModel
    @State private var isConfirming = false

    var body: some View {
        Button("Empty") { isConfirming = true }
            .buttonStyle(.borderless)
            .disabled(model.trashedNotes.isEmpty)
            .help("Delete every note in the trash now")
            .confirmationDialog("Delete the \(model.trashedNotes.count) notes in the trash for good?", isPresented: $isConfirming) {
                Button("Empty trash", role: .destructive) { model.store.emptyTrash() }
            } message: {
                Text("This can't be undone.")
            }
    }
}

extension SidebarPlace {
    var isTag: Bool {
        if case .tag = self { return true }
        return false
    }

    /// "Work", "Projects" or "work/imprint" (a tag without its "#": its symbol says it's a tag).
    var title: String {
        switch self {
        case .allNotes: "All notes"
        case .folder(let path): FolderTree.name(of: path)
        case .tag(let tag): tag
        case .everything: "All notes"
        case .bookmarks: "Bookmarks"
        case .trash: "Trash"
        case .properties: "Properties"
        case .property(let name): name
        case .propertyValue(_, let value): PropertyValueText.shown(value)
        case .types: "Types"
        case .tags: "Tags"
        case .kind(_, let name): NoteKinds.plural(name)
        case .lists: "Lists"
        case .recent: "Recent"
        }
    }

    /// The last part only: "imprint" for work/imprint, under its parent in the tag list.
    var shortName: String {
        switch self {
        case .tag(let tag): tag.split(separator: "/").last.map(String.init) ?? tag
        default: title
        }
    }
}

/// The filter field: at the foot of the sidebar's list, tokens for what notes must be
/// (`Topics: design`, `#work`, `Unread`), then what's typed, matched with titles; at the top of
/// the two-column list, the typed text alone, with what's filtering as chips below it (see
/// `FilterChips`). While a word is typed, what it could mean among the notes here is suggested
/// (above the field at the foot, below it at the top); picking one (with the arrow keys and
/// Return, or a click) makes it a token. Terms typed in full (`#work`, `has:read`) become
/// tokens at a space.
private struct FilterField: View {
    @EnvironmentObject private var model: VaultModel
    /// The filter's text and terms (see `FilterToolsState`): watched here, not through the model.
    @EnvironmentObject private var filterTools: FilterToolsState
    var isFocused: FocusState<Bool>.Binding
    /// The sidebar's row height, so the field is as tall as a selected row.
    let height: CGFloat
    /// What the word being typed could mean (worked out by the list, which may draw them).
    let suggestions: [VaultModel.FilterSuggestion]
    /// The suggestion chosen with the arrow keys, if any.
    @Binding var highlighted: Int?
    /// Escape hides the suggestions until the text changes.
    @Binding var dismissed: Bool
    /// At the top of the list: the tokens are chips below, and the list draws the suggestions.
    let atTop: Bool
    let pick: (VaultModel.FilterSuggestion) -> Void
    let onSubmit: () -> Void

    var body: some View {
        // At the foot, the suggestions above the field, in the same stack (not an overlay
        // reaching out of it, where glass isn't drawn).
        VStack(spacing: 6) {
            if !atTop, !suggestions.isEmpty {
                FilterSuggestionList(suggestions: suggestions, highlighted: $highlighted, pick: pick)
            }
            field
        }
        .help("Filter by title, or pick a tag, a property's value or a time as you type")
        // Backspace in an empty field takes the last token away. (The text field takes the
        // key before `onKeyPress` would see it.)
        .onAppear {
            deleteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
                guard event.keyCode == 51, isFocused.wrappedValue, model.noteFilter.isEmpty, !model.filterTokens.isEmpty,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                model.filterTokens.removeLast()
                return nil
            }
        }
        .onDisappear {
            if let deleteMonitor { NSEvent.removeMonitor(deleteMonitor) }
            deleteMonitor = nil
        }
    }

    private var field: some View {
        let suggestions = suggestions
        let tokens = atTop ? [] : model.filterTokens
        return HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            // Tokens first, as wide as their names while there's room, then the text.
            TokenLine {
                ForEach(tokens, id: \.self) { term in
                    FilterTokenView(term: term)
                }
                TextField(tokens.isEmpty ? "Filter" : "", text: $model.noteFilter)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .frame(minWidth: 40)
                    .onSubmit {
                        model.takeTypedTerms(finished: true)
                        onSubmit()
                    }
                    .onKeyPress(.downArrow) {
                        guard !suggestions.isEmpty else { return .ignored }
                        highlighted = min((highlighted ?? -1) + 1, suggestions.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard let current = highlighted else { return .ignored }
                        highlighted = current == 0 ? nil : current - 1
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard let index = highlighted, index < suggestions.count else { return .ignored }
                        pick(suggestions[index])
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if !suggestions.isEmpty {
                            dismissed = true
                            highlighted = nil
                        } else if atTop, !model.isFiltering {
                            // Nothing to clear: put the tools away.
                            model.setFilterTools(shown: false)
                        } else {
                            model.clearFilter()
                        }
                        return .handled
                    }
                    .onChange(of: model.noteFilter) {
                        highlighted = nil
                        dismissed = false
                        model.takeTypedTerms()
                    }
            }
            // At the foot, clears the lot, tokens and all. At the top, only what's typed: each chip
            // has its ×, and two or more have Clear filters after them.
            if atTop ? !model.noteFilter.isEmpty : model.isFiltering {
                Button {
                    if atTop { model.noteFilter = "" } else { model.clearFilter() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(atTop ? "Clear text" : "Clear filter")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: height)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: PaneTabs.cornerRadius - PaneTabs.inset, style: .continuous))
    }

    @State private var deleteMonitor: Any?
}

/// What's filtering the list, below the controls at its top: each term as a chip with its
/// whole name (wrapping onto more lines rather than shortening), and Only Unread as one too.
/// A chip's × takes it away; a click on its name offers to leave those notes out instead (or
/// include them again). With two or more, Clear filters follows, taking them all away.
private struct FilterChips: View {
    @EnvironmentObject private var model: VaultModel
    /// The filter's text and terms (see `FilterToolsState`): watched here, not through the model.
    @EnvironmentObject private var filterTools: FilterToolsState

    var body: some View {
        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
            if model.showsOnlyUnread {
                FilterChip(label: "Unread", negated: false, help: "Only unread notes, kept for this place") {
                    model.toggleOnlyUnread()
                }
            }
            ForEach(model.filterTokens, id: \.self) { term in
                FilterChip(term: term)
            }
            // Two or more: all of them at once (words typed too).
            if model.filterTokens.count + (model.showsOnlyUnread ? 1 : 0) > 1 {
                Button("Clear filters") { model.clearAllFilters() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(height: FilterChip.height)
                    .contentShape(Rectangle())
                    .help("Remove every filter")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What filters the list, as chips at its top, scrolling with the notes, while the filter
/// tools are away: drawn only (a click on the row shows the tools, to change them).
struct FilterSummaryView: View {
    let items: [FilterSummaryItem]

    var body: some View {
        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item.label)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .frame(height: FilterChip.height)
                    .foregroundStyle(item.negated ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .background(Color.accentColor.opacity(item.negated ? 0.08 : 0.15), in: Capsule())
            }
        }
        // In line with the count above (the row's own padding), and room below before the notes.
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filtered by " + items.map(\.label).joined(separator: ", "))
    }
}

/// One chip: its name (a click offers Leave Out or Include, and Remove, for a term), and ×.
private struct FilterChip: View {
    @EnvironmentObject private var model: VaultModel
    /// The filter's text and terms (see `FilterToolsState`): watched here, not through the model.
    @EnvironmentObject private var filterTools: FilterToolsState
    let label: String
    let negated: Bool
    let help: String
    /// The term it stands for; nil for Only Unread, which is the place's, not a term.
    var term: String?
    let remove: () -> Void
    @State private var anchor = MenuAnchor.Holder()

    static let height: CGFloat = 22

    init(label: String, negated: Bool, help: String, remove: @escaping () -> Void) {
        self.label = label
        self.negated = negated
        self.help = help
        self.remove = remove
    }

    init(term: String) {
        self.label = FilterText.label(of: term)
        self.negated = term.hasPrefix("-")
        self.help = negated ? "Notes without this. Click to include it." : "Click to leave these out"
        self.term = term
        self.remove = {}
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(MenuAnchor(holder: anchor))
                .onTapGesture { showMenu() }
                .help(help)
            Button(action: removeIt) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
            .padding(.trailing, 2)
        }
        .font(.callout)
        .frame(height: Self.height)
        .foregroundStyle(negated ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        .background(Color.accentColor.opacity(negated ? 0.08 : 0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAction(named: "Remove") { removeIt() }
    }

    private func removeIt() {
        if let term { model.filterTokens.removeAll { $0 == term } } else { remove() }
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        if let term {
            menu.addItem(BlockMenuItem(term.hasPrefix("-") ? "Include" : "Leave Out") {
                if let index = model.filterTokens.firstIndex(of: term) { model.filterTokens[index] = FilterText.toggled(term) }
            })
        }
        menu.addItem(BlockMenuItem("Remove") { removeIt() })
        // Below the chip: the list is beneath.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }
}

/// Lays its views out in rows, left to right, starting a new row when the next doesn't fit;
/// one wider than a row gets the row's width (and shortens).
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private struct Placed { var index: Int; var origin: CGPoint; var width: CGFloat }

    private func arrange(width: CGFloat, subviews: Subviews) -> (placed: [Placed], size: CGSize) {
        var placed: [Placed] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let ideal = view.sizeThatFits(.unspecified)
            let w = min(ideal.width, width)
            if x > 0, x + w > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            placed.append(Placed(index: index, origin: CGPoint(x: x, y: y), width: w))
            x += w + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, ideal.height)
        }
        return (placed, CGSize(width: widest, height: placed.isEmpty ? 0 : y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews: subviews).placed {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                       anchor: .topLeading, proposal: ProposedViewSize(width: item.width, height: nil))
        }
    }
}

/// The filter field's tokens and its text, in a row: the tokens as wide as they'd like while
/// they fit with room for the text (`textWidth`); beyond that, the widest shortened first.
private struct TokenLine: Layout {
    var spacing: CGFloat = 4
    var textWidth: CGFloat = 40

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let ideal = subviews.dropLast().reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + spacing } + textWidth
        return CGSize(width: proposal.width ?? ideal, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.last else { return }
        let tokens = Array(subviews.dropLast())
        let ideals = tokens.map { $0.sizeThatFits(.unspecified).width }
        let room = max(0, bounds.width - textWidth - spacing * CGFloat(tokens.count))
        // The largest width every token can have so they all fit: the narrow keep theirs.
        var cap = ideals.max() ?? 0
        if ideals.reduce(0, +) > room {
            var left = room, count = CGFloat(ideals.count)
            for width in ideals.sorted() {
                if width * count <= left { left -= width; count -= 1 } else { break }
            }
            cap = count > 0 ? left / count : 0
        }
        var x = bounds.minX
        for (token, ideal) in zip(tokens, ideals) {
            let offered = ProposedViewSize(width: min(ideal, cap), height: bounds.height)
            token.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: offered)
            // As wide as it took: shortened text may be narrower than offered.
            x += min(token.sizeThatFits(offered).width, ideal) + spacing
        }
        text.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: max(textWidth, bounds.maxX - x), height: bounds.height))
    }
}

/// A term in the filter field, as a token: a click offers to turn it round or remove it.
private struct FilterTokenView: View {
    @EnvironmentObject private var model: VaultModel
    /// The filter's text and terms (see `FilterToolsState`): watched here, not through the model.
    @EnvironmentObject private var filterTools: FilterToolsState
    let term: String
    @State private var anchor = MenuAnchor.Holder()

    var body: some View {
        let negated = term.hasPrefix("-")
        let label = FilterText.label(of: term)
        // Its whole name, unless that's long: the field is narrow.
        Text(label.count > 22 ? label.prefix(21) + "…" : label)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(negated ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            .background(Color.accentColor.opacity(negated ? 0.08 : 0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background(MenuAnchor(holder: anchor))
            .contentShape(Rectangle())
            .onTapGesture { showMenu() }
            .help(negated ? "Notes without this. Click to include it or remove it." : "Click to leave these out, or remove it")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showMenu() }
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.addItem(BlockMenuItem(term.hasPrefix("-") ? "Include" : "Leave Out") {
            if let index = model.filterTokens.firstIndex(of: term) { model.filterTokens[index] = FilterText.toggled(term) }
        })
        menu.addItem(BlockMenuItem("Remove") { model.filterTokens.removeAll { $0 == term } })
        // Opening above the token, as the field's other menus do.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4 + menu.size.height), in: view)
    }
}

/// What the word being typed could mean, above the field: values, tags, properties, times.
private struct FilterSuggestionList: View {
    let suggestions: [VaultModel.FilterSuggestion]
    @Binding var highlighted: Int?
    let pick: (VaultModel.FilterSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                let isOn = highlighted == index
                HStack(spacing: 8) {
                    Image(systemName: suggestion.symbol)
                        .frame(width: 16)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    Text(suggestion.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let count = suggestion.count {
                        Text(count.formatted())
                            .monospacedDigit()
                            .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                    }
                }
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isOn ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
                .onHover { if $0 { highlighted = index } }
                .onTapGesture { pick(suggestion) }
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Floating over the list as a menu does, so in glass as menus are.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename note")
                .font(.headline)
            TextField("Name", text: $title)
                .frame(width: 320)
                .onSubmit(rename)
            Text("Links to this note in other notes will be updated.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { title = note.title }
    }

    private func rename() {
        model.rename(note, to: title)
        dismiss()
    }
}

/// Renames a property, a value or a tag in every note that has it.
/// The images no note shows, found from the index: each can be shown in the Finder, and all
/// moved to the Trash, from where the Finder can put them back.
private struct UnusedImagesSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var images: [VaultImage]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unused images")
                .font(.headline)
            Group {
                if let images, images.isEmpty {
                    Text("Every image in the vault is shown in a note.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let images {
                    List(images) { image in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(image.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text((image.path as NSString).deletingLastPathComponent.isEmpty ? "Top of the vault" : (image.path as NSString).deletingLastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                                .buttonStyle(.link)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 440, height: 280)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 440, alignment: .leading)
            HStack {
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    if let images { model.store.trashUnusedImages(images) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(images?.isEmpty ?? true)
            }
        }
        .padding(20)
        .task { images = await model.store.unusedImages() }
    }

    private var detail: String {
        guard let images, !images.isEmpty else { return "No note embeds or links to these." }
        let count = images.count == 1 ? "This image isn’t" : "These \(images.count) images aren’t"
        return "\(count) embedded or linked in any note. Moved to the Trash, they can be put back from the Finder."
    }
}

/// Renames a tag or property, or changes a value, in every note: from the sidebar, or a
/// property from Settings (with no window to follow it in).
struct RenameAcrossVaultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rename: VaultStore.VaultRename
    let store: VaultStore
    var model: VaultModel?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
            TextField("Name", text: $name)
                .frame(width: 320)
                .onSubmit(apply)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isValue ? "Change" : "Rename", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == rename.current)
            }
        }
        .padding(20)
        .onAppear { name = rename.current }
    }

    private var isValue: Bool {
        if case .value = rename { return true }
        return false
    }

    private var heading: String {
        switch rename {
        case .property: "Rename property"
        case .value(let name, _): "Change value of \(name)"
        case .tag: "Rename tag"
        }
    }

    private var place: SidebarPlace {
        switch rename {
        case .property(let name): .property(name)
        case .value(let name, let value): .propertyValue(name, value)
        case .tag(let tag): .tag(tag)
        }
    }

    private var detail: String {
        let count = store.noteCount(of: place)
        let notes = count == 1 ? "1 note" : "\(count) notes"
        return switch rename {
        case .property: "Renamed in \(notes). Their values stay as they are."
        case .value: "Changed in \(notes)."
        case .tag: "Renamed in \(notes), and tags inside it too."
        }
    }

    private func apply() {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != rename.current else { return }
        dismiss()
        store.rename(rename, to: new)
        // Listed in the sidebar: listed by its new name.
        if case .property(let old) = rename, store.showsInSidebar(property: old) {
            store.sidebarProperties = store.sidebarProperties.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }
        // Still browsing what was renamed: follow it to its new name.
        guard let model else { return }
        switch (rename, model.place) {
        case (.property(let old), .property(let current)) where old == current: model.browse(.property(new))
        case (.value(let property, let old), .propertyValue(let name, let current)) where old == current && property == name:
            model.browse(.propertyValue(property, new))
        case (.tag(let old), .tag(let current)) where old.lowercased() == current.lowercased(): model.browse(.tag(new))
        default: break
        }
    }
}

private struct NewFolderSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let parent: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New folder")
                .font(.headline)
            TextField("Name", text: $name)
                .frame(width: 320)
                .onSubmit(create)
            Text("In " + ([model.root?.lastPathComponent ?? "Vault"] + parent.split(separator: "/").map(String.init)).joined(separator: " › "))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.createFolder(named: name, in: parent)
        dismiss()
    }
}

/// Choosing a template to start a new note from, with a name. (Applying one to a note is
/// done in the palette.)
private struct TemplatePicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?
    @State private var name = ""

    /// The sheet's width; everything in it spans it, inside even margins.
    private static let width: CGFloat = 400
    private static let margin: CGFloat = 20

    var body: some View {
        let templates = model.templates
        let density = model.sidebarDensity
        VStack(alignment: .leading, spacing: 14) {
            Text("New note from template")
                .font(.headline)
            if templates.isEmpty {
                Text(model.settings.templatesFolder.isEmpty
                     ? "No templates folder is set. Choose one in Settings, under Templates."
                     : "There are no templates in “\(model.settings.templatesFolder)”.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // As the sidebar's list: its row size (compact or comfortable) and its selection.
                List(templates, id: \.url, selection: $selection) { template in
                    Label(template.name, systemImage: "doc.text")
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .environment(\.sidebarRowSize, density == .compact ? .small : .medium)
                .contextMenu(forSelectionType: URL.self, menu: { _ in }, primaryAction: { _ in choose() })
                // As tall as its rows, up to about eight; then it scrolls.
                .frame(height: min(CGFloat(templates.count), 8) * density.rowHeight + 16)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
                .onAppear { selection = templates.first?.url }
                TextField("Name (or leave it to the first line)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(choose)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: choose)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(Self.margin)
        .frame(width: Self.width)
    }

    private func choose() {
        guard let selection else { return }
        dismiss()
        model.createNote(fromTemplate: selection, titled: name)
    }
}


/// Chooses a folder to move a note into.
private struct MoveSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var filter = ""
    @State private var selection: String?

    /// Every folder ("" is the vault root), filtered as you type, except the note's own.
    private var folders: [String] {
        let all = [""] + model.folderTree.noteCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let current = FolderTree.folder(of: note.id)
        return all.filter { $0 != current && (filter.isEmpty || $0.localizedCaseInsensitiveContains(filter)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move “\(note.title)”")
                .font(.headline)
            TextField("Filter folders", text: $filter)
            // The rows' edges on the field's, their icons where its text starts.
            List(folders, id: \.self, selection: $selection) { folder in
                Label(folder.isEmpty ? "Vault (top level)" : folder, systemImage: "folder")
                    .lineLimit(1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: 260)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move", action: move)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: filter) { _ in selection = folders.first }
    }

    private func move() {
        guard let selection else { return }
        dismiss()
        model.move(noteID: note.id, toFolder: selection)
    }
}

/// "Updated links in 12 notes", after a rename or move. Click it to see which (each opens);
/// it goes after a few seconds, unless the pointer is on it or it's open.
private struct LinkUpdateNotice: View {
    @EnvironmentObject private var model: VaultModel
    @EnvironmentObject private var store: VaultStore
    let update: VaultStore.LinkUpdate
    @State private var isShowingNotes = false
    @State private var isHovering = false

    var body: some View {
        Button { isShowingNotes.toggle() } label: {
            Label(text, systemImage: "link")
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(NoticeBackground())
        .onHover { isHovering = $0 }
        .help("Show the notes")
        .popover(isPresented: $isShowingNotes, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(update.notes, id: \.self) { id in
                    Button(model.note(id)?.title ?? (id as NSString).deletingPathExtension) {
                        model.selection = id
                        isShowingNotes = false
                    }
                    .buttonStyle(.link)
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
            .frame(minWidth: 220, maxHeight: 360, alignment: .topLeading)
        }
        .task(id: update.id) { await dismissLater() }
    }

    private var text: String {
        update.notes.count == 1 ? "Updated the link in 1 note" : "Updated links in \(update.notes.count) notes"
    }

    private func dismissLater() async {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        while isHovering || isShowingNotes {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
        if store.linkUpdate?.id == update.id { store.linkUpdate = nil }
    }
}

/// "Renamed #work to #job in 12 notes", with Undo; it goes after a few seconds, unless the
/// pointer is on it.
private struct VaultChangeNoticeView: View {
    @EnvironmentObject private var store: VaultStore
    let notice: VaultStore.VaultChangeNotice
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            if notice.isWorking {
                ProgressView().controlSize(.small)
                Text(notice.text)
            } else {
                Label(notice.text, systemImage: notice.symbol)
            }
            if notice.canUndo, store.lastVaultChange != nil {
                Button("Undo") { store.undoLastVaultChange() }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .modifier(NoticeBackground())
        .onHover { isHovering = $0 }
        .task(id: notice.id) {
            if notice.isWorking { return } // Replaced when the work is done.
            try? await Task.sleep(nanoseconds: notice.isWarning ? 10_000_000_000 : notice.canUndo ? 8_000_000_000 : 3_000_000_000)
            while isHovering {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
            if store.vaultChangeNotice?.id == notice.id { store.vaultChangeNotice = nil }
        }
    }
}

/// Glass on macOS 26, a material before.
private struct NoticeBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}

/// The `#tag` words in a search, which filter its results by tag.
enum SearchTags {
    static func tags(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
    }

    static func removing(_ tag: String, from query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).filter { $0 != "#" + tag }.joined(separator: " ")
    }
}

/// A property value as the sidebar names it: a link without its brackets.
enum PropertyValueText {
    static func shown(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return trimmed.isEmpty ? "Empty" : trimmed }
        let inside = String(trimmed.dropFirst(2).dropLast(2))
        return inside.split(separator: "|", maxSplits: 1).last.map(String.init) ?? inside
    }
}
