import AppKit
import VaultKit

/// The open vault and its notes.
@MainActor
final class VaultModel: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var notes: [Note] = []
    @Published private(set) var errorMessage: String?
    @Published var selection: Note.ID?
    @Published var sort: NoteSort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Keys.sort)
            notes = notes.sorted(by: sort)
        }
    }

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let sort = "noteSort"
    }

    init() {
        sort = UserDefaults.standard.string(forKey: Keys.sort).flatMap(NoteSort.init) ?? .modified
        restoreVault()
    }

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose the folder that holds your notes. It can be an existing Obsidian vault."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try VaultLocation.bookmark(for: url), forKey: Keys.bookmark)
        } catch {
            errorMessage = "Imprint couldn't remember this folder: \(error.localizedDescription)"
        }
        open(url)
    }

    func reload() async {
        guard let root else { return }
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try VaultScanner.scan(root)
            }.value
            notes = scanned.sorted(by: sort)
            errorMessage = nil
            if let selection, !notes.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch {
            errorMessage = "Imprint couldn't read the vault: \(error.localizedDescription)"
        }
    }

    private func restoreVault() {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "ImprintVault") {
            open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return
        }
        #endif
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.bookmark) else { return }
        do {
            let (url, isStale) = try VaultLocation.resolve(bookmark)
            open(url)
            if isStale, let fresh = try? VaultLocation.bookmark(for: url) {
                UserDefaults.standard.set(fresh, forKey: Keys.bookmark)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: Keys.bookmark)
            errorMessage = "Imprint lost access to your vault. Open it again."
        }
    }

    private func open(_ url: URL) {
        root?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        root = url
        notes = []
        selection = nil
        Task { await reload() }
    }
}
