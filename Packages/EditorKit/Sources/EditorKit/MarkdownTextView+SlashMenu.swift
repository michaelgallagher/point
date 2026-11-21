#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The slash menu on the Mac: typing `/` at a line's start or after a space shows what can be
/// put in there, in the editor's popup (see +Popup), which puts in the one chosen in place of
/// the `/` and what was typed.
extension MarkdownTextView {
    /// Puts in a command in place of the `/` and what was typed after it, as one step to undo,
    /// back to the `/` as typed. A command with choices (a callout's type) offers them first.
    func runSlashCommand(_ command: SlashCommand) {
        guard let query = slashPopupQuery ?? SlashMenu.query(in: string, tokens: tokens, at: selectedRange().location) else { return }
        if !command.choices.isEmpty, command.choice == nil {
            // Its name and a space, after the `/`: the menu offers its choices.
            replace(query.range, with: "/" + command.name.lowercased() + " ")
            return
        }
        hidePopup()
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        replace(query.range, with: "")
        performSlash(command)
        // Named for the command, not its choice: Undo Callout, not Undo Warning.
        undoManager?.setActionName(SlashCommand.all.first { $0.id == command.id }?.name ?? command.name)
        undoManager?.endUndoGrouping()
    }

    /// The `/` and what's typed after it, while the popup offers commands for it.
    private var slashPopupQuery: SlashQuery? {
        if case .slash(let query) = popup?.context { return query }
        return nil
    }

    private func performSlash(_ command: SlashCommand) {
        if performSlashCommand?(command) == true { return }
        switch command.id {
        case .list:
            insertListBlock(nil)
        case .table:
            insertTable(nil)
        case .image:
            chooseImageToInsert()
        default:
            guard let edit = MarkdownEditing(text: string, tokens: tokens, selection: selectedRange()).slashEdit(command) else { return }
            apply(edit)
            // A link or embed being typed: the notes it could be.
            if command.id == .linkToNote || command.id == .embedNote { updatePopup() }
        }
    }

    /// Asks for an image file, and embeds it at the cursor.
    private func chooseImageToInsert() {
        guard let window, saveImage != nil else { return NSSound.beep() }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to put in the note"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let images = panel.urls.compactMap { url in
                (try? Data(contentsOf: url)).map { (data: $0, type: UTType(filenameExtension: url.pathExtension)) }
            }
            self.insertImages(images)
        }
    }
}

#endif
