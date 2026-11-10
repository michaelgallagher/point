import ClipKit
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
    /// Whether the vault has been read since launch: until then, no notes doesn't mean none.
    @Published private(set) var hasScanned = false
    /// Whether the app has what it needs to show, after launch: the notes, folders and tags. Until
    /// then the launch cover is up, not home half filled in.
    @Published private(set) var isReady = false
    /// Every folder in the vault, by path ("Projects/Point").
    @Published private(set) var folders: [String] = []
    /// Each note's tags, from the search index (nested tags as written: `work/point`).
    @Published private(set) var tagsByNote: [Note.ID: [String]] = [:]
    /// The property names used in notes, with how many notes use each, most used first.
    @Published private(set) var propertyNames: [(name: String, count: Int)] = []
    @Published private(set) var bookmarks: [ObsidianBookmarks.Bookmark] = []
    /// The folders and tags on home's Favourites, in their order: the phone's own, in its
    /// defaults, not the vault's (Obsidian has nothing like it).
    @Published private(set) var favourites: [Favourite] = UserDefaults.standard.data(forKey: PhoneVault.defaultsKey("favourites"))
        .flatMap { try? JSONDecoder().decode([Favourite].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(favourites), forKey: PhoneVault.defaultsKey("favourites")) }
    }
    /// What's typed in the search field, and what's found.
    let search = PhoneSearch()
    /// Goes up each time the search index takes in changed notes, for what's read from it to
    /// be read again.
    @Published private(set) var indexUpdates = 0
    /// Notes show their raw Markdown, every marker visible, as on the Mac: for every note,
    /// until it's turned off or the app quits.
    @Published var showsMarkdown = false
    /// How folders, All notes and tags list their notes, as on the Mac. Recent keeps its own
    /// order, and is the only list that opening a note changes.
    @Published var sort = UserDefaults.standard.string(forKey: "noteSort").flatMap(NoteSort.init) ?? .modified {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "noteSort") }
    }

    /// How note text is set, from Settings.
    @Published var typography: Typography = UserDefaults.standard.data(forKey: "typography")
        .flatMap { try? JSONDecoder().decode(Typography.self, from: $0) } ?? PhoneTextView.standardTypography {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(typography), forKey: "typography") }
    }

    let root = PhoneVault.root
    private var index: SearchIndex?
    /// How a clip is going, if one is (see `clip`).
    @Published var clipStatus: ClipStatus?

    /// A note whose `source` is this address (a page clipped before).
    func notes(withSource address: String) async -> Note.ID? {
        guard let index, let id = try? await index.notes(matching: NoteQuery([.property("source", .equals(address))])).first,
              note(id) != nil else { return nil }
        return id
    }
    /// The search index, for lists' queries.
    var searchIndex: SearchIndex? { index }
    /// Images and lists that notes embed.
    let embeds = PhoneEmbeds()

    /// Where edits that can't be saved are kept, outside the vault.
    let drafts = NoteDrafts(storage: PhoneVault.storage("Drafts"), vaultKey: PhoneVault.key)

    init() {
        history = Self.loadHistory(from: historyFile)
        embeds.store = self
        PhoneVault.makeSampleNotes()
        index = try? SearchIndex(url: PhoneVault.storage("Index/vault.sqlite"))
        search.find = { [weak self] query in
            guard let self, let index = self.index else { return nil }
            let results = (try? await index.search(query)) ?? []
            // The notes opened and picked most move up among matches of similar quality.
            return self.history.rank(results, for: query)
        }
        Task { await reload() }
        // Changes from elsewhere (the Mac, through iCloud) and notes arriving: read again.
        presenter = VaultPresenter(root: root, changed: { [weak self] urls in self?.refresh(urls) },
                                   conflicted: { [weak self] url in self?.surfaceConflicts([url]) })
        becameActive = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }

    // MARK: Changes from elsewhere

    /// Notes iCloud found changed on two devices before either synced, as a note to show:
    /// the other version is in a conflict copy beside each.
    @Published var conflictNotice: String?
    private var hasLookedForConflicts = false

    /// Writes out iCloud's hidden conflict versions of these notes as conflict copies beside
    /// them (off the main thread), says so, and reads the vault again to show them.
    func surfaceConflicts(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let copied = await Task.detached(priority: .utility) {
                urls.compactMap { url -> String? in
                    guard ICloudConflicts.has(url) else { return nil }
                    do {
                        return try ICloudConflicts.surface(url).isEmpty ? nil : url.deletingPathExtension().lastPathComponent
                    } catch {
                        PhoneVault.log("couldn't copy out an iCloud conflict of \(url.lastPathComponent): \(error.localizedDescription)")
                        return nil
                    }
                }
            }.value
            guard !copied.isEmpty else { return }
            conflictNotice = copied.count == 1
                ? "“\(copied[0])” was changed on two devices at once. The other version is in a conflict copy beside it."
                : "\(copied.count) notes were changed on two devices at once. The other versions are in conflict copies beside them."
            refresh()
        }
    }

    /// Hears of changes to the vault's folder.
    private var presenter: VaultPresenter?
    private var becameActive: NSObjectProtocol?
    /// How many notes iCloud hasn't brought to the phone yet. Each is asked for, and read
    /// (and indexed) as it arrives.
    @Published private(set) var downloadingCount = 0
    private var askedToDownload: Set<Note.ID> = []
    private var downloadCheck: Task<Void, Never>?

    /// Stops watching the vault (another is being chosen).
    func stopWatching() {
        presenter?.stop()
        presenter = nil
        if let becameActive { NotificationCenter.default.removeObserver(becameActive) }
        becameActive = nil
        downloadCheck?.cancel()
    }

    /// Reads the vault again, in the background, once it's been read since launch: only the
    /// files given, if they are (those the presenter heard of), else all of it.
    func refresh(_ urls: Set<URL>? = nil) {
        guard hasScanned, presenter != nil else { return }
        if let urls {
            guard !urls.isEmpty else { return }
            Task { await read(files: urls) }
        } else {
            Task { await reload() }
        }
    }

    /// Fetches the text of notes changed elsewhere as opening one does (a coordinated read,
    /// which iCloud serves at once), rather than waiting for the requested download, which took
    /// up to a minute. Then each is read again. Only notes that were here before: not the
    /// thousands of a first sync.
    private func fetchChanged(_ urls: Set<URL>) {
        guard !urls.isEmpty, urls.count <= 50 else { return }
        Task {
            await Task.detached(priority: .userInitiated) {
                for url in urls { NoteReader.fetch(url) }
            }.value
            refresh(urls)
        }
    }

    /// Asks iCloud for the notes not on the phone yet, and looks again in a few seconds (the
    /// presenter hears of most arrivals; this catches any it doesn't).
    private func requestDownloads(_ scanned: [Note]) {
        let waiting = scanned.filter { !$0.isDownloaded }
        if waiting.count != downloadingCount { downloadingCount = waiting.count }
        // Arrived: asked for again when it's next changed elsewhere (it was asked for only once).
        askedToDownload.formIntersection(waiting.map(\.id))
        let ask = waiting.filter { askedToDownload.insert($0.id).inserted }.map(\.url)
        if !ask.isEmpty {
            Task.detached(priority: .utility) {
                for url in ask { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            }
        }
        downloadCheck?.cancel()
        guard !waiting.isEmpty else { return }
        let urls = Set(waiting.map(\.url))
        downloadCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.refresh(urls)
        }
    }

    /// The read under way, if one is, and what the next is to look at: all of the vault, or
    /// only these files.
    private var reloading: Task<Void, Never>?
    private var pendingAll = false
    private var pendingFiles: Set<URL> = []

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

    /// Scans the folder again, and brings the search index up to date behind it. One read at a
    /// time: asked for during one, another follows it, and both callers wait for that.
    func reload() async { await read(all: true) }

    private func read(all: Bool = false, files: Set<URL> = []) async {
        if all { pendingAll = true } else { pendingFiles.formUnion(files) }
        if let reloading { return await reloading.value }
        let task = Task { [weak self] in
            guard let self else { return }
            while pendingAll || !pendingFiles.isEmpty {
                if pendingAll {
                    pendingAll = false
                    pendingFiles = []
                    await scan()
                } else {
                    let files = pendingFiles
                    pendingFiles = []
                    await scan(only: files)
                }
            }
            reloading = nil
        }
        reloading = task
        await task.value
    }

    /// Reads the vault (or only `files`, those heard of as changed: a few milliseconds, where
    /// all of it takes seconds in iCloud Drive), and brings everything up to date behind it.
    private func scan(only files: Set<URL>? = nil) async {
        let root = root
        let start = CACurrentMediaTime()
        // On the first read, the tags and properties the index had last time are read beside the
        // scan, so home has its tags when it shows; the index catches up after.
        let early: Task<([Note.ID: [String]]?, [(name: String, count: Int)]?), Never>? = isReady ? nil : index.map { index in
            Task { (try? await index.tagsByNote(), try? await index.propertyNames()) }
        }
        let notesAtStart = notes
        let listed: [Note]
        var result: VaultScanner.Scan?
        if let files {
            guard let changed = await Task.detached(priority: .userInitiated, operation: {
                VaultScanner.rescan(files, in: root, notes: notesAtStart)
            }).value else {
                pendingAll = true // A folder or an image: all of it.
                return
            }
            listed = changed
        } else {
            result = try? await Task.detached(priority: .userInitiated) { try VaultScanner.quickScan(root) }.value
            listed = result?.notes ?? []
        }
        // A note made, renamed or moved here while the folder was being read: read it again,
        // rather than put back the list from before (a new note's screen went blank as it was
        // named, its new name not in the list).
        if notes != notesAtStart {
            if let files { pendingFiles.formUnion(files) } else { pendingAll = true }
            return
        }
        var scanned = listed
        let before = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scannedIDs = Set(scanned.map(\.id))
        // Notes not there last time, and those gone: renamed or moved on another device, the
        // one is the other, and what's known about it here follows it (see `isSameNote`). A
        // rename can arrive over two reads, so a note gone and not found waits one more.
        let newlyAppeared = before.isEmpty ? [] : scanned.filter { before[$0.id] == nil }
        var appeared = newlyAppeared + appearedBefore.filter { scannedIDs.contains($0.id) && before[$0.id] != nil }
        let vanished = notes.filter { !scannedIDs.contains($0.id) }
        var unmatched: [Note] = []
        var titles: [Note.ID: String] = [:]
        // Notes that were here and changed elsewhere, their text not here yet: fetched now.
        var fetchNow: Set<URL> = []
        for gone in vanished + vanishedBefore.filter({ !scannedIDs.contains($0.id) }) {
            guard let index = appeared.firstIndex(where: { Self.isSameNote(gone, $0) }) else {
                unmatched.append(gone)
                continue
            }
            let new = appeared.remove(at: index)
            noteMovedElsewhere(from: gone.id, to: new)
            // Its title, while its text is on the way: the one it had if it's only moved (or
            // its new name says the same), not if it was renamed for a new title (`…-test`).
            if new.name == gone.name || NoteNames.renamed(gone.name, to: gone.title) == new.name {
                titles[new.id] = gone.title
            }
            if gone.isDownloaded, !new.isDownloaded { fetchNow.insert(new.url) }
        }
        vanishedBefore = unmatched.filter { before[$0.id] != nil }
        // How long changes from elsewhere take to reach the phone: each note found changed, and
        // when it was saved (in `spike-timings.txt`, beside Point's own folder).
        if !before.isEmpty {
            for note in scanned {
                guard let known = before[note.id] else { continue }
                let ago = "saved \(Int(Date().timeIntervalSince(note.modified))) s ago"
                if note.modified > known.modified {
                    PhoneVault.log("heard of a change: \(note.title), \(ago)" + (note.isDownloaded ? "" : ", text still coming"))
                } else if note.isDownloaded, !known.isDownloaded {
                    PhoneVault.log("change arrived: \(note.title), \(ago)")
                }
            }
        }
        appearedBefore = newlyAppeared.filter { new in appeared.contains { $0.id == new.id } }
        // A note iCloud hasn't brought yet has only its file name for a title (for a note Point
        // named, its lowercase slug): the title it had is kept until its text arrives.
        scanned = scanned.map { note in
            guard !note.isDownloaded, let title = titles[note.id] ?? before[note.id]?.title, title != note.title else { return note }
            return Note(id: note.id, url: note.url, title: title, modified: note.modified, created: note.created, isDownloaded: false)
        }
        let appearedNow = before.isEmpty ? [] : scanned.filter { before[$0.id] == nil }
        if let early {
            let (tags, names) = await early.value
            if let tags { tagsByNote = tags }
            if let names { propertyNames = names }
        }
        if scanned != notes { notes = scanned }
        hasScanned = true
        for note in scanned where !note.isDownloaded && before[note.id]?.isDownloaded == true { fetchNow.insert(note.url) }
        fetchChanged(fetchNow)
        requestDownloads(scanned)
        NotificationCenter.default.post(name: .phoneVaultScanned, object: self, userInfo: ["appeared": appearedNow])
        // Once a launch, every note checked for conflict versions iCloud kept while one of the
        // devices was offline (those arriving later are heard of by the presenter).
        if !hasLookedForConflicts, !scanned.isEmpty, !PhoneVault.isOwnFolder {
            hasLookedForConflicts = true
            surfaceConflicts(scanned.filter(\.isDownloaded).map(\.url))
        }
        // Notes that are gone take what was learned about them (not while the folder reads
        // as empty, which is more likely unavailable for a moment), once they've had their
        // chance to be found renamed.
        if !scanned.isEmpty {
            let known = history
            history.keepOnly(scannedIDs.union(vanishedBefore.map(\.id)))
            if history != known { historyFile.save(history) }
        }
        if let images = result?.images, images != embeds.images { embeds.images = images }
        if let result { folders = result.folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
        bookmarks = ObsidianBookmarks.load(vault: root)
        propertyTypes = PropertyTypes.load(vault: root)
        pointTypes = PointTypes.load(vault: root)
        settings = ObsidianSettings.load(vault: root)
        templates = Templates.available(in: root, settings: settings)
        kinds = NoteKinds.load(vault: root)
        pointTypes.implied = kinds.choice.map { [kinds.property: $0] } ?? [:]
        refreshTrash()
        // Notes left untitled when the app last stopped (none is open yet): named, or removed.
        if !isLaunched {
            isLaunched = true
            untitled.forEach { finishUntitled($0) }
        }
        if !isReady {
            isReady = true
            PhoneVault.log("ready \(Int((CACurrentMediaTime() - PhoneVault.launched) * 1000)) ms after launch")
        }
        PhoneVault.log((files.map { "read \($0.count) changed files" } ?? "scanned \(scanned.count) notes")
                       + " in \(Int((CACurrentMediaTime() - start) * 1000)) ms")
        guard let index else { return }
        let indexStart = CACurrentMediaTime()
        let changed = (try? await index.update(notes: scanned)) ?? 0
        if changed > 0 || tagsByNote.isEmpty, let tags = try? await index.tagsByNote() { tagsByNote = tags }
        if changed > 0 || propertyNames.isEmpty, let names = try? await index.propertyNames() { propertyNames = names }
        if changed > 0 {
            indexUpdates += 1
            PhoneVault.log("indexed \(changed) notes in \(Int((CACurrentMediaTime() - indexStart) * 1000)) ms")
            search.searchAgain()
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
            if LinkTarget.opensWithoutAsking(url) { UIApplication.shared.open(url) } else { linkToConfirm = url }
        case .tag(let tag):
            linkedRoute = .tag(tag)
        }
    }

    /// A link that isn't to a web page or email, for home to ask about first: a note from
    /// somewhere else shouldn't start something in another app with one tap.
    @Published var linkToConfirm: URL?
    /// Set when no app on the phone took a link.
    @Published var linkDidNotOpen = false

    func openConfirmed(_ url: URL) {
        UIApplication.shared.open(url) { [weak self] opened in
            if !opened { self?.linkDidNotOpen = true }
        }
    }

    /// What goes between `[[` and `]]` for a link to the note with this title, as on the Mac:
    /// its name, and for a note Point named, `2026-11-06-questions|Questions?`.
    func linkText(forTitle title: String) -> String {
        guard let note = notes.first(where: { $0.title == title }) ?? notes.first(where: { $0.title.lowercased() == title.lowercased() }) else { return title }
        return LinkResolver.linkText(for: note)
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

    /// The notes linking to `note`, each with the line its link is on, by title.
    func backlinks(to note: Note) async -> [Backlink] {
        (try? await index?.backlinks(to: note, notes: notes)) ?? []
    }

    /// Where to take a note to as it opens (from its backlink, the link to the note it came
    /// from), until it's taken.
    private var revealing: (id: Note.ID, range: NSRange)?

    /// Opens a note linking to another, at the link.
    func open(_ backlink: Backlink) {
        if backlink.range.location != NSNotFound { revealing = (backlink.noteID, backlink.range) }
        linkedRoute = .note(backlink.noteID)
    }

    /// Where to show in a note being opened, if it was opened at a link.
    func revealRange(for id: Note.ID) -> NSRange? {
        guard let revealing, revealing.id == id else { return nil }
        self.revealing = nil
        return revealing.range
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

    // MARK: Templates

    /// The vault's Obsidian settings, which say where its templates are.
    private(set) var settings = ObsidianSettings()
    /// The templates in the vault's templates folder, by name.
    @Published private(set) var templates: [(name: String, url: URL)] = []

    // MARK: Property types

    /// The vault's property types, kept where Obsidian keeps them.
    @Published private(set) var propertyTypes = PropertyTypes()

    func setPropertyType(_ type: PropertyType, forKey key: String) {
        guard propertyTypes.type(forKey: key) != type else { return }
        propertyTypes.set(type, forKey: key)
        saveTypes()
    }

    /// The property names to suggest: those in notes, most used first, then those only given a
    /// type so far, and Obsidian's own. A name differing only in case isn't repeated.
    var suggestedPropertyNames: [(name: String, count: Int)] {
        let used = Set(propertyNames.map { $0.name.lowercased() })
        let unused = (propertyTypes.raw.keys + ["aliases", "tags"])
            .filter { !used.contains($0.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var seen: Set<String> = []
        return propertyNames + unused.filter { seen.insert($0.lowercased()).inserted }.map { ($0, 0) }
    }

    /// A property renamed in a note: its type goes with the new name, for that name.
    func renamePropertyType(_ key: String, to newKey: String) {
        let before = propertyTypes
        propertyTypes.rename(key, to: newKey)
        if propertyTypes != before { saveTypes() }
        let pointBefore = pointTypes
        pointTypes.rename(key, to: newKey)
        if pointTypes != pointBefore { try? pointTypes.save(vault: root) }
    }

    private func saveTypes() {
        do {
            try propertyTypes.save(vault: root)
        } catch {
            PhoneVault.log("couldn't save property types: \(error.localizedDescription)")
        }
    }

    // MARK: Kinds of note

    /// What notes can be (`.point/kinds.json`), as on the Mac: offered for new notes from
    /// home's New note, and as `type`'s choices.
    @Published private(set) var kinds = NoteKinds()
    /// The kinds home shows as tiles of their own, by name, chosen in Settings (each vault its own).
    @Published var homeKinds: [String] = UserDefaults.standard.stringArray(forKey: PhoneVault.defaultsKey("homeKinds")) ?? [] {
        didSet { UserDefaults.standard.set(homeKinds, forKey: PhoneVault.defaultsKey("homeKinds")) }
    }

    /// Shows a kind on home as a tile of its own, or stops.
    func toggleHomeKind(_ name: String) {
        if let index = homeKinds.firstIndex(of: name) { homeKinds.remove(at: index) } else { homeKinds.append(name) }
    }

    /// How many notes are of each kind, by its name in lowercase (once property values are loaded).
    var kindCounts: [String: Int] {
        Dictionary((propertyValues[kinds.property.lowercased()] ?? []).map { ($0.value.lowercased(), $0.count) }, uniquingKeysWith: +)
    }

    /// A kind's templates in the templates folder, each with a short label.
    func templates(of kind: NoteKinds.Kind) -> [(label: String, url: URL)] {
        NoteKinds.templates(of: kind, among: templates)
    }

    /// A new note of a kind, from one of its templates (its first, if not given), in the
    /// kind's folder (the vault root, if it has none), with `type` set to the kind.
    func createNote(kind: NoteKinds.Kind, template url: URL? = nil) -> Note.ID? {
        let url = url ?? templates(of: kind).first?.url
        let template = url.flatMap { try? NoteReader.read(contentsOf: $0) } ?? ""
        return createNote(in: kind.folder ?? "", text: kinds.text(for: kind, from: Templates.render(template, title: "", settings: settings)))
    }

    // MARK: Point's own kinds, and people

    /// Point's own kinds of property (choice, person, rating, link to note), from the vault's
    /// `.point/types.json`, as on the Mac.
    @Published private(set) var pointTypes = PointTypes()

    /// What came before a note (its earlier meetings with the same people, or the notes on a
    /// post's topics), as on the Mac: people are in the properties of Point's person kind, else
    /// in `people`.
    func recall(of frontmatter: Frontmatter?, name: String) -> Recall? {
        let personKeys = pointTypes.properties.filter { $0.value.type == .person }.map(\.key)
        return Recall(frontmatter: frontmatter, name: name, typeProperty: kinds.property,
                      personProperties: personKeys.isEmpty ? ["people"] : personKeys.sorted())
    }

    /// Gives a property one of Point's own kinds (nil: back to Obsidian's types alone). It's
    /// kept in Obsidian's types too, as the type it's written as.
    func setPointType(_ definition: PointTypes.Definition?, forKey key: String) {
        guard pointTypes.definition(forKey: key) != definition else { return }
        pointTypes.set(definition, forKey: key)
        do { try pointTypes.save(vault: root) } catch {
            PhoneVault.log("couldn't save Point's types: \(error.localizedDescription)")
        }
        if let definition, propertyTypes.type(forKey: key) != definition.type.baseType {
            propertyTypes.set(definition.type.baseType, forKey: key)
            saveTypes()
        }
    }

    /// The values each property is given across the vault (by its name, lowercased), most used
    /// first: read from the index when the properties sheet opens, and again after it changes.
    @Published private(set) var propertyValues: [String: [(value: String, count: Int)]] = [:]
    private var propertyValuesUpdate = -1

    func loadPropertyValues() async {
        guard propertyValuesUpdate != indexUpdates, let index else { return }
        let update = indexUpdates
        guard let values = try? await index.propertyValues() else { return }
        if let kind = kinds.personKind {
            let ids = Set((try? await index.notes(matching: NoteQuery([.property(kinds.property, .equals(kind.name))]))) ?? [])
            personNotes = notes.filter { ids.contains($0.id) }.map(\.title)
        } else {
            personNotes = []
        }
        propertyValues = values
        propertyValuesUpdate = update
    }

    /// A property's values, each once whatever its case, most used first.
    func propertyValueList(_ key: String) -> [String] {
        var seen = Set<String>()
        return (propertyValues[key.lowercased()] ?? []).map(\.value).filter { seen.insert($0.lowercased()).inserted }
    }

    /// The notes that are lists, for Lists and to mark them in lists of notes.
    @Published private(set) var listNoteIDs: Set<Note.ID> = []
    private var listsUpdate = -1

    func loadLists() async {
        guard listsUpdate != indexUpdates, let index else { return }
        let update = indexUpdates
        guard let ids = try? await index.listNotes() else { return }
        let found = Set(ids)
        if found != listNoteIDs { listNoteIDs = found }
        listsUpdate = update
    }

    /// The titles of notes of the person kind (`type: Person`), read with the property values.
    private var personNotes: [String] = []

    /// People, by their notes' titles: notes of the person kind, notes in the people folder,
    /// and whoever's linked in a property of the person kind, most linked first.
    var people: [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for title in personNotes { counts[title.lowercased()] = (title, 0) }
        if let folder = pointTypes.peopleFolder(among: folders.filter { !$0.contains("/") }) {
            for note in notes where FolderTree.folder(of: note.id) == folder || note.id.hasPrefix(folder + "/") {
                counts[note.title.lowercased()] = (note.title, 0)
            }
        }
        for key in pointTypes.properties.filter({ $0.value.type == .person }).map({ $0.key.lowercased() }) {
            for entry in propertyValues[key] ?? [] {
                guard let name = PropertyLinks.linkedName(entry.value) else { continue }
                let existing = counts[name.lowercased()]
                counts[name.lowercased()] = (existing?.name ?? name, (existing?.count ?? 0) + entry.count)
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.name)
    }

    /// People whose names have a word starting with what's typed (the most linked, with nothing
    /// typed), less those already given.
    func peopleSuggestions(for typed: String, excluding: [String] = [], limit: Int = 8) -> [String] {
        let query = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]@ "))
        let taken = Set(excluding.map { (PropertyLinks.linkedName($0) ?? $0).lowercased() })
        return Array(people.filter { name in
            !taken.contains(name.lowercased())
                && (query.isEmpty || name.lowercased().hasPrefix(query) || name.lowercased().split(separator: " ").contains { $0.hasPrefix(query) })
        }.prefix(limit))
    }

    /// Notes to link to from a property of the link-to-note kind: those in its folder (any, if
    /// none) whose titles fit what's typed.
    func noteSuggestions(inFolder folder: String?, typed: String, limit: Int = 8) -> [String] {
        let query = typed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return Array(notes.lazy.filter { note in
            (folder == nil || FolderTree.folder(of: note.id) == folder || note.id.hasPrefix(folder! + "/"))
                && (query.isEmpty || note.title.lowercased().contains(query))
        }.map(\.title).prefix(limit))
    }

    // MARK: New notes

    private var isLaunched = false

    /// New notes not yet named: each takes its name from its first line when it's left, or
    /// goes if it's still empty. Kept across launches, for a note open when the app stopped.
    private var untitled: Set<Note.ID> {
        get { Set(UserDefaults.standard.stringArray(forKey: PhoneVault.defaultsKey("untitled")) ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: PhoneVault.defaultsKey("untitled"))
            startingTexts = startingTexts.filter { newValue.contains($0.key) }
            untitledMade = untitledMade.filter { newValue.contains($0.key) }
        }
    }

    /// When each new note not yet named was made here: a note at its path made at another time
    /// is another device's (both once named their first note of the day alike), and is left be.
    private var untitledMade: [Note.ID: Double] {
        get { UserDefaults.standard.dictionary(forKey: PhoneVault.defaultsKey("untitledMade")) as? [Note.ID: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: PhoneVault.defaultsKey("untitledMade")) }
    }

    /// What new notes not yet named started with, if not nothing (a tag): left as it was, a
    /// note goes just as an empty one does.
    private var startingTexts: [Note.ID: String] {
        get { UserDefaults.standard.dictionary(forKey: PhoneVault.defaultsKey("untitledStarts")) as? [Note.ID: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: PhoneVault.defaultsKey("untitledStarts")) }
    }

    func isUntitled(_ id: Note.ID) -> Bool { untitled.contains(id) }

    /// A new note in `folder` ("" for the vault's top level), starting with `text`, to be named
    /// from its first line; or, given a title, named from that at once (a clip).
    func createNote(in folder: String = "", text: String = "", titled title: String? = nil) -> Note.ID? {
        do {
            // Named for its day, `2026-11-06-untitled.md`, until it's left and named from its first line.
            let url = try NoteFiles.createDated(title: title, text: text, in: url(ofFolder: folder))
            let name = url.deletingPathExtension().lastPathComponent
            let note = Note(id: id(of: url, in: folder), url: url, title: title ?? NoteNames.fallbackTitle(for: name),
                            modified: Date(), created: Date(), isDownloaded: true)
            notes.append(note)
            guard title == nil else { return note.id }
            untitled.insert(note.id)
            untitledMade[note.id] = note.created.timeIntervalSince1970
            if !text.isEmpty { startingTexts[note.id] = text }
            return note.id
        } catch {
            PhoneVault.log("couldn't create a note: \(error.localizedDescription)")
            return nil
        }
    }

    /// Names a new note from its first line, or removes it if it's empty or as it started, once
    /// it's been left (and saved). Only a note read back that way is removed; if it can't be
    /// read, renamed or removed, it stays as it is, to try again next time.
    func finishUntitled(_ id: Note.ID) {
        guard untitled.contains(id) else { return }
        guard let note = note(id) ?? (FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
            ? Note(id: id, url: root.appendingPathComponent(id), title: (id as NSString).deletingPathExtension, modified: Date(), created: Date(), isDownloaded: true)
            : nil) else {
            untitled.remove(id) // Gone already.
            return
        }
        // Only a note made here: not another device's under the same name, nor one from before
        // this was known (its file is left as it is, to remove by hand if it's empty).
        guard let made = untitledMade[id], abs(note.created.timeIntervalSince1970 - made) < 120 else {
            untitled.remove(id)
            return
        }
        guard let text = try? NoteReader.read(contentsOf: note.url) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == startingTexts[id] {
            guard (try? FileManager.default.removeItem(at: note.url)) != nil else { return }
            untitled.remove(id)
            notes.removeAll { $0.id == id }
            return
        }
        untitled.remove(id)
        // Kept under its untitled name if it can't be named now, to name next time.
        func keep() {
            untitled.insert(id)
            untitledMade[id] = made
        }
        guard let line = PlainText.firstLine(of: text) else { return }
        if NoteNames.isDated(note.name) {
            // A note Point named: its title is the line as written, and its name follows.
            if (try? retitle(note, to: line, text: text)) == nil { keep() }
            return
        }
        let title = NoteFiles.sanitizedTitle(line)
        guard !title.isEmpty, title != note.title else { return }
        let available = NoteFiles.availableURL(for: title, in: note.url.deletingLastPathComponent())
        guard let url = try? NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent) else {
            keep()
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
        if NoteNames.isDated(note.name) {
            untitled.remove(id)
            return try retitle(note, to: title, text: NoteReader.read(contentsOf: note.url))
        }
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

    /// Gives a note Point named a new title, as on the Mac: its `title:` is set, its file is
    /// renamed to match (keeping its day), and links to it follow, with any label that was its
    /// old title. Throws if the note changed meanwhile or can't be written.
    @discardableResult
    private func retitle(_ note: Note, to newTitle: String, text: String) throws -> Note {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !title.isEmpty else { throw NoteFiles.FileError.emptyTitle }
        guard title != note.title || NoteNames.title(in: text) == nil else { return note }
        let retitled = NoteNames.settingTitle(title, in: text)
        guard case .saved = try NoteWriter.write(retitled, to: note.url, expecting: text, ifChanged: .report, keepingDate: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let vault = notes
        var url = note.url
        if let name = NoteNames.renamed(note.name, to: title), name != note.name {
            let available = NoteFiles.availableDatedURL(for: name, in: note.url.deletingLastPathComponent(), excluding: note.url)
            // If it can't be renamed, the title's still set; links to its old name still work.
            url = (try? NoteFiles.rename(note.url, to: available.deletingPathExtension().lastPathComponent)) ?? note.url
        }
        let renamed = moved(note, to: url, title: title)
        let newName = renamed.name, oldTitle = note.title
        Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(to: note, newTitle: newName, notes: vault, retitling: (oldTitle, title))
            if !result.updatedNotes.isEmpty { PhoneVault.log("updated links in \(result.updatedNotes.count) notes") }
            await self.reload()
        }
        return renamed
    }

    /// Moves a note into a folder ("" for the vault's top level), as on the Mac: its bookmarks
    /// follow, and links to it are updated behind it, by the time `links` is done. Throws if the
    /// file can't be moved (the note's left as it was).
    func move(_ id: Note.ID, toFolder folder: String) throws -> (note: Note, links: Task<Void, Never>) {
        guard let note = note(id) else { throw CocoaError(.fileNoSuchFile) }
        let vault = notes, root = root
        let url = try NoteFiles.move(note.url, toFolder: url(ofFolder: folder))
        let moved = moved(note, to: url, in: folder)
        let newID = moved.id
        let links = Task.detached(priority: .userInitiated) {
            let result = LinkUpdater.updateLinks(afterMoving: note, to: newID, notes: vault, root: root)
            if !result.updatedNotes.isEmpty { PhoneVault.log("updated links in \(result.updatedNotes.count) notes") }
            await self.reload()
        }
        return (moved, links)
    }

    /// Moves a note to the vault's trash, as the Mac does: Deleted Notes, where it can be put
    /// back, here or on the Mac (or in Obsidian). What it was known by (opened, worked on, its
    /// bookmark) goes with it.
    func moveToTrash(_ id: Note.ID) {
        guard let note = note(id) else { return }
        do {
            let name = try VaultTrash.move(note.url, vault: root)
            trashRecords[name] = VaultTrash.Record(deleted: Date(), folder: FolderTree.folder(of: note.id), deletedByPoint: true)
            refreshTrash()
        } catch {
            trashProblem = "“\(note.title)” is still in your notes (\(error.localizedDescription))."
            return
        }
        untitled.remove(id)
        notes.removeAll { $0.id == id }
        history.keepOnly(Set(notes.map(\.id)))
        historyFile.save(history)
        if UserDefaults.standard.string(forKey: PhoneVault.defaultsKey("workingOn")) == id { stopWorking() }
        if isBookmarked(id) {
            try? ObsidianBookmarks.remove(id, vault: root)
            bookmarks = ObsidianBookmarks.load(vault: root)
        }
        Task { await reload() }
    }

    /// Why a note couldn't be deleted, for home to say: its own screen has gone by then.
    @Published var trashProblem: String?

    // MARK: Deleted notes

    /// The notes in the vault's trash, newest first.
    @Published private(set) var deletedNotes: [VaultTrash.Item] = []
    /// Why a deleted note couldn't be put back or deleted for good.
    @Published var deletedNotesProblem: String?
    /// How long the notes Point deletes are kept, as on the Mac by default.
    static let keepsDeletedNotesDays = 30

    /// When each note in the trash was deleted, and where from, by its name there: in the
    /// vault for those Point deleted, so the Mac puts them back where they were too.
    private var trashRecords: [String: VaultTrash.Record] {
        get { trashBook.all }
        set {
            do {
                try trashBook.set(newValue)
            } catch {
                PhoneVault.log("couldn't keep the trash's records: \(error.localizedDescription)")
            }
        }
    }

    private var trashBook: TrashRecords {
        let key = PhoneVault.defaultsKey("trashRecords")
        return TrashRecords(root: root, loadLocal: { UserDefaults.standard.data(forKey: key) },
                            saveLocal: { UserDefaults.standard.set($0, forKey: key) })
    }

    /// Lists the trash, removing for good the notes Point deleted more than 30 days ago, as the
    /// Mac does. Notes found there (put there by Obsidian, say) stay until it's emptied.
    func refreshTrash() {
        trashBook.shareOwn()
        var records = trashRecords
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(Self.keepsDeletedNotesDays) * 86_400)
        let all = VaultTrash.items(in: root, records: records, now: now)
        var expired: Set<String> = []
        for item in VaultTrash.expired(all, before: cutoff) {
            do {
                try VaultTrash.delete(item)
                expired.insert(item.name)
            } catch {
                PhoneVault.log("couldn't remove \(item.name) from the trash: \(error.localizedDescription)")
            }
        }
        let items = all.filter { !expired.contains($0.name) }
        for item in items where records[item.name] == nil {
            records[item.name] = VaultTrash.Record(deleted: now, folder: item.folder ?? "", deletedByPoint: false)
        }
        // Forget notes no longer there (emptied or put back elsewhere): those deleted on another
        // device in the last week once they've had time to arrive.
        let names = Set(items.map(\.name))
        records = records.filter { names.contains($0.key) || ($0.value.deletedByPoint && $0.value.deleted > now.addingTimeInterval(-7 * 86_400)) }
        if records != trashRecords { trashRecords = records }
        if items != deletedNotes { deletedNotes = items }
    }

    /// Puts a note back where it was (or at the top level, if its folder is gone).
    func restore(_ item: VaultTrash.Item) {
        do {
            _ = try VaultTrash.restore(item, vault: root)
            trashRecords[item.name] = nil
            refreshTrash()
            Task { await reload() }
        } catch {
            deletedNotesProblem = "“\(item.title)” couldn’t be put back (\(error.localizedDescription))."
        }
    }

    func deleteForever(_ item: VaultTrash.Item) {
        do {
            try VaultTrash.delete(item)
        } catch {
            deletedNotesProblem = "“\(item.title)” couldn’t be deleted (\(error.localizedDescription))."
        }
        refreshTrash()
    }

    func deleteAllForever() {
        var failed: [String] = []
        for item in deletedNotes {
            do { try VaultTrash.delete(item) } catch { failed.append(item.title) }
        }
        refreshTrash()
        if !failed.isEmpty {
            deletedNotesProblem = failed.count == 1 ? "“\(failed[0])” couldn’t be deleted." : "\(failed.count) notes couldn’t be deleted."
        }
    }

    /// Notes gone in the last read and not yet found renamed or moved, and those that appeared
    /// in it and weren't one of them.
    private var vanishedBefore: [Note] = []
    private var appearedBefore: [Note] = []

    /// Whether a note that's gone and one that's appeared are the same, renamed or moved on
    /// another device: the same name in another folder, or another name in the same folder
    /// made at the same moment (a rename keeps when a file was made).
    static func isSameNote(_ gone: Note, _ new: Note) -> Bool {
        let goneFolder = FolderTree.folder(of: gone.id)
        let newFolder = FolderTree.folder(of: new.id)
        if gone.url.lastPathComponent == new.url.lastPathComponent { return goneFolder != newFolder }
        return goneFolder == newFolder && abs(gone.created.timeIntervalSince(new.created)) < 1
    }

    /// A note renamed or moved on another device: what it was known by follows it, as for a
    /// rename here (the list already has it, from the scan; bookmarks, from the Mac).
    func noteMovedElsewhere(from id: Note.ID, to note: Note) {
        guard id != note.id else { return }
        renamedIDs[id] = note.id
        if untitled.contains(id) {
            let start = startingTexts[id]
            let made = untitledMade[id]
            untitled.remove(id)
            untitled.insert(note.id)
            startingTexts[note.id] = start
            untitledMade[note.id] = made
        }
        history.renamed(from: id, to: note.id)
        historyFile.save(history)
        if UserDefaults.standard.string(forKey: PhoneVault.defaultsKey("workingOn")) == id {
            UserDefaults.standard.set(note.id, forKey: PhoneVault.defaultsKey("workingOn"))
        }
    }

    /// A note's file renamed: the list, and what it was known by (opened, worked on, its
    /// bookmarks), follow it.
    @discardableResult
    private func moved(_ note: Note, to url: URL, in folder: String? = nil, title: String? = nil) -> Note {
        let newID = id(of: url, in: folder ?? (note.id as NSString).deletingLastPathComponent)
        let name = url.deletingPathExtension().lastPathComponent
        let shown = title ?? NoteNames.shownTitle(name: name, url: url)
        let renamed = Note(id: newID, url: url, title: shown,
                           modified: note.modified, created: note.created, isDownloaded: true)
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = renamed }
        renamedIDs[note.id] = newID
        if untitled.contains(note.id) {
            let start = startingTexts[note.id]
            let made = untitledMade[note.id]
            untitled.remove(note.id)
            untitled.insert(newID)
            startingTexts[newID] = start
            untitledMade[newID] = made
        }
        history.renamed(from: note.id, to: newID)
        historyFile.save(history)
        if UserDefaults.standard.string(forKey: PhoneVault.defaultsKey("workingOn")) == note.id { UserDefaults.standard.set(newID, forKey: PhoneVault.defaultsKey("workingOn")) }
        if isBookmarked(note.id) {
            try? ObsidianBookmarks.rename(note.id, to: newID, vault: root)
            bookmarks = ObsidianBookmarks.load(vault: root)
        }
        return renamed
    }

    // MARK: Folders and tags

    /// Where a folder is ("" for the vault's top level).
    private func url(ofFolder folder: String) -> URL {
        folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
    }

    /// The ID of the note at `url`, in `folder`.
    private func id(of url: URL, in folder: String) -> Note.ID {
        folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
    }

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

    /// Moves a folder, with everything in it, into another ("" for the vault's top level), as on
    /// the Mac, and returns its new path. Links by name, as Obsidian makes them, keep working;
    /// links written as paths aren't rewritten. Throws with a message to show if it can't move.
    func moveFolder(_ path: String, into parent: String) throws -> String {
        let prefix = path + "/"
        let moving = notes.filter { $0.id.hasPrefix(prefix) }
        let url = try NoteFiles.moveFolder(url(ofFolder: path), into: url(ofFolder: parent))
        let newPath = parent.isEmpty ? url.lastPathComponent : parent + "/" + url.lastPathComponent
        for note in moving {
            let inside = note.id.dropFirst(prefix.count)
            let folder = ((newPath + "/" + inside) as NSString).deletingLastPathComponent
            moved(note, to: root.appendingPathComponent(newPath + "/" + inside), in: folder)
        }
        // Favourites follow it, and anything inside it.
        favourites = favourites.map { favourite in
            guard case .folder(let folder) = favourite, folder == path || folder.hasPrefix(prefix) else { return favourite }
            return .folder(newPath + folder.dropFirst(path.count))
        }
        Task { await reload() }
        return newPath
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

    /// `folders` in the chosen order: as given (by name), or by the newest note inside each.
    func sorted(folders: [String]) -> [String] {
        guard sort != .title else { return folders }
        var newest: [String: Date] = [:]
        for note in notes {
            var folder = FolderTree.folder(of: note.id)
            while !folder.isEmpty {
                newest[folder] = max(newest[folder] ?? .distantPast, sortDate(note))
                folder = FolderTree.parent(of: folder)
            }
        }
        return folders.sorted { (newest[$0] ?? .distantPast) > (newest[$1] ?? .distantPast) }
    }

    /// `tags` in the chosen order: as given (by name), or by the newest note with each, with
    /// nested tags still under their parents.
    func sorted(tags: [(tag: String, count: Int)]) -> [(tag: String, count: Int)] {
        guard sort != .title else { return tags }
        var newest: [String: Date] = [:]
        for note in notes {
            for tag in tagsByNote[note.id] ?? [] {
                let parts = tag.split(separator: "/").map(String.init)
                for depth in 1...max(parts.count, 1) {
                    let tag = parts.prefix(depth).joined(separator: "/")
                    newest[tag] = max(newest[tag] ?? .distantPast, sortDate(note))
                }
            }
        }
        let nested = Dictionary(grouping: tags) { ($0.tag as NSString).deletingLastPathComponent }
        func walk(_ parent: String) -> [(tag: String, count: Int)] {
            (nested[parent] ?? [])
                .sorted { (newest[$0.tag] ?? .distantPast) > (newest[$1.tag] ?? .distantPast) }
                .flatMap { [$0] + walk($0.tag) }
        }
        return walk("")
    }

    private func sortDate(_ note: Note) -> Date { sort == .created ? note.created : note.modified }

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

    /// What search learns on this phone: which notes are opened, and which are picked for
    /// what's typed (`SearchHistory`). Kept in the app's own storage, never in the vault.
    private(set) var history = SearchHistory()
    private let historyFile = SearchHistory.File(url: PhoneVault.storage("History/vault.json"))
    /// A note just picked from search, whose screen appearing isn't another open.
    private var pickedID: Note.ID?

    /// What search had learned before: when each note was last opened, kept in the defaults.
    private static func loadHistory(from file: SearchHistory.File) -> SearchHistory {
        // Only Point's own folder had it: a chosen vault starts afresh.
        guard PhoneVault.isOwnFolder, !FileManager.default.fileExists(atPath: file.url.path),
              let data = UserDefaults.standard.data(forKey: "opened"),
              let opened = try? JSONDecoder().decode([Note.ID: Date].self, from: data) else { return file.load() }
        var history = SearchHistory()
        for (id, date) in opened.sorted(by: { $0.value < $1.value }) { history.opened(id, at: date) }
        file.save(history)
        UserDefaults.standard.removeObject(forKey: "opened")
        return history
    }

    func noteOpened(_ id: Note.ID) {
        if pickedID == id {
            pickedID = nil
            return
        }
        history.opened(id)
        historyChanged()
    }

    /// A search result chosen after typing `query`.
    func resultPicked(_ id: Note.ID, for query: String) {
        history.picked(id, for: query)
        pickedID = id
        // Only for the screen that opens now: the note may have been showing already.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.pickedID == id { self?.pickedID = nil }
        }
        historyChanged()
    }

    func forgetSearchHistory() {
        history.forget()
        historyChanged()
    }

    private func historyChanged() {
        historyFile.save(history)
        objectWillChange.send()
    }

    /// Every note, the most recently edited (anywhere) or opened (here) first.
    var recent: [Note] {
        notes.sorted { lastTouched($0) > lastTouched($1) }
    }

    /// The notes last opened on this phone, for switching between them, newest first.
    func recentlyOpened(limit: Int, excluding excluded: Note.ID?) -> [Note] {
        let ids = history.recentlyOpened.filter { $0 != excluded }
        return Array(ids.lazy.compactMap { self.note($0) }.prefix(limit))
    }

    /// What was searched for on this phone, newest first, for Search to offer before typing.
    func recentSearches(limit: Int) -> [String] { history.recentQueries(limit: limit) }

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
    private func lastTouched(_ note: Note) -> Date { max(note.modified, history.lastOpened(note.id) ?? .distantPast) }

    // MARK: The note being worked on

    /// Notes the note last edited on this phone, and when.
    func noteEdited(_ id: Note.ID) {
        UserDefaults.standard.set(id, forKey: PhoneVault.defaultsKey("workingOn"))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PhoneVault.defaultsKey("workingOnDate"))
    }

    /// The note being worked on: the one last edited here, if that was today.
    var workingOn: (note: Note, edited: Date)? {
        let date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: PhoneVault.defaultsKey("workingOnDate")))
        guard Calendar.current.isDateInToday(date), let id = UserDefaults.standard.string(forKey: PhoneVault.defaultsKey("workingOn")),
              let note = note(id) else { return nil }
        return (note, date)
    }

    /// Where the cursor was in the note being worked on, kept for coming back to it.
    func noteCursor(_ location: Int) { UserDefaults.standard.set(location, forKey: PhoneVault.defaultsKey("workingOnCursor")) }

    /// Going home, or to another note: the app no longer comes back to this one.
    func stopWorking() { UserDefaults.standard.removeObject(forKey: PhoneVault.defaultsKey("workingOn")) }

    /// Coming back into the note being worked on, at launch: its ID, its cursor kept for
    /// `resumeCursor(for:)`.
    func resumeWorking() -> Note.ID? {
        guard let id = workingOn?.note.id else { return nil }
        resuming = (id, UserDefaults.standard.integer(forKey: PhoneVault.defaultsKey("workingOnCursor")))
        return id
    }

    private var resuming: (id: Note.ID, cursor: Int)?

    /// Where to put the cursor in a note being opened, if it's being come back to.
    func resumeCursor(for id: Note.ID) -> Int? {
        guard let resuming, resuming.id == id else { return nil }
        self.resuming = nil
        return resuming.cursor
    }

    // MARK: Bookmarks

    func isBookmarked(_ id: Note.ID) -> Bool { bookmarks.contains { $0.path == id } }

    func toggleBookmark(_ id: Note.ID) {
        UISelectionFeedbackGenerator().selectionChanged()
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

    // MARK: Favourites

    func isFavourite(_ favourite: Favourite) -> Bool { favourites.contains(favourite) }

    /// Adds it to the end of Favourites, or takes it off.
    func toggleFavourite(_ favourite: Favourite) {
        UISelectionFeedbackGenerator().selectionChanged()
        if let index = favourites.firstIndex(of: favourite) {
            favourites.remove(at: index)
        } else {
            favourites.append(favourite)
        }
    }

    /// Favourites in the order shown (`shown`, those whose folder or tag is still there),
    /// with the rest after, in case they come back.
    func reorderFavourites(_ shown: [Favourite]) {
        favourites = shown + favourites.filter { !shown.contains($0) }
    }
}

/// A folder or a tag on home's Favourites.
enum Favourite: Hashable, Codable {
    case folder(String)
    case tag(String)

    var route: Route {
        switch self {
        case .folder(let folder): .folder(folder)
        case .tag(let tag): .tag(tag)
        }
    }
}

/// Search: what's typed in the search field, and the results, which follow as it changes. An
/// object of its own, not part of the store: as the store's, every keystroke, and Search opening,
/// redrew every page showing the vault, home under Search among them.
@MainActor
final class PhoneSearch: ObservableObject {
    @Published var text = "" {
        didSet { if text != oldValue { searchAgain() } }
    }
    /// Results for `text`, or nil when not searching.
    @Published private(set) var results: [SearchResult]?
    /// Searches the vault (nil if it can't).
    var find: ((String) async -> [SearchResult]?)?
    /// Whether Search is up.
    @Published var isShown = false
    /// The app's window's width, for the bar's search field.
    @Published var windowWidth: CGFloat = 0
    /// Where the bar's search field was when Search opened, in the window, for Search's field
    /// to open out from (nil when Search opened from elsewhere).
    private(set) var from: CGRect?
    private var task: Task<Void, Never>?

    /// Opens Search, from the bar's field at `frame`, or from nowhere in particular.
    func present(from frame: CGRect?) {
        guard !isShown else { return }
        from = frame.flatMap { $0.isEmpty ? nil : $0 }
        isShown = true
    }

    /// Searches for what's typed, if anything, after a pause in typing.
    func searchAgain() {
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            if results != nil { results = nil }
            return
        }
        guard let find else { return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // Waits for a pause in typing.
            guard !Task.isCancelled, let results = await find(query), !Task.isCancelled else { return }
            self?.results = results
        }
    }
}

