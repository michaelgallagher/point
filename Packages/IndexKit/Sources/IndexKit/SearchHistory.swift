import Foundation
import VaultKit

/// What search learns on this device: which notes are opened, and how recently ("frecency"),
/// and which note was picked for what was typed. It reorders results of similar quality, and
/// never puts a weak match above a clearly better one. With nothing learned, it changes
/// nothing. Kept outside the vault (`SearchHistory.File`), private to the device.
public struct SearchHistory: Codable, Equatable, Sendable {
    /// When each note was opened, oldest first, the last `opensKept` of them.
    private(set) var opens: [Note.ID: [Date]] = [:]
    /// What was typed and which note was then picked, newest last.
    private(set) var picks: [Pick] = []

    struct Pick: Codable, Equatable, Sendable {
        let query: String
        let id: Note.ID
        let date: Date
    }

    static let opensKept = 20
    static let notesKept = 2000
    static let picksKept = 500
    /// An open counts for half as much after this long.
    static let halfLife: TimeInterval = 14 * 24 * 60 * 60

    public init() {}

    public var isEmpty: Bool { opens.isEmpty && picks.isEmpty }

    // MARK: Learning

    /// A note opened on purpose: not restored at launch, nor gone back or forward to.
    public mutating func opened(_ id: Note.ID, at date: Date = Date()) {
        var dates = opens[id] ?? []
        dates.append(date)
        opens[id] = Array(dates.suffix(Self.opensKept))
        if opens.count > Self.notesKept {
            // The notes opened longest ago go first.
            let kept = opens.sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }.prefix(Self.notesKept)
            opens = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }

    /// A result picked after typing `query`. It's also an open.
    public mutating func picked(_ id: Note.ID, for query: String, at date: Date = Date()) {
        opened(id, at: date)
        let query = Self.normalised(query)
        guard !query.isEmpty else { return }
        picks.removeAll { $0.query == query }
        picks.append(Pick(query: query, id: id, date: date))
        picks = Array(picks.suffix(Self.picksKept))
    }

    /// A note moved or renamed: it keeps what was learned about it.
    public mutating func renamed(from old: Note.ID, to new: Note.ID) {
        if let dates = opens.removeValue(forKey: old) { opens[new] = ((opens[new] ?? []) + dates).sorted().suffix(Self.opensKept) }
        picks = picks.map { $0.id == old ? Pick(query: $0.query, id: new, date: $0.date) : $0 }
    }

    /// Forgets notes that no longer exist.
    public mutating func keepOnly(_ ids: Set<Note.ID>) {
        opens = opens.filter { ids.contains($0.key) }
        picks.removeAll { !ids.contains($0.id) }
    }

    public mutating func forget() {
        self = SearchHistory()
    }

    // MARK: Scores

    /// How much a note has been opened lately: each open counts for 1, halving every
    /// `halfLife`. An edit at `modified`, if given, counts as an open.
    public func score(of id: Note.ID, modified: Date? = nil, now: Date = Date()) -> Double {
        let dates = (opens[id] ?? []) + (modified.map { [$0] } ?? [])
        return dates.reduce(0) { $0 + pow(0.5, max(now.timeIntervalSince($1), 0) / Self.halfLife) }
    }

    /// When a note was last opened on this device.
    public func lastOpened(_ id: Note.ID) -> Date? { opens[id]?.last }

    /// The notes opened on this device, the most recently opened first.
    public var recentlyOpened: [Note.ID] {
        opens.sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }.map(\.key)
    }

    /// The note picked for `query`, or for text that `query` and it start alike. A pick is
    /// kept under what was typed when it was made, often part of a word, so both less and more
    /// than that find it: "mov" and "movies" both find the note picked after typing "movi".
    /// An exact match comes first, then the newest pick for longer text, then the pick for the
    /// longest text that `query` starts with. One letter is too little to go on.
    public func pick(for query: String) -> Note.ID? {
        let query = Self.normalised(query)
        guard query.count >= 2 else { return nil }
        if let exact = picks.last(where: { $0.query == query }) { return exact.id }
        if let longer = picks.last(where: { $0.query.hasPrefix(query) }) { return longer.id }
        return picks.filter { $0.query.count >= 2 && query.hasPrefix($0.query) }
            .max { $0.query.count != $1.query.count ? $0.query.count < $1.query.count : $0.date < $1.date }?.id
    }

    // MARK: Ranking

    /// How many matches in the text count as of about the same relevance, so that a note
    /// opened more often may move up among them.
    static let textGroup = 5

    /// Results reordered by what's been learned, without changing which they are:
    /// - the note picked for this query before, first, if it's among them;
    /// - title matches (`titleQuality` not nil, 0 best) stay grouped by quality, the notes
    ///   opened more coming first within a group;
    /// - text matches keep their order but for small groups, within which the notes opened
    ///   more come first.
    /// Title matches stay before text matches. Ties keep the order given.
    public func rank<T>(_ items: [T], for query: String, now: Date = Date(),
                        id: (T) -> Note.ID, titleQuality: (T) -> Int?) -> [T] {
        guard !isEmpty else { return items }
        let scores = Dictionary(items.map { (id($0), score(of: id($0), now: now)) }, uniquingKeysWith: { a, _ in a })
        func more(_ a: T, _ b: T) -> Bool { scores[id(a)]! > scores[id(b)]! }

        let titled = items.enumerated().compactMap { item in titleQuality(item.element).map { (item.offset, item.element, $0) } }
        let titles = titled.sorted { a, b in
            if a.2 != b.2 { return a.2 < b.2 }
            if scores[id(a.1)]! != scores[id(b.1)]! { return more(a.1, b.1) }
            return a.0 < b.0
        }.map(\.1)

        let text = items.filter { titleQuality($0) == nil }
        var texts: [T] = []
        for start in stride(from: 0, to: text.count, by: Self.textGroup) {
            let group = Array(text[start..<min(start + Self.textGroup, text.count)]).enumerated()
            texts += group.sorted { more($0.element, $1.element) || (!more($1.element, $0.element) && $0.offset < $1.offset) }.map(\.element)
        }

        var ranked = titles + texts
        if let picked = pick(for: query), let index = ranked.firstIndex(where: { id($0) == picked }) {
            ranked.insert(ranked.remove(at: index), at: 0)
        }
        return ranked
    }

    /// Search results reordered (`rank`), title matches by how well their titles match.
    public func rank(_ results: [SearchResult], for query: String, now: Date = Date()) -> [SearchResult] {
        let words = query.split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("#") }.flatMap { Fuzzy.words(String($0)) }
        return rank(results, for: query, now: now, id: \.id) { result in
            result.matchedTitle ? (words.isEmpty ? 0 : Fuzzy.titleScore(words: words, title: result.title) ?? 0) : nil
        }
    }

    /// What was typed, as remembered: lowercased, with single spaces.
    static func normalised(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Keeping it

    /// Where a vault's history is kept, and saving it there.
    public struct File: Sendable {
        public let url: URL

        public init(url: URL) { self.url = url }

        /// What was learned, or nothing if there's no file yet or it can't be read.
        public func load() -> SearchHistory {
            guard let data = try? Data(contentsOf: url) else { return SearchHistory() }
            return (try? JSONDecoder().decode(SearchHistory.self, from: data)) ?? SearchHistory()
        }

        public func save(_ history: SearchHistory) {
            guard let data = try? JSONEncoder().encode(history) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
