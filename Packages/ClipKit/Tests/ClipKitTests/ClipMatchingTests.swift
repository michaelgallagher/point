import ClipKit
import XCTest

final class ClipMatchingTests: XCTestCase {
    private func candidate(_ title: String, _ source: String? = nil) -> ClipMatching.Candidate {
        ClipMatching.Candidate(id: title + ".md", title: title, source: source)
    }

    func testTheSamePageAtAnotherAddress() {
        let key = ClipMatching.pageKey(URL(string: "https://www.example.com/posts/how-teams-decide/")!)
        for other in ["http://example.com/posts/how-teams-decide", "https://m.example.com/posts/how-teams-decide?ref=feed#top",
                      "https://example.com/posts/How-Teams-Decide/amp", "https://example.com/posts/how-teams-decide/index.html"] {
            XCTAssertEqual(ClipMatching.pageKey(URL(string: other)!), key, other)
        }
        XCTAssertNotEqual(ClipMatching.pageKey(URL(string: "https://example.com/posts/how-teams-decide-2")!), key)
        XCTAssertNotEqual(ClipMatching.pageKey(URL(string: "https://other.com/posts/how-teams-decide")!), key)
    }

    func testYouTubeVideosByTheirID() {
        XCTAssertEqual(ClipMatching.pageKey(URL(string: "https://youtu.be/abc123?t=40")!),
                       ClipMatching.pageKey(URL(string: "https://www.youtube.com/watch?v=abc123&list=x")!))
        XCTAssertNotEqual(ClipMatching.pageKey(URL(string: "https://youtube.com/watch?v=abc123")!),
                          ClipMatching.pageKey(URL(string: "https://youtube.com/watch?v=def456")!))
    }

    func testNearMissesSamePageFirstThenSimilarTitles() {
        let candidates = [
            candidate("Teams and decisions", "https://other.com/teams"),
            candidate("How teams decide in practice"),
            candidate("Old notes", "http://www.example.com/posts/how-teams-decide/"),
            candidate("Shopping list"),
        ]
        let matches = ClipMatching.nearMisses(url: URL(string: "https://example.com/posts/how-teams-decide")!,
                                              title: "How Teams Decide, in Practice | The Example", among: candidates)
        XCTAssertEqual(matches.map(\.title), ["Old notes", "How teams decide in practice"])
        XCTAssertEqual(matches.map(\.reason), [.samePage, .similarTitle])
    }

    func testSimilarTitles() {
        func similar(_ a: String, _ b: String) -> Bool {
            !ClipMatching.nearMisses(url: URL(string: "https://a.com/x")!, title: a, among: [candidate(b)]).isEmpty
        }
        XCTAssertTrue(similar("The quiet power of slow gardens", "Quiet power of slow gardens"))
        XCTAssertTrue(similar("Café culture in Paris – Le Monde", "Cafe culture in Paris"))
        XCTAssertTrue(similar("Why design systems fail at scale", "Why design systems fail at scale, and what to do about it"))
        XCTAssertFalse(similar("Design systems at scale", "Design leadership at scale"))
        XCTAssertFalse(similar("Notes", "Notes from Monday"))
        XCTAssertFalse(similar("Weekly planning", "Weekly review"))
    }
}
