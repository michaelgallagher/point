import Foundation
import WebKit

/// Fetches a page and finds its article, in a web view no one sees: the page is only parsed,
/// so its scripts never run and nothing it refers to is loaded. Mozilla's Readability finds the
/// article; Turndown writes it as Markdown (see `Scripts`; not `Resources`, which an iOS bundle can't have at its top).
@MainActor
public final class ClipExtractor: NSObject, WKNavigationDelegate {
    public enum ClipError: LocalizedError {
        case notAPage
        case unreadable
        public var errorDescription: String? {
            switch self {
            case .notAPage: "That address isn’t a web page Point can read."
            case .unreadable: "Point couldn’t read the page."
            }
        }
    }

    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?

    public override init() {}

    /// Fetches the page at `url` and clips it.
    public func clip(_ url: URL) async throws -> Clip {
        let (html, finalURL) = try await Self.fetch(url)
        return try await clip(html: html, url: finalURL)
    }

    /// Clips a page from its HTML, as found at `url`.
    public func clip(html: String, url: URL) async throws -> Clip {
        let webView = try await readyWebView()
        let found = try await webView.callAsyncJavaScript("return pointClip(html, url)",
                                                          arguments: ["html": html, "url": url.absoluteString],
                                                          contentWorld: .defaultClient)
        guard let found = found as? [String: Any] else { throw ClipError.unreadable }
        var clip = Clip(url: url, found: found)
        if clip.title.isEmpty { clip.title = url.host ?? url.absoluteString }
        return clip
    }

    /// The page's HTML, and where it ended up after any redirects.
    public static func fetch(_ url: URL) async throws -> (html: String, url: URL) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // As Safari asks, so sites send the page they'd show a person.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ClipError.unreadable }
        if let type = http.mimeType, !type.contains("html") { throw ClipError.notAPage }
        let encoding = http.textEncodingName.map { CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString)) }
        let html = encoding.flatMap { String(data: data, encoding: String.Encoding(rawValue: $0)) }
            ?? String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (html, http.url ?? url)
    }

    // MARK: The web view

    private func readyWebView() async throws -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        for name in ["Readability", "turndown", "turndown-plugin-gfm", "clip"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Scripts"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { throw ClipError.unreadable }
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString("<!doctype html><html><head></head><body></body></html>", baseURL: nil)
        }
        return webView
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }
}
