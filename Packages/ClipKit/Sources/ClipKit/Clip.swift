import Foundation
import VaultKit

/// A page clipped from the web: its article as Markdown, and what's known about it.
public struct Clip: Equatable, Sendable {
    /// Where it is, without tracking parameters.
    public var url: URL
    public var title: String
    public var authors: [String]
    /// When it was published, `yyyy-MM-dd`, if the page says.
    public var published: String?
    public var siteName: String?
    /// What it is: Article, or Video for a video site's page.
    public var format: String
    /// The article, as Markdown. Empty if none could be found (the note then has a link).
    public var markdown: String

    public init(url: URL, title: String, authors: [String] = [], published: String? = nil, siteName: String? = nil,
                format: String = "Article", markdown: String = "") {
        self.url = url
        self.title = title
        self.authors = authors
        self.published = published
        self.siteName = siteName
        self.format = format
        self.markdown = markdown
    }

    /// From what the page script found (`clip.js`).
    init(url: URL, found: [String: Any]) {
        let format = Self.format(of: url)
        let siteName = (found["siteName"] as? String).map(Self.tidy).flatMap { $0.isEmpty ? nil : $0 }
        self.init(url: Self.cleaned(url),
                  title: Self.title(Self.tidy((found["title"] as? String) ?? ""), siteName: siteName),
                  authors: ((found["authors"] as? [String]) ?? []).flatMap(Self.authors(in:)),
                  published: (found["published"] as? String).flatMap(Self.day),
                  siteName: siteName,
                  format: format,
                  markdown: Self.tidyMarkdown((found["markdown"] as? String) ?? ""))
    }

    // MARK: Reading what pages say

