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
