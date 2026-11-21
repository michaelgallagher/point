#if os(iOS)
import MarkdownKit
import UIKit

/// The slash menu on the iPhone: typing `/` at a line's start or after a space offers what can
/// be put in there, in the bar above the keyboard (the app draws it, from `onSlashMenuChange`).
/// Typing narrows it; a tap, or Return for the one highlighted (the first, or another chosen
/// with up and down on a hardware keyboard), puts it in place of the `/` and what was typed, as
/// one step to undo; moving away, typing what matches nothing, or Escape closes it.
extension PhoneTextView {
    /// Shows, narrows or closes the menu for the cursor where it is now.
    func updateSlashMenu(force: Bool = false) {
        guard !slashCommands.isEmpty else { return }
        var query = selectedRange.length == 0 && markedTextRange == nil && isFirstResponder
            ? SlashMenu.query(in: textStorage.string, tokens: tokens, at: selectedRange.location) : nil
        // Escape closed it: closed for that `/`, until another is typed.
        if dismissedSlash != nil, query?.slash != dismissedSlash { dismissedSlash = nil }
        if let slash = query?.slash, slash == dismissedSlash { query = nil }
        let commands = query.map { SlashMenu.matching(slashCommands, typed: $0.typed) } ?? []
        let changed = commands.map(\.name) != slashOffered.map(\.name)
        slashQuery = commands.isEmpty ? nil : query
        slashOffered = commands
        if changed { slashHighlighted = 0 }
        if changed || force { onSlashMenuChange?(commands, slashHighlighted) }
    }

    /// Up, down, Tab and Escape on a hardware keyboard, while the menu shows (Return is in
    /// `shouldChangeTextIn`). Whether the key was for it.
    func handleSlashMenuKey(_ key: UIKey) -> Bool {
        guard slashQuery != nil, !slashOffered.isEmpty, key.modifierFlags.intersection([.shift, .control, .alternate, .command]).isEmpty else { return false }
        switch key.keyCode {
        case .keyboardUpArrow: slashMenuUp()
        case .keyboardDownArrow: slashMenuDown()
        case .keyboardTab: slashMenuChoose()
        case .keyboardEscape: slashMenuClose()
        default: return false
        }
        return true
    }

    func slashMenuUp() { moveSlashHighlight(by: -1) }
    func slashMenuDown() { moveSlashHighlight(by: 1) }

    func slashMenuChoose() {
        guard let command = highlightedSlashCommand else { return }
        runSlashCommand(command)
    }

    func slashMenuClose() {
        guard let query = slashQuery else { return }
        dismissedSlash = query.slash
        updateSlashMenu()
    }

    private func moveSlashHighlight(by step: Int) {
        guard !slashOffered.isEmpty else { return }
        slashHighlighted = (slashHighlighted + step + slashOffered.count) % slashOffered.count
        onSlashMenuChange?(slashOffered, slashHighlighted)
    }

    /// What Return or Tab puts in.
    var highlightedSlashCommand: SlashCommand? {
        slashOffered.isEmpty ? nil : slashOffered[min(slashHighlighted, slashOffered.count - 1)]
    }

    /// Puts in a command in place of the `/` and what was typed after it, as one step to undo,
    /// back to the `/` as typed. A command with choices (a callout's type) offers them first.
    public func runSlashCommand(_ command: SlashCommand) {
        guard let query = slashQuery ?? SlashMenu.query(in: textStorage.string, tokens: tokens, at: selectedRange.location) else { return }
        if !command.choices.isEmpty, command.choice == nil {
            // Its name and a space, after the `/`: the menu offers its choices.
            let typed = "/" + command.name.lowercased() + " "
            apply(MarkdownEdit(range: query.range, replacement: typed,
                               selection: NSRange(location: query.slash + (typed as NSString).length, length: 0)))
            return
        }
        undoManager?.beginUndoGrouping()
        apply(MarkdownEdit(range: query.range, replacement: "", selection: NSRange(location: query.slash, length: 0)))
        performSlash(command)
        undoManager?.setActionName(SlashCommand.all.first { $0.id == command.id }?.name ?? command.name)
        undoManager?.endUndoGrouping()
    }

    private func performSlash(_ command: SlashCommand) {
        if performSlashCommand?(command) == true { return }
        let editing = MarkdownEditing(text: textStorage.string, selection: selectedRange)
        if command.id == .list {
            // On lines of its own, the cursor after it; then its filters open.
            let edit = editing.insertingBlock("```\(MarkdownStyler.listLanguage)\n```", selecting: nil)
            apply(edit)
            let tokens = MarkdownParser.parse(textStorage.string)
            let start = edit.range.location + (edit.replacement.hasPrefix("\n") ? (edit.replacement.prefix { $0 == "\n" } as Substring).utf16.count : 0)
            if let index = ListBlocks.index(ofBlockAt: start, tokens: tokens) { onListBlockInserted?(index) }
            return
        }
        guard let edit = editing.slashEdit(command) else { return }
        apply(edit)
    }
}
#endif
