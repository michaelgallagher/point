import Foundation
import MarkdownKit

/// A change made to many notes at once (a property, a value or a tag renamed everywhere),
/// kept so it can be undone: each note's text before and after.
public struct VaultChange: Sendable, Equatable {
    public struct Edit: Sendable, Equatable {
        public let noteID: String
        public let url: URL
        public let before: String
        public let after: String
    }

    /// What was changed, for saying so ("Renamed “status” to “state”").
    public var name: String
    public var edits: [Edit] = []
    /// Notes changed (by someone else) while being updated: left alone.
    public var skippedNotes: [String] = []
    /// Notes that couldn't be read (not downloaded, or not UTF-8): not updated.
    public var unreadNotes: [String] = []
    /// Notes left alone because the change would have clashed with what's in them (a
    /// property renamed to a name the note already uses).
    public var clashingNotes: [String] = []

    public var updatedNotes: [String] { edits.map(\.noteID) }

    public init(name: String) { self.name = name }
}

/// Changes across the vault: each note read, changed, and written only if it's still as read,
/// so nothing anyone else wrote meanwhile is lost; and undone the same way.
public enum VaultChanges {
    /// A change that can't be made to a note without losing something.
    public struct Clash: Error {}

    /// Applies `transform` to every note in `notes` (nil: no change to it). Notes are written
    /// in place, as a save is, and only if unchanged since read.
    public static func apply(_ name: String, to notes: [Note], _ transform: (String) throws -> String?) -> VaultChange {
        var change = VaultChange(name: name)
        for note in notes {
            guard let text = try? NoteReader.read(contentsOf: note.url) else { change.unreadNotes.append(note.id); continue }
            let changed: String?
            do { changed = try transform(text) } catch { change.clashingNotes.append(note.id); continue }
            guard let changed, changed != text else { continue }
            switch try? NoteWriter.write(changed, to: note.url, expecting: text, ifChanged: .report) {
            case .saved?: change.edits.append(VaultChange.Edit(noteID: note.id, url: note.url, before: text, after: changed))
            default: change.skippedNotes.append(note.id)
            }
        }
        return change
    }

    /// Puts each note back as it was, if it's still as the change left it. Returns the notes
    /// that weren't (changed since): those keep their changes.
    @discardableResult
    public static func undo(_ change: VaultChange) -> [String] {
        var missed: [String] = []
        for edit in change.edits {
            switch try? NoteWriter.write(edit.before, to: edit.url, expecting: edit.after, ifChanged: .report) {
            case .saved?: continue
            default: missed.append(edit.noteID)
            }
        }
        return missed
    }

    // MARK: The changes

    /// A note's text with the property `key` (in any case) renamed to `newKey`, its value and
    /// everything else as it was. Nil if it has no such property. Throws `Clash` if it already
    /// has a property called `newKey` (another than `key` in another case).
    public static func renamingProperty(_ key: String, to newKey: String, in text: String) throws -> String? {
        let newName = newKey.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, let frontmatter = Frontmatter.parse(text) else { return nil }
        let matching = frontmatter.properties.filter { $0.key.lowercased() == key.lowercased() && $0.key != newName }
        guard !matching.isEmpty else { return nil }
        if newName.lowercased() != key.lowercased(), frontmatter.properties.contains(where: { $0.key.lowercased() == newName.lowercased() }) {
            throw Clash()
        }
        let ns = NSMutableString(string: text)
        for property in matching.sorted(by: { $0.range.location > $1.range.location }) {
            let line = ns.lineRange(for: NSRange(location: property.range.location, length: 0))
            let colon = ns.range(of: ":", range: line)
            guard colon.location != NSNotFound else { continue }
            ns.replaceCharacters(in: NSRange(location: line.location, length: colon.location - line.location), with: Frontmatter.written(key: newName))
        }
        return ns as String
    }

