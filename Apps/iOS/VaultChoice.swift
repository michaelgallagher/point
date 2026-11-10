import CryptoKit
import Foundation
import SwiftUI
import VaultKit

/// Which vault the phone uses: Point's own folder, or one chosen in Files (the Obsidian vault
/// in iCloud Drive). The chosen folder is kept as a bookmark across launches. Choosing another
/// makes a new `PhoneStore` for it, so nothing read from one vault is used on another.
@MainActor
final class VaultChoice: ObservableObject {
    @Published private(set) var store: PhoneStore
    /// Why the chosen vault couldn't be opened at launch (Point's own folder is used instead).
    @Published var problem: String?
    /// The chosen folder, while Point has access to it.
    private var accessed: URL?

    private static let bookmarkKey = "vaultBookmark"

    init() {
        var problem: String?
        var accessed: URL?
        if let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            do {
                let (url, isStale) = try VaultLocation.resolve(bookmark)
                guard url.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: url.path) else {
                    throw CocoaError(.fileReadNoPermission)
                }
                var isFolder: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                    url.stopAccessingSecurityScopedResource()
                    throw CocoaError(.fileReadNoSuchFile)
                }
                if isStale, let fresh = try? VaultLocation.bookmark(for: url) {
                    UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
                }
                accessed = url
                PhoneVault.use(url, key: Self.key(for: url))
            } catch {
                // Kept, to try again next launch; Settings can choose it again.
                problem = "Point couldn’t open your vault (\(error.localizedDescription)), so it’s showing its own folder. Choose the vault again in Settings."
            }
        }
        self.accessed = accessed
        self.problem = problem
        store = PhoneStore()
    }

    /// The vault's name, as Files shows it.
    var name: String { PhoneVault.isOwnFolder ? "Point’s own folder" : PhoneVault.root.lastPathComponent }
    var isOwnFolder: Bool { PhoneVault.isOwnFolder }

    /// Uses a folder chosen in Files (from `fileImporter`, which gives access to it).
    func choose(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        let bookmark: Data
        do {
            bookmark = try VaultLocation.bookmark(for: url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        switchTo(url, key: Self.key(for: url), accessing: url)
    }

    /// Goes back to Point's own folder. The chosen vault is forgotten (and untouched).
    func useOwnFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        switchTo(PhoneVault.ownFolder, key: PhoneVault.ownKey, accessing: nil)
    }

    private func switchTo(_ root: URL, key: String, accessing url: URL?) {
        // The open note's edits saved first, into the vault they belong to.
        NotificationCenter.default.post(name: .phoneSaveNow, object: nil)
        store.stopWatching()
        if let accessed, accessed != url { accessed.stopAccessingSecurityScopedResource() }
        accessed = url
        problem = nil
        PhoneVault.use(root, key: key)
        store = PhoneStore()
    }

    /// A short, stable key for a chosen folder, from where it is.
    private static func key(for url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        return "vault-" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    /// Every open note saves its edits now (the vault is about to change).
    static let phoneSaveNow = Notification.Name("PhoneSaveNow")
    /// The vault has been read again: an open note with no edits takes in any change to its file.
    static let phoneVaultScanned = Notification.Name("PhoneVaultScanned")
}

/// Told by the system when anything in the vault's folder changes: a note edited on the Mac
/// arriving through iCloud, or a download finishing. `changed` is called on the main queue,
/// at most once a second, with the files changed since (nil: the folder itself, so anything).
/// `conflicted`, at once, with a note iCloud has found changed on two devices before either synced.
final class VaultPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main
    private let changed: @MainActor (Set<URL>?) -> Void
    private let conflicted: @MainActor (URL) -> Void
    private var pending: DispatchWorkItem?
    /// The files heard of since `changed` was last called; nil once the folder itself is.
    private var urls: Set<URL>? = []

    init(root: URL, changed: @escaping @MainActor (Set<URL>?) -> Void, conflicted: @escaping @MainActor (URL) -> Void) {
        presentedItemURL = root
        self.changed = changed
        self.conflicted = conflicted
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedSubitemDidChange(at url: URL) { schedule([url]) }
    func presentedSubitemDidAppear(at url: URL) { schedule([url]) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { schedule([oldURL, newURL]) }
    func presentedItemDidChange() { schedule(nil) }
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        if version.isConflict { MainActor.assumeIsolated { conflicted(url) } }
        schedule([url])
    }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        completionHandler(nil)
        schedule([url])
    }

    private func schedule(_ changedURLs: Set<URL>?) {
        if let changedURLs { urls?.formUnion(changedURLs) } else { urls = nil }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let heard = urls
            urls = []
            MainActor.assumeIsolated { changed(heard) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
