import Testing
@testable import VaultKit

struct NoteTagsTests {
    @Test func combinesFrontmatterAndInlineTags() {
        let text = "---\ntags: [work, Ideas]\n---\nSome #ideas and #work/imprint, not `#code`."
        #expect(NoteTags.tags(in: text) == ["work", "Ideas", "work/imprint"])
    }

    @Test func noTags() {
        #expect(NoteTags.tags(in: "# Heading\nPlain text").isEmpty)
    }
}
