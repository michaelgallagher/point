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