    /// A page's title without its site's name after it: "Good services | Example" is "Good
    /// services" on Example.
    public static func title(_ title: String, siteName: String?) -> String {
        guard let siteName, !siteName.isEmpty else { return title }
        for separator in [" | ", " - ", " – ", " — ", " · ", " :: "] {
            let suffix = separator + siteName
            if title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }

    /// A video site's page is a Video; anything else an Article.
    public static func format(of url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let videos = ["youtube.com", "youtu.be", "vimeo.com"]
        return videos.contains { host == $0 || host.hasSuffix("." + $0) } ? "Video" : "Article"
    }

    /// The address without what's only there to track where it was found (`utm_…`, `fbclid`
    /// and the like) or a trailing `#`.
    public static func cleaned(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let tracking = ["fbclid", "gclid", "mc_cid", "mc_eid", "ref_src", "igshid"]
        parts.queryItems = parts.queryItems?.filter { item in
            !item.name.lowercased().hasPrefix("utm_") && !tracking.contains(item.name.lowercased())
        }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        if parts.fragment?.isEmpty == true { parts.fragment = nil }
        return parts.url ?? url
    }

    /// People from a byline: "By Sam Lee and Ann Cole" is Sam Lee and Ann Cole. A byline
    /// that isn't names (a long sentence, an address) gives none.
    public static func authors(in byline: String) -> [String] {
        var text = tidy(byline)
        if text.lowercased().hasPrefix("by ") { text = String(text.dropFirst(3)) }
        if text.contains("://") || text.contains("@") { return [] }
        let names = text.replacingOccurrences(of: " and ", with: ", ").replacingOccurrences(of: " & ", with: ", ")
            .split(separator: ",").map { tidy(String($0)) }.filter { !$0.isEmpty }
        guard !names.isEmpty, names.allSatisfy({ $0.split(separator: " ").count <= 4 && $0.count <= 40 }) else { return [] }
        return names
    }

    /// The day a date says, `yyyy-MM-dd`: from `2026-02-09T10:00:00Z`, `2026-02-09` and the
    /// like.
    public static func day(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    /// Text on one line, its spaces single.
    static func tidy(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Markdown as Point writes it: no spaces at line ends or soft hyphens in words, no more
    /// than one empty line in a row, nothing empty at the start or end, and no stray indent
    /// on a line that isn't part of a list or code.
    static func tidyMarkdown(_ markdown: String) -> String {
        var lines: [String] = []
        var inFence = false
        var inList = false
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{00AD}", with: "")
        for raw in text.components(separatedBy: "\n") {
            var line = raw
            if line.trimmingCharacters(in: .whitespaces).isEmpty { line = "" }
            while line.last == " " || line.last == "\t" { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence {
                if line.isEmpty, lines.last?.isEmpty ?? true { continue }
                let isItem = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil
                if !line.isEmpty {
                    if line.first == " ", !inList { line = trimmed }
                    inList = isItem || (inList && line.first == " ")
                }
            }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        return lines.joined(separator: "\n")
    }
}

/// A request to clip, as the browser extension and share sheet send it:
/// `point://clip?url=…&title=…&selection=…`.
public struct ClipRequest: Equatable, Sendable {
    public var url: URL
    public var title: String?
    /// The text selected on the page, if any: kept as a quote above the article.
    public var selection: String?

    public init(url: URL, title: String? = nil, selection: String? = nil) {
        self.url = url
        self.title = title
        self.selection = selection
    }

    /// The request a `point://clip` address makes, if it is one, for a web page.
    public init?(_ address: URL) {
        guard address.scheme?.lowercased() == "point", address.host?.lowercased() == "clip",
              let items = URLComponents(url: address, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        guard let page = value("url").flatMap(URL.init(string:)), ["http", "https"].contains(page.scheme?.lowercased() ?? "") else { return nil }
        self.init(url: page, title: value("title"), selection: value("selection"))
    }

    /// The `point://clip` address for this request.
    public var address: URL {
        var parts = URLComponents()
        parts.scheme = "point"
        parts.host = "clip"
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            + [title.map { URLQueryItem(name: "title", value: $0) }, selection.map { URLQueryItem(name: "selection", value: $0) }].compactMap { $0 }
        return parts.url!
    }
}

/// A clip's note: a template (a kind's, usually Media's) filled in with what's known, and the
/// article under it.
public enum ClipNote {
    /// The note's text. Of the template's properties, `title`, `author`, `published`, `format`,
    /// `source` and `saved` are filled in (any missing are added, but `published` only if
    /// known), and the type property is set to `kind` unless the template sets it. With no
    /// template, those properties alone. The selection, if any, is quoted above the article;
    /// with no article, there's a link to the page.
    public static func text(for clip: Clip, selection: String? = nil, template: String? = nil,
                            typeProperty: String = "type", kind: String? = nil, saved: Date = Date(),
                            calendar: Calendar = .current) -> String {
        var text = template.flatMap { Frontmatter.parse($0) == nil ? nil : $0 } ?? "---\n---\n"
        func set(_ key: String, _ values: [String], isList: Bool = false, onlyIfKnown: Bool = false) {
            guard let frontmatter = Frontmatter.parse(text) else { return }
            let existing = frontmatter.properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
            if existing == nil, onlyIfKnown, values.isEmpty { return }
            if let existing, !values.isEmpty || existing.values.allSatisfy({ $0.isEmpty }) {
                let (range, replacement) = frontmatter.edit(setting: existing.key, to: values, isList: isList || existing.isList)
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
            } else if existing == nil {
                let (range, replacement) = frontmatter.edit(setting: key, to: values, isList: isList)
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
            }
        }
        if let kind, let frontmatter = Frontmatter.parse(text),
           !frontmatter.properties.contains(where: { $0.key.caseInsensitiveCompare(typeProperty) == .orderedSame && !($0.values.first ?? "").isEmpty }) {
            set(typeProperty, [kind])
            if let moved = Frontmatter.parse(text), let key = moved.properties.first(where: { $0.key.caseInsensitiveCompare(typeProperty) == .orderedSame })?.key,
               let (range, replacement) = moved.edit(moving: key, to: 0, in: text) {
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
            }
        }
        set("title", [clip.title])
        set("author", clip.authors.map { "[[\($0)]]" }, isList: true)
        set("published", clip.published.map { [$0] } ?? [], onlyIfKnown: true)
        set("format", [clip.format])
        set("source", [clip.url.absoluteString])
        set("saved", [day(saved, calendar: calendar)])

        let frontmatterEnd = Frontmatter.parse(text).map { NSMaxRange($0.range) } ?? 0
        let ns = text as NSString
        var head = ns.substring(to: frontmatterEnd)
        if !head.hasSuffix("\n") { head += "\n" }
        let templateBody = ns.substring(from: frontmatterEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if let selection = selection.map(Clip.tidyMarkdown), !selection.isEmpty {
            parts.append(selection.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n"))
        }
        if !templateBody.isEmpty { parts.append(templateBody) }
        parts.append(clip.markdown.isEmpty ? "[\(clip.title.isEmpty ? clip.url.absoluteString : clip.title)](\(clip.url.absoluteString))" : clip.markdown)
        return head + parts.joined(separator: "\n\n") + "\n"
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
