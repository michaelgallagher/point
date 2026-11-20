#if canImport(AppKit)
import AppKit
import MarkdownKit

/// Lists written in the note, as `list` blocks: their lines rewritten by the list drawn in
/// their place (its filters, its order, its columns), and new ones put in.
extension MarkdownTextView {
    /// The lines between the fences of the note's `index`th closed `list` block (from 0, as
    /// `BlockEmbed.list` counts them), each with its line break.
    public func listBlockBody(at index: Int) -> NSRange? {
        let text = string as NSString
        var count = 0
        for token in tokens {
            guard case .codeBlock(let language) = token.kind, language == MarkdownStyler.listLanguage else { continue }
            defer { count += 1 }
            guard count == index else { continue }
            guard token.syntax.count == 2 else { return nil }
            let opening = text.lineRange(for: token.syntax[0]), closing = text.lineRange(for: token.syntax[1])
            return NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening))
        }
        return nil
    }

    /// Replaces the lines of the note's `index`th `list` block, as one undoable edit named
    /// `actionName`. False if there's no such block, or nothing changed.
    @discardableResult
    public func replaceListBlockBody(at index: Int, with body: String, actionName: String) -> Bool {
        guard let range = listBlockBody(at: index) else { return false }
        guard (string as NSString).substring(with: range) != body else { return false }
        applyEdit(replacing: range, with: body)
        undoManager?.setActionName(actionName)
        return true
    }

    /// Puts in an empty `list` block (a list of every note) on lines of its own, with a blank
    /// line before and after it, and the cursor after it; then tells `onListBlockInserted`
    /// which block of the note it is, for the app to open its filters.
    @objc public func insertListBlock(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        guard !tokens.contains(where: { token in
            if case .codeBlock = token.kind { return NSLocationInRange(selection.location, token.range) && selection.location > token.range.location }
            return false
        }) else { return NSSound.beep() }
        let block = "```\(MarkdownStyler.listLanguage)\n```"
        func isBlank(_ range: NSRange) -> Bool {
            text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: NSMaxRange(selection), length: 0))
        // What it replaces ends at the start of a line (or the note's end): a blank line, all
        // of it; after a line with text, nothing, at the start of the next.
        let target: NSRange, prefix: String
        if isBlank(NSRange(location: start, length: contentsEnd - start)) {
            target = NSRange(location: start, length: end - start)
            let previousIsBlank = start == 0 || isBlank(text.lineRange(for: NSRange(location: start - 1, length: 0)))
            prefix = previousIsBlank ? "" : "\n"
        } else {
            target = NSRange(location: end, length: 0)
            prefix = end > contentsEnd ? "\n" : "\n\n"
        }
        let next = NSMaxRange(target)
        let nextIsText = next < text.length && !isBlank(text.lineRange(for: NSRange(location: next, length: 0)))
        // A blank line after it, unless there's one already; the cursor goes there, to go
        // on writing after the list.
        let inserted = prefix + block + "\n" + (nextIsText ? "\n" : "")
        let blockStart = target.location + (prefix as NSString).length
        let after = blockStart + (block as NSString).length + 1
        guard replace(target, with: inserted, select: NSRange(location: after, length: 0)) else { return }
        undoManager?.setActionName("Insert List")
        let index = tokens.filter { token in
            guard case .codeBlock(let language) = token.kind else { return false }
            return language == MarkdownStyler.listLanguage && token.range.location < blockStart
        }.count
        onListBlockInserted?(index)
    }
}
#endif
