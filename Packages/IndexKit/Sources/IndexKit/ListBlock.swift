import Foundation
import VaultKit

/// A list written in a note, as a fenced block named `list`, rather than a note of its own.
/// It holds the same choices as a list note's properties, without the `list-` prefix:
///
/// ````markdown
/// ```list
/// from: Reading
/// where:
///   - format is Book
///   - read is not set
/// sort: published descending
/// show:
///   - author
///   - published
/// ```
/// ````
///
/// Its body, here, is the lines between the fences, each with its line break. The fence
/// already says it's a list, so an empty block is one too: of every note.
extension ListDefinition {
    /// The fence's name: ```` ```list ````.
    public static let blockLanguage = "list"

    /// A block's keys, and the list note's properties they stand for.
    static let blockKeys: [String: String] = [
        "from": Key.from, "tags": Key.tags, "where": Key.conditions,
        "match": Key.match, "sort": Key.sort, "show": Key.columns,
    ]

    /// The list a block's body describes. Nil if any of it can't be read, so a mistake shows
    /// as the block's text rather than as a different list: a key that isn't a list's, one
    /// written twice, a line that isn't `key: value` or an item under one, or a condition or
    /// sort that doesn't read.
    public init?(block body: String) {
        guard let properties = Self.blockProperties(body) else { return nil }
        let values = Self.values(of: properties) { Self.blockKeys[$0] }
        if let conditions = values(Key.conditions), conditions.contains(where: { ListCondition(parsing: $0) == nil }) { return nil }
        if let sort = values(Key.sort), sort.contains(where: { Self.sort(parsing: $0) == nil }) { return nil }
        self.init(values: values)
    }

