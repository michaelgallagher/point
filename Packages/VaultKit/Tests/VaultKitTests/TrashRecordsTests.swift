import Foundation
import Testing
@testable import VaultKit

@Suite struct TrashRecordsTests {
    /// A device: the vault's records, and its own kept apart.
    private final class Device {
        var data: Data?
        func records(_ root: URL) -> TrashRecords { TrashRecords(root: root, loadLocal: { self.data }, saveLocal: { self.data = $0 }) }
    }

    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TrashRecords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let day = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func eachDeviceSeesTheOthersDeletions() throws {
        let root = try makeVault()
        let mac = Device(), phone = Device()
        var onMac = mac.records(root).all
        onMac["Plan.md"] = VaultTrash.Record(deleted: day, folder: "Projects", deletedByPoint: true)
        try mac.records(root).set(onMac)
        var onPhone = phone.records(root).all
        #expect(onPhone["Plan.md"]?.folder == "Projects")
        onPhone["Trip.md"] = VaultTrash.Record(deleted: day, folder: "Travel", deletedByPoint: true)
        try phone.records(root).set(onPhone)
        #expect(Set(mac.records(root).all.keys) == ["Plan.md", "Trip.md"])
        // Put back on the Mac: forgotten on both.
        onMac = mac.records(root).all
        onMac["Plan.md"] = nil
        try mac.records(root).set(onMac)
        #expect(Set(phone.records(root).all.keys) == ["Trip.md"])
    }

    @Test func aRecordArrivingLaterIsKept() throws {
        let root = try makeVault()
        let mac = Device(), phone = Device()
        // The phone changes its records before the Mac's has arrived through iCloud…
        try phone.records(root).set(["Trip.md": VaultTrash.Record(deleted: day, folder: "Travel", deletedByPoint: true)])
        // …and it arrives: both kept, each in a file of its own.
        try mac.records(root).set(mac.records(root).all.merging(["Plan.md": VaultTrash.Record(deleted: day, folder: "Projects", deletedByPoint: true)]) { $1 })
        try phone.records(root).set(phone.records(root).all)
        #expect(Set(mac.records(root).all.keys) == ["Plan.md", "Trip.md"])
    }

    @Test func foundNotesStayOnTheDevice() throws {
        let root = try makeVault()
        let mac = Device(), phone = Device()
        try mac.records(root).set(["Old.md": VaultTrash.Record(deleted: day, folder: "", deletedByPoint: false)])
        #expect(phone.records(root).all.isEmpty)
        #expect(mac.records(root).all["Old.md"] != nil)
    }

    @Test func recordsKeptOnTheDeviceMoveIntoTheVault() throws {
        let root = try makeVault()
        let mac = Device(), phone = Device()
        mac.data = try JSONEncoder().encode(["Plan.md": VaultTrash.Record(deleted: day, folder: "Projects", deletedByPoint: true)])
        mac.records(root).shareOwn()
        #expect(phone.records(root).all["Plan.md"]?.folder == "Projects")
        #expect(mac.data == nil)
        let file = try String(contentsOf: TrashRecords.file(for: "Plan.md", in: root), encoding: .utf8)
        #expect(file.hasSuffix("}\n"))
        #expect(file.contains("\"folder\" : \"Projects\""))
    }
}
