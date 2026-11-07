import Foundation
import Testing
@testable import IndexKit

struct SearchHistoryTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let day: TimeInterval = 24 * 60 * 60

    struct Item: Equatable {
        let id: String
        let quality: Int?
    }

    func ids(_ items: [Item]) -> [String] { items.map(\.id) }

    func rank(_ history: SearchHistory, _ items: [Item], for query: String = "q") -> [String] {
        ids(history.rank(items, for: query, now: now, id: \.id, titleQuality: \.quality))
    }

    @Test func recentQueriesAreNewestFirstAndOncePerSearch() {
        var history = SearchHistory()
        history.picked("a", for: "movi", at: now)
        history.picked("b", for: "Recipes", at: now + 1)
        history.picked("a", for: "movies", at: now + 2)
        history.picked("c", for: "  ", at: now + 3)
        history.picked("d", for: "travel", at: now + 4)
        #expect(history.recentQueries(limit: 10) == ["travel", "movies", "recipes"])
        #expect(history.recentQueries(limit: 2) == ["travel", "movies"])
        #expect(SearchHistory().recentQueries(limit: 5).isEmpty)
    }

    @Test func withNothingLearnedTheOrderIsUnchanged() {
        let items = [Item(id: "b", quality: 1), Item(id: "a", quality: 0), Item(id: "c", quality: nil), Item(id: "d", quality: nil)]
        #expect(rank(SearchHistory(), items) == ["b", "a", "c", "d"])
    }

    @Test func opensCountForLessAsTheyAge() {
        var history = SearchHistory()
        history.opened("a", at: now)
        history.opened("b", at: now.addingTimeInterval(-14 * day))
        #expect(abs(history.score(of: "a", now: now) - 1) < 0.001)
        #expect(abs(history.score(of: "b", now: now) - 0.5) < 0.001)
        #expect(history.score(of: "never", now: now) == 0)
        // An edit counts as an open.
        #expect(abs(history.score(of: "never", modified: now, now: now) - 1) < 0.001)
    }

    @Test func manyOpensBeatOneRecentOne() {
        var history = SearchHistory()
        for k in 0..<10 { history.opened("often", at: now.addingTimeInterval(-Double(k + 10) * day)) }
        history.opened("once", at: now.addingTimeInterval(-day))
        #expect(history.score(of: "often", now: now) > history.score(of: "once", now: now))
    }

    @Test func aTitleMatchMovesUpOnlyWithinItsQuality() {
        var history = SearchHistory()
        history.opened("weak", at: now)
        history.opened("good2", at: now)
        let items = [Item(id: "good1", quality: 0), Item(id: "good2", quality: 0), Item(id: "weak", quality: 3), Item(id: "text", quality: nil)]
        #expect(rank(history, items) == ["good2", "good1", "weak", "text"])
    }

    @Test func aTextMatchMovesUpOnlyAFewPlaces() {
        var history = SearchHistory()
        history.opened("t4", at: now)
        history.opened("t7", at: now)
        let items = (1...8).map { Item(id: "t\($0)", quality: nil) }
        #expect(rank(history, items) == ["t4", "t1", "t2", "t3", "t5", "t7", "t6", "t8"])
    }

    @Test func titleMatchesStayBeforeTextMatches() {
        var history = SearchHistory()
        for _ in 0..<5 { history.opened("text", at: now) }
        #expect(rank(history, [Item(id: "title", quality: 4), Item(id: "text", quality: nil)]) == ["title", "text"])
    }

    @Test func aPickForWhatsTypedComesFirst() {
        var history = SearchHistory()
        history.picked("Meetings.md", for: "MTG ", at: now)
        let items = [Item(id: "Other.md", quality: 0), Item(id: "Meetings.md", quality: 4)]
        #expect(rank(history, items, for: "mtg") == ["Meetings.md", "Other.md"])
        #expect(rank(history, items, for: "mt") == ["Meetings.md", "Other.md"]) // The start of it.
        #expect(rank(history, items, for: "m") == ["Other.md", "Meetings.md"]) // Too little to go on.
        #expect(rank(history, items, for: "mtgs") == ["Meetings.md", "Other.md"]) // More than it.
        #expect(rank(history, items, for: "mx") == ["Other.md", "Meetings.md"])
        // Only among the results: it never adds a note.
        #expect(rank(history, [Item(id: "Other.md", quality: 0)], for: "mtg") == ["Other.md"])
    }

    @Test func aNewerPickReplacesAnOlderOne() {
        var history = SearchHistory()
        history.picked("a", for: "plan", at: now.addingTimeInterval(-day))
        history.picked("b", for: "plan", at: now)
        #expect(history.pick(for: "plan") == "b")
        history.picked("c", for: "planning", at: now)
        #expect(history.pick(for: "plan") == "b") // An exact match first.
        #expect(history.pick(for: "plann") == "c")
    }

    @Test func typingMoreThanAPickWasMadeForStillFindsIt() {
        var history = SearchHistory()
        history.picked("Movies.md", for: "movi", at: now)
        history.picked("Design.md", for: "nhs desi", at: now)
        #expect(history.pick(for: "movies") == "Movies.md")
        #expect(history.pick(for: "movies 2026") == "Movies.md")
        #expect(history.pick(for: "nhs design") == "Design.md")
        #expect(history.pick(for: "nhs design vision") == "Design.md")
        #expect(history.pick(for: "nhs") == "Design.md") // And less.
        #expect(history.pick(for: "mon") == nil)
    }

    @Test func theLongestPickTypedSoFarWins() {
        var history = SearchHistory()
        history.picked("Plans.md", for: "pl", at: now)
        history.picked("Planning.md", for: "plann", at: now.addingTimeInterval(-day))
        #expect(history.pick(for: "planning") == "Planning.md") // "plann" says more than "pl".
        #expect(history.pick(for: "plans") == "Plans.md")
    }

    @Test func renamedNotesKeepTheirHistoryAndDeletedOnesLoseIt() {
        var history = SearchHistory()
        history.picked("Old.md", for: "old", at: now)
        history.renamed(from: "Old.md", to: "New.md")
        #expect(history.pick(for: "old") == "New.md")
        #expect(history.score(of: "New.md", now: now) > 0)
        history.keepOnly(["Other.md"])
        #expect(history.isEmpty)
    }

    @Test func itStaysSmall() {
        var history = SearchHistory()
        for k in 0..<30 { history.opened("a", at: now.addingTimeInterval(Double(k))) }
        #expect(history.opens["a"]?.count == SearchHistory.opensKept)
        for k in 0..<(SearchHistory.picksKept + 10) { history.picked("n\(k)", for: "q\(k)", at: now) }
        #expect(history.picks.count == SearchHistory.picksKept)
    }

    @Test func itsKeptInAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("History-\(UUID().uuidString)/history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = SearchHistory.File(url: url)
        #expect(file.load().isEmpty)
        var history = SearchHistory()
        history.picked("a", for: "alpha", at: now)
        file.save(history)
        #expect(file.load() == history)
    }
}

struct SearchHistoryRankingTests {
    @Test func searchResultsAreRankedByHowTheirTitlesMatch() {
        let now = Date()
        var history = SearchHistory()
        history.opened("Meeting notes.md", at: now)
        let results = [
            SearchResult(id: "Meeting.md", title: "Meeting", snippet: nil, matchedTitle: true),
            SearchResult(id: "Meeting notes.md", title: "Meeting notes", snippet: nil, matchedTitle: true),
            SearchResult(id: "Meetup.md", title: "Meetup", snippet: nil, matchedTitle: true),
        ]
        // Both whole-word matches are equally good, so the one opened goes first; the partial
        // match stays after them.
        #expect(history.rank(results, for: "meeting", now: now).map(\.title) == ["Meeting notes", "Meeting", "Meetup"])
    }
}
