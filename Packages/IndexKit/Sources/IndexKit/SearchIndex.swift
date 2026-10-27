import Foundation
import MarkdownKit
import VaultKit

/// A note found by search.
public struct SearchResult: Sendable, Identifiable, Equatable {
    public let id: Note.ID
    public let title: String
    /// A short piece of matching text, with each match between `SearchResult.matchStart`
    /// and `SearchResult.matchEnd`. Nil when only the title matched.
    public let snippet: String?
    public let matchedTitle: Bool

    public static let matchStart: Character = "\u{2}"
    public static let matchEnd: Character = "\u{3}"
}

/// A note that links to another.
public struct Backlink: Sendable, Identifiable, Equatable {
    public let noteID: Note.ID
    public let title: String
    /// The line the link is on, without Markdown markers.
    public let context: String
    /// Where the link is in that note's text (UTF-16 offsets): its target, or the whole link.
    public var range = NSRange(location: NSNotFound, length: 0)
    public var id: Note.ID { noteID }
}

/// A note mentioning another by name without linking to it.
public struct Mention: Sendable, Identifiable, Equatable {
    public let noteID: Note.ID
    public let title: String
    /// Where the mention is in that note's text (UTF-16 offsets).
    public let range: NSRange
    /// The mention as written, which may differ in case from the title.
    public let matched: String
    public let context: String
    public var id: String { "\(noteID)@\(range.location)" }

    /// The mentioning note's text with this mention turned into a link to `title`, or nil if
    /// the text has changed since the mention was found.
    public func linking(in text: String, to title: String) -> String? {
        let ns = text as NSString
        guard NSMaxRange(range) <= ns.length, ns.substring(with: range) == matched else { return nil }
        let link = matched == title ? "[[\(title)]]" : "[[\(title)|\(matched)]]"
        return ns.replacingCharacters(in: range, with: link)
    }
}

