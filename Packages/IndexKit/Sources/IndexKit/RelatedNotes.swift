import Foundation
import VaultKit

/// Everything related to a note, in one list (links and recall made one, 8 November 2026):
/// first the notes sharing its topics or people (see `Recall`), most shared first; then the
/// notes linking here, grouped by what they are to it (see `LinkGroups`). A note that both
/// shares something and links here shows once, where `placement` says. The type chips narrow
/// both.
public struct RelatedNotes: Sendable, Equatable {
    /// A note sharing topics or people with this one.
    public struct Shared: Sendable, Equatable, Identifiable {
        public let noteID: Note.ID
        public let title: String
        public let type: String?
        /// Its day, `yyyy-MM-dd`: its `date:`, else the day its name starts with.
        public let day: String?
        /// The topics or people it shares, as named in this note.
        public let names: [String]
        public var id: Note.ID { noteID }
        public var date: Date? { day.flatMap(Recall.dayDate) }
    }

    /// The notes sharing the same number of this note's topics or people: all of them first,
    /// then one fewer, down to one. Newest first within each.
    public struct Tier: Sendable, Equatable, Identifiable {
        public let sharedCount: Int
        public let notes: [Shared]
        public let heading: String
        public var id: Int { sharedCount }
    }

    /// Where a note that both shares something and links here goes.
    public enum Placement: String, Sendable, CaseIterable {
        /// Among the shared notes (what's shared leads).
        case shared
        /// In its relation group (By, About…), as a link.
        case links
    }

    /// The most shared notes ranked; past that, rarely wanted, and each costs a lookup.
    public static let sharedLimit = 300

    public let recall: Recall?
    public let tiers: [Tier]
    /// The notes linking here that aren't among the shared ones (or all of them, with
    /// `placement` `.links`), by relation.
    public let links: LinkGroups
    /// The types among all of them, most common first, for the chips.
    public let types: [(type: String, count: Int)]
    /// How many share something, before narrowing by type; and how many more the recall query
    /// found than were ranked.
    public let sharedTotal: Int
    public let sharedBeyondLimit: Int

    /// Nothing yet.
    public static let empty = RelatedNotes(noteID: "", recall: nil, sharedIDs: [], values: [:], title: { _ in nil },
                                           name: { _ in nil }, typeProperty: "type", backlinks: [])

    public static func == (a: RelatedNotes, b: RelatedNotes) -> Bool {
        a.recall == b.recall && a.tiers == b.tiers && a.links == b.links && a.sharedTotal == b.sharedTotal
            && a.types.map(\.type) == b.types.map(\.type) && a.types.map(\.count) == b.types.map(\.count)
    }

