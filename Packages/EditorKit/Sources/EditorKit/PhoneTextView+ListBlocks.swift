#if os(iOS)
import UIKit
import MarkdownKit

/// Lists written in the note, as `list` blocks: their lines rewritten as their filters change
/// on the phone.
extension PhoneTextView {
    /// The lines between the fences of the note's `index`th closed `list` block (from 0, as
    /// `BlockEmbed.list` counts them), each with its line break. Read from the text as it is
    /// now, not as last styled: the phone restyles just after edits.
    public func listBlockBody(at index: Int) -> NSRange? {
        ListBlocks.body(at: index, tokens: MarkdownParser.parse(textStorage.string), text: textStorage.string as NSString)
    }

    /// Replaces the lines of the note's `index`th `list` block, as one step to undo named
    /// `actionName`, the cursor kept on the same text. False if there's no such block, or
    /// nothing changed.
    @discardableResult
    public func replaceListBlockBody(at index: Int, with body: String, actionName: String) -> Bool {
        guard let range = listBlockBody(at: index), (textStorage.string as NSString).substring(with: range) != body else { return false }
        applyAboveBody(range, with: body)
        undoManager?.setActionName(actionName)
        return true
    }
}
#endif
