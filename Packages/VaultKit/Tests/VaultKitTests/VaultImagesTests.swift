import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VaultKit

struct VaultImagesTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VaultImages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func imagesAreKnownByExtension() {
        #expect(VaultImages.isImage("a.PNG"))
        #expect(VaultImages.isImage("photo.heic"))
        #expect(!VaultImages.isImage("note.md"))
        #expect(!VaultImages.isImage(".hidden.png"))
        #expect(!VaultImages.isImage("png"))
    }

    @Test func theAttachmentFolderFollowsObsidian() {
        let root = URL(fileURLWithPath: "/v")
        let note = URL(fileURLWithPath: "/v/Projects/Plan.md")
        #expect(VaultImages.folder(forNoteAt: note, vault: root, setting: "").path == "/v")
        #expect(VaultImages.folder(forNoteAt: note, vault: root, setting: "./").path == "/v/Projects")
        #expect(VaultImages.folder(forNoteAt: note, vault: root, setting: "./assets").path == "/v/Projects/assets")
        #expect(VaultImages.folder(forNoteAt: note, vault: root, setting: "Attachments").path == "/v/Attachments")
    }

    @Test func imagesAreNamedAfterTheirNote() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(VaultImages.availableName(forNote: "2026-11-06-meeting", ext: "png", in: dir) == "2026-11-06-meeting-1.png")
        #expect(VaultImages.availableName(forNote: "Meeting", ext: "png", in: dir) == "Meeting 1.png")
        try Data().write(to: dir.appendingPathComponent("2026-11-06-meeting-1.jpg"))
        // Numbered past any image of the note, whatever its kind.
        #expect(VaultImages.availableName(forNote: "2026-11-06-meeting", ext: "png", in: dir) == "2026-11-06-meeting-2.png")
        #expect(VaultImages.availableName(forNote: "2026-11-06-meeting", ext: "png", in: dir, taken: ["2026-11-06-meeting-2.png"])
                == "2026-11-06-meeting-3.png")
    }

    @Test func imagesFollowTheirNoteRenamed() {
        #expect(VaultImages.renamed("2026-11-06-meeting-2.png", fromNote: "2026-11-06-meeting", toNote: "2026-11-06-standup") == "2026-11-06-standup-2.png")
        #expect(VaultImages.renamed("Meeting 3.jpg", fromNote: "Meeting", toNote: "Standup") == "Standup 3.jpg")
        #expect(VaultImages.renamed("Meeting notes.png", fromNote: "Meeting", toNote: "Standup") == nil)
        #expect(VaultImages.renamed("Pasted image 2026.png", fromNote: "Meeting", toNote: "Standup") == nil)
        #expect(VaultImages.renamed("2026-11-06-meeting-plan-1.png", fromNote: "2026-11-06-meeting", toNote: "x") == nil)
    }

    @Test func findsEmbedsOfEveryKind() {
        let text = "![[a.png]]\n![[b.jpg|300]]\n![[Note]]\n![alt](Attachments/c%20d.png)\n![w|200](https://x.com/e.gif)\n[[f.png]]\n"
        let embeds = VaultImages.embeds(in: text)
        #expect(embeds.map(\.name) == ["a.png", "b.jpg", "c d.png", "e.gif"])
        #expect(embeds.map(\.width) == [nil, 300, nil, 200])
        #expect(embeds.map(\.isWeb) == [false, false, false, true])
    }

    @Test func renamesEmbedsAsWritten() {
        let text = "![[Meeting 1.png|300]] and ![x](Attachments/Meeting%201.png) and ![[Other.png]]"
        #expect(VaultImages.renamingEmbeds(of: "meeting 1.png", to: "Standup 1.png", in: text)
                == "![[Standup 1.png|300]] and ![x](Attachments/Standup%201.png) and ![[Other.png]]")
        #expect(VaultImages.renamingEmbeds(of: "none.png", to: "x.png", in: text) == nil)
    }

    @Test func resolvesByNameNearestTheTop() {
        let root = URL(fileURLWithPath: "/v")
        let images = [VaultImage(path: "Deep/Down/a.png", url: root.appendingPathComponent("Deep/Down/a.png")),
                      VaultImage(path: "Attachments/a.png", url: root.appendingPathComponent("Attachments/a.png"))]
        let byName = VaultImages.byName(images)
        #expect(VaultImages.resolve("A.png", from: "Note.md", images: byName, root: root)?.path == "Attachments/a.png")
        #expect(VaultImages.resolve("Some/Path/a.png", from: "Note.md", images: byName, root: root)?.path == "Attachments/a.png")
        #expect(VaultImages.resolve("https://x.com/a.png", from: "Note.md", images: byName, root: root) == nil)
        #expect(VaultImages.resolve("missing.png", from: "Note.md", images: byName, root: root) == nil)
    }

    @Test func findsUnusedImages() {
        let images = ["b.png", "a.png", "c.png"].map { VaultImage(path: $0, url: URL(fileURLWithPath: "/v/" + $0)) }
        #expect(VaultImages.unused(images, linkedNames: ["b.png"]).map(\.name) == ["a.png", "c.png"])
    }

    @Test func savesScreenshotsAsPNGAndPhotosAsJPEG() throws {
        let tiff = try Self.image(.tiff)
        #expect(VaultImages.forSaving(tiff, type: .tiff)?.ext == "png")
        let png = try Self.image(.png)
        #expect(VaultImages.forSaving(png, type: nil).map { ($0.ext, $0.data) } ?? ("", Data()) == ("png", png))
        #expect(VaultImages.forSaving(Data("not an image".utf8), type: nil) == nil)
    }

    @Test func savesNextToNothingElseItsNamedFor() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let noteURL = root.appendingPathComponent("2026-11-06-meeting.md")
        try Data("x".utf8).write(to: noteURL)
        let note = Note(id: "2026-11-06-meeting.md", url: noteURL, title: "Meeting", modified: Date(), created: Date(), isDownloaded: true)
        let first = try VaultImages.save(try Self.image(.png), type: .png, forNote: note, vault: root, setting: "Attachments")
        let second = try VaultImages.save(try Self.image(.tiff), type: .tiff, forNote: note, vault: root, setting: "Attachments")
        #expect(first.path == "Attachments/2026-11-06-meeting-1.png")
        #expect(second.path == "Attachments/2026-11-06-meeting-2.png")
        #expect(FileManager.default.fileExists(atPath: second.url.path))
    }

    @Test func theScanFindsImages() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Attachments/a.png"))
        try Data().write(to: root.appendingPathComponent("Attachments/.b.jpg.icloud"))
        try Data().write(to: root.appendingPathComponent("Note.md"))
        let scan = try VaultScanner.scanAll(root)
        #expect(scan.notes.map(\.id) == ["Note.md"])
        #expect(Set(scan.images.map(\.path)) == ["Attachments/a.png", "Attachments/b.jpg"])
        #expect(scan.images.first { $0.name == "b.jpg" }?.isDownloaded == false)
    }

    @Test func imagesGoToTheTrashAndComeBack() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Attachments/a.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: url)
        let trashed = VaultTrash.move([VaultImage(path: "Attachments/a.png", url: url)], vault: root)
        #expect(trashed == [VaultTrash.TrashedImage(name: "a.png", path: "Attachments/a.png")])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Not listed as a note in the trash.
        #expect(VaultTrash.items(in: root, records: [:]).isEmpty)
        VaultTrash.restore(trashed, vault: root)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// A small image, encoded as `type`.
    static func image(_ type: UTType) throws -> Data {
        let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
