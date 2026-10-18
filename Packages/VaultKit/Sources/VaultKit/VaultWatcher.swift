import CoreServices
import Foundation

/// Reports changes to files in a vault, from any app or device, using FSEvents.
public final class VaultWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Imprint.VaultWatcher")
    private let onChange: @Sendable ([URL]) -> Void

    /// Starts watching `root`. `onChange` receives the changed files (never inside dot-folders
    /// such as `.obsidian`), batched over `latency` seconds, on a background queue.
    public init(root: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable ([URL]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
                let array = unsafeBitCast(paths, to: NSArray.self)
                let urls = (0..<count).compactMap { array[$0] as? String }
                    .filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") && $0 != ".." } || $0.hasSuffix(".icloud") }
                    .map { URL(fileURLWithPath: $0) }
                if !urls.isEmpty { watcher.onChange(urls) }
            },
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
