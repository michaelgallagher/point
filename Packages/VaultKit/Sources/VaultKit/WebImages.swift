import Foundation
import ImageIO
import MarkdownKit
import UniformTypeIdentifiers

/// Keeping a note's web images in the vault, when asked: each picture embedded from the web
/// (`![alt](https://…)`, or `<img src="https://…">`) downloaded, saved in the attachment
/// folder named after the note, as a pasted image is, and the note pointed at the copy.
/// Never done unasked: clipping leaves pictures on the web.
public enum WebImages {
    /// A picture a note embeds from the web.
    public struct Found: Equatable, Sendable {
        /// The whole picture as written: `![alt](https://…)` or `<img …>`.
        public let range: NSRange
        /// Its address, as written.
        public let address: String
        /// What its text says it shows, as written (Markdown escapes and all), without a width.
        public let alt: String
        /// The width asked for (`![alt|300](…)`, or `width="300"`).
        public let width: Int?
        /// Whether it's the picture of a link (`[![alt](picture)](page)`).
        public let isLinked: Bool
        /// Whether it's written as HTML.
        public let isHTML: Bool

        public var url: URL? { URL(string: address) ?? address.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init) }
    }

    /// How the vault writes links to its files, as set in Obsidian (Files and links).
    public enum LinkStyle: Equatable, Sendable {
        /// `![[Meeting 1.png]]`, Obsidian's default and how Point embeds pasted images.
        case wikilink
        /// `![alt](Meeting%201.png)`, with the path as "New link format" says.
        case markdown(LinkFormat)

        public enum LinkFormat: String, Sendable {
            /// The file name alone (Obsidian's default).
            case shortest
            /// From the note's folder.
            case relative
            /// From the vault's root.
            case absolute
        }

        public init(settings: ObsidianSettings) {
            self = settings.usesMarkdownLinks ? .markdown(LinkFormat(rawValue: settings.newLinkFormat) ?? .shortest) : .wikilink
        }
    }

    // MARK: Finding them

    private static let imgTag = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive])
    private static func attribute(_ name: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#, options: [.caseInsensitive])
    }
    private static let srcAttribute = attribute("src")
    private static let altAttribute = attribute("alt")
    private static let widthAttribute = attribute("width")

    /// Whether a note's text might embed a web picture: a quick look, for whether to offer the
    /// command, that `find` then makes sure of.
    public static func mightHaveAny(in text: String) -> Bool {
        text.range(of: "](http", options: .caseInsensitive) != nil
            || text.range(of: "](<http", options: .caseInsensitive) != nil
            || (text.range(of: "<img", options: .caseInsensitive) != nil && text.range(of: "http", options: .caseInsensitive) != nil)
    }

    /// The pictures a note embeds from the web, in order. Not those in code, or in its
    /// properties.
    public static func find(in text: String) -> [Found] {
        let tokens = MarkdownParser.parse(text)
        let ns = text as NSString
        var found: [Found] = []
        var excluded: [NSRange] = []
        for token in tokens {
            switch token.kind {
            case .codeBlock, .code, .frontmatter:
                excluded.append(token.range)
            case .image(let source):
                let address = source.trimmingCharacters(in: .whitespaces)
                guard isWeb(address), NSMaxRange(token.range) <= ns.length else { continue }
                let whole = ns.substring(with: token.range)
                guard whole.hasPrefix("!["), let close = whole.range(of: "](") else { continue }
                var alt = String(whole[whole.index(whole.startIndex, offsetBy: 2)..<close.lowerBound])
                var width: Int?
                if let bar = alt.lastIndex(of: "|"), let size = VaultImages.width(String(alt[alt.index(after: bar)...])) {
                    width = size
                    alt = String(alt[..<bar])
                }
                found.append(Found(range: token.range, address: address, alt: alt, width: width,
                                   isLinked: isLinked(token.range, in: ns), isHTML: false))
            default:
                continue
            }
        }
        for match in imgTag.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            guard let address = value(of: srcAttribute, in: tag), isWeb(address) else { continue }
            found.append(Found(range: match.range, address: decodingEntities(address), alt: value(of: altAttribute, in: tag).map(decodingEntities) ?? "",
                               width: value(of: widthAttribute, in: tag).flatMap(VaultImages.width), isLinked: false, isHTML: true))
        }
        return found
            .filter { picture in !excluded.contains { NSIntersectionRange($0, picture.range).length > 0 } }
            .sorted { $0.range.location < $1.range.location }
    }

    private static func isWeb(_ address: String) -> Bool {
        let lowered = address.lowercased()
        return lowered.hasPrefix("https://") || lowered.hasPrefix("http://")
    }

    /// `[![alt](picture)](page)`: the picture is a link's text.
    private static func isLinked(_ range: NSRange, in text: NSString) -> Bool {
        guard range.location > 0, NSMaxRange(range) + 2 <= text.length else { return false }
        return text.character(at: range.location - 1) == 0x5B /* [ */
            && text.substring(with: NSRange(location: NSMaxRange(range), length: 2)) == "]("
    }

    private static func value(of attribute: NSRegularExpression, in tag: String) -> String? {
        let ns = tag as NSString
        guard let match = attribute.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return nil
    }

    private static func decodingEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Writing the links

    /// The embed to write in place of `picture`, now saved as `image` for the note at
    /// `noteURL`: `![[Meeting 1.jpg|alt]]` in a vault of wikilinks, or `![alt](Meeting%201.jpg)`.
    /// The picture of a link stays a Markdown image (`[![alt](Meeting%201.jpg)](page)`), since
    /// Obsidian doesn't show an embed in a link's text.
    public static func embed(for picture: Found, image: VaultImage, noteURL: URL, root: URL, style: LinkStyle) -> String {
        switch style {
        case .wikilink where !picture.isLinked:
            let alt = plainAlt(picture.alt, markdown: !picture.isHTML)
            if let width = picture.width { return "![[\(image.name)|\(width)]]" }
            return alt.isEmpty ? "![[\(image.name)]]" : "![[\(image.name)|\(alt)]]"
        case .wikilink:
            return markdownImage(picture, path: encoded(image.name))
        case .markdown(let format):
            let path: String
            switch format {
            case .shortest: path = image.name
            case .absolute: path = image.path
            case .relative: path = relativePath(of: image.url, from: noteURL.deletingLastPathComponent(), root: root)
            }
            return markdownImage(picture, path: encoded(path))
        }
    }

    private static func markdownImage(_ picture: Found, path: String) -> String {
        var alt = picture.isHTML ? markdownAlt(picture.alt) : picture.alt
        if let width = picture.width { alt += "|\(width)" }
        return "![\(alt)](\(path))"
    }

    /// Alt text as a wikilink can hold it: no Markdown escapes, and nothing that would end the
    /// link or start a size, on one line.
    static func plainAlt(_ alt: String, markdown: Bool) -> String {
        var text = alt
        if markdown {
            text = text.replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!|<>~=])"#, with: "$1", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"[\[\]|]"#, with: "", options: .regularExpression)
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// HTML alt text as Markdown's: brackets escaped, on one line.
    private static func markdownAlt(_ alt: String) -> String {
        alt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    /// A path as a Markdown link writes it: spaces and the like percent-encoded, slashes kept.
    private static func encoded(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private static func relativePath(of file: URL, from folder: URL, root: URL) -> String {
        let to = VaultImages.relativePath(of: file, in: root).split(separator: "/").map(String.init)
        let from = VaultImages.relativePath(of: folder, in: root).split(separator: "/").map(String.init)
        var shared = 0
        while shared < min(to.count - 1, from.count), to[shared] == from[shared] { shared += 1 }
        return (Array(repeating: "..", count: from.count - shared) + to[shared...]).joined(separator: "/")
    }

    /// The edits that point a note's text at the saved copies of its web pictures (`saved`, by
    /// address as written), last first, so each leaves the ranges before it as they were.
    /// Pictures not saved stay as they are.
    public static func edits(for text: String, saved: [String: VaultImage], noteURL: URL, root: URL, style: LinkStyle) -> [(range: NSRange, replacement: String)] {
        find(in: text).compactMap { picture in
            saved[picture.address].map { (picture.range, embed(for: picture, image: $0, noteURL: noteURL, root: root, style: style)) }
        }
        .reversed()
    }

    /// `text` with the edits made.
    public static func applying(_ edits: [(range: NSRange, replacement: String)], to text: String) -> String {
        let result = NSMutableString(string: text)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }

    // MARK: Downloading and saving them

    /// A picture downloaded, as it will be saved: its data and extension.
    public struct Download: Sendable {
        public let data: Data
        public let ext: String
    }

    /// Why a picture couldn't be kept.
    public enum Failure: Error, Sendable {
        case badAddress, notAnImage, tooBig
        case http(Int)
        case network(String)
    }

    /// The most a picture may be, downloaded.
    static let largest = 50 * 1024 * 1024

    /// Gets pictures, several at a time, each ready to save, by address: the copy kept in
    /// `cache` when a note has shown it already, else downloaded, as the cache does (no
    /// cookies), asking for kinds every app shows.
    public static func download(_ addresses: [String], cache: WebImageCache = .standard, session: URLSession = WebImageCache.session,
                                atOnce: Int = 6) async -> [String: Result<Download, Failure>] {
        var results: [String: Result<Download, Failure>] = [:]
        var unique: [String] = []
        for address in addresses where !unique.contains(address) { unique.append(address) }
        await withTaskGroup(of: (String, Result<Download, Failure>).self) { group in
            var next = 0
            func start() {
                guard next < unique.count else { return }
                let address = unique[next]
                next += 1
                group.addTask { (address, await download(address, cache: cache, session: session)) }
            }
            for _ in 0..<atOnce { start() }
            while let (address, result) = await group.next() {
                results[address] = result
                start()
            }
        }
        return results
    }

    private static func download(_ address: String, cache: WebImageCache, session: URLSession) async -> Result<Download, Failure> {
        guard let url = Found(range: NSRange(), address: address, alt: "", width: nil, isLinked: false, isHTML: false).url else { return .failure(.badAddress) }
        if let kept = cache.cached(url), let data = try? Data(contentsOf: kept), let prepared = prepared(data) {
            return .success(prepared)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("image/png,image/jpeg,image/gif;q=0.9,image/webp;q=0.8,image/*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return .failure(.http(http.statusCode)) }
            guard data.count <= largest else { return .failure(.tooBig) }
            guard let prepared = prepared(data) else { return .failure(.notAnImage) }
            return .success(prepared)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Downloaded data as it will be saved, by what it is rather than what the server said:
    /// PNG, JPEG, GIF, WebP and AVIF as they are, SVG as it is, other kinds as `VaultImages`
    /// saves a pasted image. Nil if it isn't a picture (a web page, say).
    public static func prepared(_ data: Data) -> Download? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
           let kind = (CGImageSourceGetType(source) as String?).flatMap({ UTType($0) }) {
            if let avif = UTType("public.avif"), kind.conforms(to: avif) { return Download(data: data, ext: "avif") }
            return VaultImages.forSaving(data, type: kind).map { Download(data: $0.data, ext: $0.ext) }
        }
        let start = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        if start.contains("<svg"), !start.contains("<html") {
            return Download(data: data, ext: "svg")
        }
        return nil
    }

    /// Saves downloaded pictures for a note, in the order it shows them, each named after it
    /// (`Meeting 1.jpg`, `Meeting 2.png`) with a number no file in the folder, or image in the
    /// vault (`taken`, any case), has. Never writes over a file. Returns those saved, by
    /// address, and the addresses of any that couldn't be.
    public static func save(_ downloads: [(address: String, download: Download)], forNote note: Note, vault root: URL,
                            setting: String, taken: Set<String> = []) -> (saved: [String: VaultImage], failed: [String]) {
        let folder = VaultImages.folder(forNoteAt: note.url, vault: root, setting: setting)
        var taken = taken
        var saved: [String: VaultImage] = [:]
        var failed: [String] = []
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return ([:], downloads.map(\.address))
        }
        for (address, download) in downloads where saved[address] == nil && !failed.contains(address) {
            var attempts = 0
            while true {
                let name = VaultImages.availableName(forNote: note.name, ext: download.ext, in: folder, taken: taken)
                taken.insert(name)
                let url = folder.appendingPathComponent(name)
                do {
                    try download.data.write(to: url, options: .withoutOverwriting)
                    saved[address] = VaultImages.image(named: name, in: folder, vault: root)
                } catch CocoaError.fileWriteFileExists where attempts < 20 {
                    attempts += 1 // Made meanwhile (by iCloud, say): the next number.
                    continue
                } catch {
                    failed.append(address)
                }
                break
            }
        }
        return (saved, failed)
    }
}
