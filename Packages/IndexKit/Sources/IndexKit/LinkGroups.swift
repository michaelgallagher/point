import Foundation

/// What a note linking here is to this note, from where the link is: a property says it
/// (`author:` means by them, `topics:` about it, `people:` with them); a link in the text
/// only mentions it. A person's note is mostly linked from meetings they were in, so the
/// articles they wrote and the notes about them would be lost among those without this.
public enum LinkRelation: Hashable, Sendable, Comparable {
    /// From `author`, `creator` and the like.
    case by
    /// From `topics`, `about` and the like.
    case about
    /// From any other property, named as written.
    case property(String)
    /// From `people`, `attendees` and the like.
    case with
    /// From the text alone.
    case mentioned

    static let byNames: Set<String> = ["author", "authors", "by", "creator", "creators", "writer", "writers", "director", "directors", "speaker", "speakers", "host", "hosts", "artist", "artists"]
    static let aboutNames: Set<String> = ["topic", "topics", "about", "subject", "subjects", "related", "project", "projects", "theme", "themes"]
    static let withNames: Set<String> = ["people", "person", "attendees", "attendee", "participants", "with", "who", "invitees", "present"]

    /// The relation a property's link gives.
    public init(property: String) {
        let name = property.lowercased()
        if Self.byNames.contains(name) { self = .by }
        else if Self.aboutNames.contains(name) { self = .about }
        else if Self.withNames.contains(name) { self = .with }
        else { self = .property(property) }
    }

    /// A backlink's relation: the first of its properties' to come in this order (by, about,
    /// another property, with), else mentioned.
    public init(_ backlink: Backlink) {
        self = backlink.properties.map(LinkRelation.init(property:)).min() ?? .mentioned
    }

    /// The group's heading.
    public var label: String {
        switch self {
        case .by: "By"
        case .about: "About"
        case .property(let name): name.prefix(1).uppercased() + name.dropFirst()
        case .with: "With"
        case .mentioned: "Mentioned"
        }
    }

    public static func < (a: LinkRelation, b: LinkRelation) -> Bool {
        func rank(_ relation: LinkRelation) -> Int {
            switch relation {
            case .by: 0
            case .about: 1
            case .property: 2
            case .with: 3
            case .mentioned: 4
            }
        }
        if case .property(let x) = a, case .property(let y) = b { return x.localizedStandardCompare(y) == .orderedAscending }
        return rank(a) < rank(b)
    }
}

/// The notes linking here, grouped by relation and narrowed by type: what the links panel
/// shows.
public struct LinkGroups: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public let relation: LinkRelation
        /// Newest first.
        public let backlinks: [Backlink]
        public var id: LinkRelation { relation }
    }

    /// Every group, in order: by, about, other properties, with, mentioned.
    public let groups: [Group]
    /// The types among them, most common first, with how many of each. Notes with no type
    /// aren't counted.
    public let types: [(type: String, count: Int)]

    public static func == (a: LinkGroups, b: LinkGroups) -> Bool {
        a.groups == b.groups && a.types.map(\.type) == b.types.map(\.type) && a.types.map(\.count) == b.types.map(\.count)
    }

    /// The groups for these backlinks, of the type given only, if any.
    public init(_ backlinks: [Backlink], type: String? = nil) {
        var counts: [String: Int] = [:]
        for backlink in backlinks { if let type = backlink.type { counts[type, default: 0] += 1 } }
        types = counts.map { ($0.key, $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type.localizedStandardCompare($1.type) == .orderedAscending }
        let shown = type.map { type in backlinks.filter { $0.type?.caseInsensitiveCompare(type) == .orderedSame } } ?? backlinks
        groups = Dictionary(grouping: shown, by: LinkRelation.init)
            .map { relation, backlinks in
                Group(relation: relation, backlinks: backlinks.sorted { a, b in
                    switch (a.date, b.date) {
                    case let (x?, y?) where x != y: x > y
                    case (_?, nil): true
                    case (nil, _?): false
                    default: a.title.localizedStandardCompare(b.title) == .orderedAscending
                    }
                })
            }
            .sorted { $0.relation < $1.relation }
    }

    public var count: Int { groups.reduce(0) { $0 + $1.backlinks.count } }
}
