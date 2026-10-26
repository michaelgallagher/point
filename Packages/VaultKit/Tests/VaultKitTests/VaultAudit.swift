import Foundation
import Testing
@testable import VaultKit

/// A read-only audit of a real vault, for using Point with it safely (see
/// `plan/live-vault-safety.md`, phase 1). Runs only when `POINT_AUDIT_VAULT` names a
/// vault folder; writes a Markdown report to `POINT_AUDIT_REPORT`. It never writes to the
/// vault, and skips notes iCloud hasn't downloaded (reading them would download them).
struct VaultAudit {
    @Test func audit() throws {
        guard let path = ProcessInfo.processInfo.environment["POINT_AUDIT_VAULT"] else { return }
        let root = URL(fileURLWithPath: path)
        let reportURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["POINT_AUDIT_REPORT"] ?? NSTemporaryDirectory() + "vault-audit.md")
        var report = Report()
        let notes = try VaultScanner.scan(root)
        report.count("Notes", notes.count)

        var texts: [(Note, String)] = []
        for note in notes {
            let values = try? note.url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current, status != .downloaded,
               !FileManager.default.fileExists(atPath: note.url.path) {
                report.add("Not downloaded (skipped)", note.id)
                continue
            }
            do {
                texts.append((note, try NoteReader.read(contentsOf: note.url)))
            } catch NoteReader.ReadError.notLossless {
                report.add("Not UTF-8 (Point refuses to edit)", note.id)
            } catch {
                report.add("Unreadable", "\(note.id): \(error.localizedDescription)")
            }
        }
        report.count("Notes read", texts.count)

        // MARK: Text

        for (note, text) in texts {
            let ns = text as NSString
            if text.hasPrefix("\u{FEFF}") { report.add("Starts with a byte-order mark", note.id) }
            if text.contains("\r\n") { report.add("Windows line endings (CRLF)", note.id) }
            else if text.contains("\r") { report.add("Old Mac line endings (CR)", note.id) }
            if ns.length > 0, !text.hasSuffix("\n") { report.tally("No line break at the end") }
            if text != text.precomposedStringWithCanonicalMapping { report.add("Not in Unicode NFC (decomposed accents)", note.id) }
        }

        // MARK: Frontmatter

        let types = PropertyTypes.load(vault: root)
        for (note, text) in texts {
            let startsWithFence = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).hasPrefix("---")
            guard let frontmatter = Frontmatter.parse(text) else {
                if startsWithFence { report.add("Starts with --- but no frontmatter found (unclosed?)", note.id) }
                continue
            }
            report.tally("Notes with frontmatter")
            let ns = text as NSString
            // Lines between the fences no property covers (comments, stray text): kept as they are.
            var covered = IndexSet()
            for property in frontmatter.properties { covered.insert(integersIn: property.range.location..<NSMaxRange(property.range)) }
            var keys: [String: Int] = [:]
            for property in frontmatter.properties { keys[property.key.lowercased(), default: 0] += 1 }
            if keys.values.contains(where: { $0 > 1 }) { report.add("Duplicate keys", note.id) }

