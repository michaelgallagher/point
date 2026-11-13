import Foundation

/// Whether a page about to be clipped may be in the vault already, though not at the same
/// address (that's `Clipping.sources(of:)`): the same page at an address that differs only in
/// ways that don't change the page (http or https, `www.`, a mobile or AMP copy, a trailing
/// slash, its query or fragment), or a note whose title is all but the same.
public enum ClipMatching {
    /// A note to compare with: its title, and the page it was clipped from, if it says.
    public struct Candidate: Sendable {
        public let id: String
        public let title: String
        public let source: String?

        public init(id: String, title: String, source: String?) {
            self.id = id
            self.title = title
            self.source = source
        }
    }

    /// A note that may be the page, and why.
    public struct Match: Identifiable, Equatable, Sendable {
        public enum Reason: Sendable { case samePage, similarTitle }
        public let id: String
        public let title: String
        public let reason: Reason

        /// Why, in a few words: "Same page, other address", "Similar title".
        public var why: String { reason == .samePage ? "Same page, other address" : "Similar title" }
    }

    /// The notes that may be this page, the same page first, then similar titles; at most `limit`.
    public static func nearMisses(url: URL, title: String?, among candidates: [Candidate], limit: Int = 4) -> [Match] {
        let key = pageKey(url)
        let words = title.map(titleWords) ?? []
        let normalized = title.map(normalizedTitle)
        var same: [Match] = [], similar: [Match] = []
        for candidate in candidates {
            if let key, let source = candidate.source.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespaces)) }),
               pageKey(source) == key {
                same.append(Match(id: candidate.id, title: candidate.title, reason: .samePage))
            } else if let normalized, !normalized.isEmpty,
                      normalizedTitle(candidate.title) == normalized || isSimilar(words, titleWords(candidate.title)) {
                similar.append(Match(id: candidate.id, title: candidate.title, reason: .similarTitle))
            }
        }
        return Array((same + similar).prefix(limit))
    }

    /// The page an address is, whatever's around it: its host without `www.`, `m.` or `amp.`,
    /// and its path without a trailing slash, `/amp` or `index.html`, in lower case. A YouTube
    /// video is its video's ID. Nil for an address that isn't a web page's.
    public static func pageKey(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        for prefix in ["www.", "m.", "mobile.", "amp."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        if host == "youtu.be", let id = components.path.split(separator: "/").first {
            return "youtube.com/watch/" + id
        }
        if host == "youtube.com", components.path == "/watch",
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return "youtube.com/watch/" + id
        }
        var path = components.path.lowercased()
        for suffix in ["/index.html", "/index.htm", "/amp", "/"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// A title as compared: lower case, without accents or punctuation, and without the site's
    /// name after a separator (`How we work | The Example`), unless that leaves too little.
    static func normalizedTitle(_ title: String) -> String {
        var main = title
        for separator in [" | ", " - ", " — ", " – ", " · ", " :: "] {
            if let range = main.range(of: separator, options: .backwards) {
                let before = String(main[..<range.lowerBound])
                if before.split(separator: " ").count >= 3 { main = before }
            }
        }
        let folded = main.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        let words = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(words).split(separator: " ").joined(separator: " ")
    }

    /// A title's words that say what it's about: small words left out.
    static func titleWords(_ title: String) -> Set<String> {
        Set(normalizedTitle(title).split(separator: " ").map(String.init).filter { !smallWords.contains($0) })
    }

    /// Two titles all but the same: three or more words each, and at least three quarters of
    /// them shared; or the shorter's four or more words all in the longer.
    static func isSimilar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard a.count >= 3, b.count >= 3 else { return false }
        let shared = a.intersection(b).count
        if Double(shared) / Double(a.union(b).count) >= 0.75 { return true }
        return min(a.count, b.count) >= 4 && shared == min(a.count, b.count)
    }

    private static let smallWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "from", "by", "with", "as",
        "is", "are", "was", "be", "it", "its", "this", "that", "how", "why", "what", "we", "you", "i", "your", "our",
    ]
}
