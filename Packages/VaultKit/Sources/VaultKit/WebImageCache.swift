import CryptoKit
import Foundation
import ImageIO

/// Images on the web that notes show (`![](https://…)`, most of a vault's images, in pages
/// clipped from the web), kept in the app's own caches, never in the vault: loaded once, then
/// shown from here, offline too. Loaded without cookies or a referrer, so a site learns no
/// more than that its image was asked for.
public struct WebImageCache: Sendable {
    public let folder: URL
    /// The most an image may be, so a huge file can't fill the cache.
    public var largest = 30 * 1024 * 1024

    public init(folder: URL) {
        self.folder = folder
    }

    /// The app's cache, in its caches folder.
    public static let standard = WebImageCache(folder: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Point/Web images", isDirectory: true))

    /// Whether an embed's target is on the web.
    public static func isWeb(_ target: String) -> Bool {
        let lowered = target.lowercased()
        return lowered.hasPrefix("https://") || lowered.hasPrefix("http://")
    }

    /// Where an image from `address` is kept: named by a hash of the address.
    public func file(for address: URL) -> URL {
        let digest = SHA256.hash(data: Data(address.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest)
    }

    /// The kept copy, if it's been loaded.
    public func cached(_ address: URL) -> URL? {
        let file = file(for: address)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    public enum LoadError: Error { case notAnImage, tooBig, failed(Int) }

    /// Loads an image and keeps it, returning where. Only an image is kept.
    public func load(_ address: URL, session: URLSession = WebImageCache.session) async throws -> URL {
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LoadError.failed(http.statusCode) }
        guard data.count <= largest else { throw LoadError.tooBig }
        guard Self.isImage(data) else { throw LoadError.notAnImage }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = file(for: address)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Whether data is an image ImageIO can read.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
    }

    /// No cookies, no stored credentials, no cache of its own (this is the cache).
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        // Says what it is, as sites ask: some turn away requests that don't say.
        configuration.httpAdditionalHeaders = ["User-Agent": "Point/1.0 (notes app; loads images notes show)"]
        return URLSession(configuration: configuration)
    }()

    /// How much the cache holds, in bytes.
    public func size() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Empties the cache.
    public func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
