import Foundation

/// Kinds of note: what a note is (a meeting, a book, an article), as its `type` property says.
/// Kept in the vault's `.point/kinds.json`, in the order they're offered:
///
/// ```json
/// {
///   "kinds": [
///     {"name": "Meeting", "symbol": "person.2", "templates": ["Meeting template", "1-1 template"]},
///     {"name": "Media", "symbol": "books.vertical", "folder": "Clippings", "templates": ["Media template", "Book template"],
///      "detail": ["topics"], "read": "read"}
///   ]
/// }
/// ```
///
/// A kind's name is the value of `type` (or `property`, if set) on its notes. New notes of a
/// kind start from its first template, or another of its templates, and go in its folder (the
/// vault root, if none). Several kinds can share a template. A kind with no templates isn't
/// offered for new notes, but is still known: `type` offers it, and its symbol shows.
/// A kind can also say how its notes look in note lists: `detail`, the properties whose
/// values show under the title (the first that has any), and `read`, the property whose
/// absence marks a note unread.
/// Nothing here is written into notes beyond `type` itself, so other apps read them as before.
public struct NoteKinds: Sendable, Equatable {
    public struct Kind: Codable, Sendable, Equatable, Identifiable {
        public var name: String
        /// An SF Symbol.
        public var symbol: String?
        /// Where new notes of this kind go: a folder's path, or the vault root if unset.
        public var folder: String?
        /// The templates new notes start from, by name in the templates folder; the first is
        /// the usual one.
        public var templates: [String]?
        /// What a note list shows under the titles of notes of this kind: the first of these
        /// properties that has a value (`["people", "topics"]`: the people, or the topics when
        /// nobody's named).
        public var detail: [String]?
        /// The property that says a note of this kind has been read (`read`): while it isn't
        /// set, note lists mark the note unread.
        public var read: String?

        public var id: String { name }

        public init(name: String, symbol: String? = nil, folder: String? = nil, templates: [String]? = nil,
                    detail: [String]? = nil, read: String? = nil) {
            self.name = name
            self.symbol = symbol
            self.folder = folder
            self.templates = templates
            self.detail = detail
            self.read = read
        }

        /// Its symbol, or a plain page.
        public var shownSymbol: String { symbol ?? "doc.text" }
    }

    private struct File: Codable {
        var property: String?
        var kinds: [Kind]?
    }

    /// The property that says what a note is.
    public var property: String
    public var kinds: [Kind]

    public init(property: String = "type", kinds: [Kind] = []) {
        self.property = property
        self.kinds = kinds
    }

    public var isEmpty: Bool { kinds.isEmpty }

    public static func file(in root: URL) -> URL {
        root.appendingPathComponent(".point").appendingPathComponent("kinds.json")
    }

