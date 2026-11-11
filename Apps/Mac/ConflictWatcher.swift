import Foundation

/// Told by the system when iCloud keeps a conflict version of a note in the vault: one
/// changed on two devices (the iPhone and this Mac, say) before either had synced. The file
/// watcher doesn't hear of these, as the note's own file needn't change. `conflicted` is
/// called on the main queue with the note.
final class ConflictWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main
    private let conflicted: @MainActor (URL) -> Void

    init(root: URL, conflicted: @escaping @MainActor (URL) -> Void) {
        presentedItemURL = root
        self.conflicted = conflicted
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        guard version.isConflict else { return }
        MainActor.assumeIsolated { conflicted(url) }
    }
}
