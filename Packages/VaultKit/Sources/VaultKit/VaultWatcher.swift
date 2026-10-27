import CoreServices
import Foundation

/// Reports changes to files in a vault, from any app or device, using FSEvents.
public final class VaultWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Point.VaultWatcher")
    /// The vault's path as the file system reports it (FSEvents gives `/private/var/…` where
    /// Foundation's own resolving gives `/var/…`), and as given: changes are matched to either.
    private let rootPaths: [String]
    private let onChange: @Sendable ([URL]) -> Void
    private let onMissedChanges: @Sendable () -> Void
    /// Whether watching started. If not, changes made elsewhere aren't reported at all.
    public private(set) var isWatching = false

    /// Starts watching `root`. `onChange` receives the changed files (never inside the vault's
    /// dot-folders, such as `.obsidian`), batched over `latency` seconds, on a background
    /// queue. `onMissedChanges` is called when changes may have gone unreported (events
    /// dropped while the system was busy, or the vault's folder moved), so the whole vault
    /// should be looked at again.
    public init(root: URL, latency: TimeInterval = 0.3,
                onChange: @escaping @Sendable ([URL]) -> Void,
                onMissedChanges: @escaping @Sendable () -> Void = {}) {
        rootPaths = Array(Set([root.path, root.resolvingSymlinksInPath().path, realpath(root.path, nil).map {
            defer { free($0) }
            return String(cString: $0)
        } ?? root.path]))
        self.onChange = onChange
        self.onMissedChanges = onMissedChanges
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
                let array = unsafeBitCast(paths, to: NSArray.self)
                let events = (0..<count).compactMap { index in (array[index] as? String).map { ($0, eventFlags[index]) } }
                watcher.handle(events)
            },
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            isWatching = FSEventStreamStart(stream)
        }
    }

    private func handle(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        if events.contains(where: { Self.meansMissedChanges($0.flags) }) { onMissedChanges() }
        let urls = Self.notePaths(events.map(\.path), under: rootPaths).map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { onChange(urls) }
    }

    /// The paths that are the vault's own files: not in its dot-folders (`.obsidian`,
    /// `.trash`), but iCloud's placeholders (`.Note.md.icloud`) count. Only folders inside the
    /// vault are looked at: a vault kept inside a dot-folder of its own is still watched.
    static func notePaths(_ paths: [String], under roots: [String]) -> [String] {
        paths.filter { path in
            let root = roots.first { path.hasPrefix($0 + "/") }
            let relative = root.map { path.dropFirst($0.count + 1) } ?? Substring(path)
            return !relative.split(separator: "/").contains { $0.hasPrefix(".") && $0 != ".." } || path.hasSuffix(".icloud")
        }
    }

    /// Whether an event says some changes went unreported: the system dropped events, or
    /// asks for a folder to be scanned again, or the vault's own folder was moved or deleted.
    static func meansMissedChanges(_ flags: FSEventStreamEventFlags) -> Bool {
        let missed = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        return flags & FSEventStreamEventFlags(missed) != 0
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isWatching = false
    }

    deinit { stop() }
}
