import Foundation
import IndexKit
import SwiftUI
import VaultKit

/// The vault on the phone: its notes, the bookmarked ones (Obsidian's), which were edited or
/// opened most recently, the one being worked on, and search.
@MainActor
final class PhoneStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var bookmarks: [ObsidianBookmarks.Bookmark] = []
    /// What's typed in the search field; results follow as it changes.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    /// Results for `searchText`, or nil when not searching.
    @Published private(set) var searchResults: [SearchResult]?

    let root = PhoneVault.root
    private var index: SearchIndex?
    private var searchTask: Task<Void, Never>?

    init() {
        PhoneVault.makeSampleNotes()
        index = try? SearchIndex(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Index/vault.sqlite"))
        Task { await reload() }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }

    /// Scans the folder again, and brings the search index up to date behind it.
    func reload() async {
        let root = root
        let start = CACurrentMediaTime()
        let scanned = (try? await Task.detached(priority: .userInitiated) { try VaultScanner.scan(root) }.value) ?? []
        notes = scanned
        bookmarks = ObsidianBookmarks.load(vault: root)
        PhoneVault.log("scanned \(scanned.count) notes in \(Int((CACurrentMediaTime() - start) * 1000)) ms")
        guard let index else { return }
        let indexStart = CACurrentMediaTime()
        let changed = (try? await index.update(notes: scanned)) ?? 0
        if changed > 0 {
            PhoneVault.log("indexed \(changed) notes in \(Int((CACurrentMediaTime() - indexStart) * 1000)) ms")
            if !searchText.isEmpty { scheduleSearch() }
        }
    }

    // MARK: Recent

    /// When each note was last opened on this phone, by ID.
    private var opened: [Note.ID: Date] {
        get { UserDefaults.standard.data(forKey: "opened").flatMap { try? JSONDecoder().decode([Note.ID: Date].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "opened") }
    }

    func noteOpened(_ id: Note.ID) {
        var dates = opened
        dates[id] = Date()
        // Only the last few hundred are worth keeping.
        if dates.count > 300 { dates = Dictionary(uniqueKeysWithValues: dates.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) }) }
        opened = dates
        objectWillChange.send()
    }

    /// Every note, the most recently edited (anywhere) or opened (here) first.
    var recent: [Note] {
        let opened = opened
        return notes.sorted { max($0.modified, opened[$0.id] ?? .distantPast) > max($1.modified, opened[$1.id] ?? .distantPast) }
    }

    /// When a note was last edited or opened, whichever is later, for the list.
    func lastTouched(_ note: Note) -> Date { max(note.modified, opened[note.id] ?? .distantPast) }

    // MARK: The note being worked on

    /// Notes the note last edited on this phone, and when.
    func noteEdited(_ id: Note.ID) {
        UserDefaults.standard.set(id, forKey: "workingOn")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "workingOnDate")
    }

    /// The note being worked on: the one last edited here, if that was today.
    var workingOn: (note: Note, edited: Date)? {
        let date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "workingOnDate"))
        guard Calendar.current.isDateInToday(date), let id = UserDefaults.standard.string(forKey: "workingOn"),
              let note = note(id) else { return nil }
        return (note, date)
    }

    // MARK: Bookmarks

    func isBookmarked(_ id: Note.ID) -> Bool { bookmarks.contains { $0.path == id } }

    func toggleBookmark(_ id: Note.ID) {
        do {
            if isBookmarked(id) { try ObsidianBookmarks.remove(id, vault: root) } else { try ObsidianBookmarks.add(id, vault: root) }
        } catch {
            PhoneVault.log("couldn't change bookmarks: \(error.localizedDescription)")
        }
        bookmarks = ObsidianBookmarks.load(vault: root)
    }

    func moveBookmarks(from offsets: IndexSet, to destination: Int) {
        var paths = bookmarks.map(\.path)
        paths.move(fromOffsets: offsets, toOffset: destination)
        try? ObsidianBookmarks.reorder(paths, vault: root)
        bookmarks = ObsidianBookmarks.load(vault: root)
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        guard let index else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // Waits for a pause in typing.
            guard !Task.isCancelled else { return }
            let results = (try? await index.search(query)) ?? []
            guard !Task.isCancelled else { return }
            self?.searchResults = results
        }
    }
}