    /// - Parameters:
    ///   - sharedIDs: what the recall's query found, newest first (the note itself may be
    ///     among them; it's left out).
    ///   - values: those notes' `date`, type and `recall.propertyNames` values, by note, then by
    ///     property in lowercase (as `SearchIndex.propertyValues` gives them).
    ///   - type: the type chosen in the chips, if any.
    public init(noteID: Note.ID, recall: Recall?, sharedIDs: [Note.ID], values: [Note.ID: [String: [String]]],
                title: (Note.ID) -> String?, name: (Note.ID) -> String?, typeProperty: String,
                backlinks: [Backlink], type chosen: String? = nil, placement: Placement = .shared) {
        self.recall = recall
        let linking = Set(backlinks.map(\.noteID))
        var ids = sharedIDs.filter { $0 != noteID }
        if placement == .links { ids.removeAll { linking.contains($0) } }
        sharedBeyondLimit = max(ids.count - Self.sharedLimit, 0)
        ids = Array(ids.prefix(Self.sharedLimit))

        // What each shares, its type and day.
        var shared: [Shared] = []
        if let recall {
            let wanted = Dictionary(recall.names.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            for id in ids {
                let row = values[id] ?? [:]
                var seen = Set<String>()
                let names = recall.propertyNames.flatMap { row[$0.lowercased()] ?? [] }
                    .compactMap(Recall.personName)
                    .compactMap { wanted[$0.lowercased()] }
                    .filter { seen.insert($0.lowercased()).inserted }
                guard !names.isEmpty else { continue }
                let type = row[typeProperty.lowercased()]?.first?.trimmingCharacters(in: .whitespaces)
                shared.append(Shared(noteID: id, title: title(id) ?? id, type: type?.isEmpty == false ? type : nil,
                                     day: row["date"]?.lazy.compactMap(Recall.day).first ?? name(id).flatMap(Recall.day),
                                     names: names))
            }
        }
        sharedTotal = shared.count
        let remainingLinks = placement == .shared ? backlinks.filter { link in !shared.contains { $0.noteID == link.noteID } } : backlinks

        // The chips count both.
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for type in shared.compactMap(\.type) + remainingLinks.compactMap(\.type) {
            counts[type.lowercased(), default: 0] += 1
            if spelling[type.lowercased()] == nil { spelling[type.lowercased()] = type }
        }
        types = counts.map { (spelling[$0.key]!, $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type.localizedStandardCompare($1.type) == .orderedAscending }

        let narrowed = chosen.map { chosen in shared.filter { $0.type?.caseInsensitiveCompare(chosen) == .orderedSame } } ?? shared
        let total = recall?.names.count ?? 0
        tiers = Dictionary(grouping: narrowed, by: \.names.count)
            .sorted { $0.key > $1.key }
            .map { count, notes in Tier(sharedCount: count, notes: notes, heading: Self.heading(sharing: count, of: total, recall: recall)) }
        links = LinkGroups(remainingLinks, type: chosen)
    }

    /// A tier's heading. By topics: "On Org design", "On all 3 topics", "On 2 of 3 topics". By
    /// people: "Earlier meetings with Sam Lee", "…with all 3", "…with 2 of 3".
    static func heading(sharing count: Int, of total: Int, recall: Recall?) -> String {
        guard let recall else { return "" }
        let which: String
        if total == 1 { which = recall.names[0] }
        else if count == total { which = "all \(total)" + (recall.basis == .topics ? " topics" : "") }
        else { which = "\(count) of \(total)" + (recall.basis == .topics ? " topics" : "") }
        switch recall.basis {
        case .topics: return "On " + which
        case .people: return "Earlier \(NoteKinds.plural(recall.type ?? "note").lowercased()) with " + which
        }
    }

    public var isEmpty: Bool { tiers.isEmpty && links.groups.isEmpty }
    /// The newest shared note's day, for the readout.
    public var newestSharedDay: String? { tiers.flatMap(\.notes).compactMap(\.day).max() }

    /// The line that opens the list. With notes sharing something, recall's own ("9 earlier
    /// meetings · last on 9 September", "23 notes on Org design"). Without, the links and what
    /// kinds they are: "12 links (articles by this person, mentions, and meetings with this
    /// person)". Nil with nothing to show.
    public func readout(ownType: String?, unlinkedMentions: Int, now: Date = Date()) -> String? {
        if let recall, sharedTotal > 0 {
            let lastDay = recall.basis == .people ? newestSharedDay : nil
            return recall.summary(count: sharedTotal + sharedBeyondLimit, lastDay: lastDay, now: now)
        }
        let all = LinkGroups(links.groups.flatMap(\.backlinks))
        let count = all.count + unlinkedMentions
        guard count > 0 else { return nil }
        var kinds = all.groups.map { Self.phrase(for: $0, ownType: ownType) }
        if unlinkedMentions > 0 { kinds.append("unlinked mentions") }
        let number = unlinkedMentions >= 50 ? "\(all.count + 50)+" : count.formatted()
        return "\(number) \(count == 1 ? "link" : "links") (\(Self.joined(kinds)))"
    }

    /// What a group of links is, in words: "articles by this person", "meetings with this
    /// person", "mentions", or the property's name.
    public static func phrase(for group: LinkGroups.Group, ownType: String?) -> String {
        let this = "this " + (ownType?.lowercased() ?? "note")
        let plural = commonType(of: group.backlinks).map { NoteKinds.plural($0).lowercased() } ?? "notes"
        switch group.relation {
        case .by: return "\(plural) by \(this)"
        case .about: return "\(plural) about \(this)"
        case .with: return "\(plural) with \(this)"
        case .property(let name): return name
        case .mentioned: return "mentions"
        }
    }

    /// "a", "a and b", "a, b, and c": with the serial comma, whatever the locale.
    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return items[0] + " and " + items[1]
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    /// The type more than half of these have, if one does ("notes" otherwise: five of five
    /// kinds aren't "books").
    static func commonType(of backlinks: [Backlink]) -> String? {
        var counts: [String: Int] = [:]
        for type in backlinks.compactMap(\.type) { counts[type, default: 0] += 1 }
        guard let top = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
              top.value * 2 > backlinks.count else { return nil }
        return top.key
    }
}