    /// A note's text with `value` (in any case) given to the property `key` changed to
    /// `newValue`, written as the note writes its values. A list that has `newValue` already
    /// keeps it once. Nil if the note doesn't give the property that value. For tags, use
    /// `renamingTag`, which renames them in the text too.
    public static func renamingValue(_ value: String, to newValue: String, ofProperty key: String, in text: String) -> String? {
        let replacement = newValue.trimmingCharacters(in: .whitespaces)
        guard let frontmatter = Frontmatter.parse(text) else { return nil }
        let wanted = value.trimmingCharacters(in: .whitespaces).lowercased()
        let ns = NSMutableString(string: text)
        var changed = false
        for property in frontmatter.properties.reversed() where property.key.lowercased() == key.lowercased() {
            guard property.values.contains(where: { $0.lowercased() == wanted }) else { continue }
            var values: [String] = []
            for item in property.values {
                let new = item.lowercased() == wanted ? replacement : item
                if property.isList, values.contains(where: { $0.lowercased() == new.lowercased() }) { continue }
                values.append(new)
            }
            if property.isList { values.removeAll { $0.isEmpty } }
            ns.replaceCharacters(in: property.range, with: rewritten(property, values: values))
            changed = true
        }
        return changed ? ns as String : nil
    }

    /// A note's text with the tag `tag` renamed to `newTag`, and tags nested under it too
    /// (`work/point` becomes `job/point`), in its properties and its text. Matched in any
    /// case. Nil if it has no such tag.
    public static func renamingTag(_ tag: String, to newTag: String, in text: String) -> String? {
        func clean(_ tag: String) -> String { tag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
        let old = clean(tag).lowercased(), new = clean(newTag)
        guard !old.isEmpty, !new.isEmpty else { return nil }
        func renamed(_ tag: String) -> String? {
            let lowered = tag.lowercased()
            if lowered == old { return new }
            if lowered.hasPrefix(old + "/") { return new + tag.dropFirst(old.count) }
            return nil
        }
        var replacements: [(NSRange, String)] = []
        let ns = text as NSString
        // In the text: `#work/point`.
        for token in MarkdownParser.parse(text) {
            guard case .tag(let name) = token.kind, let new = renamed(name) else { continue }
            replacements.append((token.range, "#" + new))
        }
        // In the properties: `tags: [work]`, `tags: work ideas`, or a list.
        if let frontmatter = Frontmatter.parse(text) {
            for property in frontmatter.properties where ["tags", "tag"].contains(property.key.lowercased()) {
                let items = property.isList ? property.values : property.values.flatMap { $0.split(separator: " ").map(String.init) }
                var changed = false
                var values: [String] = []
                for item in items {
                    let hash = item.hasPrefix("#") ? "#" : ""
                    let new = renamed(clean(item)).map { hash + $0 } ?? item
                    if new != item { changed = true }
                    if values.contains(where: { clean($0).lowercased() == clean(new).lowercased() }) { continue }
                    values.append(new)
                }
                guard changed else { continue }
                replacements.append((property.range, rewritten(property, values: property.isList ? values : [values.joined(separator: " ")])))
            }
        }
        guard !replacements.isEmpty else { return nil }
        let result = NSMutableString(string: ns)
        for (range, text) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: text)
        }
        return result as String
    }

    /// A property's lines with new values, written as it writes them: its key as it was
    /// (quoted, say), a list in brackets kept in brackets, and each value it had as written.
    static func rewritten(_ property: Frontmatter.Property, values: [String]) -> String {
        let key = String(property.written.prefix { $0 != ":" })
        let firstLine = property.written.prefix { $0 != "\n" }
        if property.isList, firstLine.contains("[") {
            let quote = property.rawValues.first?.first.flatMap { $0 == "\"" || $0 == "'" ? $0 : nil }
            let items = values.map { value -> String in
                if let index = property.values.firstIndex(of: value), property.rawValues.indices.contains(index) { return property.rawValues[index] }
                return value.contains(",") && quote == nil ? Frontmatter.quoted(value, preferring: "\"") : Frontmatter.quoted(value, preferring: quote)
            }
            return key + ": [" + items.joined(separator: ", ") + "]\n"
        }
        let yaml = Frontmatter.yaml(key: property.key, values: values, isList: property.isList, like: property)
        return key + yaml.drop { $0 != ":" }
    }
}
