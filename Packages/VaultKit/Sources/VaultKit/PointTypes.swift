import Foundation

/// Point's own kinds of property, beyond Obsidian's, kept in the vault's `.point/types.json`:
///
/// ```json
/// {
///   "properties": {
///     "status": {"type": "choice", "choices": ["draft", "review", "published"]},
///     "people": {"type": "person"},
///     "rating": {"type": "rating", "max": 5},
///     "post": {"type": "note", "folder": "Posts"}
///   },
///   "people": {"folder": "People"}
/// }
/// ```
///
/// Values are still ordinary YAML, so other tools read them as text, lists and numbers. Each
/// kind is also kept in Obsidian's types file as the type it's written as (`baseType`), so
/// Obsidian, editing alongside, treats it the same way.
public struct PointTypes: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        /// One of a fixed set of values.
        case choice
        /// Links to people's notes.
        case person
        /// A number of stars, up to `max`.
        case rating
        /// A link to a note, offered from one folder.
        case note

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .choice: "Choice"
            case .person: "Person"
            case .rating: "Rating"
            case .note: "Link to note"
            }
        }

        public var symbol: String {
            switch self {
            case .choice: "list.bullet.circle"
            case .person: "person"
            case .rating: "star"
            case .note: "doc.text"
            }
        }

        /// The Obsidian type it's written as.
        public var baseType: PropertyType {
            switch self {
            case .choice, .note: .text
            case .person: .list
            case .rating: .number
            }
        }
    }

    public struct Definition: Codable, Sendable, Equatable {
        public var type: Kind
        /// For a choice: the values to choose from, in order.
        public var choices: [String]?
        /// For a rating: the most stars (5 if unset).
        public var max: Int?
        /// For a link to a note: the folder its notes are offered from (any, if unset).
        public var folder: String?

        public init(type: Kind, choices: [String]? = nil, max: Int? = nil, folder: String? = nil) {
            self.type = type
            self.choices = choices
            self.max = max
            self.folder = folder
        }

        /// A rating's most stars.
        public var stars: Int { Swift.max(1, Swift.min(max ?? 5, 10)) }
    }

    public struct People: Codable, Sendable, Equatable {
        /// The folder people's notes are in.
        public var folder: String?
        public init(folder: String? = nil) { self.folder = folder }
    }

    private struct File: Codable {
        var properties: [String: Definition]?
        var people: People?
    }

    /// By key, as written.
    public private(set) var properties: [String: Definition] = [:]
    public var people = People()

    public init(properties: [String: Definition] = [:], people: People = People()) {
        self.properties = properties
        self.people = people
    }

    public static func file(in root: URL) -> URL {
        root.appendingPathComponent(".point").appendingPathComponent("types.json")
    }

    public static func load(vault root: URL) -> PointTypes {
        guard let data = try? Data(contentsOf: file(in: root)), let file = try? JSONDecoder().decode(File.self, from: data) else {
            return PointTypes()
        }
        return PointTypes(properties: file.properties ?? [:], people: file.people ?? People())
    }

    /// Writes the file, with its keys in order, so it changes as little as it can between saves
    /// (it's synced with the vault).
    public func save(vault root: URL) throws {
        let url = Self.file(in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let file = File(properties: properties.isEmpty ? nil : properties, people: people.folder == nil ? nil : people)
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    /// A key's definition, matched regardless of case.
    public func definition(forKey key: String) -> Definition? {
        properties[key] ?? properties.first { $0.key.lowercased() == key.lowercased() }?.value
    }

    /// Sets (or with nil, clears) a key's definition, replacing one set with different case.
    public mutating func set(_ definition: Definition?, forKey key: String) {
        for existing in properties.keys where existing.lowercased() == key.lowercased() { properties[existing] = nil }
        if let definition { properties[key] = definition }
    }

    /// A key renamed: its definition goes with it, unless the new name has one already.
    public mutating func rename(_ key: String, to newKey: String) {
        guard let definition = definition(forKey: key), self.definition(forKey: newKey) == nil else { return }
        set(nil, forKey: key)
        properties[newKey] = definition
    }

    /// The folder people's notes are in: the one set, else a top-level folder called People
    /// (in any case), if the vault has one.
    public func peopleFolder(among folders: [String]) -> String? {
        if let folder = people.folder { return folder }
        return folders.first { !$0.contains("/") && $0.lowercased() == "people" }
    }
}
