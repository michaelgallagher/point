import Foundation
import Testing
@testable import VaultKit

/// What Point writes, tried on a copy of a real vault and checked (see
/// `plan/live-vault-safety.md`, phase 2). Runs only when `POINT_AUDIT_COPY` names a copy of a
/// vault, which it changes: property edits and template merges in memory, on every note;
/// renames, moves and the trash on the copy's files. Writes a report to `POINT_AUDIT_REPORT`.
/// Never point it at the vault itself.
@Suite(.serialized)
struct VaultWriteAudit {
    private var copy: URL? { ProcessInfo.processInfo.environment["POINT_AUDIT_COPY"].map { URL(fileURLWithPath: $0) } }
    private var reportURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["POINT_AUDIT_REPORT"] ?? NSTemporaryDirectory() + "vault-write-audit.md")
    }

    @Test func audit() throws {
        guard let root = copy else { return }
        var report = WriteReport()
        try propertyEdits(root, &report)
        try templateMerges(root, &report)
        try renames(root, &report)
        try moves(root, &report)
        try trash(root, &report)
        try report.markdown().write(to: reportURL, atomically: true, encoding: .utf8)
    }

    // MARK: Properties, in memory

    /// Every property of every note set to a new value, removed and renamed: nothing else in
    /// the note may change, and the note must read back with just that change.
    private func propertyEdits(_ root: URL, _ report: inout WriteReport) throws {
        for (note, text) in try Self.texts(root) {
            guard let frontmatter = Frontmatter.parse(text) else { continue }
            let ns = text as NSString
            var seen = Set<String>()
            for property in frontmatter.properties where seen.insert(property.key.lowercased()).inserted {
                report.tally("Properties edited")
                let others = frontmatter.properties.filter { $0.key != property.key }
                let new = property.isList ? property.values + ["Point test"] : [(property.values.first ?? "") + " (Point test)"]
                for (label, edit, expect) in [
                    ("set", frontmatter.edit(setting: property.key, to: new, isList: property.isList), Optional(new)),
                    ("removed", frontmatter.edit(removing: property.key) ?? (property.range, ""), nil),
                ] {
                    let edited = ns.replacingCharacters(in: edit.0, with: edit.1)
                    let before = ns.substring(to: property.range.location), after = ns.substring(from: NSMaxRange(property.range))
                    let editedNS = edited as NSString
                    let changedElsewhere = !edited.hasPrefix(before) || !edited.hasSuffix(after)
                        || editedNS.length < (before as NSString).length + (after as NSString).length
                    let reread = Frontmatter.parse(edited)
                    let mine = reread?.properties.first { $0.key == property.key }
                    let othersKept = others.allSatisfy { other in reread?.properties.contains { $0.key == other.key && $0.values == other.values } == true }
                    if changedElsewhere || reread == nil || !othersKept || (expect != nil ? mine?.values != expect : mine != nil) {
                        report.add("Property \(label) wrongly", "\(note.id): \(property.key) → `\(edit.1.replacingOccurrences(of: "\n", with: "⏎"))`")
                    }
                }
                if let rename = frontmatter.edit(renaming: property.key, to: property.key + " test", in: text) {
                    let reread = Frontmatter.parse(ns.replacingCharacters(in: rename.0, with: rename.1))
                    if reread?.properties.first(where: { $0.key == property.key + " test" })?.values != property.values {
                        report.add("Property renamed wrongly", "\(note.id): \(property.key)")
                    }
                }
            }
        }
    }

    /// Each template applied to every note, in memory: the note's own values stay (a shared
    /// list only gains items), the template's other properties are added, and the note's text
    /// is untouched apart from the frontmatter and the body put in.
    private func templateMerges(_ root: URL, _ report: inout WriteReport) throws {
        let settings = ObsidianSettings.load(vault: root)
        let templates = Templates.available(in: root, settings: settings)
        report.setting("Templates tried", templates.map(\.name).joined(separator: ", "))
        for template in templates {
            guard let raw = try? NoteReader.read(contentsOf: template.url) else { continue }
            for (note, text) in try Self.texts(root) {
                let rendered = Templates.render(raw, title: note.title, settings: settings)
                let merge = Templates.merge(rendered, into: text)
                report.tally("Templates applied")
                guard let range = merge.frontmatterRange, let block = merge.frontmatter else { continue }
                let rest = (text as NSString).substring(from: NSMaxRange(range))
                let merged = block + rest
                guard let after = Frontmatter.parse(merged) else { report.add("Template merge broke the frontmatter", "\(template.name) → \(note.id)"); continue }
                for property in Frontmatter.parse(text)?.properties ?? [] {
                    guard let now = after.properties.first(where: { $0.key == property.key }) else {
                        report.add("Template merge lost a property", "\(template.name) → \(note.id): \(property.key)"); continue
                    }
                    let kept = now.values == property.values || (now.values.starts(with: property.values) && now.isList)
                    if !kept { report.add("Template merge changed a value", "\(template.name) → \(note.id): \(property.key)") }
                }
            }
        }
    }

    // MARK: Renames and moves, on the copy

    /// The busiest notes, notes sharing a name, and notes linked in each form, renamed: every
    /// link that led to the note must lead to it under its new name, and no other link, and
    /// nothing else in any note, may change.
    private func renames(_ root: URL, _ report: inout WriteReport) throws {
        for id in try Self.chooseTargets(root) {
            let notes = try VaultScanner.scan(root)
            guard let note = notes.first(where: { $0.id == id }) else { continue }
            let before = try Self.linkMap(root, notes: notes)
            let snapshot = try Self.texts(root)
            // As `VaultStore.rename` does: the file first, then links, from the vault as it was.
            let url = try NoteFiles.rename(note.url, to: note.title + " renamed")
            let result = LinkUpdater.updateLinks(to: note, newTitle: url.deletingPathExtension().lastPathComponent, notes: notes)
            let newID = (LinkResolver.folder(of: note.id).isEmpty ? "" : LinkResolver.folder(of: note.id) + "/") + url.lastPathComponent
            report.tally("Notes renamed")
            Self.check(root, renamed: note.id, to: newID, before: before, snapshot: snapshot, skipped: result.skippedNotes, label: "rename", &report)
        }
    }

    /// Notes linked by path, and by relative Markdown link, moved to another folder.
    private func moves(_ root: URL, _ report: inout WriteReport) throws {
        let notes = try VaultScanner.scan(root)
        let map = try Self.linkMap(root, notes: notes)
        // Linked to by path, or holding relative Markdown links, plus one plain note.
        let pathLinked = Set(map.links.filter { $0.target.contains("/") }.compactMap(\.resolved))
        let candidates = notes.filter { pathLinked.contains($0.id) }.prefix(3) + notes.filter { !LinkResolver.folder(of: $0.id).isEmpty }.prefix(1)
        let destination = "Point move test"
        try FileManager.default.createDirectory(at: root.appendingPathComponent(destination), withIntermediateDirectories: true)
        for note in candidates {
            let notes = try VaultScanner.scan(root)
            guard let current = notes.first(where: { $0.id == note.id }) else { continue }
            let before = try Self.linkMap(root, notes: notes)
            let snapshot = try Self.texts(root)
            let url = try NoteFiles.move(current.url, toFolder: root.appendingPathComponent(destination))
            let newID = destination + "/" + url.lastPathComponent
            let result = LinkUpdater.updateLinks(afterMoving: current, to: newID, notes: notes, root: root)
            report.tally("Notes moved")
            Self.check(root, renamed: current.id, to: newID, before: before, snapshot: snapshot, skipped: result.skippedNotes, label: "move", &report)
        }
    }

    /// After a rename or move: links resolve as before (the moved note's under its new ID),
    /// and each changed note differs only inside its links' targets.
    private static func check(_ root: URL, renamed oldID: String, to newID: String, before: LinkMap, snapshot: [(Note, String)],
                              skipped: [String], label: String, _ report: inout WriteReport) {
        guard let notes = try? VaultScanner.scan(root), let after = try? linkMap(root, notes: notes) else { return }
        for id in skipped { report.add("\(label): note skipped (changed while updating)", "\(oldID): \(id)") }
        func moved(_ id: String) -> String { id == oldID ? newID : id }
        let beforeBySource = Dictionary(grouping: before.links, by: { moved($0.source) })
        let afterBySource = Dictionary(grouping: after.links, by: \.source)
        for (source, links) in beforeBySource {
            let now = afterBySource[source] ?? []
            guard links.count == now.count else {
                report.add("\(label): links added or lost", "\(oldID) → \(source) (\(links.count) → \(now.count))"); continue
            }
            for (old, new) in zip(links, now) {
                let expected = old.resolved.map(moved)
                if new.resolved != expected {
                    let place = old.inFrontmatter ? " (in frontmatter)" : ""
                    if expected == newID {
                        report.add("\(label): link to the note not updated\(place)", "\(source): [[\(old.target)]] → [[\(new.target)]]")
                    } else {
                        report.add("\(label): another link changed\(place)", "\(source): [[\(old.target)]] (to \(old.resolved ?? "nothing")) → [[\(new.target)]] (to \(new.resolved ?? "nothing"))")
                    }
                }
                if old.rest != new.rest { report.add("\(label): a link's heading or alias changed", "\(source): [[\(old.target)\(old.rest)]] → [[\(new.target)\(new.rest)]]") }
            }
        }
        // Outside the links, every note reads exactly as it did.
        let texts = Dictionary((try? Self.texts(root))?.map { ($0.0.id, $0.1) } ?? [], uniquingKeysWith: { a, _ in a })
        for (note, text) in snapshot {
            guard let now = texts[moved(note.id)], now != text else { continue }
            report.tally("\(label): notes changed")
            if blankLinks(now) != blankLinks(text) { report.add("\(label): text changed outside links", "\(oldID) → \(note.id)") }
        }
    }

    // MARK: Trash

    /// Notes moved to the trash and put back: back where they were, byte for byte.
    private func trash(_ root: URL, _ report: inout WriteReport) throws {
        let notes = try VaultScanner.scan(root)
        for note in notes.filter({ !LinkResolver.folder(of: $0.id).isEmpty }).prefix(3) {
            let original = try Data(contentsOf: note.url)
            let name = try VaultTrash.move(note.url, vault: root)
            let record = VaultTrash.Record(deleted: Date(), folder: LinkResolver.folder(of: note.id), deletedByPoint: true)
            guard let item = VaultTrash.items(in: root, records: [name: record]).first(where: { $0.name == name }) else {
                report.add("Trash: not listed after trashing", note.id); continue
            }
            let restored = try VaultTrash.restore(item, vault: root)
            report.tally("Notes trashed and put back")
            if restored.standardizedFileURL.path != note.url.standardizedFileURL.path { report.add("Trash: put back somewhere else", "\(note.id) → \(restored.path)") }
            if (try? Data(contentsOf: restored)) != original { report.add("Trash: put back changed", note.id) }
        }
    }

    // MARK: Reading the vault

    private static func texts(_ root: URL) throws -> [(Note, String)] {
        try VaultScanner.scan(root).compactMap { note in (try? NoteReader.read(contentsOf: note.url)).map { (note, $0) } }
    }

    struct Link {
        let source: String
        let target: String
        /// What follows the name: `#heading`, `|alias`.
        let rest: String
        let resolved: String?
        let inFrontmatter: Bool
    }

    struct LinkMap {
        var links: [Link] = []
    }

    private static let wiki = try! NSRegularExpression(pattern: #"!?\[\[([^\[\]\n|#]*)([^\[\]\n]*)\]\]"#)
    private static let inlineCode = try! NSRegularExpression(pattern: "`[^`\n]*`")

    /// Every wikilink in the vault, in order, with what it leads to.
    static func linkMap(_ root: URL, notes: [Note]) throws -> LinkMap {
        let resolver = LinkResolver(notes: notes)
        var map = LinkMap()
        for note in notes {
            guard let original = try? NoteReader.read(contentsOf: note.url) else { continue }
            // Links inside inline code aren't links, to Obsidian or Point: blanked out.
            let blanked = NSMutableString(string: original)
            for code in inlineCode.matches(in: original, range: NSRange(location: 0, length: blanked.length)) {
                blanked.replaceCharacters(in: code.range, with: String(repeating: " ", count: code.range.length))
            }
            let text = blanked as String
            let ns = text as NSString
            let frontmatterEnd = Frontmatter.parse(original).map { NSMaxRange($0.range) } ?? 0
            for match in wiki.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let target = ns.substring(with: match.range(at: 1))
                map.links.append(Link(source: note.id, target: target, rest: ns.substring(with: match.range(at: 2)),
                                      resolved: resolver.resolve(wikiTarget: target, from: note.id)?.id,
                                      inFrontmatter: match.range.location < frontmatterEnd))
            }
        }
        return map
    }

    /// A note's text with every wikilink's target blanked, to compare what's outside them.
    static func blankLinks(_ text: String) -> String {
        wiki.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "[[•$2]]")
    }

    /// Notes worth renaming: those sharing a name, the most linked, the most linked from
    /// frontmatter, and ones linked with an alias, a heading, an embed or a path.
    static func chooseTargets(_ root: URL) throws -> [String] {
        let notes = try VaultScanner.scan(root)
        let map = try linkMap(root, notes: notes)
        var chosen: [String] = []
        func add(_ ids: [String]) { for id in ids where !chosen.contains(id) { chosen.append(id) } }
        let byTitle = Dictionary(grouping: notes, by: { $0.title.lowercased() })
        add(byTitle.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) }.sorted().prefix(2).map { $0 })
        func top(_ links: [Link], _ count: Int) -> [String] {
            Dictionary(grouping: links.compactMap(\.resolved), by: { $0 }).sorted { $0.value.count > $1.value.count }.prefix(count).map(\.key)
        }
        add(top(map.links, 3))
        add(top(map.links.filter(\.inFrontmatter), 2))
        add(top(map.links.filter { $0.rest.hasPrefix("|") || $0.rest.contains("|") }, 1))
        add(top(map.links.filter { $0.rest.hasPrefix("#") }, 1))
        add(top(map.links.filter { $0.target.contains("/") }, 1))
        return chosen
    }
}

/// Counts and examples, in the order first seen.
private struct WriteReport {
    private var order: [String] = []
    private var totals: [String: Int] = [:]
    private var examples: [String: [String]] = [:]
    private var settings: [(String, String)] = []

    mutating func tally(_ label: String) {
        if totals[label] == nil { order.append(label) }
        totals[label, default: 0] += 1
    }

    mutating func add(_ label: String, _ example: String) {
        tally(label)
        examples[label, default: []].append(example)
    }

    mutating func setting(_ label: String, _ value: String) { settings.append((label, value)) }

    func markdown() -> String {
        var lines = ["# What Point writes, tried on a copy", ""]
        for (label, value) in settings { lines.append("- \(label): \(value)") }
        lines.append("")
        for label in order {
            lines.append("## \(label): \(totals[label] ?? 0)")
            let list = examples[label] ?? []
            for example in list.prefix(30) { lines.append("- \(example)") }
            if list.count > 30 { lines.append("- … and \(list.count - 30) more") }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
