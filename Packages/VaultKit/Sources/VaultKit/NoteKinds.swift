import Foundation

/// Kinds of note: what a note is (a meeting, a book, an article), as its `type` property says.
/// Kept in the vault's `.point/kinds.json`, in the order they're offered:
///
/// ```json
/// {
///   "kinds": [
///     {"name": "Meeting", "symbol": "person.2", "templates": ["Meeting template", "1-1 template"]},
///     {"name": "Book", "symbol": "book", "folder": "Sources", "templates": ["Book template"]},
///     {"name": "Article", "symbol": "doc.richtext", "folder": "Clippings", "templates": ["Media template"]}
///   ]
/// }
/// ```
///
/// A kind's name is the value of `type` (or `property`, if set) on its notes. New notes of a
/// kind start from its first template, or another of its templates, and go in its folder (the
/// vault root, if none). Several kinds can share a template. A kind with no templates isn't
/// offered for new notes, but is still known: `type` offers it, and its symbol shows.
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

        public var id: String { name }

        public init(name: String, symbol: String? = nil, folder: String? = nil, templates: [String]? = nil) {
            self.name = name
            self.symbol = symbol
            self.folder = folder
            self.templates = templates
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
    /// kind, unless the template sets it already, everything else as the template has it.
    public func text(for kind: Kind, from rendered: String = "") -> String {
        guard let frontmatter = Frontmatter.parse(rendered) else {
            return Frontmatter.edit(adding: property, values: [kind.name], isList: false).1 + rendered
        }
        let existing = frontmatter.properties.first { $0.key.caseInsensitiveCompare(property) == .orderedSame }
        if let existing, !(existing.values.first ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return rendered }
        let (range, replacement) = frontmatter.edit(setting: existing?.key ?? property, to: [kind.name], isList: false)
        return (rendered as NSString).replacingCharacters(in: range, with: replacement)
    }

    /// `type` as a choice of the kinds, for the properties to offer them. Nil if there are none.
    public var choice: PointTypes.Definition? {
        kinds.isEmpty ? nil : PointTypes.Definition(type: .choice, choices: kinds.map(\.name))
    }
}
