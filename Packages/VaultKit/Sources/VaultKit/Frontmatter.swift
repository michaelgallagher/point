import Foundation

/// A note's YAML frontmatter, read and edited without disturbing anything else in it.
///
/// Only the simple YAML Obsidian writes is understood: `key: value`, `key: [a, b]` and
/// `key:` followed by `  - item` lines. Anything else is kept exactly as it is and shown
/// as raw text. Edits rewrite only the lines of the property being changed.
public struct Frontmatter: Equatable, Sendable {
    public struct Property: Equatable, Sendable, Identifiable {
        public var key: String
        /// The value as shown: a single value, or the items of a list.
        public var values: [String]
        public var isList: Bool
        /// Where the property's lines are in the note (UTF-16 offsets), including line breaks.
        public var range: NSRange
        public var id: String { key }
    }

    /// The whole block, from the opening `---` through the closing one.
    public var range: NSRange
    /// The text between the fences.
    public var body: String
    public var properties: [Property]

    /// Finds frontmatter at the very start of a note.
    public static func parse(_ text: String) -> Frontmatter? {
        let ns = text as NSString
        var start = 0
        if ns.length > 0, ns.character(at: 0) == 0xFEFF { start = 1 }
        let firstLine = ns.lineRange(for: NSRange(location: start, length: 0))
        guard ns.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }

        var location = NSMaxRange(firstLine)
        var lines: [NSRange] = []
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if content == "---" || content == "..." {
                var contentsEnd = 0, end = 0, lineStart = 0
                ns.getLineStart(&lineStart, end: &end, contentsEnd: &contentsEnd, for: line)
                let range = NSRange(location: 0, length: contentsEnd)
                let bodyRange = NSRange(location: NSMaxRange(firstLine), length: line.location - NSMaxRange(firstLine))
                return Frontmatter(range: range, body: ns.substring(with: bodyRange), properties: properties(in: lines, of: ns))
            }
            lines.append(line)
            location = NSMaxRange(line)
        }
        return nil
    }

    private static func properties(in lines: [NSRange], of text: NSString) -> [Property] {
        var properties: [Property] = []
        for line in lines {
            let raw = text.substring(with: line)
            let content = raw.trimmingCharacters(in: .newlines)
            if content.hasPrefix(" ") || content.hasPrefix("\t") || content.hasPrefix("-") {
                // A continuation: a list item belonging to the property above.
                guard var last = properties.popLast() else { continue }
                let item = content.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") || item == "-" {
                    last.values.append(unquote(String(item.dropFirst(item == "-" ? 1 : 2))))
                    last.isList = true
                }
                last.range = NSUnionRange(last.range, line)
                properties.append(last)
                continue
            }
            guard let colon = content.firstIndex(of: ":"), !content.hasPrefix("#") else { continue }
            let key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            var property = Property(key: key, values: [], isList: false, range: line)
            if value.hasPrefix("["), value.hasSuffix("]") {
                property.isList = true
                property.values = value.dropFirst().dropLast().split(separator: ",")
                    .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
            } else if !value.isEmpty {
                property.values = [unquote(value)]
            } else {
                property.isList = false // `key:` alone; becomes a list if items follow.
            }
            properties.append(property)
        }
        return properties
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// The tags listed under `tags:` (or Obsidian's older `tag:`), without `#`.
    public var tags: [String] {
        properties.filter { $0.key == "tags" || $0.key == "tag" }
            .flatMap { $0.isList ? $0.values : $0.values.flatMap { $0.split(separator: " ").map(String.init) } }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    // MARK: Editing

    /// The text of a property, written the way Obsidian writes it.
    public static func yaml(key: String, values: [String], isList: Bool) -> String {
        if isList {
            return "\(key):\n" + values.map { "  - \(quoteIfNeeded($0))\n" }.joined()
        }
        return "\(key): \(values.first.map(quoteIfNeeded) ?? "")\n"
    }

    static func quoteIfNeeded(_ value: String) -> String {
        let special = CharacterSet(charactersIn: ":#[]{},&*!|>'\"%@`")
        let needsQuotes = value.unicodeScalars.contains { special.contains($0) } || value.hasPrefix(" ") || value.hasSuffix(" ")
        return needsQuotes ? "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"" : value
    }

    /// The edit that sets a property's values: the range to replace and its new text.
    /// A new property goes at the end of the block.
    public func edit(setting key: String, to values: [String], isList: Bool? = nil) -> (NSRange, String) {
        if let existing = properties.first(where: { $0.key == key }) {
            return (existing.range, Self.yaml(key: key, values: values, isList: isList ?? existing.isList))
        }
        let closingFence = closingFenceLocation
        return (NSRange(location: closingFence, length: 0), Self.yaml(key: key, values: values, isList: isList ?? (values.count > 1)))
    }

    /// The edit that removes a property.
    public func edit(removing key: String) -> (NSRange, String)? {
        properties.first { $0.key == key }.map { ($0.range, "") }
    }

    /// The edit that renames a property: the range of its name on its first line, and the new
    /// name. Its value, and every other line, stay as they are. Nil if the new name is empty,
    /// unchanged or already used.
    public func edit(renaming key: String, to newKey: String, in text: String) -> (NSRange, String)? {
        let name = newKey.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != key, !properties.contains(where: { $0.key == name }),
              let property = properties.first(where: { $0.key == key }) else { return nil }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: property.range.location, length: 0))
        let colon = ns.range(of: ":", range: line)
        guard colon.location != NSNotFound else { return nil }
        // A name YAML would misread (a colon and space, a leading # or quote) is quoted.
        let needsQuotes = name.contains(": ") || name.hasSuffix(":") || name.first.map { "#'\"[{&*!|>%@`-?".contains($0) } == true
        let written = needsQuotes ? "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\"" : name
        return (NSRange(location: line.location, length: colon.location - line.location), written)
    }

    /// The edit that moves a property to a new place among the others: the range to
    /// replace and its new text. `destination` is an index into `properties` before the
    /// move, as in SwiftUI's `onMove` (the property goes in front of the one there, or last).
    /// Only the lines between the old and new places are rewritten, each exactly as it was.
    public func edit(moving key: String, to destination: Int, in text: String) -> (NSRange, String)? {
        guard let source = properties.firstIndex(where: { $0.key == key }),
              (0...properties.count).contains(destination),
              destination != source, destination != source + 1 else { return nil }
        let ns = text as NSString
        let moved = properties[source].range
        let movedText = ns.substring(with: moved)
        if destination < source {
            let start = properties[destination].range.location
            let between = ns.substring(with: NSRange(location: start, length: moved.location - start))
            return (NSRange(location: start, length: NSMaxRange(moved) - start), movedText + between)
        } else {
            let end = NSMaxRange(properties[destination - 1].range)
            let between = ns.substring(with: NSRange(location: NSMaxRange(moved), length: end - NSMaxRange(moved)))
            return (NSRange(location: moved.location, length: end - moved.location), between + movedText)
        }
    }

    /// Where the closing `---` line starts.
    var closingFenceLocation: Int {
        NSMaxRange(range) - 3
    }

    /// The edit that adds frontmatter to a note that has none.
    public static func edit(adding key: String, values: [String], isList: Bool) -> (NSRange, String) {
        (NSRange(location: 0, length: 0), "---\n" + yaml(key: key, values: values, isList: isList) + "---\n")
    }
}