            for property in frontmatter.properties {
                let lines = ns.substring(with: property.range)
                let firstLine = lines.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                let value = firstLine.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                if value.hasPrefix("[") { report.tally("Lists written [a, b]") }
                if value == "|" || value == ">" || value.hasPrefix("|-") || value.hasPrefix(">-") { report.add("Multi-line text values (| or >)", "\(note.id): \(property.key)") }
                if value.hasPrefix("{") { report.add("Map values written {a: b}", "\(note.id): \(property.key)") }
                if value.hasPrefix("&") || value.hasPrefix("*") { report.add("YAML anchors or aliases", "\(note.id): \(property.key)") }
                if value.hasPrefix("\"") || value.hasPrefix("'") { report.tally("Quoted values") }
                if value.isEmpty, !property.isList { report.tally("Empty values") }
                // Indented lines under a key that aren't list items: a nested map, or text.
                let continuation = lines.split(separator: "\n").dropFirst()
                if continuation.contains(where: { line in
                    let item = line.trimmingCharacters(in: .whitespaces)
                    return !item.isEmpty && !item.hasPrefix("- ") && item != "-"
                }) { report.add("Nested values under a key (a map, or wrapped text)", "\(note.id): \(property.key)") }
                if property.key.hasPrefix("\"") || property.key.hasPrefix("'") { report.add("Quoted keys", "\(note.id): \(property.key)") }

                // The round trip: the property written back with the value it has.
                let edit = frontmatter.edit(setting: property.key, to: property.values, isList: property.isList)
                let rewritten = ns.replacingCharacters(in: edit.0, with: edit.1)
                if rewritten != text {
                    let flowList = value.hasPrefix("[") && property.isList
                    let kind = flowList ? "Round trip: [a, b] list rewritten as - lines (planned)" : "Round trip: property changed by a no-op edit"
                    report.add(kind, "\(note.id): `\(lines.replacingOccurrences(of: "\n", with: "⏎"))` → `\(edit.1.replacingOccurrences(of: "\n", with: "⏎"))`")
                }
                if let type = types.type(forKey: property.key) { report.tally("Properties with a type in types.json: \(type.rawValue)") }
            }
            let body = NSRange(location: 0, length: NSMaxRange(frontmatter.range))
            var line = NSRange(location: 0, length: 0)
            var location = NSMaxRange(ns.lineRange(for: NSRange(location: 0, length: 0)))
            while location < NSMaxRange(body) {
                line = ns.lineRange(for: NSRange(location: location, length: 0))
                let content = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                if !covered.contains(line.location), !content.isEmpty, content != "---", content != "..." {
                    report.add("Frontmatter lines no property covers (kept as they are)", "\(note.id): `\(content)`")
                }
                location = NSMaxRange(line)
            }
        }

        // MARK: Names

        var byName: [String: [Note]] = [:]
        for note in notes { byName[note.title.lowercased(), default: []].append(note) }
        for (_, group) in byName where group.count > 1 {
            let titles = Set(group.map(\.title))
            report.add(titles.count > 1 ? "Names differing only in case" : "Same name in different folders", group.map(\.id).joined(separator: " · "))
        }
        let special = CharacterSet(charactersIn: "#^[]|:\\")
        for note in notes {
            if note.title.unicodeScalars.contains(where: special.contains) { report.add("Names with # ^ [ ] | : or \\", note.id) }
            if note.title != note.title.trimmingCharacters(in: .whitespaces) { report.add("Names starting or ending with a space", note.id) }
        }

        // MARK: Links

        let resolver = LinkResolver(notes: notes)
        let wiki = try NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]+)\]\]"#)
        let markdown = try NSRegularExpression(pattern: #"(?<!!)\[[^\]\n]*\]\(([^)\s]+)\)"#)
        for (note, text) in texts {
            let ns = text as NSString
            let frontmatterEnd = Frontmatter.parse(text).map { NSMaxRange($0.range) } ?? 0
            for match in wiki.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let embed = match.range(at: 1).length > 0
                let inner = ns.substring(with: match.range(at: 2))
                let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? inner
                var kinds: [String] = []
                if embed { kinds.append("embed ![[…]]") }
                if inner.contains("|") { kinds.append("alias [[…|…]]") }
                if target.contains("#^") { kinds.append("block [[…#^…]]") } else if target.contains("#") { kinds.append("heading [[…#…]]") }
                if target.contains("/") { kinds.append("path [[folder/…]]") }
                if match.range.location < frontmatterEnd { kinds.append("in frontmatter") }
                if kinds.isEmpty { kinds.append("plain [[…]]") }
                for kind in kinds { report.tally("Links: \(kind)") }
                let name = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
                if !name.isEmpty, !embed || name.lowercased().hasSuffix(".md") || !name.contains("."),
                   resolver.resolve(wikiTarget: name, from: note.id) == nil {
                    report.add("Links to notes that don't exist", "\(note.id) → [[\(name)]]\(match.range.location < frontmatterEnd ? " (in frontmatter)" : "")")
                }
                if !name.isEmpty, resolver.isAmbiguous(title: (name as NSString).lastPathComponent), !name.contains("/") {
                    report.add("Links to a name more than one note has", "\(note.id) → [[\(name)]]")
                }
            }
            for match in markdown.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let destination = ns.substring(with: match.range(at: 1))
                if destination.contains("://") || destination.hasPrefix("mailto:") { report.tally("Links: web [](…)") }
                else { report.tally("Links: Markdown to a file [](…)") }
            }
        }

        // MARK: Settings

        let folder = root.appendingPathComponent(".obsidian")
        func json(_ name: String) -> [String: Any]? {
            (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        if let app = json("app.json") {
            for key in ["newLinkFormat", "useMarkdownLinks", "attachmentFolderPath", "trashOption", "alwaysUpdateLinks", "newFileLocation", "newFileFolderPath"] {
                report.setting("app.json \(key)", app[key].map { "\($0)" } ?? "(Obsidian's default)")
            }
        }
        for (file, keys) in [("daily-notes.json", ["folder", "format", "template"]), ("templates.json", ["folder", "dateFormat", "timeFormat"])] {
            let object = json(file)
            for key in keys { report.setting("\(file) \(key)", object?[key].map { "\($0)" } ?? (object == nil ? "(no file)" : "(Obsidian's default)")) }
        }
        report.setting("types.json", json("types.json").map { "\((($0["types"] as? [String: Any]) ?? [:]).count) types" } ?? "(no file)")
        if let plugins = (try? Data(contentsOf: folder.appendingPathComponent("community-plugins.json"))).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String] }) {
            report.setting("Community plugins", plugins.joined(separator: ", "))
        }
        if let core = json("core-plugins.json") {
            report.setting("Core plugins on", core.filter { ($0.value as? Bool) == true }.map(\.key).sorted().joined(separator: ", "))
        }

        try report.markdown(vault: root.lastPathComponent).write(to: reportURL, atomically: true, encoding: .utf8)
    }
}

/// Counts and examples, in the order first seen.
private struct Report {
    private var counts: [(String, Int)] = []
    private var examples: [String: [String]] = [:]
    private var order: [String] = []
    private var settings: [(String, String)] = []

    mutating func count(_ label: String, _ value: Int) { counts.append((label, value)) }

    mutating func tally(_ label: String) {
        if examples[label] == nil { examples[label] = []; order.append(label) }
        bump(label)
    }

    mutating func add(_ label: String, _ example: String) {
        if examples[label] == nil { examples[label] = []; order.append(label) }
        examples[label]!.append(example)
        bump(label)
    }

    private var totals: [String: Int] = [:]
    private mutating func bump(_ label: String) { totals[label, default: 0] += 1 }

    mutating func setting(_ label: String, _ value: String) { settings.append((label, value)) }

    func markdown(vault: String) -> String {
        var lines = ["# Vault audit: \(vault)", ""]
        for (label, value) in counts { lines.append("- \(label): \(value)") }
        lines.append("")
        for label in order {
            let list = examples[label] ?? []
            lines.append("## \(label): \(totals[label] ?? 0)")
            if !list.isEmpty {
                for example in list.prefix(25) { lines.append("- \(example)") }
                if list.count > 25 { lines.append("- … and \(list.count - 25) more") }
            }
            lines.append("")
        }
        lines.append("## Settings")
        for (label, value) in settings { lines.append("- \(label): \(value)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
