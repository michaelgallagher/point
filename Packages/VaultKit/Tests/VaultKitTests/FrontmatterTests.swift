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

    @Test func quotesValuesThatNeedIt() {
        #expect(Frontmatter.yaml(key: "title", values: ["A: B"], isList: false) == "title: \"A: B\"\n")
    }
}
