import AppKit
import Testing
@testable import EditorKit

/// Every note of a real vault (or a copy) loaded into the editor: its text must come back
/// byte for byte, so opening a note and saving it untouched changes nothing (see
/// `plan/live-vault-safety.md`, phase 2). Runs only when `POINT_AUDIT_VAULT` names a vault;
/// reads only. Lists any that differ in `POINT_AUDIT_REPORT`.
@MainActor
struct VaultRoundTripAudit {
    @Test func everyNoteRoundTrips() throws {
        guard let path = ProcessInfo.processInfo.environment["POINT_AUDIT_VAULT"] else { return }
        let root = URL(fileURLWithPath: path)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" } ?? []
        let view = EditorTestSupport.makeEditor("", height: 600)
        var differing: [String] = []
        var count = 0
        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard Data(text.utf8) == data else { continue } // Point won't open these.
            view.load(text)
            count += 1
            if Data(view.string.utf8) != data { differing.append(url.path.replacingOccurrences(of: root.path + "/", with: "")) }
        }
        let report = "# Editor round trip\n\n- Notes loaded: \(count)\n- Notes whose text changed: \(differing.count)\n" + differing.map { "  - \($0)\n" }.joined()
        let out = ProcessInfo.processInfo.environment["POINT_AUDIT_REPORT"] ?? NSTemporaryDirectory() + "editor-round-trip.md"
        try report.write(toFile: out, atomically: true, encoding: .utf8)
        #expect(differing.isEmpty)
    }
}