    /// The vault's kinds, or none if it has no file (or one that can't be read).
    public static func load(vault root: URL) -> NoteKinds {
        guard let data = try? Data(contentsOf: file(in: root)), let file = try? JSONDecoder().decode(File.self, from: data) else {
            return NoteKinds()
        }
        let property = file.property?.trimmingCharacters(in: .whitespaces) ?? ""
        // A kind without a name can't be told apart, and the first of two the same is the one.
        var seen = Set<String>()
        let kinds = (file.kinds ?? []).filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0.name.lowercased()).inserted }
        return NoteKinds(property: property.isEmpty ? "type" : property, kinds: kinds)
    }

    /// A kind, by name in any case.
    public func kind(named name: String) -> Kind? {
        let name = name.trimmingCharacters(in: .whitespaces)
        return kinds.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The kind a note's text says it is, if it's one of these.
    public func kind(of text: String) -> Kind? {
        guard !kinds.isEmpty, let frontmatter = Frontmatter.parse(text),
              let value = frontmatter.properties.first(where: { $0.key.caseInsensitiveCompare(property) == .orderedSame })?.values.first else { return nil }
        return kind(named: value)
    }

    // MARK: In note lists

    /// How a note shows in a note list, by its kind: whether it's unread, and the values under
    /// its title.
    public struct ListLook: Sendable, Equatable {
        public var isUnread: Bool
        public var detail: [String]
        /// The property that says the note's been read, if its kind has one: what marking it
        /// read or unread changes.
        public var readProperty: String?

        public init(isUnread: Bool = false, detail: [String] = [], readProperty: String? = nil) {
            self.isUnread = isUnread
            self.detail = detail
            self.readProperty = readProperty
        }

        /// Shown, and acted on, as any other note.
        public var isPlain: Bool { !isUnread && detail.isEmpty && readProperty == nil }
    }

    /// Whether any kind changes how its notes look in note lists.
    public var changesListLook: Bool {
        kinds.contains { !($0.detail ?? []).isEmpty || !($0.read ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The properties to know about each note, in lowercase, to work out its look: what it is,
    /// and each kind's detail and read properties.
    public var listLookProperties: [String] {
        guard changesListLook else { return [] }
        var names = [property.lowercased()]
        for kind in kinds {
            for name in (kind.detail ?? []) + [kind.read].compactMap({ $0 }) {
                let name = name.trimmingCharacters(in: .whitespaces).lowercased()
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// A note's look in note lists, from its properties' values (by name in lowercase, as the
    /// index gives them). Nil when its kind changes nothing, or it has none.
    public func listLook(values: [String: [String]]) -> ListLook? {
        func given(_ name: String) -> [String] {
            (values[name.trimmingCharacters(in: .whitespaces).lowercased()] ?? [])
                .map(Self.shownValue).filter { !$0.isEmpty }
        }
        guard let name = given(property).first, let kind = kind(named: name) else { return nil }
        var look = ListLook()
        if let read = kind.read?.trimmingCharacters(in: .whitespaces), !read.isEmpty {
            look.readProperty = read
            look.isUnread = given(read).isEmpty
        }
        for name in kind.detail ?? [] {
            let shown = given(name)
            if !shown.isEmpty { look.detail = shown; break }
        }
        return look.isPlain ? nil : look
    }

    /// A day as a note's properties have it: `2026-11-19`.
    public static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The note with `property` set to `date` (`2026-11-19`), as read that day, unless it says
    /// it's read already: filled in where it's empty or `false` (as a template leaves it), or
    /// added at the end of the properties. The rest of the file stays exactly as it was.
    public static func markingRead(_ text: String, property: String, on date: String) -> String {
        let edit: (NSRange, String)
        if let frontmatter = Frontmatter.parse(text) {
            let existing = frontmatter.properties.first { $0.key.caseInsensitiveCompare(property) == .orderedSame }
            if let existing, existing.values.contains(where: { !shownValue($0).isEmpty }) { return text }
            edit = frontmatter.edit(setting: existing?.key ?? property, to: [date], isList: false)
        } else {
            edit = Frontmatter.edit(adding: property, values: [date], isList: false)
        }
        return (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
    }

    /// The note with `property` emptied, so it's unread again: `read:` kept, with nothing after
    /// it, where a template puts it. A note that doesn't say it's read stays as it is.
    public static func markingUnread(_ text: String, property: String) -> String {
        guard let frontmatter = Frontmatter.parse(text),
              let existing = frontmatter.properties.first(where: { $0.key.caseInsensitiveCompare(property) == .orderedSame }),
              existing.values.contains(where: { !shownValue($0).isEmpty }) else { return text }
        let edit = frontmatter.edit(setting: existing.key, to: [], isList: false)
        return (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
    }

    /// A value as a list shows it: a link by its name (or the text it's shown as), not its
    /// brackets; `false` and `no` as nothing, so `read: false` is unread.
    static func shownValue(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespaces)
        if ["false", "no"].contains(value.lowercased()) { return "" }
        if value.hasPrefix("[["), value.hasSuffix("]]"), value.count > 4 {
            let inside = String(value.dropFirst(2).dropLast(2))
            value = inside.split(separator: "|", maxSplits: 1).last.map(String.init) ?? inside
            if let hash = value.firstIndex(of: "#"), hash != value.startIndex { value = String(value[..<hash]) }
            value = value.split(separator: "/").last.map(String.init) ?? value
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// The kinds that new notes can be made as: those with a template.
    public var offered: [Kind] { kinds.filter { !($0.templates ?? []).isEmpty } }

    /// A kind's templates that are in the templates folder (`available`, as `Templates.available`
    /// gives them), in the kind's order, each with a short label: its name less a closing
    /// "template" ("1-1 template" is "1-1").
    public static func templates(of kind: Kind, among available: [(name: String, url: URL)]) -> [(label: String, url: URL)] {
        (kind.templates ?? []).compactMap { wanted in
            guard let found = available.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else { return nil }
            return (label(forTemplate: found.name), found.url)
        }
    }

    static func label(forTemplate name: String) -> String {
        let suffix = " template"
        guard name.lowercased().hasSuffix(suffix), name.count > suffix.count else { return name }
        return String(name.dropLast(suffix.count))
    }

    /// A new note's text, from a template filled in (or nothing): with `property` set to the
    /// kind, unless the template sets it already, everything else as the template has it. A
    /// `property` Point adds goes first, where the vault keeps it.
    public func text(for kind: Kind, from rendered: String = "") -> String {
        guard let frontmatter = Frontmatter.parse(rendered) else {
            return Frontmatter.edit(adding: property, values: [kind.name], isList: false).1 + rendered
        }
        let existing = frontmatter.properties.first { $0.key.caseInsensitiveCompare(property) == .orderedSame }
        if let existing, !(existing.values.first ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return rendered }
        let key = existing?.key ?? property
        let (range, replacement) = frontmatter.edit(setting: key, to: [kind.name], isList: false)
        let set = (rendered as NSString).replacingCharacters(in: range, with: replacement)
        guard existing == nil, let added = Frontmatter.parse(set),
              let (moveRange, moved) = added.edit(moving: key, to: 0, in: set) else { return set }
        return (set as NSString).replacingCharacters(in: moveRange, with: moved)
    }

    /// A kind's name for many of them, as the sidebar lists it: Meetings, Daily notes, People.
    /// Only the last word changes; words that are the same for many (Media) stay as they are.
    public static func plural(_ name: String) -> String {
        guard let range = name.range(of: #"[A-Za-z]+$"#, options: .regularExpression) else { return name }
        let word = String(name[range])
        let lower = word.lowercased()
        let same: Set<String> = ["media", "news", "series", "species", "data", "info", "information", "music", "software",
                                 "research", "feedback", "advice", "equipment", "reading", "writing", "admin"]
        let irregular = ["person": "people", "child": "children", "man": "men", "woman": "women", "analysis": "analyses",
                         "thesis": "theses", "index": "indexes", "quiz": "quizzes"]
        var plural: String
        if same.contains(lower) || lower.hasSuffix("s") && lower.count > 3 && !lower.hasSuffix("ss") && !lower.hasSuffix("us") && !lower.hasSuffix("is") {
            return name // Already plural (Notes), or the same for many.
        } else if let found = irregular[lower] {
            plural = found
        } else if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) {
            plural = String(lower.dropLast()) + "ies"
        } else if ["s", "x", "z", "ch", "sh"].contains(where: lower.hasSuffix) {
            plural = lower + "es"
        } else {
            plural = lower + "s"
        }
        // In the word's own case: Person is People, PERSON is PEOPLE.
        if word == word.uppercased(), word.count > 1 { plural = plural.uppercased() }
        else if word.first?.isUppercase == true { plural = plural.prefix(1).uppercased() + plural.dropFirst() }
        return name.replacingCharacters(in: range, with: plural)
    }

    /// The kind people's notes are (Person, or People), if the vault has one: a property of
    /// the person kind suggests notes of it.
    public var personKind: Kind? {
        kinds.first { ["person", "people"].contains($0.name.lowercased()) }
    }

    /// `type` as a choice of the kinds, for the properties to offer them. Nil if there are none.
    public var choice: PointTypes.Definition? {
        kinds.isEmpty ? nil : PointTypes.Definition(type: .choice, choices: kinds.map(\.name))
    }
}
