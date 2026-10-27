import Foundation

/// The kinds of value a property holds, as Obsidian names them in `.obsidian/types.json`.
public enum PropertyType: String, CaseIterable, Sendable, Identifiable {
    case text
    case list = "multitext"
    case number
    case checkbox
    case date
    case datetime
    case tags
    case aliases

    public var id: String { rawValue }

    /// The types offered when choosing one (aliases is Obsidian's own, for the `aliases` key).
    public static let choosable: [PropertyType] = [.text, .list, .number, .checkbox, .date, .datetime, .tags]

    public var name: String {
        switch self {
        case .text: "Text"
        case .list: "List"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .datetime: "Date & Time"
        case .tags: "Tags"
        case .aliases: "Aliases"
        }
    }

    /// The SF Symbol shown beside a property of this type, as Obsidian shows an icon.
    public var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .list: "list.bullet"
        case .number: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .datetime: "clock"
        case .tags: "tag"
        case .aliases: "arrow.turn.up.right"
        }
    }

    /// Whether its value is written as a list.
    public var isList: Bool { self == .list || self == .tags || self == .aliases }

    /// The types some keys have in Obsidian before anything is set.
    static func builtIn(for key: String) -> PropertyType? {
        switch key.lowercased() {
        case "tags", "tag": .tags
        case "aliases", "alias": .aliases
        case "cssclasses": .list
        default: nil
        }
    }

    /// The type a new property with this name probably has, before it has a value.
    public static func suggested(forKey key: String) -> PropertyType {
        builtIn(for: key) ?? (PropertyDate.names.contains(key.lowercased()) ? .date : .text)
    }

    /// A type worked out from how one note writes the value, for a key with no type set.
    public static func guess(for property: Frontmatter.Property) -> PropertyType {
        if let builtIn = builtIn(for: property.key) { return builtIn }
        if property.isList { return .list }
        guard let value = property.values.first else {
            return PropertyDate.names.contains(property.key.lowercased()) ? .date : .text
        }
        if let date = PropertyDate.parse(value) { return date.hasTime ? .datetime : .date }
        if ["true", "false"].contains(value.lowercased()) { return .checkbox }
        if Double(value) != nil { return .number }
        return .text
    }

    /// A value carried over to this type, when a property's type changes: a list's items
    /// joined into text, text split into items at commas, and anything that doesn't fit the
    /// new type (a word as a number, say) left empty.
    public func convert(_ values: [String], from old: PropertyType) -> [String] {
        let joined = values.joined(separator: ", ")
        switch self {
        case .list, .tags, .aliases:
            let items = old.isList ? values : values.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            let cleaned = items.filter { !$0.isEmpty }
            return self == .tags ? cleaned.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 } : cleaned
        case .text:
            return [joined]
        case .number:
            return Double(joined) != nil ? [joined] : []
        case .checkbox:
            return [joined.lowercased() == "true" ? "true" : "false"]
        case .date, .datetime:
            guard let value = values.first.flatMap({ PropertyDate.parse($0) }) else { return [] }
            return [PropertyDate.format(value.date, like: PropertyDate.Value(date: value.date, hasTime: self == .datetime,
                                                                              separator: value.separator, hasSeconds: value.hasSeconds))]
        }
    }
}

/// The vault's property types, kept by Obsidian in `.obsidian/types.json`
/// (`{"types": {"status": "text", "due": "date"}}`), so a property has the same type in
/// every note, in Point and in Obsidian.
public struct PropertyTypes: Sendable, Equatable {
    /// As written in the file, by key, including types Point doesn't know (from plugins).
    public private(set) var raw: [String: String] = [:]

    public init(raw: [String: String] = [:]) { self.raw = raw }

    static func file(in root: URL) -> URL {
        root.appendingPathComponent(".obsidian").appendingPathComponent("types.json")
    }

    public static func load(vault root: URL) -> PropertyTypes {
        guard let data = try? Data(contentsOf: file(in: root)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let types = object["types"] as? [String: Any] else { return PropertyTypes() }
        return PropertyTypes(raw: types.compactMapValues { $0 as? String })
    }

    /// The type set for a key, matched regardless of case, as Obsidian does.
    public func type(forKey key: String) -> PropertyType? {
        let value = raw[key] ?? raw.first { $0.key.lowercased() == key.lowercased() }?.value
        return value.flatMap(PropertyType.init(rawValue:))
    }

    /// A property's type: the vault's, else Obsidian's own for the key, else a guess from
    /// the note.
    public func type(of property: Frontmatter.Property) -> PropertyType {
        type(forKey: property.key) ?? PropertyType.guess(for: property)
    }

    /// Sets a key's type (replacing one set with different case).
    public mutating func set(_ type: PropertyType, forKey key: String) {
        for existing in raw.keys where existing.lowercased() == key.lowercased() && existing != key { raw[existing] = nil }
        raw[key] = type.rawValue
    }

    /// A key renamed: its type goes with it, unless the new name has one already.
    public mutating func rename(_ key: String, to newKey: String) {
        guard let type = raw[key], self.type(forKey: newKey) == nil else { return }
        raw[newKey] = type
    }

    /// Writes the types back, keeping everything else in the file as it was.
    public func save(vault root: URL) throws {
        let url = Self.file(in: root)
        var object = try ObsidianJSON.object(at: url)
        object["types"] = raw
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
