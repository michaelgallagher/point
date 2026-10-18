import AppKit
import Foundation
import Testing
@testable import EditorKit

/// Writes PNGs of the editor to $IMPRINT_SNAPSHOT_DIR when it is set; otherwise skipped.
@MainActor
struct SnapshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IMPRINT_SNAPSHOT_DIR"] != nil))
    func formattingTour() throws {
        let env = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: env["IMPRINT_SNAPSHOT_DIR"]!)
        let markdown = try String(contentsOfFile: env["IMPRINT_SNAPSHOT_NOTE"]!, encoding: .utf8)
        let editor = EditorTestSupport.makeEditor(markdown)
        // Select a stretch that crosses a highlight and inline code, to check boxes line up.
        let selection = (markdown as NSString).range(of: "strikethrough~~, ==highlight== and `inline")
        if selection.location != NSNotFound { editor.setSelectionDirectly(selection) }
        try EditorTestSupport.snapshot(editor, to: directory.appendingPathComponent("tour-light.png"))
        try EditorTestSupport.snapshot(editor, to: directory.appendingPathComponent("tour-dark.png"), appearance: .darkAqua)
    }
}
