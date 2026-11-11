import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VaultKit

struct WebImagesTests {
    private let root = URL(fileURLWithPath: "/v")
    private let noteURL = URL(fileURLWithPath: "/v/Clippings/Storm hits the coast.md")

    private func image(_ path: String) -> VaultImage {
        VaultImage(path: path, url: root.appendingPathComponent(path))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WebImages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png() -> Data {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    // MARK: Finding

    @Test func findsWebPicturesOnly() {
        let text = """
        ---
        cover: "![x](https://in.properties/a.jpg)"
        ---
        ![A wave](https://cdn.example.com/a.jpg)
        ![[Local.png]] and ![local](Attachments/b.png)
        `![code](https://in.code/c.png)`

        ```
        ![fenced](https://in.fence/d.png)
        ```
        ![](<https://cdn.example.com/with space.png> "A title")
        <img src="https://cdn.example.com/e.webp" alt="Rain &amp; wind" width="300">
        [![Linked](https://cdn.example.com/f.png)](https://example.com/page)

        """
        let found = WebImages.find(in: text)
        #expect(found.map(\.address) == ["https://cdn.example.com/a.jpg", "https://cdn.example.com/with space.png",
                                         "https://cdn.example.com/e.webp", "https://cdn.example.com/f.png"])
        #expect(found.map(\.alt) == ["A wave", "", "Rain & wind", "Linked"])
        #expect(found.map(\.isLinked) == [false, false, false, true])
        #expect(found.map(\.isHTML) == [false, false, true, false])
        #expect(found[2].width == 300)
        #expect(WebImages.mightHaveAny(in: text))
        #expect(!WebImages.mightHaveAny(in: "![[a.png]] and [a link](notes/b.md)"))
    }

    @Test func aWidthInTheAltTextIsKept() {
        let found = WebImages.find(in: "![Chart|400](https://x.com/c.png)\n")
        #expect(found.first?.alt == "Chart")
        #expect(found.first?.width == 400)
    }

    // MARK: Writing the links

