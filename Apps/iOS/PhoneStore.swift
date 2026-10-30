import EditorKit
import Foundation
import IndexKit
import MarkdownKit
import SwiftUI
import VaultKit

/// The vault on the phone: its notes, the bookmarked ones (Obsidian's), which were edited or
/// opened most recently, the one being worked on, and search.
@MainActor
final class PhoneStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// Every folder in the vault, by path ("Projects/Point").
    @Published private(set) var folders: [String] = []
    /// Each note's tags, from the search index (nested tags as written: `work/point`).
    @Published private(set) var tagsByNote: [Note.ID: [String]] = [:]
    @Published private(set) var bookmarks: [ObsidianBookmarks.Bookmark] = []
    /// What's typed in the search field; results follow as it changes.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    /// Results for `searchText`, or nil when not searching.
    @Published private(set) var searchResults: [SearchResult]?
    /// How folders, the top level and tags list their notes, as on the Mac. Recent keeps its own
    /// order, and is the only list that opening a note changes.
    @Published var sort = UserDefaults.standard.string(forKey: "noteSort").flatMap(NoteSort.init) ?? .modified {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "noteSort") }
    }

    let root = PhoneVault.root
    private var index: SearchIndex?
    private var searchTask: Task<Void, Never>?

    /// Where edits that can't be saved are kept, outside the vault.
    let drafts = NoteDrafts(storage: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Drafts", isDirectory: true), vaultKey: "phone")

    init() {
        PhoneVault.makeSampleNotes()
        index = try? SearchIndex(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Index/vault.sqlite"))
        Task { await reload() }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }

    /// Notes renamed while the app's open, old ID to new, so a screen opened under the old
    /// one (navigation keeps the ID it was given) still finds its note.
    private var renamedIDs: [Note.ID: Note.ID] = [:]

    /// A note's ID now, following any renames since `id` was given out.
    func currentID(_ id: Note.ID) -> Note.ID {
        var id = id
        var seen: Set<Note.ID> = []
        while let next = renamedIDs[id], seen.insert(id).inserted { id = next }
        return id
    }

    /// Scans the folder again, and brings the search index up to date behind it.
    func reload() async {
        let root = root
        let start = CACurrentMediaTime()
        let result = try? await Task.detached(priority: .userInitiated) { try VaultScanner.scanWithFolders(root) }.value
        let scanned = result?.notes ?? []
        notes = scanned
        folders = (result?.folders ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        bookmarks = ObsidianBookmarks.load(vault: root)
        // Notes left untitled when the app last stopped (none is open yet): named, or removed.
        if !isLaunched {
            isLaunched = true
            untitled.forEach { finishUntitled($0) }
        }
        PhoneVault.log("scanned \(scanned.count) notes in \(Int((CACurrentMediaTime() - start) * 1000)) ms")
        guard let index else { return }
        let indexStart = CACurrentMediaTime()
        let changed = (try? await index.update(notes: scanned)) ?? 0
        if changed > 0 || tagsByNote.isEmpty, let tags = try? await index.tagsByNote() { tagsByNote = tags }
        if changed > 0 {
            PhoneVault.log("indexed \(changed) notes in \(Int((CACurrentMediaTime() - indexStart) * 1000)) ms")
            if !searchText.isEmpty { scheduleSearch() }
        }
    }

    // MARK: Links

    /// Where a tapped link leads, for home's navigation to go to.
    @Published var linkedRoute: Route?

    /// Follows a link in a note, as on the Mac: a link to a note that doesn't exist makes it.
    func open(_ link: LinkTarget, from sourceID: Note.ID) {
        let resolver = LinkResolver(notes: notes)
        switch link {
        case .note(let target):
            let id = resolver.resolve(wikiTarget: target, from: sourceID)?.id ?? createLinkedNote(named: target)
            linkedRoute = id.map(Route.note)
        case .file(let destination):
            linkedRoute = resolver.resolve(markdownDestination: destination, from: sourceID).map { .note($0.id) }
        case .web(let url):
            if LinkTarget.opensWithoutAsking(url) { UIApplication.shared.open(url) }
        case .tag(let tag):
            linkedRoute = .tag(tag)
        }
    }

    /// Note titles for completing a `[[link`, as on the Mac: names starting with the typed text
    /// first, then names with a word starting with it, then names containing it anywhere.
    func titleSuggestions(for partial: String) -> [String] {
        let query = partial.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(recent.prefix(20).map(\.title)) }
        func rank(_ title: String) -> Int? {
            let lowered = title.lowercased()
            if lowered.hasPrefix(query) { return 0 }
            if lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) { return 1 }
            if lowered.contains(query) { return 2 }
            return nil
        }
        var ranked: [(title: String, rank: Int)] = []
        for note in notes {
            if let rank = rank(note.title) { ranked.append((note.title, rank)) }
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.title.count < $1.title.count }
        var seen = Set<String>()
        var titles: [String] = []
        for entry in ranked where titles.count < 20 && seen.insert(entry.title.lowercased()).inserted {
            titles.append(entry.title)
        }
        return titles
    }

    /// Tags for completing a `#tag`: those starting with the typed text.
    func tagSuggestions(for partial: String) -> [String] {
        let query = partial.lowercased()
        return Array(tags.map(\.tag).filter { $0.lowercased().hasPrefix(query) }.prefix(20))
    }

    private func createLinkedNote(named target: String) -> Note.ID? {
        let name = target.split(separator: "#").first.map(String.init) ?? target
        let title = NoteFiles.sanitizedTitle((name as NSString).lastPathComponent)
        guard !title.isEmpty, let url = try? NoteFiles.create(title: title, in: root) else { return nil }
        let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                        modified: Date(), created: Date(), isDownloaded: true)
        notes.append(note)
        return note.id
    }

    // MARK: New notes

    private var isLaunched = false

    /// New notes not yet named: each takes its name from its first line when it's left, or
    /// goes if it's still empty. Kept across launches, for a note open when the app stopped.
    private var untitled: Set<Note.ID> {
        get { Set(UserDefaults.standard.stringArray(forKey: "untitled") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "untitled") }
    }

    func isUntitled(_ id: Note.ID) -> Bool { untitled.contains(id) }

    /// A new, empty note at the vault's top level, to be named from its first line.
    func createNote() -> Note.ID? {
        do {
            let url = try NoteFiles.create(title: NoteFiles.untitledName(), in: root)
            let note = Note(id: url.lastPathComponent, url: url, title: url.deletingPathExtension().lastPathComponent,
                            modified: Date(), created: Date(), isDownloaded: true)
            notes.append(note)
            untitled.insert(note.id)
            return note.id
        } catch {
            PhoneVault.log("couldn't create a note: \(error.localizedDescription)")
            return nil
        }
    }

    /// Names a new note from its first line, or removes it if it's empty, once it's been left
    /// (and saved). Only a note read back as empty is removed; if it can't be read, renamed or
    /// removed, it stays as it is, to try again next time.
    func finishUntitled(_ id: Note.ID) {
        guard untitled.contains(id) else { return }
        guard let note = note(id) ?? (FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
            ? Note(id: id, url: root.appendingPathComponent(id), title: (id as NSString).deletingPathExtension, modified: Date(), created: Date(), isDownloaded: true)
            : nil) else {
            untitled.remove(id) // Gone already.
            return
        }
        guard let text = try? NoteReader.read(contentsOf: note.url) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard (try? FileManager.default.removeItem(at: note.url)) != nil else { return }
            untitled.remove(id)
            notes.removeAll { $0.id == id }
            return
        }
        untitled.remove(id)
        guard let line = PlainText.firstLine(of: text) else { return }
        let title = NoteFiles.sanitizedTitle(line)
        guard !title.isEmpty, title != note.title else { return }
        let available = NoteFiles.availableURL(for: title, in: note.url.deletingLastPathComponent())
        guard let url = try? NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent) else {
            untitled.insert(id) // Kept under its untitled name; named next time.
            return
        }
        moved(note, to: url)
        Task { await reload() }
    }

    /// Renames a note, as typed in its title: links to it across the vault, and its
    /// bookmarks, follow, as on the Mac. Throws if the name's taken or the file can't be
    /// renamed (the note's left as it was).
    func rename(_ id: Note.ID, to title: String) throws -> Note {
        guard let note = note(id) else { throw CocoaError(.fileNoSuchFile) }
        let vault = notes
        let url = try NoteFiles.rename(note.url, to: title)
        untitled.remove(id)
        let renamed = moved(note, to: url)
        let newTitle = renamed.title
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newTitle, notes: vault)
            if !result.updatedNotes.isEmpty { PhoneVault.log("updated links in \(result.updatedNotes.count) notes") }
            await self.reload()
        }
        return renamed
    }

    /// A note's file renamed: the list, and what it was known by (opened, worked on, its
    /// bookmarks), follow it.
    @discardableResult
    private func moved(_ note: Note, to url: URL) -> Note {
        let folder = (note.id as NSString).deletingLastPathComponent
        let newID = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
        let renamed = Note(id: newID, url: url, title: url.deletingPathExtension().lastPathComponent,
                           modified: note.modified, created: note.created, isDownloaded: true)
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = renamed }
        renamedIDs[note.id] = newID
        var dates = opened
        if let date = dates.removeValue(forKey: note.id) { dates[newID] = date; opened = dates }
        if UserDefaults.standard.string(forKey: "workingOn") == note.id { UserDefaults.standard.set(newID, forKey: "workingOn") }
        if isBookmarked(note.id) {
            try? ObsidianBookmarks.rename(note.id, to: newID, vault: root)
            bookmarks = ObsidianBookmarks.load(vault: root)
        }
        return renamed
    }

    // MARK: Folders and tags

    /// Makes a folder called `name` inside `parent` ("" for the vault's top level), as on the
    /// Mac, and returns its path. Throws with a message to show if the name can't be used.
    func createFolder(named name: String, in parent: String) throws -> String {
        // Folder names can't contain the path separators macOS and Obsidian use.
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { throw FolderError("A folder needs a name that doesn’t start with a dot.") }
        let path = parent.isEmpty ? clean : parent + "/" + clean
        let url = root.appendingPathComponent(path, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FolderError("There’s already a folder or note called “\(clean)” there.") }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        folders = (folders + [path]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return path
    }

    struct FolderError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// The folders directly inside `folder` ("" for the vault's top level), by name.
    func subfolders(of folder: String) -> [String] {
        folders.filter { ($0 as NSString).deletingLastPathComponent == folder }
    }

    /// The notes directly in `folder`, in the chosen order.
    func notes(in folder: String) -> [Note] {
        notes.filter { ($0.id as NSString).deletingLastPathComponent == folder }.sorted(by: sort)
    }

    /// How many notes are in a folder, and the folders inside it.
    func noteCount(inFolder folder: String) -> Int {
        let prefix = folder + "/"
        return notes.count { $0.id.hasPrefix(prefix) }
    }

    /// Every tag, with how many notes have it (or a tag nested under it), by name.
    var tags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tags in tagsByNote.values {
            // Each note counts once for a tag, and once for each tag it's nested under.
            var seen: Set<String> = []
            for tag in tags {
                let parts = tag.split(separator: "/").map(String.init)
                for depth in 1...max(parts.count, 1) { seen.insert(parts.prefix(depth).joined(separator: "/")) }
            }
            for tag in seen { counts[tag, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// The notes with a tag (or one nested under it), in the chosen order.
    func notes(taggedWith tag: String) -> [Note] {
        let lowered = tag.lowercased()
        return notes.filter { note in
            (tagsByNote[note.id] ?? []).contains { $0.lowercased() == lowered || $0.lowercased().hasPrefix(lowered + "/") }
        }.sorted(by: sort)
    }

    // MARK: Recent

    /// When each note was last opened on this phone, by ID.
    private var opened: [Note.ID: Date] = UserDefaults.standard.data(forKey: "opened")
        .flatMap { try? JSONDecoder().decode([Note.ID: Date].self, from: $0) } ?? [:] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(opened), forKey: "opened") }
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

    /// `recent`, under date headings, as a sorted list's are.
    var recentGroups: [(label: String, notes: [Note])] {
        var groups: [(label: String, notes: [Note])] = []
        for note in recent {
            let label = NoteDateGroup.label(for: lastTouched(note))
            if groups.last?.label == label {
                groups[groups.count - 1].notes.append(note)
            } else {
                groups.append((label, [note]))
            }
        }
        return groups
    }

    /// When a note was last edited or opened, whichever is later.
    private func lastTouched(_ note: Note) -> Date { max(note.modified, opened[note.id] ?? .distantPast) }

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
