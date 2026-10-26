import Foundation

/// Obsidian's core Templates plugin, and its daily notes.
public enum Templates {
    /// Fills in `{{title}}`, `{{date}}`, `{{time}}` and `{{date:FORMAT}}` / `{{time:FORMAT}}`,
    /// as Obsidian's core Templates plugin does. Anything else, including Templater's
    /// `<% %>` code, is left exactly as written.
    public static func render(_ template: String, title: String, date: Date = Date(), settings: ObsidianSettings) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let inside = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            let parts = inside.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            switch parts[0].lowercased() {
            case "title":
                result += title
            case "date":
                result += MomentFormat(parts.count > 1 ? parts[1] : settings.templatesDateFormat).string(from: date)
            case "time":
                result += MomentFormat(parts.count > 1 ? parts[1] : settings.templatesTimeFormat).string(from: date)
            default:
                result += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    /// A template applied to a note: its properties merged into the note's, and its body.
    public struct Application: Equatable, Sendable {
        /// The note's frontmatter block (`frontmatterRange`) and the text to replace it with:
        /// the note's properties, with the template's it didn't have added after them, and
        /// lists the two share combined. Where the note had no frontmatter, the range is empty,
        /// at its start. Nil when the template has no properties.
        public var frontmatterRange: NSRange?
        public var frontmatter: String?
        /// The template without its frontmatter, to insert where the cursor is.
        public var body: String
    }

    /// Applies a filled-in template to a note's text. The note's own values win: a property
    /// it has keeps its value, except that a list (tags, say) gains the template's items it
    /// doesn't have. Properties only the template has are added, written as in the template.
    public static func merge(_ rendered: String, into note: String) -> Application {
        let ns = rendered as NSString
        guard let template = Frontmatter.parse(rendered) else { return Application(body: rendered) }
        // The body starts after the closing fence's line break.
        var bodyStart = NSMaxRange(template.range)
        if bodyStart < ns.length, ns.character(at: bodyStart) == 0x0A { bodyStart += 1 }
        let body = ns.substring(from: bodyStart)
        guard !template.properties.isEmpty else { return Application(body: body) }

        guard let existing = Frontmatter.parse(note) else {
            // No properties yet: the template's block, as written, at the start.
            return Application(frontmatterRange: NSRange(location: 0, length: 0),
                               frontmatter: ns.substring(with: template.range) + "\n", body: body)
        }
        var head = (note as NSString).substring(with: existing.range)
        for property in template.properties {
            guard let current = Frontmatter.parse(head) else { break }
            let shared = current.properties.first { $0.key.caseInsensitiveCompare(property.key) == .orderedSame }
            let edit: (NSRange, String)
            if let shared {
                let isList = shared.isList || property.isList || ["tags", "tag", "aliases", "alias"].contains(shared.key.lowercased())
                guard isList else { continue } // The note's value wins.
                let added = property.values.filter { value in !shared.values.contains { $0.caseInsensitiveCompare(value) == .orderedSame } }
                guard !added.isEmpty || !shared.isList else { continue }
                edit = current.edit(setting: shared.key, to: shared.values + added, isList: true)
            } else {
                var lines = ns.substring(with: property.range)
                if !lines.hasSuffix("\n") { lines += "\n" }
                edit = (NSRange(location: current.closingFenceLocation, length: 0), lines)
            }
            head = (head as NSString).replacingCharacters(in: edit.0, with: edit.1)
        }
        return Application(frontmatterRange: existing.range, frontmatter: head, body: body)
    }

    /// The templates in the vault's templates folder, by name.
    public static func available(in root: URL, settings: ObsidianSettings) -> [(name: String, url: URL)] {
        guard !settings.templatesFolder.isEmpty else { return [] }
        let folder = root.appendingPathComponent(settings.templatesFolder)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Where today's daily note lives (whether or not it exists yet).
    public static func dailyNoteURL(for date: Date = Date(), in root: URL, settings: ObsidianSettings) -> URL {
        // The format can include folders, such as `YYYY/MM/YYYY-MM-DD`.
        let name = MomentFormat(settings.dailyNotesFormat).string(from: date)
        let folder = settings.dailyNotesFolder.isEmpty ? root : root.appendingPathComponent(settings.dailyNotesFolder)
        return folder.appendingPathComponent(name + ".md")
    }

    /// The daily note's starting text, from its template if one is set.
    public static func dailyNoteText(for date: Date = Date(), title: String, in root: URL, settings: ObsidianSettings) -> String {
        guard !settings.dailyNotesTemplate.isEmpty else { return "" }
        var path = settings.dailyNotesTemplate
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        guard let template = try? NoteReader.read(contentsOf: root.appendingPathComponent(path)) else { return "" }
        return render(template, title: title, date: date, settings: settings)
    }
}
