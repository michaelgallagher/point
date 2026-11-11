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
                        title: "Flood fill vs. the magic circle", authors: ["Robin Sloan"], published: "2026",
                        markdown: "If you’ve used Photoshop…\n\n![The paint bucket](https://www.robinsloan.com/img/flood-fill.webp)")
        let text = ClipNote.text(for: clip, template: media, kind: "Media", saved: saved, calendar: calendar)
        #expect(text == """
        ---
        type: Media
        title: Flood fill vs. the magic circle
        author:
          - "[[Robin Sloan]]"
        published: 2026
        format: Article
        source: https://www.robinsloan.com/winter-garden/magic-circle/
        topics:
        referrer:
        saved: 2026-11-07
        read:
        ---
        ==---- Text ----==

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

        ==---- Text ----==

        [A: the sequel](https://example.com/a)

        """)
    }

    @Test func keepsATypeTheTemplateSets() {
        let clip = Clip(url: URL(string: "https://example.com/b")!, title: "B")
        let text = ClipNote.text(for: clip, template: "---\ntype: Book\n---\nNotes:\n", kind: "Media", saved: saved, calendar: calendar)
        #expect(text.hasPrefix("---\ntype: Book\n"))
        #expect(text.contains("\n---\nNotes:\n\n==---- Text ----==\n\n[B](https://example.com/b)\n"))
    }

    @Test func aTemplateWithTheMarkerKeepsItsOwn() {
        let clip = Clip(url: URL(string: "https://example.com/c")!, title: "C", markdown: "The article.")
        let text = ClipNote.text(for: clip, template: "---\ntype: Media\n---\n## Notes\n\n==---- Text ----==\n", kind: "Media", saved: saved, calendar: calendar)
        #expect(text.hasSuffix("\n---\n## Notes\n\n==---- Text ----==\n\nThe article.\n"))
        #expect(ReaderNotes.notes(in: text) == "## Notes")
    }

    @Test func readsClipAddresses() throws {
        let request = ClipRequest(url: URL(string: "https://example.com/a?b=1&c=2")!, title: "A & B", selection: "Some text")
        #expect(ClipRequest(request.address) == request)
        #expect(ClipRequest(URL(string: "point://clip?url=javascript:alert(1)")!) == nil)
        #expect(ClipRequest(URL(string: "point://open?url=https://example.com")!) == nil)
        #expect(ClipRequest(URL(string: "point://clip?url=https%3A%2F%2Fexample.com%2Fx&title=")!)?.title == nil)
    }

    @Test func readsThePageTheBrowserSent() throws {
        let html = "<!doctype html>\n<html><body><p>Only for subscribers: “café” 東京</p></body></html>"
        let request = ClipRequest(url: URL(string: "https://example.com/a")!, html: html)
        #expect(ClipRequest(request.address)?.html == html)
        // Compressed and in base64url, as the extension sends it: no `+`, `/` or `=`.
        let page = try #require(URLComponents(url: request.address, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value)
        #expect(page.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")) == nil)
        // As a browser's CompressionStream("deflate-raw") packs it, in the extension.
        let sent = try #require(ClipRequest(URL(string: "point://clip?url=https%3A%2F%2Fexample.com%2Fa&page=symw88_LqVRIyy9SKC5NKk4uykxKLSq2UnjUMCc5Me3wykcNcxWezd34ZNcaG_0COwA")!))
        #expect(sent.html == "<p>Only for subscribers: “café” 東京</p>")
        // A page that isn't one is ignored, not a reason to refuse the clip.
        let garbled = try #require(ClipRequest(URL(string: "point://clip?url=https%3A%2F%2Fexample.com%2Fa&page=not-a-page")!))
        #expect(garbled.html == nil)
    }

    @MainActor @Test func leavesOutWhatsAroundANewspaperArticle() async throws {
        let paragraph = { (n: Int) in "Walk \(n): the city is a place of wrenching history and astonishing beauty, best seen at night, when the tour buses have gone and the streets are quiet again. " }
        let figure = { (n: Int) in
            #"<figure><div><span class="visually-hidden">Image</span><img src="https://example.com/\#(n).jpg" alt=""></div><figcaption><span>The bridge at dusk.</span><span><span class="visually-hidden">Credit...</span><span>Ann Lee</span></span></figcaption></figure>"#
        }
        let html = """
        <!doctype html><html><head><title>Night walks - The Daily</title>
        <link rel="canonical" href="https://www.example.com/2026/11/06/night-walks.html">
        <meta property="og:site_name" content="The Daily"></head>
        <body><header><nav><a href="/">Home</a></nav></header>
        <main><article id="story"><header><h1 data-testid="headline">Night walks</h1>
        <p id="summary">The city is a place of wrenching history and astonishing beauty, best seen at night.</p>\(figure(0))
        <div><div><time datetime="2026-11-06">Nov. 6, 2026</time></div></div></header>
        <section name="articleBody"><p>\(paragraph(1))\(paragraph(2))</p>\(figure(1))<p>\(paragraph(3))</p>
        <div data-testid="StandardAd"><p>Advertisement</p><a href="#after">Skip advertisement</a></div>
        <p id="after">\(paragraph(4))\(paragraph(5))</p><p>\(paragraph(6)) We went back on <time datetime="2026-08-01">Aug. 1</time>.</p>
        <div data-testid="DiptychBlock"><div>\(figure(2))</div><div>\(figure(3))</div></div></section></article>
        <div data-testid="related-links"><h2>Related content</h2><p>\(paragraph(7))</p></div>
        <section aria-label="Newsletters"><p>Make sense of the day’s news and ideas.</p></section></main>
        <div aria-label="Trending in The Daily"><h3>Trending</h3><ul><li><a href="/x">\(paragraph(8))</a></li></ul></div>
        </body></html>
        """
        let clip = try await ClipExtractor().clip(html: html, url: URL(string: "https://www.example.com/2026/11/06/night-walks.html?nl=the-world&user_id=123&emc=edit")!)
        #expect(clip.url.absoluteString == "https://www.example.com/2026/11/06/night-walks.html")
        #expect(!clip.markdown.contains("# Night walks"))
        #expect(!clip.markdown.contains("Image"))
        #expect(!clip.markdown.contains("Credit"))
        #expect(clip.markdown.contains("The bridge at dusk. Ann Lee"))
        #expect(!clip.markdown.contains("Advertisement"))
        #expect(!clip.markdown.contains("Related"))
        #expect(!clip.markdown.contains("news and ideas"))
        #expect(!clip.markdown.contains("Trending"))
        for n in 1...6 { #expect(clip.markdown.contains("Walk \(n):")) }
        #expect(!clip.markdown.contains("Nov. 6, 2026"))
        #expect(clip.markdown.contains("We went back on Aug. 1."))
        for n in 0...3 { #expect(clip.markdown.contains("![](https://example.com/\(n).jpg)")) }
        #expect(!clip.markdown.contains("Walk 7:"))
        #expect(!clip.markdown.contains("Walk 8:"))
        // The caption, as different pictures' captions may be the same, is kept each time.
        #expect(clip.markdown.components(separatedBy: "The bridge at dusk. Ann Lee").count == 5)
    }

    @MainActor @Test func takesOnlyTheDateByTheHeadline() async throws {
        let paragraph = "A long paragraph about contextual design, which goes on for a while so that Readability treats it as the article and not as a sidebar. "
        // A course starting soon, and no date for the article: none.
        let undated = """
        <!doctype html><html><head><title>Contextual design</title></head><body>
        <main><div><div><h1>Contextual design</h1></div></div><p>\(paragraph)\(paragraph)\(paragraph)</p></main>
        <aside><p>Next course starts <time datetime="2026-11-18">18 November</time></p></aside></body></html>
        """
        #expect(try await ClipExtractor().clip(html: undated, url: URL(string: "https://example.com/a")!).published == nil)
        let dated = """
        <!doctype html><html><head><title>Night walks</title></head><body><article>
        <header><h1>Night walks</h1><div><time datetime="2024-03-02T05:00:00-05:00">March 2, 2024</time></div></header>
        <p>\(paragraph)\(paragraph)\(paragraph)</p></article></body></html>
        """
        #expect(try await ClipExtractor().clip(html: dated, url: URL(string: "https://example.com/b")!).published == "2024")
    }

    @Test func dropsRepeatsAndTheTitleHeading() {
        let long = "A paragraph long enough that seeing it twice means it's a copy."
        #expect(Clip.withoutRepeats("\(long)\n\n## Night walks\n\n\(long)\n\nYes.\n\nYes.\n\n![](a.jpg)\n\n![](a.jpg)\n\n```\n\(long)\n\n\(long)\n```", title: "Night Walks")
                == "\(long)\n\nYes.\n\nYes.\n\n![](a.jpg)\n\n![](a.jpg)\n\n```\n\(long)\n\n\(long)\n```")
        #expect(Clip.canonical(URL(string: "https://example.com/a"), of: URL(string: "https://www.example.com/a?x=1")!).absoluteString == "https://example.com/a")
        #expect(Clip.canonical(URL(string: "https://elsewhere.com/a"), of: URL(string: "https://example.com/a?x=1")!).absoluteString == "https://example.com/a?x=1")
    }

    @MainActor @Test func keepsHeadingsWithClassesThatSoundLikeThePage() async throws {
        let paragraph = "This is a long paragraph about design leadership that goes on for a while, so that Readability treats it as the article and not as a sidebar or navigation. "
        // As Substack writes its headings: classes with "header" in them (which Readability
        // drops), an anchor button inside, and sometimes the whole heading bold.
        let anchor = #"<div class="header-anchor-parent"><div class="header-anchor" id="§x"></div><button type="button"><svg viewBox="0 0 24 24"><path d="M0 0"/></svg></button></div>"#
        let html = """
        <!doctype html><html><head><title>Jobs</title></head><body><article>
        <p>\(paragraph)\(paragraph)</p>
        <h3 class="header-anchor-post">What is your role\(anchor)</h3>
        <p>\(paragraph)</p>
        <h4 class="header-anchor-post"><strong>1. Are you a practice lead?</strong>\(anchor)</h4>
        <p>\(paragraph)</p>
        <a class="image-link" href="https://cdn.example.com/image/fetch/w_1456/big.jpeg"><picture><img src="https://cdn.example.com/small.jpeg" alt="A chart"></picture></a>
        <a href="https://example.com/elsewhere"><img src="https://example.com/b.png" alt="B"></a>
        <p class="button-wrapper"><a class="button primary" href="https://example.com/p/jobs/comments"><span>Leave a comment</span></a></p>
        <p>\(paragraph)</p></article></body></html>
        """
        let clip = try await ClipExtractor().clip(html: html, url: URL(string: "https://example.com/p/jobs")!)
        #expect(clip.markdown.contains("\n### What is your role\n"))
        #expect(clip.markdown.contains("\n#### 1. Are you a practice lead?\n"))
        #expect(!clip.markdown.contains("Leave a comment"))
        #expect(clip.markdown.contains("\n![A chart](https://cdn.example.com/small.jpeg)\n"))
        #expect(clip.markdown.contains("\n[![B](https://example.com/b.png)](https://example.com/elsewhere)"))
    }

    @Test func readsBylinesDatesAndAddresses() {
        #expect(Clip.authors(in: "By Sam Lee and Ann Cole") == ["Sam Lee", "Ann Cole"])
        #expect(Clip.authors(in: "Robin Sloan") == ["Robin Sloan"])
        #expect(Clip.authors(in: "Posted on 9 February 2026 by the editorial team of our wonderful magazine") == [])
        #expect(Clip.authors(in: "https://example.com/sam") == [])
        #expect(Clip.day("2026-02-09T10:00:00Z") == "2026-02-09")
        #expect(Clip.day("February 9") == nil)
        let now = Date(timeIntervalSince1970: 1_794_000_000) // 7 November 2026
        #expect(Clip.year("2026-02-09T10:00:00Z", now: now) == "2026")
        #expect(Clip.year("2019", now: now) == "2019")
        #expect(Clip.year("2026-11-18", now: now) == nil)
        #expect(Clip.year("2027", now: now) == nil)
        #expect(Clip.year("219014", now: now) == nil)
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
        #expect(clip.published == "2025")
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

/// Clips a live page, to try the clipper on the real web: `POINT_CLIP_URL=https://… swift test`
/// (or a saved one, see below).
/// Skipped otherwise.
struct LiveClipTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["POINT_CLIP_URL"] != nil))
    func clipsALivePage() async throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["POINT_CLIP_URL"].flatMap(URL.init(string:)))
        // A page saved from the browser (`POINT_CLIP_FILE=…`), or a `point://clip` address the
        // extension made, saved to a file (`POINT_CLIP_ADDRESS=…`), instead of fetching it.
        let clip: Clip
        if let file = environment["POINT_CLIP_FILE"] {
            clip = try await ClipExtractor().clip(html: String(contentsOfFile: file, encoding: .utf8), url: url)
        } else if let file = environment["POINT_CLIP_ADDRESS"] {
            let address = try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let request = try #require(URL(string: address).flatMap(ClipRequest.init))
            clip = try await ClipExtractor().clip(html: try #require(request.html), url: request.url)
        } else {
            clip = try await ClipExtractor().clip(url)
        }
        print(ClipNote.text(for: clip, kind: "Media"))
        #expect(!clip.markdown.isEmpty)
    }
}
