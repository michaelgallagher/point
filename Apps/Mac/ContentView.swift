import IndexKit
import SwiftUI
import VaultKit

struct ContentView: View {
    @EnvironmentObject private var model: VaultModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var isAddingProperty = false

    var body: some View {
        Group {
            if model.root == nil {
                OpenVaultView()
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    NoteList()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    if let note = model.selectedNote {
                        NoteEditor(note: note, model: model)
                            .id(note.id)
                    } else {
                        Text("No Note Selected")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle(model.selectedNote?.title ?? model.root?.lastPathComponent ?? "Imprint")
                .toolbar(model.isFocused ? .hidden : .visible, for: .windowToolbar)
                .overlay(alignment: .topLeading) {
                    if model.isFocused {
                        // The one control kept in focus mode: bring the note list back.
                        Button { model.isFocused = false } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 14))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Show Note List")
                        .padding(.leading, 76)
                        .padding(.top, 2)
                    }
                }
                .onChange(of: model.searchFocusRequest) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { columns = .all } // Search needs the list.
                }
                .onChange(of: model.isFocused) { focused in
                    withAnimation(.easeInOut(duration: 0.2)) { columns = focused ? .detailOnly : .all }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .overlay(alignment: .top) {
            if model.isPaletteShown {
                ZStack(alignment: .top) {
                    // Clicking outside the palette closes it.
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture { model.isPaletteShown = false }
                    CommandPalette()
                        .padding(.top, 80)
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $model.renaming) { note in
            RenameSheet(note: note)
        }
        .sheet(isPresented: $model.isChoosingTemplate) {
            TemplatePicker()
        }
        .sheet(isPresented: $isAddingProperty) {
            AddPropertySheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imprintAddProperty)) { _ in
            if model.selectedNote != nil { isAddingProperty = true }
        }
    }
}

private struct OpenVaultView: View {
    @EnvironmentObject private var model: VaultModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Imprint")
                .font(.largeTitle.weight(.semibold))
            Text("Choose the folder that holds your notes.")
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Button("Open Vault…") { model.chooseVault() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteList: View {
    @EnvironmentObject private var model: VaultModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $model.searchText, isFocused: $searchFocused) {
                // Return opens the top result.
                if let first = model.searchResults?.first { model.selection = first.id }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            if let results = model.searchResults {
                List(results, selection: $model.selection) { result in
                    SearchResultRow(result: result)
                }
                .overlay {
                    if results.isEmpty {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                List(model.notes, selection: $model.selection) { note in
                    NoteRow(note: note)
                        .help(note.id)
                        .contextMenu {
                            Button("Rename…") { model.renaming = note }
                            Button("Move to Trash") { model.moveToTrash(note) }
                        }
                }
                .onDeleteCommand {
                    model.selectedNote.map(model.moveToTrash)
                }
            }
        }
        .onChange(of: model.searchFocusRequest) { _ in searchFocused = true }
        .overlay {
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}

/// The search field above the note list.
private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
    }
}

/// A search result: the note's name and, if its text matched, a snippet with the match marked.
private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .lineLimit(1)
            if let snippet = result.snippet {
                Text(Self.highlighted(snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    /// The snippet with matches in bold, from the index's start and end marks.
    static func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var isMatch = false
        var current = ""
        func flush() {
            var piece = AttributedString(current.replacingOccurrences(of: "\n", with: " "))
            if isMatch {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = .primary
            }
            result += piece
            current = ""
        }
        for character in snippet {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                isMatch = character == SearchResult.matchStart
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Note")
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

private struct TemplatePicker: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: URL?

    var body: some View {
        let templates = model.templates
        VStack(alignment: .leading, spacing: 12) {
            Text("Insert Template")
                .font(.headline)
            if templates.isEmpty {
                Text(model.settings.templatesFolder.isEmpty
                     ? "No templates folder is set. Choose one in Obsidian's Templates settings."
                     : "There are no templates in “\(model.settings.templatesFolder)”.")
                    .foregroundStyle(.secondary)
                    .frame(width: 320, alignment: .leading)
            } else {
                List(templates, id: \.url, selection: $selection) { template in
                    Text(template.name)
                }
                .frame(width: 320, height: 220)
                .onAppear { selection = templates.first?.url }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
    }

    private func insert() {
        guard let selection else { return }
        dismiss()
        model.insertTemplate(at: selection)
    }
}

/// A note in the list: its name, and optionally its date and tags.
private struct NoteRow: View {
    @EnvironmentObject private var model: VaultModel
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(note.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !note.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .help("In iCloud, not yet downloaded")
                }
                if model.showsDateInList {
                    Text(Self.label(for: model.listDate == .edited ? note.modified : note.created))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if model.showsTagsInList, let tags = model.tagsByNote[note.id], !tags.isEmpty {
                Text(tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Today's notes show the time, this week's the weekday, older ones the date.
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
