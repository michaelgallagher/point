import IndexKit
import SwiftUI
import VaultKit

/// The search page, from any page. It opens without the field focused, so its lists can be seen
/// and picked from: recent notes (which stand in for tabs), bookmarks, notes linked with the one
/// it was opened from, and commands. Typing shows results in their place. Opened from a note, the
/// first result finds the text in that note.
struct SearchScreen: View {
    @EnvironmentObject private var store: PhoneStore
    /// The note search was opened from, if any.
    let note: Note?
    let open: (Note.ID) -> Void
    let find: (String) -> Void
    let newNote: () -> Void
    let showSettings: () -> Void
    /// The note's text, for counting matches in it.
    @State private var noteText = ""
    /// The notes linked with the note.
    @State private var linked: [Note] = []

    private var query: String { store.searchText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            if query.isEmpty {
                lists
            } else {
                results
            }
        }
        .navigationTitle("Search")
        .searchable(text: $store.searchText, prompt: "Search")
        .onAppear {
            if let note { noteText = (try? NoteReader.read(note)) ?? "" }
        }
        .task {
            if let note { linked = await store.linkedNotes(of: note) }
        }
        .onDisappear { store.searchText = "" }
    }

    @ViewBuilder private var lists: some View {
        let recent = store.recentlyOpened(limit: 5, excluding: note?.id)
        if !recent.isEmpty {
            Section("Recent") {
                ForEach(recent) { note in row(note.id) { NoteRow(title: note.title) } }
            }
        }
        if !store.bookmarks.isEmpty {
            Section("Bookmarks") {
                ForEach(store.bookmarks, id: \.path) { bookmark in
                    if let note = store.note(bookmark.path) {
                        row(note.id) { NoteRow(title: bookmark.title ?? note.title) }
                    }
                }
            }
        }
        // Those not listed already.
        let others = linked.lazy.filter { note in !recent.contains { $0.id == note.id } && !store.isBookmarked(note.id) }.prefix(5)
        if !others.isEmpty {
            Section("Linked") {
                ForEach(Array(others)) { note in row(note.id) { NoteRow(title: note.title) } }
            }
        }
        Section("Commands") {
            if note != nil {
                command("Find in Note", symbol: "text.magnifyingglass") { find("") }
            }
            command("New Note", symbol: "square.and.pencil", action: newNote)
            command("Settings", symbol: "gear", action: showSettings)
        }
    }

    @ViewBuilder private var results: some View {
        if let note, matches > 0 {
            Section {
                Button { find(query) } label: {
                    HStack {
                        Label("Find in “\(note.title)”", systemImage: "text.magnifyingglass")
                        Spacer()
                        Text("\(matches)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        if let results = store.searchResults {
            Section {
                ForEach(results) { result in row(result.id) { SearchRow(result: result) } }
            }
            if results.isEmpty, matches == 0 {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// How many times what's typed is in the note.
    private var matches: Int {
        guard !query.isEmpty else { return 0 }
        var count = 0
        var rest = noteText[...]
        while let range = rest.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            count += 1
            rest = rest[range.upperBound...]
        }
        return count
    }

    private func row<Label: View>(_ id: Note.ID, @ViewBuilder label: () -> Label) -> some View {
        Button { open(id) } label: { label() }
            .foregroundStyle(.primary)
    }

    private func command(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .foregroundStyle(.primary)
    }
}

/// A search result: its title, and the matching text with the matches in bold.
private struct SearchRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .fontWeight(result.matchedTitle ? .semibold : .regular)
            if let snippet = result.snippet {
                Text(Self.marked(snippet))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// The snippet with each match (between `SearchResult.matchStart` and `matchEnd`) bold.
    static func marked(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var bold = false
        var run = ""
        func flush() {
            var part = AttributedString(run)
            if bold { part.inlinePresentationIntent = .stronglyEmphasized }
            result += part
            run = ""
        }
        for character in snippet {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                bold = character == SearchResult.matchStart
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }
}