    /// The block's body with this list written in, over the body it has now: only the keys
    /// that changed are rewritten, each in the block's own way (its spelling of the key, its
    /// values as written), and every other line stays as it is. Keys it no longer sets are
    /// removed; new ones go at the end, in the usual order.
    public func blockBody(over body: String) -> String {
        let current = ListDefinition(block: body)
        let before = Dictionary((current?.properties ?? []).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        // The block's own spelling of each key it has, by the list note's key.
        var spelled: [String: String] = [:]
        for property in Self.blockProperties(body, strict: false) ?? [] {
            if let key = Self.blockKeys[property.key.lowercased()], spelled[key] == nil { spelled[key] = property.key }
        }
        let blockKey = Dictionary(uniqueKeysWithValues: Self.blockKeys.map { ($1, $0) })

        var text = Self.wrapped(body)
        for (key, values, isList) in properties
        where before[key]?.values != values || before[key]?.isList != isList || spelled[key] == nil {
            guard let frontmatter = Frontmatter.parse(text), let name = spelled[key] ?? blockKey[key] else { continue }
            var edit = frontmatter.edit(setting: name, to: values, isList: isList)
            // A key the block hadn't goes in its place in the usual order (from, tags, where,
            // match, sort, show), before the first that follows it, not at the end.
            if spelled[key] == nil, let following = Key.all.drop(while: { $0 != key }).dropFirst().lazy
                .compactMap({ later in spelled[later].flatMap { name in frontmatter.properties.first { $0.key == name } } }).first {
                edit = (NSRange(location: following.range.location, length: 0), Frontmatter.yaml(key: name, values: values, isList: isList))
            }
            text = (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
            spelled[key] = name
        }
        let kept = Set(properties.map(\.key))
        for (key, name) in spelled where !kept.contains(key) {
            guard let edit = Frontmatter.parse(text)?.edit(removing: name) else { continue }
            text = (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
        }
        return Self.unwrapped(text)
    }

    /// The whole block, fences and all, for a new list written into a note.
    public var block: String {
        "```\(Self.blockLanguage)\n" + blockBody(over: "") + "```\n"
    }

    // MARK: Reading the body

    /// The body's properties, read as frontmatter is. With `strict`, nil if any line isn't
    /// one of a list's keys (once each) or an item under one; blank lines and `#` comments
    /// are fine.
    static func blockProperties(_ body: String, strict: Bool = true) -> [Frontmatter.Property]? {
        guard let properties = Frontmatter.parse(wrapped(body))?.properties else { return nil }
        guard strict else { return properties }
        var seen: Set<String> = []
        for property in properties {
            let key = property.key.lowercased()
            guard blockKeys[key] != nil, seen.insert(key).inserted else { return nil }
        }
        var underKey = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            // An item under a key, or `key: …` (whose key was checked above).
            if content == "-" || content.hasPrefix("- ") {
                if underKey { continue } else { return nil }
            }
            if line.first == " " || line.first == "\t" || !content.contains(":") { return nil }
            underKey = true
        }
        return properties
    }

    /// The body inside `---` fences, so it reads, and edits, as frontmatter.
    static func wrapped(_ body: String) -> String {
        "---\n" + body + (body.isEmpty || body.hasSuffix("\n") ? "" : "\n") + "---\n"
    }

    static func unwrapped(_ text: String) -> String {
        String(text.dropFirst(4).dropLast(4))
    }
}

// MARK: Writing a list note

extension ListDefinition {
    /// What to write in a list note's properties to make it this list: each `list-` property
    /// that changed, by its spelling in the note, its values (nil: removed). A list with
    /// nothing left to choose by keeps an empty `list-where`, so it stays a list (of every
    /// note). Applied in order, as one edit.
    public func propertyChanges(over frontmatter: Frontmatter?) -> [(key: String, values: [String]?, isList: Bool)] {
        let current = ListDefinition(frontmatter: frontmatter)
        let spelled = Dictionary((frontmatter?.properties ?? []).map { ($0.key.lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
        let before = Dictionary((current?.properties ?? []).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [(key: String, values: [String]?, isList: Bool)] = []
        for (key, values, isList) in properties
        where before[key]?.values != values || before[key]?.isList != isList || spelled[key] == nil {
            changes.append((key, values, isList))
        }
        let kept = Set(properties.map(\.key))
        for key in Key.all where !kept.contains(key) && spelled[key] != nil {
            changes.append((key, nil, false))
        }
        if folders.isEmpty, tags.isEmpty, conditions.isEmpty {
            changes.removeAll { $0.key == Key.conditions }
            changes.append((Key.conditions, [], true))
        }
        return changes.map { (spelled[$0.key] ?? $0.key, $0.values, $0.isList) }
    }
    /// The same changes, made to a note's `text` as one replacement: what's different between
    /// the text before and after them, from the first line that changed to the last. Nil
    /// if this is the note's list already. For an editor that writes it as one step to undo.
    public func propertyEdit(in text: String) -> (range: NSRange, replacement: String)? {
        let frontmatter = text.hasPrefix("---") ? Frontmatter.parse(text) : nil
        guard self != ListDefinition(frontmatter: frontmatter) else { return nil }
        var edited = text
        for change in propertyChanges(over: frontmatter) {
            // Read again after each: the one before moved everything after it.
            let current = Frontmatter.parse(edited)
            var edit: (NSRange, String)
            if let values = change.values {
                edit = current?.edit(setting: change.key, to: values, isList: change.isList)
                    ?? Frontmatter.edit(adding: change.key, values: values, isList: change.isList)
                // A key the note hadn't goes with its list's others, before the first that
                // follows it in the usual order, not at the end of the frontmatter.
                let has = { (key: String) in current?.properties.first { $0.key.lowercased() == key } }
                if current != nil, has(change.key.lowercased()) == nil,
                   let following = Key.all.drop(while: { $0 != change.key.lowercased() }).dropFirst().lazy.compactMap(has).first {
                    edit = (NSRange(location: following.range.location, length: 0),
                            Frontmatter.yaml(key: change.key, values: values, isList: change.isList))
                }
            } else if let removal = current?.edit(removing: change.key) {
                edit = removal
            } else { continue }
            edited = (edited as NSString).replacingCharacters(in: edit.0, with: edit.1)
        }
        let old = text as NSString, new = edited as NSString
        guard old != new else { return nil }
        var start = 0
        while start < old.length, start < new.length, old.character(at: start) == new.character(at: start) { start += 1 }
        var end = 0
        while end < old.length - start, end < new.length - start,
              old.character(at: old.length - 1 - end) == new.character(at: new.length - 1 - end) { end += 1 }
        // Whole lines, so a character made of two (an emoji) is never split.
        start = old.lineRange(for: NSRange(location: start, length: 0)).location
        while end > 0, old.character(at: old.length - end - 1) != 0x0A { end -= 1 }
        return (NSRange(location: start, length: old.length - start - end),
                new.substring(with: NSRange(location: start, length: new.length - start - end)))
    }
}
