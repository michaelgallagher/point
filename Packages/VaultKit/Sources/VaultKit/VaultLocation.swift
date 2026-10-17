import Foundation

/// Remembers the vault folder the user picked, across launches.
///
/// The app is sandboxed, so it can only reach the folder through a security-scoped
/// bookmark created while it has the user's permission.
public enum VaultLocation {
    #if os(macOS)
    private static let createOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let createOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: createOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Returns the folder and whether the bookmark is stale and should be recreated.
    public static func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}
