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
    /// The queries of lists embedded or written in notes, whose room changes with what they
    /// find, and the most rows any of them shows.
    private var embeddedQueries: [NoteQuery: Int] = [:]

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
                // Restyled only if the rows shown, or whether there are more, have changed.
                if let rows = embeddedQueries[query], before.map({ min($0.count, rows + 1) }) != min(ids.count, rows + 1) { changedSoon() }
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
        embeddedQueries[list.query] = max(embeddedQueries[list.query] ?? 0, PhoneListView.embedLimit)
        guard let ids = noteIDs(matching: list.query) else { return nil }
        return PhoneListView.height(count: ids.count, limit: PhoneListView.embedLimit, hasDetails: !list.columns.isEmpty)
    }

    /// How tall the block drawn for a `list` block in a note is, showing `rows` of what it
    /// finds: nil if the block doesn't read as a list, so it shows as code. Until what it finds
    /// is known, the room for none, so its lines don't show for a moment first.
    func listBlockHeight(_ body: String, rows: Int) -> CGFloat? {
        guard let list = ListDefinition(block: body) else { return nil }
        embeddedQueries[list.query] = max(embeddedQueries[list.query] ?? 0, rows)
        return PhoneListBlockView.height(count: noteIDs(matching: list.query)?.count ?? 0, rows: rows, hasDetails: !list.columns.isEmpty)
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
    /// Opens the list's filters, from a line at its top saying what it is ("In Reading ·
    /// format is Book · by published"), with a filter button at its end. Without it, no line.
    var edit: (() -> Void)?
    @State private var values: [Note.ID: [String: [String]]] = [:]

    static let embedLimit = 10
    static let summaryHeight: CGFloat = 34, countHeight: CGFloat = 26, rowHeight: CGFloat = 44, detailedRowHeight: CGFloat = 60, moreHeight: CGFloat = 40

    /// Unfolds it in place to show this many rows, rather than opening the list: a list written
    /// in a note, which has no note of its own to open. With it, "Show all" and "Show more"
    /// unfold, and "Show fewer" folds it to the first 10 again.
    var unfold: ((Int) -> Void)?
    static let unfoldStep = 50

    /// Whether it shows "Show fewer": unfolded, with more than the first 10 to fold away.
    static func canFold(count: Int, limit: Int) -> Bool { limit > embedLimit && count > embedLimit }

    static func height(count: Int, limit: Int, hasDetails: Bool, unfolds: Bool = false, edits: Bool = false) -> CGFloat {
        let rows = min(count, limit)
        let buttons = count > limit || unfolds && canFold(count: count, limit: limit)
        return (edits ? summaryHeight : 0) + countHeight + CGFloat(rows) * (hasDetails ? detailedRowHeight : rowHeight) + (buttons ? moreHeight : 0)
    }

    var body: some View {
        let ids = embeds.noteIDs(matching: list.query)
        let shown = Array((ids ?? []).prefix(limit)).compactMap { embeds.store?.note($0) }
        VStack(alignment: .leading, spacing: 0) {
            if let edit { summaryLine(edit) }
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
            if let ids, let unfold {
                if ids.count > limit || Self.canFold(count: ids.count, limit: limit) {
                    HStack(spacing: 20) {
                        if ids.count > limit {
                            Button(limit == Self.embedLimit ? "Show all \(ids.count)" : "Show more") {
                                unfold(limit == Self.embedLimit ? Self.unfoldStep : limit + Self.unfoldStep)
                            }
                        }
                        if Self.canFold(count: ids.count, limit: limit) {
                            Button("Show fewer") { unfold(Self.embedLimit) }
                        }
                    }
                    .font(.subheadline)
                    .frame(height: Self.moreHeight, alignment: .leading)
                }
            } else if let ids, ids.count > limit {
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
            onHeight?(Self.height(count: count ?? 0, limit: limit, hasDetails: !list.columns.isEmpty, edits: edit != nil))
        }
    }

    /// What the list is, in a line, cut short if it's long, and a filter button: a tap
    /// anywhere on it opens the filters.
    private func summaryLine(_ edit: @escaping () -> Void) -> some View {
        Button(action: edit) {
            HStack(spacing: 8) {
                Text(embeds.store?.listVocabulary.summary(of: list) ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: Self.summaryHeight, alignment: .top)
        .accessibilityLabel("Filters")
        .accessibilityValue(embeds.store?.listVocabulary.summary(of: list) ?? "")
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

/// A list written in a note, as a `list` block, drawn in place of its lines, read only: its
/// first 10 notes, then Show all, which unfolds it in place (50 rows at a time), and Show
/// fewer, which folds it again; set apart from the note's text by an outline, as on the Mac.
/// Its filters open from the line at its top.
struct PhoneListBlockView: View {
    @ObservedObject var embeds: PhoneEmbeds
    let list: ListDefinition
    /// Which `list` block of the note it is, from 0.
    let index: Int
    @ObservedObject var rows: ListBlockRows
    let open: (Note.ID) -> Void
    let unfold: (Int) -> Void
    let edit: () -> Void

    static let inset: CGFloat = 12, insetY: CGFloat = 6

    var body: some View {
        PhoneListView(embeds: embeds, list: list, limit: rows.rows(of: index), open: { if let id = $0 { open(id) } }, edit: edit, unfold: unfold)
            .padding(.horizontal, Self.inset)
            .padding(.vertical, Self.insetY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
    }

    /// How tall it is for a list finding `count` notes, showing up to `rows` of them.
    static func height(count: Int, rows: Int, hasDetails: Bool) -> CGFloat {
        PhoneListView.height(count: count, limit: rows, hasDetails: hasDetails, unfolds: true, edits: true) + insetY * 2
    }
}

/// How many rows each `list` block of an open note shows, by which block it is (from 0): the
/// first 10 unless unfolded. Kept while the note is open, not written in it.
@MainActor
final class ListBlockRows: ObservableObject {
    @Published private var rows: [Int: Int] = [:]
    func rows(of index: Int) -> Int { rows[index] ?? PhoneListView.embedLimit }
    func set(_ count: Int, of index: Int) { rows[index] = count == PhoneListView.embedLimit ? nil : count }
}
