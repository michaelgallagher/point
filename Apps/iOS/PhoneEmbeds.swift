import EditorKit
import IndexKit
import MarkdownKit
import SwiftUI
import VaultKit

extension Notification.Name {
    /// What notes embed has changed (an image arrived, a list found more or fewer notes): open
    /// notes restyle, so the room made for them fits.
    static let phoneEmbedsChanged = Notification.Name("phoneEmbedsChanged")
}

/// What notes show of other files on the phone, as on the Mac: the vault's images and web
/// images (kept in the cache), and lists, in the list note itself and embedded in others.
@MainActor
final class PhoneEmbeds: ObservableObject {
    weak var store: PhoneStore?

    /// The vault's images, wherever they are, as the scan found them.
    var images: [VaultImage] = [] {
        didSet {
            let byName = VaultImages.byName(images)
            let changed = Set(byName.keys) != Set(imagesByName.keys)
            imagesByName = byName
            if changed { changedSoon() }
        }
    }
    private var imagesByName: [String: VaultImage] = [:]

    // MARK: Images

    /// Where the image an embed in a note names is, if it's here: in the vault (downloaded from
    /// iCloud), or a web image already kept. One that isn't yet is fetched, and notes restyle
    /// when it arrives.
    func imageURL(for target: String, from noteID: Note.ID) -> URL? {
        if WebImageCache.isWeb(target) { return webImageURL(target) }
        guard let root = store?.root, let image = VaultImages.resolve(target, from: noteID, images: imagesByName, root: root) else { return nil }
        guard image.isDownloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: image.url)
            return nil
        }
        return image.url
    }

    private var webImagesLoading: Set<URL> = []
    private var webImagesFailed: Set<URL> = []

    private func webImageURL(_ target: String) -> URL? {
        guard let address = URL(string: target) ?? target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init) else { return nil }
        let cache = WebImageCache.standard
        if let file = cache.cached(address) { return file }
        guard !webImagesLoading.contains(address), !webImagesFailed.contains(address) else { return nil }
        webImagesLoading.insert(address)
        Task {
            do {
                _ = try await cache.load(address)
                changedSoon()
            } catch {
                webImagesFailed.insert(address)
            }
            webImagesLoading.remove(address)
        }
        return nil
    }

    /// The image being looked at, full screen, after a tap on it in a note.
    @Published var shownImage: URL?

    // MARK: Lists

    /// What each note read as a list is (nil: not one), as of its file's date.
    private var listsRead: [Note.ID: (modified: Date, list: ListDefinition?)] = [:]
    private var readingLists: Set<Note.ID> = []
    /// What each query last found, and as of which index update.
    private var queryResults: [NoteQuery: (update: Int, ids: [Note.ID])] = [:]
    private var runningQueries: Set<NoteQuery> = []
    /// The queries of lists embedded in notes, whose room changes with what they find.
    private var embeddedQueries: Set<NoteQuery> = []

    /// The list a note is, if it is one: read off the main thread, notes restyling once it's known.
    func listDefinition(of id: Note.ID) -> ListDefinition? {
        guard let note = store?.note(id) else { return nil }
        let read = listsRead[id]
        if read?.modified != note.modified, readingLists.insert(id).inserted {
            let url = note.url, modified = note.modified
            Task {
                let list = await Task.detached(priority: .userInitiated) {
                    (try? NoteReader.read(contentsOf: url)).flatMap { ListDefinition(frontmatter: Frontmatter.parse($0)) }
                }.value
                readingLists.remove(id)
                let changed = listsRead[id]?.list != list
                listsRead[id] = (modified, list)
                if changed { changedSoon() }
            }
        }
        return read?.list
    }

    /// The notes a query finds, in its order: what it last found at once (nil the first time),
    /// asked again in the background when the index has changed since. Never waits on the index.
    func noteIDs(matching query: NoteQuery) -> [Note.ID]? {
        guard let store else { return nil }
        let cached = queryResults[query]
        let update = store.indexUpdates
        if cached?.update != update, let index = store.searchIndex, runningQueries.insert(query).inserted {
            Task {
                let ids = try? await index.notes(matching: query)
                runningQueries.remove(query)
                guard let ids else { return }
                let before = queryResults[query]?.ids
                queryResults[query] = (update, ids)
                guard before != ids else { return }
                objectWillChange.send()
                if embeddedQueries.contains(query), before.map(PhoneListView.embedRows) != PhoneListView.embedRows(ids) { changedSoon() }
            }
        }
        return cached?.ids
    }

    /// Some properties' values for some notes, from the index, by note, then by property name
    /// in lowercase.
    func propertyValues(_ names: [String], of ids: [Note.ID]) async -> [Note.ID: [String: [String]]] {
        guard let index = store?.searchIndex, !names.isEmpty, !ids.isEmpty else { return [:] }
        return (try? await index.propertyValues(names, of: ids)) ?? [:]
    }

    /// The list note an embed names, if it's a list (and not the note itself).
    func embeddedList(_ target: String, from sourceID: Note.ID) -> (id: Note.ID, list: ListDefinition)? {
        guard let notes = store?.notes,
              let note = LinkResolver(notes: notes).resolve(wikiTarget: target, from: sourceID), note.id != sourceID,
              let list = listDefinition(of: note.id) else { return nil }
        return (note.id, list)
    }

    /// How tall the block drawn for `![[target]]` is, if it's a list: nil until that's known.
    func listEmbedHeight(_ target: String, from sourceID: Note.ID) -> CGFloat? {
        guard let (_, list) = embeddedList(target, from: sourceID) else { return nil }
        embeddedQueries.insert(list.query)
        guard let ids = noteIDs(matching: list.query) else { return nil }
        return PhoneListView.height(count: ids.count, limit: PhoneListView.embedLimit, hasDetails: !list.columns.isEmpty)
    }

    // MARK: Telling notes

    private var isQueued = false

    /// Restyles open notes, once, soon.
    func changedSoon() {
        guard !isQueued else { return }
        isQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isQueued = false
            NotificationCenter.default.post(name: .phoneEmbedsChanged, object: nil)
        }
    }
}

