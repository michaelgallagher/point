import Foundation
import ImageIO
import MarkdownKit
import UniformTypeIdentifiers

/// An image file in the vault.
public struct VaultImage: Hashable, Sendable, Identifiable {
    /// Its path from the vault's root, such as `Attachments/2026-11-06-meeting-1.png`.
    public let path: String
    public let url: URL
    /// Whether its contents are here, not an evicted iCloud placeholder.
    public let isDownloaded: Bool

    public var id: String { path }
    /// Its file name, which is what embeds name it by: `2026-11-06-meeting-1.png`.
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, url: URL, isDownloaded: Bool = true) {
        self.path = path
        self.url = url
        self.isDownloaded = isDownloaded
    }
}

/// How Point looks after a vault's images: where new ones go (the attachment folder Obsidian is
/// set to), what they're called (after their note: `2026-11-06-meeting-1.png`), and the embeds
/// that show them (`![[2026-11-06-meeting-1.png]]`, as Obsidian writes them).
///
/// An image belongs to a note by its name, so it can be renamed with the note, and go to the
/// trash with it when no other note shows it.
public enum VaultImages {
    /// The kinds of file shown as images.
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "svg"]

    public static func isImage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && extensions.contains(ext) && !name.hasPrefix(".")
    }

    // MARK: Where they go

    /// The folder a new image for the note at `noteURL` goes in, as Obsidian's "Default location
    /// for new attachments" says (`attachmentFolderPath`): the vault's top level (""), the
    /// note's own folder (`./`), a folder under it (`./assets`), or a folder in the vault.
    public static func folder(forNoteAt noteURL: URL, vault root: URL, setting: String) -> URL {
        let setting = setting.trimmingCharacters(in: .whitespaces)
        if setting.isEmpty || setting == "/" { return root }
        if setting == "./" || setting == "." { return noteURL.deletingLastPathComponent() }
        if setting.hasPrefix("./") {
            return noteURL.deletingLastPathComponent().appendingPathComponent(String(setting.dropFirst(2)), isDirectory: true)
        }
        let path = setting.hasPrefix("/") ? String(setting.dropFirst()) : setting
        return root.appendingPathComponent(path, isDirectory: true)
    }

    // MARK: What they're called

    /// What an image named after the note `noteName` is called, with its number: `2026-11-06-meeting-1`
    /// for a note Point named, `Meeting 1` for any other.
    public static func stem(forNote noteName: String, number: Int) -> String {
        NoteNames.isDated(noteName) ? "\(noteName)-\(number)" : "\(noteName) \(number)"
    }

    /// A free name in `folder` for a new image of `note`, with the extension `ext`: the first
    /// number not taken by any image already named after the note (in any case).
    public static func availableName(forNote noteName: String, ext: String, in folder: URL, taken: Set<String> = []) -> String {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() })
            .union(taken.map { $0.lowercased() })
        let stems = Set(existing.map { ($0 as NSString).deletingPathExtension })
        var number = 1
        while stems.contains(stem(forNote: noteName, number: number).lowercased()) { number += 1 }
        return stem(forNote: noteName, number: number) + "." + ext
    }

    /// The number an image is named after `noteName` with, if it is: `Meeting 2.png` and
    /// `2026-11-06-meeting-2.png` are, `Meeting notes.png` isn't.
    public static func number(of imageName: String, forNote noteName: String) -> Int? {
        let stem = (imageName as NSString).deletingPathExtension
        let separator = NoteNames.isDated(noteName) ? "-" : " "
        let prefix = noteName + separator
        guard stem.count > prefix.count, stem.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let digits = stem.dropFirst(prefix.count)
        guard digits.allSatisfy(\.isASCIIDigit), let number = Int(digits) else { return nil }
        return number
    }

    /// An image's name when its note is renamed from `oldName` to `newName`: `Meeting 2.png`
    /// becomes `Standup 2.png`. Nil if it isn't named after the note.
    public static func renamed(_ imageName: String, fromNote oldName: String, toNote newName: String) -> String? {
        guard let number = number(of: imageName, forNote: oldName) else { return nil }
        let ext = (imageName as NSString).pathExtension
        return stem(forNote: newName, number: number) + (ext.isEmpty ? "" : "." + ext)
    }

    // MARK: Embeds

    /// An image embed, as written in a note.
    public struct Embed: Equatable, Sendable {
        /// The whole embed: `![[a.png|300]]` or `![alt](a.png)`.
        public let range: NSRange
        /// What it names: `a.png`, or a path (`Attachments/a.png`) or a web address.
        public let target: String
        /// The width asked for (`|300`, or `|300x200`), in points.
        public let width: Int?
        /// The file name it names, without any path: what it's found by.
        public var name: String {
            let decoded = target.removingPercentEncoding ?? target
            return (decoded as NSString).lastPathComponent
        }
        public var isWeb: Bool {
            let lowered = target.lowercased()
            return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        }
    }

    /// The images a note's text embeds, in order: `![[a.png]]`, `![[a.png|300]]`, `![](a.png)`
    /// and `![](https://…)`.
    public static func embeds(in text: String) -> [Embed] {
        embeds(in: MarkdownParser.parse(text), text: text as NSString)
    }

    public static func embeds(in tokens: [MarkdownToken], text: NSString) -> [Embed] {
        var embeds: [Embed] = []
        for token in tokens {
            switch token.kind {
            case .embed:
                // As written, `a.png|300`: the parser's target leaves off what follows the bar.
                guard token.range.length > 5, NSMaxRange(token.range) <= text.length else { continue }
                let target = text.substring(with: NSRange(location: token.range.location + 3, length: token.range.length - 5))
                let parts = target.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let file = parts[0].trimmingCharacters(in: .whitespaces)
                guard isImage((file as NSString).lastPathComponent) else { continue }
                embeds.append(Embed(range: token.range, target: file, width: parts.count > 1 ? width(parts[1]) : nil))
            case .image(let source):
                let file = source.trimmingCharacters(in: .whitespaces)
                embeds.append(Embed(range: token.range, target: file, width: alternativeText(of: token, in: text).flatMap(widthInAlt)))
            default:
                continue
            }
        }
        return embeds
    }

    /// `300` or `300x200`: the width.
    static func width(_ size: String) -> Int? {
        let first = size.trimmingCharacters(in: .whitespaces).split(separator: "x", maxSplits: 1).first.map(String.init) ?? ""
        guard !first.isEmpty, first.allSatisfy(\.isASCIIDigit), let value = Int(first), value > 0 else { return nil }
        return value
    }

    /// `![alt|300](a.png)`: Obsidian's width in a Markdown image's text.
    private static func widthInAlt(_ alt: String) -> Int? {
        guard let bar = alt.lastIndex(of: "|") else { return nil }
        return width(String(alt[alt.index(after: bar)...]))
    }

    private static func alternativeText(of token: MarkdownToken, in text: NSString) -> String? {
        let range = token.range
        guard range.length > 4, text.length >= NSMaxRange(range) else { return nil }
        let whole = text.substring(with: range)
        guard whole.hasPrefix("!["), let close = whole.range(of: "](") else { return nil }
        return String(whole[whole.index(whole.startIndex, offsetBy: 2)..<close.lowerBound])
    }

    /// A note's text with its embeds of the image `oldName` naming `newName` instead, written
    /// as they were (a path keeps its folders, a width stays). Nil if it has none.
    public static func renamingEmbeds(of oldName: String, to newName: String, in text: String) -> String? {
        let ns = text as NSString
        var replacements: [(NSRange, String)] = []
        for embed in embeds(in: text) where !embed.isWeb && embed.name.lowercased() == oldName.lowercased() {
            let whole = ns.substring(with: embed.range)
            guard let found = whole.range(of: embed.target) else { continue }
            let encoded = embed.target != (embed.target.removingPercentEncoding ?? embed.target)
            let newFile = encoded ? (newName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newName) : newName
            let folder = (embed.target as NSString).deletingLastPathComponent
            let newTarget = folder.isEmpty ? newFile : folder + "/" + newFile
            let local = NSRange(found, in: whole)
            replacements.append((NSRange(location: embed.range.location + local.location, length: local.length), newTarget))
        }
        guard !replacements.isEmpty else { return nil }
        let result = NSMutableString(string: text)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    /// The embed to write for an image called `name`.
    public static func embed(_ name: String) -> String { "![[\(name)]]" }

    // MARK: Finding them

    /// The vault's images by file name (in lowercase), as embeds find them: by name, wherever
    /// they are. Where two share a name, the one nearer the top of the vault wins, as in Obsidian.
    public static func byName(_ images: [VaultImage]) -> [String: VaultImage] {
        var found: [String: VaultImage] = [:]
        for image in images.sorted(by: { $0.path.split(separator: "/").count < $1.path.split(separator: "/").count }) {
            let key = image.name.lowercased()
            if found[key] == nil { found[key] = image }
        }
        return found
    }

    /// The image an embed's target names: a path from the vault's root or the note's folder if
    /// it has one there, else any image with its file name.
    public static func resolve(_ target: String, from noteID: String, images: [String: VaultImage], root: URL) -> VaultImage? {
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.lowercased().hasPrefix("http") else { return nil }
        let name = (decoded as NSString).lastPathComponent
        guard let image = images[name.lowercased()] else {
            // A path to an image not found by name (a duplicate name deeper in the vault, say).
            let folder = (noteID as NSString).deletingLastPathComponent
            for base in [root, folder.isEmpty ? root : root.appendingPathComponent(folder)] {
                let url = base.appendingPathComponent(decoded)
                if FileManager.default.fileExists(atPath: url.path) {
                    return VaultImage(path: decoded, url: url)
                }
            }
            return nil
        }
        return image
    }

    /// The images no note embeds or links to, given every name the notes link to (in lowercase).
    public static func unused(_ images: [VaultImage], linkedNames: Set<String>) -> [VaultImage] {
        images.filter { !linkedNames.contains($0.name.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Saving them

    /// Image data as it should be saved, with its extension: PNG and JPEG, GIF and WebP as they
    /// are; a TIFF (what a screenshot pastes as) as PNG; a HEIC photo as JPEG, which every app
    /// shows. Nil if it isn't an image.
    public static func forSaving(_ data: Data, type: UTType?) -> (data: Data, ext: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let found = type ?? (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        if let found {
            if found.conforms(to: .png) { return (data, "png") }
            if found.conforms(to: .jpeg) { return (data, "jpg") }
            if found.conforms(to: .gif) { return (data, "gif") }
            if found.conforms(to: .webP) { return (data, "webp") }
        }
        let isPhoto = found?.conforms(to: .heic) == true || found?.conforms(to: .heif) == true
        let output = isPhoto ? UTType.jpeg : UTType.png
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, output.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = isPhoto ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (out as Data, isPhoto ? "jpg" : "png")
    }

    /// Saves an image for a note, named after it in the attachment folder, and returns its
    /// file name, for the embed.
    public static func save(_ data: Data, type: UTType?, forNote note: Note, vault root: URL, setting: String) throws -> VaultImage {
        guard let (data, ext) = forSaving(data, type: type) else { throw CocoaError(.fileReadCorruptFile) }
        let folder = folder(forNoteAt: note.url, vault: root, setting: setting)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = availableName(forNote: note.name, ext: ext, in: folder)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        return VaultImage(path: relativePath(of: url, in: root), url: url)
    }

    /// A file's path from the vault's root.
    public static func relativePath(of url: URL, in root: URL) -> String {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parts.starts(with: base) else { return url.lastPathComponent }
        return parts.dropFirst(base.count).joined(separator: "/")
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