/// Links written in properties, as Obsidian writes them (`[[Sam Lee]]`, `[[Sam Lee|Sam]]`).
enum PropertyLinks {
    /// The note a value links to, if it's just one wikilink (`[[Sam Lee]]` gives "Sam Lee").
    static func linkedName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return nil }
        let inside = trimmed.dropFirst(2).dropLast(2)
        guard !inside.contains("[["), !inside.contains("]]") else { return nil }
        return inside.split(separator: "|", maxSplits: 1).first.map(String.init)
    }

    /// A name as a link: `Sam Lee` gives `[[Sam Lee]]`; a link stays as it is.
    static func linked(_ value: String) -> String {
        linkedName(value) == nil ? "[[\(value)]]" : value
    }
}


// MARK: Clipping

/// How a clip is going, shown over home and the note: working, then done (for a moment).
struct ClipStatus: Equatable {
    var text: String
    var symbol: String
    var isWorking = false
}

extension PhoneStore {
    /// Clips a page into the vault and opens it, as on the Mac: its article as a note of the
    /// clip kind (in that kind's folder, from its template), or a note with a link if the
    /// article can't be read. A page clipped before opens its note again.
    func clip(_ request: ClipRequest) {
        Task { @MainActor in
            // Opened by the link, Point may still be reading the vault.
            for _ in 0..<150 where !isReady { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard isReady else { return }
            if let existing = await clippedNote(of: request.url) {
                linkedRoute = .note(existing)
                show(ClipStatus(text: "Clipped before", symbol: "doc.on.doc"))
                return
            }
            let shownTitle = request.title ?? request.url.host ?? "the page"
            clipStatus = ClipStatus(text: "Clipping “\(shownTitle)”…", symbol: "scissors", isWorking: true)
            let (clip, couldRead) = await Clipping.read(request)
            // A redirect may lead to a page clipped before.
            if let existing = await clippedNote(of: clip.url) {
                linkedRoute = .note(existing)
                show(ClipStatus(text: "Clipped before", symbol: "doc.on.doc"))
                return
            }
            let kind = Clipping.kind(in: kinds)
            let folder = kind?.folder ?? Clipping.defaultFolder
            let template = kind.flatMap { templates(of: $0).first?.url }.flatMap { try? NoteReader.read(contentsOf: $0) }
            let (title, text) = Clipping.note(for: clip, request: request, kind: kind, template: template,
                                              typeProperty: kinds.property, settings: settings)
            try? FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            guard let id = createNote(in: folder, text: text, titled: title.isEmpty ? nil : title) else {
                show(ClipStatus(text: "Couldn’t make the note", symbol: "exclamationmark.triangle"))
                return
            }
            linkedRoute = .note(id)
            show(couldRead ? ClipStatus(text: "Clipped to \(folder)", symbol: "checkmark.circle")
                 : ClipStatus(text: "Couldn’t read the page, so the note has its link", symbol: "exclamationmark.triangle"))
        }
    }

    /// Clips the link copied last, if there is one: for pages shared by copying their link.
    /// (Reading the clipboard asks permission, the first time.)
    func clipCopiedLink() {
        let pasteboard = UIPasteboard.general
        // Whether there's text or a link asks no permission; reading it brings up iOS's
        // "Allow paste" prompt, so only read when there's something to read.
        guard pasteboard.hasURLs || pasteboard.hasStrings,
              let url = pasteboard.url ?? pasteboard.string.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            show(ClipStatus(text: "No link copied", symbol: "link"))
            return
        }
        clip(ClipRequest(url: url))
    }

    /// Shows how it went, for a few seconds.
    private func show(_ status: ClipStatus) {
        clipStatus = status
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if clipStatus == status { clipStatus = nil }
        }
    }

    /// The note already clipped from this page, if any: its `source` is the address.
    private func clippedNote(of url: URL) async -> Note.ID? {
        for address in Clipping.sources(of: url) {
            if let id = await notes(withSource: address) { return id }
        }
        return nil
    }
}