/// A list's notes on the phone: how many, then a row for each, its title and (if the list
/// shows columns) their values on a line under it, tapped to open. Rows are one height, so the
/// room for a list embedded in a note is known before it's drawn.
struct PhoneListView: View {
    @ObservedObject var embeds: PhoneEmbeds
    let list: ListDefinition
    /// How many rows show, and what the rest are.
    let limit: Int
    /// Opens a note; with nil, the list's own note (from "Show all").
    let open: (Note.ID?) -> Void
    /// Says how tall it is, as what it finds changes.
    var onHeight: ((CGFloat) -> Void)?
    @State private var values: [Note.ID: [String: [String]]] = [:]

    static let embedLimit = 10
    static let countHeight: CGFloat = 26, rowHeight: CGFloat = 44, detailedRowHeight: CGFloat = 60, moreHeight: CGFloat = 40

    /// How many rows an embed shows of `ids`, and whether there are more.
    static func embedRows(_ ids: [Note.ID]) -> Int { min(ids.count, embedLimit + 1) }

    static func height(count: Int, limit: Int, hasDetails: Bool) -> CGFloat {
        let rows = min(count, limit)
        return countHeight + CGFloat(rows) * (hasDetails ? detailedRowHeight : rowHeight) + (count > limit ? moreHeight : 0)
    }

    var body: some View {
        let ids = embeds.noteIDs(matching: list.query)
        let shown = Array((ids ?? []).prefix(limit)).compactMap { embeds.store?.note($0) }
        VStack(alignment: .leading, spacing: 0) {
            Text(ids.map { $0.count == 1 ? "1 note" : "\($0.count) notes" } ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: Self.countHeight, alignment: .topLeading)
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, note in
                Button { open(note.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                        if !list.columns.isEmpty {
                            Text(details(of: note))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: list.columns.isEmpty ? Self.rowHeight : Self.detailedRowHeight)
                .overlay(alignment: .top) { if index > 0 { Divider() } }
            }
            if let ids, ids.count > limit {
                Button("Show all \(ids.count)") { open(nil) }
                    .font(.subheadline)
                    .frame(height: Self.moreHeight, alignment: .leading)
            }
        }
        .task(id: ValuesKey(columns: list.columns, ids: shown.map(\.id), update: embeds.store?.indexUpdates ?? 0)) {
            let names = list.columns.filter { ListDefinition.field(named: $0) == nil }
            values = await embeds.propertyValues(names, of: shown.map(\.id))
        }
        .onChange(of: ids?.count, initial: true) { _, count in
            onHeight?(Self.height(count: count ?? 0, limit: limit, hasDetails: !list.columns.isEmpty))
        }
    }

    private struct ValuesKey: Equatable {
        let columns: [String]
        let ids: [Note.ID]
        let update: Int
    }

    /// The columns' values, one after another: "Ursula K. Le Guin · 1969 · 10 Feb 2025".
    private func details(of note: Note) -> String {
        list.columns.map { column -> String in
            switch ListDefinition.field(named: column) {
            case .title: return note.title
            case .folder: return note.id.contains("/") ? (note.id as NSString).deletingLastPathComponent : "Vault root"
            case .created: return note.created.formatted(date: .abbreviated, time: .omitted)
            case .modified: return note.modified.formatted(date: .abbreviated, time: .omitted)
            case nil:
                return (values[note.id]?[column.lowercased()] ?? []).map { value in
                    if value.hasPrefix("[["), value.hasSuffix("]]") {
                        return String(value.dropFirst(2).dropLast(2).split(separator: "|").last ?? "")
                    }
                    // A day (2025-02-10) as the phone writes it; a year (1969) stays as it is.
                    guard value.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else { return value }
                    return PropertyDate.parse(value).map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? value
                }.joined(separator: ", ")
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}