    @Test func writesWikilinksWithTheirAltText() {
        let text = "Intro\n\n![A \\[big\\] wave | crashing](https://cdn.example.com/a.jpg)\n\n![](https://cdn.example.com/b.png)\n\n![Chart|400](https://x.com/c.png)\n"
        let saved = ["https://cdn.example.com/a.jpg": image("Attachments/Storm hits the coast 1.jpg"),
                     "https://cdn.example.com/b.png": image("Attachments/Storm hits the coast 2.png"),
                     "https://x.com/c.png": image("Attachments/Storm hits the coast 3.png")]
        let edits = WebImages.edits(for: text, saved: saved, noteURL: noteURL, root: root, style: .wikilink)
        #expect(WebImages.applying(edits, to: text) == """
        Intro

        ![[Storm hits the coast 1.jpg|A big wave crashing]]

        ![[Storm hits the coast 2.png]]

        ![[Storm hits the coast 3.png|400]]

        """)
    }

    @Test func aLinkedPictureStaysALink() {
        let text = "[![Map](https://cdn.example.com/map.png)](https://example.com/map)\n"
        let saved = ["https://cdn.example.com/map.png": image("Attachments/Storm hits the coast 1.png")]
        let result = WebImages.applying(WebImages.edits(for: text, saved: saved, noteURL: noteURL, root: root, style: .wikilink), to: text)
        #expect(result == "[![Map](Storm%20hits%20the%20coast%201.png)](https://example.com/map)\n")
    }

    @Test func writesMarkdownLinksAsTheVaultSays() {
        let text = "![A wave](https://cdn.example.com/a.jpg)\n<img src='https://cdn.example.com/b.png' alt='Sea [front]'>\n"
        let saved = ["https://cdn.example.com/a.jpg": image("Attachments/Storm hits the coast 1.jpg"),
                     "https://cdn.example.com/b.png": image("Attachments/Storm hits the coast 2.png")]
        func rewritten(_ format: WebImages.LinkStyle.LinkFormat) -> String {
            WebImages.applying(WebImages.edits(for: text, saved: saved, noteURL: noteURL, root: root, style: .markdown(format)), to: text)
        }
        #expect(rewritten(.shortest) == "![A wave](Storm%20hits%20the%20coast%201.jpg)\n![Sea \\[front\\]](Storm%20hits%20the%20coast%202.png)\n")
        #expect(rewritten(.absolute) == "![A wave](Attachments/Storm%20hits%20the%20coast%201.jpg)\n![Sea \\[front\\]](Attachments/Storm%20hits%20the%20coast%202.png)\n")
        #expect(rewritten(.relative) == "![A wave](../Attachments/Storm%20hits%20the%20coast%201.jpg)\n![Sea \\[front\\]](../Attachments/Storm%20hits%20the%20coast%202.png)\n")
    }

    @Test func picturesNotSavedStayAsTheyWere() {
        let text = "![a](https://x.com/a.jpg)\n![b](https://x.com/b.jpg)\n![a again](https://x.com/a.jpg)\n"
        let saved = ["https://x.com/a.jpg": image("Note 1.jpg")]
        let result = WebImages.applying(WebImages.edits(for: text, saved: saved, noteURL: noteURL, root: root, style: .wikilink), to: text)
        #expect(result == "![[Note 1.jpg|a]]\n![b](https://x.com/b.jpg)\n![[Note 1.jpg|a again]]\n")
    }

    @Test func theLinkStyleComesFromObsidian() {
        var settings = ObsidianSettings()
        #expect(WebImages.LinkStyle(settings: settings) == .wikilink)
        settings.usesMarkdownLinks = true
        settings.newLinkFormat = "relative"
        #expect(WebImages.LinkStyle(settings: settings) == .markdown(.relative))
    }

    // MARK: Saving

    @Test func picturesAreKeptByWhatTheyAre() {
        #expect(WebImages.prepared(png())?.ext == "png")
        #expect(WebImages.prepared(Data("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8))?.ext == "svg")
        #expect(WebImages.prepared(Data("<!doctype html><html><body>Not found</body></html>".utf8)) == nil)
    }

    @Test func savesInOrderNamedAfterTheNoteWithoutOverwriting() throws {
        let vault = try folder()
        defer { try? FileManager.default.removeItem(at: vault) }
        let attachments = vault.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let existing = attachments.appendingPathComponent("Storm hits the coast 1.png")
        try Data("mine".utf8).write(to: existing)
        let url = vault.appendingPathComponent("Storm hits the coast.md")
        let note = Note(id: "Storm hits the coast.md", url: url, title: "Storm hits the coast", modified: Date(), created: Date(), isDownloaded: true)
        let data = png()
        let result = WebImages.save([("https://x.com/a.png", .init(data: data, ext: "png")),
                                     ("https://x.com/b.svg", .init(data: data, ext: "svg")),
                                     ("https://x.com/a.png", .init(data: data, ext: "png"))],
                                    forNote: note, vault: vault, setting: "Attachments", taken: ["storm hits the coast 2.jpg"])
        #expect(result.failed.isEmpty)
        #expect(result.saved["https://x.com/a.png"]?.path == "Attachments/Storm hits the coast 3.png")
        #expect(result.saved["https://x.com/b.svg"]?.path == "Attachments/Storm hits the coast 4.svg")
        #expect(try Data(contentsOf: existing) == Data("mine".utf8))
    }

    @Test func namesAreWrittenAsTheNoteSpellsThem() throws {
        let vault = try folder()
        defer { try? FileManager.default.removeItem(at: vault) }
        let title = "Storm Ciar\u{E1}n" // á, as one character, as typed.
        let note = Note(id: title + ".md", url: vault.appendingPathComponent(title + ".md"), title: title, modified: Date(), created: Date(), isDownloaded: true)
        let result = WebImages.save([("https://x.com/a.png", .init(data: png(), ext: "png"))], forNote: note, vault: vault, setting: "")
        let name = try #require(result.saved["https://x.com/a.png"]?.name)
        #expect(name.unicodeScalars.elementsEqual("Storm Ciar\u{E1}n 1.png".unicodeScalars))
        #expect(result.saved["https://x.com/a.png"]?.path.unicodeScalars.elementsEqual(name.unicodeScalars) == true)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(name).path))
    }

    /// Over the network, so only with `POINT_NETWORK_TESTS=1`: pictures downloaded at once, an
    /// address that's gone reported as such.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["POINT_NETWORK_TESTS"] != nil))
    func downloadsSeveralAtOnce() async throws {
        let cache = WebImageCache(folder: try folder())
        defer { try? FileManager.default.removeItem(at: cache.folder) }
        let addresses = ["https://upload.wikimedia.org/wikipedia/commons/5/50/Windstorm_Thomas.jpg",
                         "https://upload.wikimedia.org/wikipedia/commons/4/45/Flag_of_Ireland.svg",
                         "https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1c/Flag_of_Jersey.svg/960px-Flag_of_Jersey.svg.png",
                         "https://upload.wikimedia.org/wikipedia/commons/0/00/This_file_does_not_exist_point_test.jpg"]
        let start = Date()
        let results = await WebImages.download(addresses + [addresses[0]], cache: cache)
        print("downloaded in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        #expect(results.count == 4)
        #expect((try? results[addresses[0]]?.get())?.ext == "jpg")
        #expect((try? results[addresses[1]]?.get())?.ext == "svg")
        #expect((try? results[addresses[2]]?.get()) != nil)
        guard case .failure(.http(404))? = results[addresses[3]] else { Issue.record("expected a 404"); return }
    }
}
