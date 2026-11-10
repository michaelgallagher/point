import Foundation

/// When each note in the trash was deleted, and where from, by its name there. Those Point
/// deleted are kept in the vault, a small file each (`.point/trash/<name>.json`), so a note
/// deleted on one device goes back where it was from another, and two devices never write the
/// same file. Those it found there (put there by Obsidian, say) are kept by the app, through
/// `loadLocal` and `saveLocal`, as all of them used to be.
public struct TrashRecords {
    public let root: URL
    private let loadLocal: () -> Data?
    private let saveLocal: (Data?) -> Void

    public init(root: URL, loadLocal: @escaping () -> Data?, saveLocal: @escaping (Data?) -> Void) {
        self.root = root
        self.loadLocal = loadLocal
        self.saveLocal = saveLocal
    }

    public static func folder(in root: URL) -> URL { root.appendingPathComponent(".point/trash", isDirectory: true) }

    static func file(for name: String, in root: URL) -> URL { folder(in: root).appendingPathComponent(name + ".json") }

    /// Every record, the vault's over the app's.
    public var all: [String: VaultTrash.Record] {
        local.merging(Self.shared(in: root)) { _, shared in shared }
    }

    /// Makes the records `records`: those Point deleted written to the vault, the rest kept by
    /// the app. Only what's changed from `all` is written or removed, so records another device
    /// has added meanwhile are kept.
    public func set(_ records: [String: VaultTrash.Record]) throws {
        let shared = Self.shared(in: root)
        for (name, record) in records where record.deletedByPoint && shared[name] != record {
            try Self.write(record, for: name, in: root)
        }
        for name in shared.keys where records[name] == nil {
            Self.remove(name, in: root)
        }
        let own = records.filter { !$0.value.deletedByPoint }
        saveLocal(own.isEmpty ? nil : try? JSONEncoder().encode(own))
    }

    /// Records Point kept on this device alone, before they were in the vault, moved there.
    public func shareOwn() {
        guard local.contains(where: { $0.value.deletedByPoint }) else { return }
        try? set(all)
    }

    private var local: [String: VaultTrash.Record] {
        loadLocal().flatMap { try? JSONDecoder().decode([String: VaultTrash.Record].self, from: $0) } ?? [:]
    }

    static func shared(in root: URL) -> [String: VaultTrash.Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(in: root), includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [String: VaultTrash.Record] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? NoteReader.coordinated(file, { try Data(contentsOf: $0) }),
                  let record = try? decoder.decode(VaultTrash.Record.self, from: data) else { continue }
            records[file.deletingPathExtension().lastPathComponent] = record
        }
        return records
    }

    private static func write(_ record: VaultTrash.Record, for name: String, in root: URL) throws {
        let url = file(for: name, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(record)
        data.append(0x0A)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    private static func remove(_ name: String, in root: URL) {
        let url = file(for: name, in: root)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }
}