/// The vault's search index: full-text search that forgives typos and partial words,
/// plus tags and links, kept in a SQLite file outside the vault.
public actor SearchIndex {
    static let schemaVersion = "5" // 5: links in frontmatter count as links.

    private let db: Database
    /// Notes the last update couldn't read: kept as they were last indexed (or by title only,
    /// if new), and tried again by the next update.
    public private(set) var unreadableNotes: [Note.ID] = []
    /// Titles for fuzzy matching, kept in memory.
    private var titles: [(row: Int, id: Note.ID, title: String)] = []

    /// Opens the index at `url`, or an in-memory one when nil. An index from an older
    /// version of Point is rebuilt from scratch.
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        db = try Database(url: url)
        try db.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        try db.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        let version = try db.query("SELECT value FROM meta WHERE key = 'version'").first?.first as? String
        if version != Self.schemaVersion {
            try db.execute("""
                DROP TABLE IF EXISTS notes; DROP TABLE IF EXISTS words; DROP TABLE IF EXISTS grams;
                DROP TABLE IF EXISTS vocab; DROP TABLE IF EXISTS tags; DROP TABLE IF EXISTS links;
                DROP TABLE IF EXISTS spelled; DROP TABLE IF EXISTS spellings;
                """)
        }
        try db.execute("""
            CREATE TABLE IF NOT EXISTS notes(row INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL, title TEXT NOT NULL, modified REAL NOT NULL, body TEXT NOT NULL, properties TEXT NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5(title, body, properties, content = 'notes', content_rowid = 'row', tokenize = 'porter unicode61 remove_diacritics 2');
            CREATE VIRTUAL TABLE IF NOT EXISTS grams USING fts5(title, body, properties, content = 'notes', content_rowid = 'row', tokenize = 'trigram');
            CREATE VIRTUAL TABLE IF NOT EXISTS vocab USING fts5vocab(words, 'row');
            CREATE VIRTUAL TABLE IF NOT EXISTS spelled USING fts5(title, body, properties, content = 'notes', content_rowid = 'row', detail = none, tokenize = 'unicode61 remove_diacritics 2');
            CREATE VIRTUAL TABLE IF NOT EXISTS spellings USING fts5vocab(spelled, 'row');
            CREATE TABLE IF NOT EXISTS tags(note INTEGER NOT NULL, tag TEXT NOT NULL, lowered TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS tags_lowered ON tags(lowered);
            CREATE TABLE IF NOT EXISTS links(note INTEGER NOT NULL, name TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS links_name ON links(name);
            """)
        try db.query("INSERT OR REPLACE INTO meta(key, value) VALUES ('version', ?)", [Self.schemaVersion])
        titles = try Self.loadTitles(db)
    }

    private static func loadTitles(_ db: Database) throws -> [(row: Int, id: Note.ID, title: String)] {
        try db.query("SELECT row, id, title FROM notes").map { ($0[0] as! Int, $0[1] as! String, $0[2] as! String) }
    }

    // MARK: Keeping up to date

    /// Brings the index in line with the vault: indexes new and changed notes, forgets
    /// deleted ones. Returns how many notes were (re)indexed. A note that can't be read
    /// keeps what was indexed for it before (a new one is indexed by title only), with its
    /// old date, so the next update tries again: indexed as empty with its new date, it
    /// dropped out of search until it next changed.
    @discardableResult
    public func update(notes: [Note]) throws -> Int {
        var stored: [Note.ID: (row: Int, modified: Double)] = [:]
        for row in try db.query("SELECT id, row, modified FROM notes") {
            stored[row[0] as! String] = (row[1] as! Int, row[2] as! Double)
        }
        let current = Set(notes.map(\.id))
        let removed = stored.filter { !current.contains($0.key) }.map(\.value.row)
        // Evicted iCloud notes are indexed by title only, with no date, so they are
        // indexed fully once downloaded.
        let changed = notes.filter { stored[$0.id]?.modified != ($0.isDownloaded ? $0.modified.timeIntervalSince1970 : 0) }

        if !removed.isEmpty {
            try db.transaction {
                for row in removed { try delete(row: row) }
            }
        }
        var unreadable: [Note.ID] = []
        var indexed = 0
        for batch in stride(from: 0, to: changed.count, by: 200).map({ Array(changed[$0..<min($0 + 200, changed.count)]) }) {
            let prepared = batch.map { note in (note, note.isDownloaded ? try? NoteReader.read(contentsOf: note.url) : nil) }
            try db.transaction {
                for (note, text) in prepared {
                    if note.isDownloaded, text == nil {
                        unreadable.append(note.id)
                        if stored[note.id] != nil { continue } // Kept as last indexed.
                    } else {
                        indexed += 1
                    }
                    if let existing = stored[note.id] { try delete(row: existing.row) }
                    try insert(note, text: text)
                }
            }
        }
        unreadableNotes = unreadable
        if !removed.isEmpty || !changed.isEmpty { titles = try Self.loadTitles(db) }
        return indexed
    }

    /// The full-text tables, which all read their text from `notes` (stored once).
    private static let textTables = ["words", "grams", "spelled"]

    private func delete(row: Int) throws {
        // External-content tables are told what text to forget before the row goes.
        if let old = try db.query("SELECT title, body, properties FROM notes WHERE row = ?", [row]).first {
            for table in Self.textTables {
                try db.query("INSERT INTO \(table)(\(table), rowid, title, body, properties) VALUES ('delete', ?, ?, ?, ?)", [row, old[0], old[1], old[2]])
            }
        }
        for table in ["notes WHERE row", "tags WHERE note", "links WHERE note"] {
            try db.query("DELETE FROM \(table) = ?", [row])
        }
    }

    private func insert(_ note: Note, text: String?) throws {
        // Indexed by title only (not downloaded, or unreadable): no date, so it's indexed fully
        // once it can be read.
        let modified = text == nil ? 0 : note.modified.timeIntervalSince1970
        // Properties are searchable but kept apart from the text, so snippets read naturally.
        let body = text.map { PlainText.strippingMarkers(from: $0, includingFrontmatter: false) } ?? ""
        let properties = text.flatMap(Frontmatter.parse)?.body ?? ""
        try db.query("INSERT INTO notes(id, title, modified, body, properties) VALUES (?, ?, ?, ?, ?)",
                     [note.id, note.title, modified, body, properties])
        let row = db.lastInsertedRow
        for table in Self.textTables {
            try db.query("INSERT INTO \(table)(rowid, title, body, properties) VALUES (?, ?, ?, ?)", [row, note.title, body, properties])
        }
        guard let text else { return }
        for tag in NoteTags.tags(in: text) {
            try db.query("INSERT INTO tags(note, tag, lowered) VALUES (?, ?, ?)", [row, tag, tag.lowercased()])
        }
        for name in Set(Self.linkedNames(in: text)) {
            try db.query("INSERT INTO links(note, name) VALUES (?, ?)", [row, name])
        }
    }

    /// The lowercased note names a text links to, for finding backlinks quickly.
    static func linkedNames(in text: String) -> [String] {
        func name(_ target: String) -> String {
            var name = target.split(separator: "#", omittingEmptySubsequences: false).first.map(String.init) ?? target
            name = (name as NSString).lastPathComponent
            if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
            return name.lowercased()
        }
        // Wikilinks and embeds, those in the frontmatter too (`people: "[[Ann]]"`), then
        // Markdown links to notes.
        return LinkUpdater.wikiLinks(in: text).map { name($0.target) } + MarkdownParser.parse(text).compactMap { token in
            switch token.kind {
            case .link(let destination):
                let decoded = destination.removingPercentEncoding ?? destination
                return decoded.contains("://") || !decoded.lowercased().contains(".md") ? nil : name(decoded)
            default:
                return nil
            }
        }
    }

    // MARK: Searching

    /// Searches titles and text. Words may be partial or misspelled and come in any order;
    /// `#tag` words filter by tag (including nested tags such as `#work/imprint`).
    public func search(_ query: String, limit: Int = 50) throws -> [SearchResult] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let tags = terms.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()).lowercased() }
        let words = terms.filter { !$0.hasPrefix("#") }.flatMap(Fuzzy.words)
        let allowed = try tags.isEmpty ? nil : notes(taggedWithAll: tags)

        guard !words.isEmpty else {
            guard let allowed else { return [] }
            return try db.query("SELECT id, title, row FROM notes ORDER BY modified DESC").compactMap { row in
                allowed.contains(row[2] as! Int) ? SearchResult(id: row[0] as! String, title: row[1] as! String, snippet: nil, matchedTitle: false) : nil
            }.prefix(limit).map { $0 }
        }

        // Titles first, best match first.
        let titleMatches = titles
            .filter { allowed?.contains($0.row) ?? true }
            .compactMap { entry in Fuzzy.titleScore(words: words, title: entry.title).map { (entry, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.title.count < $1.0.title.count }

        // Then text, by relevance: whole words and word forms, then parts of words.
        // Tags filter inside the query, so the best 200 are the best 200 with those tags.
        var bodyMatches = try matches(in: "words", query: try wordQuery(words), taggedWithAll: tags)
        if bodyMatches.count < limit, words.allSatisfy({ $0.count >= 3 }) {
            let partial = words.map { "\"\($0)\"" }.joined(separator: " AND ")
            bodyMatches += try matches(in: "grams", query: partial, taggedWithAll: tags).filter { match in !bodyMatches.contains { $0.row == match.row } }
        }
        let snippets = Dictionary(bodyMatches.map { ($0.row, $0.snippet) }, uniquingKeysWith: { a, _ in a })

        var seen = Set<Int>()
        var results: [SearchResult] = []
        for (entry, _) in titleMatches where seen.insert(entry.row).inserted {
            results.append(SearchResult(id: entry.id, title: entry.title, snippet: snippets[entry.row], matchedTitle: true))
        }
        for match in bodyMatches where (allowed?.contains(match.row) ?? true) && seen.insert(match.row).inserted {
            results.append(SearchResult(id: match.id, title: match.title, snippet: match.snippet, matchedTitle: false))
        }
        return Array(results.prefix(limit))
    }

    /// An FTS5 query in which each word may be a prefix or a near-miss of a word in the vault.
    private func wordQuery(_ words: [String]) throws -> String {
        try words.map { word in
            let variants = [word] + (try corrections(for: word))
            return "(" + variants.map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
    }

    /// Words in the vault one or two typos away from `word`, if nothing starts with it.
    /// Looked up in words as written (`spellings`), not word stems, so "meetng" finds "meeting".
    private func corrections(for word: String) throws -> [String] {
        let typos = Fuzzy.allowedTypos(for: word)
        guard typos > 0, let first = word.first else { return [] }
        let exists = try db.query("SELECT 1 FROM spellings WHERE term >= ? AND term < ? LIMIT 1", [word, word + "\u{10FFFF}"])
        guard exists.isEmpty else { return [] }
        let candidates = try db.query(
            "SELECT term, doc FROM spellings WHERE term >= ? AND term < ? AND length(term) BETWEEN ? AND ?",
            [String(first), String(first) + "\u{10FFFF}", word.count - typos, word.count + typos]
        )
        return candidates
            .compactMap { row -> (String, Int, Int)? in
                let term = row[0] as! String
                return Fuzzy.editDistance(word, term, limit: typos).map { (term, $0, row[1] as! Int) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }
            .prefix(3)
            .map(\.0)
    }

    private struct BodyMatch { let row: Int; let id: Note.ID; let title: String; let snippet: String }

    private func matches(in table: String, query: String, taggedWithAll tags: [String] = []) throws -> [BodyMatch] {
        let tagged = tags.map { _ in " AND \(table).rowid IN (SELECT note FROM tags WHERE lowered = ? OR lowered LIKE ? ESCAPE '\\')" }.joined()
        let sql = """
            SELECT n.row, n.id, n.title, snippet(\(table), 1, char(2), char(3), '…', 12)
            FROM \(table) JOIN notes n ON n.row = \(table).rowid
            WHERE \(table) MATCH ?\(tagged) ORDER BY bm25(\(table), 8.0, 1.0, 0.5) LIMIT 200
            """
        var parameters = [query]
        for tag in tags { parameters += [tag, Self.likePattern(under: tag)] }
        return try db.query(sql, parameters).map {
            BodyMatch(row: $0[0] as! Int, id: $0[1] as! String, title: $0[2] as! String, snippet: $0[3] as? String ?? "")
        }
    }

    private func notes(taggedWithAll tags: [String]) throws -> Set<Int> {
        var result: Set<Int>?
        for tag in tags {
            let rows = try db.query("SELECT note FROM tags WHERE lowered = ? OR lowered LIKE ? ESCAPE '\\'", [tag, Self.likePattern(under: tag)])
            let notes = Set(rows.map { $0[0] as! Int })
            result = result.map { $0.intersection(notes) } ?? notes
        }
        return result ?? []
    }

    /// A LIKE pattern for the tags nested under `tag` (`work/…` under `work`).
    private static func likePattern(under tag: String) -> String {
        tag.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "/%"
    }

    /// Every tag in the vault with how many notes use it, most used first.
    public func allTags() throws -> [(tag: String, count: Int)] {
        try db.query("SELECT MIN(tag), COUNT(DISTINCT note) FROM tags GROUP BY lowered ORDER BY COUNT(DISTINCT note) DESC, lowered")
            .map { ($0[0] as! String, $0[1] as! Int) }
    }

    /// Every note's tags, as written, for notes that have any.
    public func tagsByNote() throws -> [Note.ID: [String]] {
        var result: [Note.ID: [String]] = [:]
        for row in try db.query("SELECT n.id, t.tag FROM tags t JOIN notes n ON n.row = t.note") {
            result[row[0] as! String, default: []].append(row[1] as! String)
        }
        return result
    }

    // MARK: Links between notes

    /// The notes linking to `note`, each with the line the link is on.
    public func backlinks(to note: Note, notes: [Note]) throws -> [Backlink] {
        let candidates = try db.query("SELECT DISTINCT n.id FROM links l JOIN notes n ON n.row = l.note WHERE l.name = ?",
                                      [note.title.lowercased()]).map { $0[0] as! String }
        let resolver = LinkResolver(notes: notes)
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return candidates.compactMap { id -> Backlink? in
            guard id != note.id, let source = byID[id], let text = try? NoteReader.read(contentsOf: source.url) else { return nil }
            let ns = text as NSString
            func backlink(at range: NSRange) -> Backlink {
                let line = ns.substring(with: ns.lineRange(for: NSRange(location: range.location, length: 0)))
                return Backlink(noteID: id, title: source.title, context: PlainText.strippingMarkers(from: line).trimmingCharacters(in: .whitespacesAndNewlines),
                                range: range)
            }
            // Wikilinks and embeds, in the frontmatter too (most of a note's links can be in
            // its properties: Obsidian counts them, and Point missed them), then Markdown links.
            for link in LinkUpdater.wikiLinks(in: text) where resolver.resolve(wikiTarget: link.target, from: id)?.id == note.id {
                return backlink(at: NSRange(location: link.location, length: (link.target as NSString).length))
            }
            for token in MarkdownParser.parse(text) {
                guard case .link(let destination) = token.kind, resolver.resolve(markdownDestination: destination, from: id)?.id == note.id else { continue }
                return backlink(at: token.range)
            }
            return nil
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Places where other notes mention `note` by name without linking to it: at most
    /// `perNote` from each note and `limit` in all, because a note named after a common word
    /// ("Meeting") can be mentioned thousands of times.
    public func unlinkedMentions(of note: Note, notes: [Note], perNote: Int = 3, limit: Int = 50) throws -> [Mention] {
        let titleWords = Fuzzy.words(note.title)
        guard !titleWords.isEmpty else { return [] }
        let phrase = "\"" + titleWords.joined(separator: " ") + "\""
        let candidates = try db.query("SELECT n.id FROM words JOIN notes n ON n.row = words.rowid WHERE words MATCH ? LIMIT 200",
                                      ["body : " + phrase]).map { $0[0] as! String }
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var mentions: [Mention] = []
        for id in candidates where id != note.id {
            guard mentions.count < limit else { break }
            guard let source = byID[id], let text = try? NoteReader.read(contentsOf: source.url) else { continue }
            mentions += Self.mentions(of: note.title, in: text, noteID: id, noteTitle: source.title).prefix(perNote)
        }
        return Array(mentions.prefix(limit))
    }

    /// Whole-word, any-case occurrences of `title` in `text` that aren't already part of a
    /// link, code, a tag or frontmatter.
    static func mentions(of title: String, in text: String, noteID: Note.ID, noteTitle: String) -> [Mention] {
        let ns = text as NSString
        let excluded = MarkdownParser.parse(text).filter { token in
            switch token.kind {
            case .wikiLink, .embed, .link, .image, .url, .code, .codeBlock, .frontmatter, .tag: true
            default: false
            }
        }.map(\.range)
        var mentions: [Mention] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: title, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            searchRange = NSRange(location: NSMaxRange(found), length: ns.length - NSMaxRange(found))
            func isWordCharacter(_ index: Int) -> Bool {
                guard index >= 0, index < ns.length, let scalar = Unicode.Scalar(ns.character(at: index)) else { return false }
                return CharacterSet.alphanumerics.contains(scalar)
            }
            guard !isWordCharacter(found.location - 1), !isWordCharacter(NSMaxRange(found)),
                  !excluded.contains(where: { NSIntersectionRange($0, found).length > 0 }) else { continue }
            let line = ns.substring(with: ns.lineRange(for: found))
            mentions.append(Mention(noteID: noteID, title: noteTitle, range: found, matched: ns.substring(with: found),
                                    context: PlainText.strippingMarkers(from: line).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return mentions
    }
}
