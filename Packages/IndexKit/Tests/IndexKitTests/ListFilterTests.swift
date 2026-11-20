import Foundation
import Testing
@testable import IndexKit
@testable import VaultKit

struct ListFilterTests {
    /// A vault with a choice-like `format` (few values, used often), a date `published`, a
    /// number `rating`, a list `authors`, a ticked `read`, and a Point kind `status`.
    let vocabulary: ListVocabulary = {
        func summary(_ name: String, notes: Int, lists: Int = 0, numbers: Int = 0, dates: Int = 0, values: Int, distinct: Int) -> SearchIndex.PropertySummary {
            SearchIndex.PropertySummary(name: name, otherSpellings: [], noteCount: notes, listCount: lists, numberValues: numbers,
                                        dateValues: dates, linkValues: 0, valueCount: values, distinctValues: distinct)
        }
        let values = ["format": ["Book", "Video"], "read": ["true", "false"], "title2": ["A", "B", "C"]]
        return ListVocabulary(
            pointTypes: PointTypes(properties: ["status": PointTypes.Definition(type: .choice, choices: ["Doing", "Done"])]),
            propertyTypes: PropertyTypes(raw: ["published": "date"]),
            summaries: [summary("format", notes: 30, values: 30, distinct: 2),
                        summary("rating", notes: 10, numbers: 10, values: 10, distinct: 5),
                        summary("authors", notes: 10, lists: 9, values: 12, distinct: 12),
                        summary("read", notes: 10, values: 10, distinct: 2),
                        summary("subtitle", notes: 10, values: 10, distinct: 10)],
            values: { values[$0.lowercased()] ?? [] })
    }()

    @Test func tellsWhatEachPropertyHolds() {
        #expect(vocabulary.kind(ofProperty: "status") == .choice(["Doing", "Done"]))
        #expect(vocabulary.kind(ofProperty: "published") == .date)
        #expect(vocabulary.kind(ofProperty: "Format") == .choice(["Book", "Video"]))
        #expect(vocabulary.kind(ofProperty: "rating") == .number)
        #expect(vocabulary.kind(ofProperty: "authors") == .list)
        #expect(vocabulary.kind(ofProperty: "read") == .checkbox)
        #expect(vocabulary.kind(ofProperty: "subtitle") == .text)
        #expect(vocabulary.kind(ofProperty: "tags") == .tag)
        #expect(vocabulary.kind(of: .folder) == .folder)
        #expect(vocabulary.kind(of: .field(.modified)) == .date)
        #expect(vocabulary.kind(of: .linksTo) == .note)
    }

    @Test func aConditionMakesTheSameConditionBack() {
        let conditions = [
            ListCondition("format", .is, "Book"),
            ListCondition("read", .isNotSet),
            ListCondition("rating", .greater, "3"),
            ListCondition("published", .before, "2020-01-01"),
            ListCondition("published", .between, "2019-01-01 and 2019-12-31"),
            ListCondition("published", .inLastDays, "2 weeks"),
            ListCondition("date edited", .thisPeriod, "month"),
            ListCondition("", .linksTo, "[[Reading]]"),
            ListCondition("", .hasWords, "garden"),
        ]
        for condition in conditions {
            let row = ListFilterRow(condition: condition)
            #expect(row.condition(kind: vocabulary.kind(of: row.subject)) == condition, "\(condition.written)")
        }
    }

    @Test func aRowNotFilledInMakesNoCondition() {
        var row = ListFilterRow(subject: .property("subtitle"), kind: .text)
        #expect(row.condition(kind: .text) == nil)
        row.text = "  "
        #expect(row.condition(kind: .text) == nil)
        row.op = .isSet
        #expect(row.condition(kind: .text) == ListCondition("subtitle", .isSet))
        var number = ListFilterRow(subject: .property("rating"), kind: .number)
        number.op = .greater
        number.text = "lots"
        #expect(number.condition(kind: .number) == nil)
    }

    @Test func readsAConditionInTheFiltersWords() {
        #expect(vocabulary.reading(ListCondition("format", .is, "Book")) == "format is Book")
        #expect(vocabulary.reading(ListCondition("read", .isNotSet)) == "read has no value")
        #expect(vocabulary.reading(ListCondition("read", .is, "true")) == "read is ticked")
        #expect(vocabulary.reading(ListCondition("authors", .is, "Le Guin")) == "authors includes Le Guin")
        #expect(vocabulary.reading(ListCondition("published", .inLastDays, "1 weeks")) == "published is in the last 1 week")
        #expect(vocabulary.reading(ListCondition("", .linksTo, "[[Reading]]")) == "links to [[Reading]]")
        let day = ListVocabulary.shownDate("2026-11-06")
        #expect(day != "2026-11-06")
        #expect(vocabulary.reading(ListCondition("published", .before, "2026-11-06")) == "published is before \(day)")
    }

    @Test func aListInOneLine() {
        let books = ListDefinition(folders: ["Reading"], conditions: [ListCondition("format", .is, "Book"), ListCondition("read", .isNotSet)],
                                   sort: [NoteQuery.Sort(.property("published"), descending: true)])
        #expect(vocabulary.summary(of: books) == "In Reading · format is Book and read has no value · by published")
        var any = books
        any.matchesAny = true
        any.folders = []
        any.tags = ["later"]
        #expect(vocabulary.summary(of: any) == "Tagged #later · format is Book or read has no value · by published")
        #expect(vocabulary.summary(of: ListDefinition()) == "Every note · by date edited")
    }
}

struct ListNotePropertyTests {
    let note = Frontmatter.parse("---\nType: list\nList-From: Reading\nlist-where:\n  - format is Book\nlist-sort: title\n---\n")

    @Test func writesOnlyWhatChangedBySpelling() throws {
        var list = try #require(ListDefinition(frontmatter: note))
        list.folders = ["Archive"]
        let changes = list.propertyChanges(over: note)
        #expect(changes.map(\.key) == ["List-From"])
        #expect(changes.first?.values == ["Archive"])
    }

    @Test func removesWhatsNoLongerSetAndAddsWhatsNew() throws {
        var list = try #require(ListDefinition(frontmatter: note))
        list.sort = []
        list.columns = ["author"]
        let changes = list.propertyChanges(over: note)
        #expect(changes.map(\.key) == ["list-show", "list-sort"])
        #expect(changes.map(\.values) == [["author"], nil])
    }

    @Test func aListOfEveryNoteKeepsAnEmptyWhere() throws {
        var list = try #require(ListDefinition(frontmatter: note))
        list.folders = []
        list.conditions = []
        let changes = list.propertyChanges(over: note)
        #expect(changes.map(\.key) == ["List-From", "list-where"])
        #expect(changes.last?.values == [])
        #expect(changes.last?.isList == true)
    }

    @Test func theSameListChangesNothing() throws {
        let list = try #require(ListDefinition(frontmatter: note))
        #expect(list.propertyChanges(over: note).isEmpty)
    }
}
