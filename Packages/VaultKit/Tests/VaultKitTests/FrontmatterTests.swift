import Foundation
import Testing
@testable import VaultKit

struct FrontmatterTests {
    private let note = """
    ---
    tags: [imprint, "big idea"]
    created: 2026-10-17
    aliases:
      - Imprint app
      - The editor
    # a comment Obsidian keeps
    nested:
      deep: value
    ---
    # Body
    """

    @Test func readsProperties() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        #expect(frontmatter.properties.map(\.key) == ["tags", "created", "aliases", "nested"])
        #expect(frontmatter.tags == ["imprint", "big idea"])
        let aliases = try #require(frontmatter.properties.first { $0.key == "aliases" })
        #expect(aliases.isList)
        #expect(aliases.values == ["Imprint app", "The editor"])
        #expect((note as NSString).substring(with: frontmatter.range).hasSuffix("deep: value\n---"))
    }

    @Test func repeatedKeysAreFlagged() throws {
        let text = "---\nread: 2024-01-02\ntitle: Book\nread: 2025-03-04\n---\n"
        let frontmatter = try #require(Frontmatter.parse(text))
        #expect(frontmatter.repeatedKeys == ["read"])
        #expect(frontmatter.properties.map(\.id) == ["read", "title", "read 2"])
        #expect(Frontmatter.parse("---\nread: 2024\n---\n")?.repeatedKeys == [])
    }

    @Test func noFrontmatterUnlessAtTheStart() {
        #expect(Frontmatter.parse("# Title\n---\na: b\n---") == nil)
        #expect(Frontmatter.parse("---\nunclosed: yes\n") == nil)
    }

    @Test func tagsAsAStringOrWithHashes() throws {
        #expect(try #require(Frontmatter.parse("---\ntags: one two\n---\n")).tags == ["one", "two"])
        #expect(try #require(Frontmatter.parse("---\ntags:\n  - \"#hashed\"\n---\n")).tags == ["hashed"])
    }

    /// Applies an edit to the note.
    private func apply(_ edit: (NSRange, String), to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.0, with: edit.1)
    }

    @Test func editingOnePropertyLeavesEverythingElse() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        let edited = apply(frontmatter.edit(setting: "created", to: ["2026-10-18"]), to: note)
        #expect(edited == note.replacingOccurrences(of: "created: 2026-10-17", with: "created: 2026-10-18"))
    }

    @Test func editingAListRewritesItsItems() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        let edited = apply(frontmatter.edit(setting: "aliases", to: ["Only one"]), to: note)
        #expect(edited.contains("aliases:\n  - Only one\n# a comment"))
    }

    @Test func renamingAPropertyChangesOnlyItsName() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        let renamed = apply(try #require(frontmatter.edit(renaming: "aliases", to: "also known as", in: note)), to: note)
        #expect(renamed.contains("\nalso known as:\n  - Imprint app\n  - The editor\n"))
        #expect(try #require(Frontmatter.parse(renamed)).properties.map(\.key) == ["tags", "created", "also known as", "nested"])
        // Everything else is untouched.
        #expect(renamed.replacingOccurrences(of: "also known as:", with: "aliases:") == note)
        // A name YAML would misread is quoted.
        let quoted = apply(try #require(frontmatter.edit(renaming: "created", to: "#made", in: note)), to: note)
        #expect(quoted.contains("\n\"#made\": 2026-10-17\n"))
        // Empty, the same, or another property's name: nothing to do.
        #expect(frontmatter.edit(renaming: "created", to: " ", in: note) == nil)
        #expect(frontmatter.edit(renaming: "created", to: "created", in: note) == nil)
        #expect(frontmatter.edit(renaming: "created", to: "tags", in: note) == nil)
    }

    @Test func movingAPropertyKeepsEveryLine() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        // Up: the list goes first, comment and nested value untouched.
        let up = apply(try #require(frontmatter.edit(moving: "aliases", to: 0, in: note)), to: note)
        #expect(up.hasPrefix("---\naliases:\n  - Imprint app\n  - The editor\ntags: [imprint, \"big idea\"]\ncreated: 2026-10-17\n# a comment"))
        #expect(try #require(Frontmatter.parse(up)).properties.map(\.key) == ["aliases", "tags", "created", "nested"])
        // Down to the end: the comment stays where it was, between the others.
        let down = apply(try #require(frontmatter.edit(moving: "tags", to: 4, in: note)), to: note)
        #expect(try #require(Frontmatter.parse(down)).properties.map(\.key) == ["created", "aliases", "nested", "tags"])
        #expect(down.contains("deep: value\ntags: [imprint, \"big idea\"]\n---\n# Body"))
        // Moving one place down.
        let swap = apply(try #require(frontmatter.edit(moving: "tags", to: 2, in: note)), to: note)
        #expect(swap.hasPrefix("---\ncreated: 2026-10-17\ntags:"))
        // No move: nothing to do.
        #expect(frontmatter.edit(moving: "tags", to: 0, in: note) == nil)
        #expect(frontmatter.edit(moving: "tags", to: 1, in: note) == nil)
        // Same lines, different order.
        #expect(up.split(separator: "\n").sorted() == note.split(separator: "\n").sorted())
    }

    @Test func addingAndRemoving() throws {
        let frontmatter = try #require(Frontmatter.parse(note))
        let added = apply(frontmatter.edit(setting: "status", to: ["draft"]), to: note)
        #expect(added.contains("deep: value\nstatus: draft\n---"))
        let removed = apply(try #require(frontmatter.edit(removing: "created")), to: note)
        #expect(!removed.contains("created"))
        #expect(removed.contains("tags: [imprint, \"big idea\"]\naliases:"))
    }

    @Test func addingFrontmatterToANote() {
        let edit = Frontmatter.edit(adding: "tags", values: ["new"], isList: true)
        #expect(apply(edit, to: "Body") == "---\ntags:\n  - new\n---\nBody")
    }

    @Test func aOneLineListIsRewrittenWithDashLines() throws {
        // Point writes lists as Obsidian does, whichever way the note had them, each item that
        // was there written as it was (quotes and all).
        let frontmatter = try #require(Frontmatter.parse(note))
        let edited = apply(frontmatter.edit(setting: "tags", to: ["imprint", "big idea", "new"]), to: note)
        #expect(edited.hasPrefix("---\ntags:\n  - imprint\n  - \"big idea\"\n  - new\ncreated: 2026-10-17\n"))
    }

    @Test func tagsWrittenOnOneLineBecomeAList() throws {
        let text = "---\ntags: work ideas\n---\n"
        let frontmatter = try #require(Frontmatter.parse(text))
        let edited = apply(frontmatter.edit(setting: "tags", to: ["work", "ideas", "next"], isList: true), to: text)
        #expect(edited == "---\ntags:\n  - work\n  - ideas\n  - next\n---\n")
    }

    @Test func quotesValuesThatNeedIt() {
        #expect(Frontmatter.yaml(key: "title", values: ["A: B"], isList: false) == "title: \"A: B\"\n")
    }
}

/// Setting a property writes only what changed, the way the note already writes it (from the
/// live vault's audit: 1,958 properties changed when set to the value they had).
struct FrontmatterRewriteTests {
    /// The note after setting `key` to `values`.
    private func set(_ key: String, to values: [String], isList: Bool? = nil, in note: String) -> String {
        let frontmatter = Frontmatter.parse(note)!
        let edit = frontmatter.edit(setting: key, to: values, isList: isList)
        return (note as NSString).replacingCharacters(in: edit.0, with: edit.1)
    }

    /// Every property set to the value it has: the note doesn't change at all.
    @Test(arguments: [
        "---\npeople:\ntopics:\n---\n",
        "---\nsource: https://example.com/a?b=c&d=e\n---\n",
        "---\ntitle: \"Meals — Ending the Morning Rush\"\n---\n",
        "---\ntitle: 'Single quoted'\n---\n",
        "---\nteam: []\n---\n",
        "---\ntags: [a, \"b c\"]\n---\n",
        "---\nauthor:\n  - \"[[Ann Smith]]\"\n  - Bo\n---\n",
        "---\npublished: \"2011\"\n---\n",
        "---\ncount: 3\ndone: true\n---\n",
    ])
    func aNoOpEditChangesNothing(note: String) {
        for property in Frontmatter.parse(note)!.properties {
            #expect(set(property.key, to: property.values, isList: property.isList, in: note) == note, "\(property.key)")
        }
    }

    @Test func anEmptyValueHasNoTrailingSpace() {
        #expect(set("status", to: [], isList: false, in: "---\nstatus: draft\n---\n") == "---\nstatus:\n---\n")
        #expect(Frontmatter.yaml(key: "status", values: [], isList: false) == "status:\n")
    }

    @Test func aChangedValueKeepsTheQuotes() {
        #expect(set("title", to: ["New title"], in: "---\ntitle: \"Old title\"\n---\n") == "---\ntitle: \"New title\"\n---\n")
        #expect(set("title", to: ["It's new"], in: "---\ntitle: 'Old'\n---\n") == "---\ntitle: 'It''s new'\n---\n")
        #expect(set("title", to: ["Plain"], in: "---\ntitle: Old\n---\n") == "---\ntitle: Plain\n---\n")
    }

    @Test func quotesOnlyWhatYAMLWouldMisread() {
        #expect(set("source", to: ["https://example.com/x"], in: "---\nsource: old\n---\n") == "---\nsource: https://example.com/x\n---\n")
        #expect(set("note", to: ["a: b"], in: "---\nnote: old\n---\n") == "---\nnote: \"a: b\"\n---\n")
        #expect(set("note", to: ["#hash"], in: "---\nnote: old\n---\n") == "---\nnote: \"#hash\"\n---\n")
        #expect(set("note", to: ["[[Link]]"], in: "---\nnote: old\n---\n") == "---\nnote: \"[[Link]]\"\n---\n")
        #expect(set("note", to: ["ends with #tag"], in: "---\nnote: old\n---\n") == "---\nnote: \"ends with #tag\"\n---\n")
    }

    @Test func listItemsKeepHowTheyWereWritten() {
        let note = "---\nauthor:\n  - \"[[Ann Smith]]\"\n  - Bo\n---\n"
        #expect(set("author", to: ["[[Ann Smith]]", "Bo", "[[Cy]]"], in: note) == "---\nauthor:\n  - \"[[Ann Smith]]\"\n  - Bo\n  - \"[[Cy]]\"\n---\n")
    }
}
