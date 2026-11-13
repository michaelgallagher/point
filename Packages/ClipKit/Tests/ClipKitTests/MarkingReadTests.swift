import ClipKit
import XCTest

final class MarkingReadTests: XCTestCase {
    func testAddsReadAtTheEndOfTheProperties() {
        let text = "---\ntype: Media\nformat: Article\n---\n\nThe article.\n"
        XCTAssertEqual(Clipping.markingRead(text, on: "2026-11-13"),
                       "---\ntype: Media\nformat: Article\nread: 2026-11-13\n---\n\nThe article.\n")
    }

    func testFillsInAnEmptyRead() {
        let text = "---\ntype: Media\nread:\nsaved: 2026-11-01\n---\nText\n"
        XCTAssertEqual(Clipping.markingRead(text, on: "2026-11-13"),
                       "---\ntype: Media\nread: 2026-11-13\nsaved: 2026-11-01\n---\nText\n")
    }

    func testLeavesAReadDateAlone() {
        let text = "---\nRead: 2026-10-01\n---\nText\n"
        XCTAssertEqual(Clipping.markingRead(text, on: "2026-11-13"), text)
    }

    func testAddsPropertiesToANoteWithout() {
        XCTAssertEqual(Clipping.markingRead("Just text\n", on: "2026-11-13"), "---\nread: 2026-11-13\n---\nJust text\n")
    }
}
