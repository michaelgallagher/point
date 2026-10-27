import IndexKit
import SwiftUI
import VaultKit

/// Home: search at the top; the note being worked on, if any; bookmarks; then every note,
/// the most recently edited or opened first. Searching shows results in place.
struct HomeScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @State private var path: [Note.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
                .navigationDestination(for: Note.ID.self) { id in
                    if let note = store.note(id) { NoteScreen(note: note) }
                }
                .refreshable { await store.reload() }
        }
        .onChange(of: store.notes) { _, notes in
            // `-SpikeTypeTest YES` opens the long note by itself, to time typing in it.
            if UserDefaults.standard.bool(forKey: "SpikeTypeTest"), path.isEmpty,
               let long = notes.first(where: { $0.title == PhoneVault.longTitle }) {
                path = [long.id]
            }
        }
    }

    @ViewBuilder private var list: some View {
        if let results = store.searchResults {
            List(results) { result in
                NavigationLink(value: result.id) { SearchRow(result: result) }
            }
            .listStyle(.plain)
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: store.searchText) } }
        } else {
            List {
                if let working = store.workingOn {
                    Section {
                        NavigationLink(value: working.note.id) {
                            NoteRow(title: working.note.title, detail: "Edited \(working.edited.formatted(.relative(presentation: .named)))")
                        }
                    }
                }
                if !store.bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(store.bookmarks, id: \.path) { bookmark in
                            if let note = store.note(bookmark.path) {
                                NavigationLink(value: note.id) { NoteRow(title: bookmark.title ?? note.title) }
                                    .contextMenu { bookmarkButton(note.id) }
                            }
                        }
                        .onMove(perform: store.moveBookmarks)
                    }
                }
                Section("Recent") {
                    ForEach(store.recent) { note in
                        NavigationLink(value: note.id) {
                            NoteRow(title: note.title, detail: Self.label(for: store.lastTouched(note)))
                        }
                        .contextMenu { bookmarkButton(note.id) }
                    }
                }
            }
            .overlay { if store.notes.isEmpty { ContentUnavailableView("No Notes", systemImage: "doc.text",
                description: Text("Copy notes into Point’s folder in the Files app.")) } }
        }
    }

    private func bookmarkButton(_ id: Note.ID) -> some View {
        let bookmarked = store.isBookmarked(id)
        return Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
            store.toggleBookmark(id)
        }
    }

    /// Today's time, this week's day, or an older date, as on the Mac.
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

private struct NoteRow: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// A search result: its title, and the matching text with the matches in bold.
private struct SearchRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .fontWeight(result.matchedTitle ? .semibold : .regular)
                .lineLimit(1)
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
