import Foundation
import Testing
@testable import ClipKit

struct ClipTests {
    let media = "---\ntype: Media\ntitle:\nauthor:\npublished:\nformat:\nsource:\ntopics:\nreferrer:\nsaved:\nread:\n---\n"
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    let saved = Date(timeIntervalSince1970: 1_794_050_000) // 2026-11-07

    @Test func fillsTheMediaTemplate() {
        let clip = Clip(url: URL(string: "https://www.robinsloan.com/winter-garden/magic-circle/")!,
                        title: "Flood fill vs. the magic circle", authors: ["Robin Sloan"], published: "2026-02-09",
                        markdown: "If you’ve used Photoshop…\n\n![The paint bucket](https://www.robinsloan.com/img/flood-fill.webp)")
        let text = ClipNote.text(for: clip, template: media, kind: "Media", saved: saved, calendar: calendar)
        #expect(text == """
        ---
        type: Media
        title: Flood fill vs. the magic circle
        author:
          - "[[Robin Sloan]]"
        published: 2026-02-09
        format: Article
        source: https://www.robinsloan.com/winter-garden/magic-circle/
        topics:
        referrer:
        saved: 2026-11-07
        read:
        ---
        If you’ve used Photoshop…

        ![The paint bucket](https://www.robinsloan.com/img/flood-fill.webp)

        """)
    }

    @Test func withoutATemplateOrWhatsUnknown() {
        let clip = Clip(url: URL(string: "https://example.com/a")!, title: "A: the sequel", markdown: "")
        let text = ClipNote.text(for: clip, selection: "One line.\n\nAnother.", kind: "Media", saved: saved, calendar: calendar)
        #expect(text == """
        ---
        type: Media
        title: "A: the sequel"
        author:
        format: Article
        source: https://example.com/a
        saved: 2026-11-07
        ---
        > One line.
        >
        > Another.

        [A: the sequel](https://example.com/a)

        """)
    }

    @Test func keepsATypeTheTemplateSets() {
        let clip = Clip(url: URL(string: "https://example.com/b")!, title: "B")
        let text = ClipNote.text(for: clip, template: "---\ntype: Book\n---\nNotes:\n", kind: "Media", saved: saved, calendar: calendar)
        #expect(text.hasPrefix("---\ntype: Book\n"))
        #expect(text.contains("\n---\nNotes:\n\n[B](https://example.com/b)\n"))
    }

    @Test func readsClipAddresses() throws {
        let request = ClipRequest(url: URL(string: "https://example.com/a?b=1&c=2")!, title: "A & B", selection: "Some text")
        #expect(ClipRequest(request.address) == request)
        #expect(ClipRequest(URL(string: "point://clip?url=javascript:alert(1)")!) == nil)
        #expect(ClipRequest(URL(string: "point://open?url=https://example.com")!) == nil)
        #expect(ClipRequest(URL(string: "point://clip?url=https%3A%2F%2Fexample.com%2Fx&title=")!)?.title == nil)
    }

    @Test func readsBylinesDatesAndAddresses() {
        #expect(Clip.authors(in: "By Sam Lee and Ann Cole") == ["Sam Lee", "Ann Cole"])
        #expect(Clip.authors(in: "Robin Sloan") == ["Robin Sloan"])
        #expect(Clip.authors(in: "Posted on 9 February 2026 by the editorial team of our wonderful magazine") == [])
        #expect(Clip.authors(in: "https://example.com/sam") == [])
        #expect(Clip.day("2026-02-09T10:00:00Z") == "2026-02-09")
        #expect(Clip.day("February 9") == nil)
        #expect(Clip.cleaned(URL(string: "https://example.com/a?utm_source=x&id=3&fbclid=y")!).absoluteString == "https://example.com/a?id=3")
        #expect(Clip.format(of: URL(string: "https://www.youtube.com/watch?v=1")!) == "Video")
        #expect(Clip.format(of: URL(string: "https://notyoutube.com/x")!) == "Article")
    }

    @Test func tidiesMarkdown() {
        #expect(Clip.tidyMarkdown("\n\nA  \n\n\n\nB\u{00A0}\n\n") == "A\n\nB")
        #expect(Clip.tidyMarkdown("Pho\u{00AD}to\n\n  ![x](y)\n \u{00A0}\n\nZ") == "Photo\n\n![x](y)\n\nZ")
        #expect(Clip.tidyMarkdown("- One\n  more\n\n  still one\n\n```\n  code\n\n\n```") == "- One\n  more\n\n  still one\n\n```\n  code\n\n\n```")
        #expect(Clip.title("Good services | Example", siteName: "Example") == "Good services")
        #expect(Clip.title("Good services — Example Blog", siteName: "Example Blog") == "Good services")
        #expect(Clip.title("Example", siteName: "Example") == "Example")
        #expect(Clip.title("Why X | Y matters", siteName: nil) == "Why X | Y matters")
    }

    @MainActor @Test func extractsAnArticle() async throws {
        let paragraph = "This is a long paragraph about service design that goes on for a while, so that Readability treats it as the article and not as a sidebar or navigation. "
        let html = """
        <!doctype html><html><head><title>Good services | Example</title>
        <meta property="og:site_name" content="Example">
        <meta property="article:published_time" content="2025-06-01T09:00:00Z">
        <meta name="author" content="Lou Downe">
        <script>document.title = "hacked"</script></head>
        <body><nav><a href="/">Home</a> <a href="/about">About</a></nav>
        <article><h1>Good services</h1>
        <p>\(paragraph)\(paragraph)</p>
        <p>A <a href="/rules">relative link</a> and <strong>bold</strong> text. \(paragraph)</p>
        <ul><li>One</li><li>Two<ul><li>Two and a half</li></ul></li></ul><ol start="3"><li>Three</li><li>Four</li></ol>
        <img src="/img/a.png" alt="A picture">
        <p>\(paragraph)</p></article>
        <footer>Copyright</footer></body></html>
        """
        let clip = try await ClipExtractor().clip(html: html, url: URL(string: "https://example.com/posts/good?utm_source=feed")!)
        #expect(clip.title == "Good services")
        #expect(clip.authors == ["Lou Downe"])
        #expect(clip.published == "2025-06-01")
        #expect(clip.siteName == "Example")
        #expect(clip.url.absoluteString == "https://example.com/posts/good")
        #expect(clip.markdown.contains("[relative link](https://example.com/rules)"))
        #expect(clip.markdown.contains("**bold**"))
        #expect(clip.markdown.contains("- One\n- Two\n  - Two and a half"))
        #expect(clip.markdown.contains("3. Three\n4. Four"))
        #expect(clip.markdown.contains("![A picture](https://example.com/img/a.png)"))
        #expect(!clip.markdown.contains("Home"))
        #expect(!clip.markdown.contains("Copyright"))
    }
}

/// Clips a live page, to try the clipper on the real web: `POINT_CLIP_URL=https://… swift test`.
/// Skipped otherwise.
struct LiveClipTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["POINT_CLIP_URL"] != nil))
    func clipsALivePage() async throws {
        let url = try #require(ProcessInfo.processInfo.environment["POINT_CLIP_URL"].flatMap(URL.init(string:)))
        let clip = try await ClipExtractor().clip(url)
        print(ClipNote.text(for: clip, kind: "Media"))
        #expect(!clip.markdown.isEmpty)
    }
}
