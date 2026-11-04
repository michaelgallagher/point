import IndexKit
import SwiftUI
import VaultKit

/// Search, over the page while the system's search field is in use: lists to pick from, recent
/// notes (which stand in for tabs) and bookmarks. Typing shows results in their place. It's on
/// the lists, not in a note, where the bottom bar finds in the note instead.
struct SearchScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    private var query: String { store.searchText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            // Only while searching: a scroll view always over the page would be the one its
            // large title follows.
            if isSearching {
                // Grouped, on the page's own background, as the lists below it are.
                List {
                    if query.isEmpty {
                        lists
                    } else {
                        results
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isSearching)
        // For the page to leave out its title and Settings meanwhile.
        // In step with the fade.
        .onChange(of: isSearching) { _, searching in
            withAnimation(.easeOut(duration: 0.25)) { store.isSearching = searching }
        }
    }

    @ViewBuilder private var lists: some View {
        let recent = store.recentlyOpened(limit: 5, excluding: nil)
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
    }

    @ViewBuilder private var results: some View {
        if let results = store.searchResults {
            Section {
                ForEach(results) { result in row(result.id, searchedFor: query) { SearchRow(result: result) } }
            }
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// A note to open, found by searching for `query` if given (search learns from it).
    private func row<Label: View>(_ id: Note.ID, searchedFor query: String? = nil, @ViewBuilder label: () -> Label) -> some View {
        Button {
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty { store.resultPicked(id, for: query) }
            dismissSearch()
            store.linkedRoute = .note(id)
        } label: { label() }
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
                // On as few lines as it fits: a line break in the note would leave a line empty.
                Text(Self.marked(snippet.split(whereSeparator: \.isNewline).joined(separator: " ")))
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
