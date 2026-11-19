import Foundation
import VaultKit

/// What some notes have to filter by: their tags and their properties' values, each with how
/// many of the notes have it, most first. What a list's filter suggests and its menu offers,
/// so neither offers what would leave nothing.
public struct FilterFacets: Equatable, Sendable {
    public struct Property: Equatable, Sendable {
        /// As most of the notes spell it.
        public var name: String
        /// How many of the notes have it, with or without a value.
        public var noteCount: Int
        /// Each value as a list shows it (a link by its name), once whatever its case.
        public var values: [Value]
    }

    public struct Value: Equatable, Sendable {
        public var value: String
        public var count: Int
    }

    public var properties: [Property]
    public var tags: [Value]

    public init(properties: [Property] = [], tags: [Value] = []) {
        self.properties = properties
        self.tags = tags
    }

    public func property(_ name: String) -> Property? {
        properties.first { $0.name.lowercased() == name.lowercased() }
    }
}

extension SearchIndex {
    /// The tags and property values of these notes (all the vault's when nil).
    public func facets(of ids: [Note.ID]?) throws -> FilterFacets {
        var names: [String: [String: Int]] = [:]          // lowered: spelling: notes
        var values: [String: [String: (shown: String, count: Int, best: Int)]] = [:]
        var tags: [String: (tag: String, count: Int)] = [:]
        func add(_ where: String, _ bindings: [Any?]) throws {
            for row in try db.query("SELECT p.lowered, p.name, COUNT(*) FROM property_names p JOIN notes n ON n.row = p.note \(`where`) GROUP BY p.lowered, p.name", bindings) {
                names[row[0] as! String, default: [:]][row[1] as! String, default: 0] += row[2] as! Int
            }
            for row in try db.query("SELECT v.name, v.value, COUNT(DISTINCT v.note) FROM property_values v JOIN notes n ON n.row = v.note \(`where`) \(`where`.isEmpty ? "WHERE" : "AND") length(v.value) <= 80 GROUP BY v.name, v.value", bindings) {
                let name = row[0] as! String, count = row[2] as! Int
                let shown = NoteKinds.shownValue(row[1] as! String)
                guard !shown.isEmpty else { continue }
                let key = shown.lowercased()
                var entry = values[name, default: [:]][key] ?? (shown, 0, 0)
                if count > entry.best { (entry.shown, entry.best) = (shown, count) }
                entry.count += count
                values[name, default: [:]][key] = entry
            }
            for row in try db.query("SELECT t.lowered, MIN(t.tag), COUNT(DISTINCT t.note) FROM tags t JOIN notes n ON n.row = t.note \(`where`) GROUP BY t.lowered", bindings) {
                let key = row[0] as! String
                tags[key] = (tags[key]?.tag ?? row[1] as! String, (tags[key]?.count ?? 0) + (row[2] as! Int))
            }
        }
        if let ids {
            // In batches, within SQLite's limit on bindings. The batches share no notes, so
            // their counts add up.
            for start in stride(from: 0, to: ids.count, by: 400) {
                let batch = Array(ids[start..<min(start + 400, ids.count)])
                try add("WHERE n.id IN (\(batch.map { _ in "?" }.joined(separator: ",")))", batch)
            }
        } else {
            try add("", [])
        }
        func sorted(_ list: [FilterFacets.Value]) -> [FilterFacets.Value] {
            list.sorted { $0.count != $1.count ? $0.count > $1.count : $0.value.localizedStandardCompare($1.value) == .orderedAscending }
        }
        var properties: [FilterFacets.Property] = []
        for (lowered, spellings) in names {
            let best = spellings.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            let shown: [FilterFacets.Value] = (values[lowered] ?? [:]).values.map { FilterFacets.Value(value: $0.shown, count: $0.count) }
            let noteCount: Int = spellings.values.reduce(0, +)
            properties.append(FilterFacets.Property(name: best[0].key, noteCount: noteCount, values: sorted(shown)))
        }
        properties.sort { $0.noteCount != $1.noteCount ? $0.noteCount > $1.noteCount : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return FilterFacets(properties: properties, tags: sorted(tags.values.map { FilterFacets.Value(value: $0.tag, count: $0.count) }))
    }
}
