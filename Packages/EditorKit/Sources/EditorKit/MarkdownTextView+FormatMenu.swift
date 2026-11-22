#if canImport(AppKit)
import AppKit

/// A command in the formatting menu: a style for the selection, or a kind of line for the lines
/// it touches. Each is one the Format menu has too, sent as its menu item sends it.
struct FormatCommand: Equatable {
    let name: String
    let symbol: String
    /// Other names it's found by: `h1` finds Heading 1.
    let otherNames: [String]
    let action: Selector

    init(_ name: String, symbol: String, _ action: Selector, otherNames: [String] = []) {
        self.name = name
        self.symbol = symbol
        self.action = action
        self.otherNames = otherNames
    }

    /// Every command, in the menu's order with nothing typed.
    @MainActor static let all: [FormatCommand] = [
        FormatCommand("Bold", symbol: "bold", #selector(MarkdownTextView.toggleBold(_:)), otherNames: ["strong"]),
        FormatCommand("Italic", symbol: "italic", #selector(MarkdownTextView.toggleItalic(_:)), otherNames: ["emphasis"]),
        FormatCommand("Highlight", symbol: "highlighter", #selector(MarkdownTextView.toggleHighlight(_:)), otherNames: ["mark"]),
        FormatCommand("Strikethrough", symbol: "strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), otherNames: ["cross out", "delete"]),
        FormatCommand("Inline code", symbol: "chevron.left.forwardslash.chevron.right", #selector(MarkdownTextView.toggleCode(_:)), otherNames: ["monospace"]),
        FormatCommand("Link", symbol: "link", #selector(MarkdownTextView.addLink(_:)), otherNames: ["url", "address"]),
        FormatCommand("Body text", symbol: "text.alignleft", #selector(MarkdownTextView.makeBodyText(_:)), otherNames: ["paragraph", "plain", "normal"]),
        FormatCommand("Heading 1", symbol: "textformat.size.larger", #selector(MarkdownTextView.makeHeading1(_:)), otherNames: ["h1", "title"]),
        FormatCommand("Heading 2", symbol: "textformat.size", #selector(MarkdownTextView.makeHeading2(_:)), otherNames: ["h2", "subheading"]),
        FormatCommand("Heading 3", symbol: "textformat.size.smaller", #selector(MarkdownTextView.makeHeading3(_:)), otherNames: ["h3"]),
        FormatCommand("Bulleted list", symbol: "list.bullet", #selector(MarkdownTextView.toggleBulletList(_:)), otherNames: ["bullets", "unordered list", "ul"]),
        FormatCommand("Numbered list", symbol: "list.number", #selector(MarkdownTextView.toggleNumberedList(_:)), otherNames: ["ordered list", "ol"]),
        FormatCommand("Checklist", symbol: "checklist", #selector(MarkdownTextView.toggleChecklist(_:)), otherNames: ["todo", "task", "checkbox"]),
        FormatCommand("Quote", symbol: "text.quote", #selector(MarkdownTextView.toggleBlockQuote(_:)), otherNames: ["blockquote", "block quote"]),
    ]

    /// The commands for what's typed, best first, as the slash menu finds them: those whose
    /// name starts with it, then those with every word typed starting one of their name's
    /// words, then those found by another name. Nothing typed: all of them.
    static func matching(_ commands: [FormatCommand], typed: String) -> [FormatCommand] {
        let typed = typed.lowercased().trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return commands }
        let words = SlashMenu.words(typed)
        func matches(_ name: String) -> Bool {
            let nameWords = SlashMenu.words(name)
            return !words.isEmpty && words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
        }
        let scored = commands.enumerated().compactMap { offset, command -> (Int, Int, FormatCommand)? in
            let name = command.name.lowercased()
            if name.hasPrefix(typed) { return (0, offset, command) }
            if matches(name) { return (1, offset, command) }
            if command.otherNames.contains(where: { $0.hasPrefix(typed) || matches($0) }) { return (2, offset, command) }
            return nil
        }
        return scored.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }
}

/// The formatting menu (⌘J in the app): the editor's popup, under the selection, offering the
/// Format menu's styles and kinds of line. Typing narrows it without touching the selection;
/// Delete takes back what was typed (or, with nothing typed, closes it); up and down choose;
/// Return, Tab or a click applies the one highlighted; Escape, or moving the selection, closes it.
extension MarkdownTextView {
    @objc public func showFormatMenu(_ sender: Any?) {
        guard !hasMarkedText(), !hasMultipleCursors else { return NSSound.beep() }
        hidePopup()
        dismissedPopup = nil
        let popup = EditorPopup(context: .format(selection: selectedRange(), typed: ""))
        popup.model.pick = { [weak self] in self?.choosePopupRow($0) }
        self.popup = popup
        addSubview(popup.view)
        showFormatCommands(in: popup, typed: "")
    }

    /// What's typed while the formatting menu shows: narrows it, unless nothing would be left
    /// (then it beeps). Whether it was for the menu.
    func typeIntoFormatMenu(_ text: String) -> Bool {
        guard let popup, case .format(_, let typed) = popup.context else { return false }
        let narrowed = typed + text
        if FormatCommand.matching(FormatCommand.all, typed: narrowed).isEmpty { NSSound.beep(); return true }
        showFormatCommands(in: popup, typed: narrowed)
        return true
    }

    /// Delete while the formatting menu shows: takes back the last character typed, or with
    /// nothing typed, closes it. Whether the menu was showing.
    func deleteInFormatMenu() -> Bool {
        guard let popup, case .format(_, let typed) = popup.context else { return false }
        guard !typed.isEmpty else { hidePopup(); return true }
        showFormatCommands(in: popup, typed: String(typed.dropLast()))
        return true
    }

    private func showFormatCommands(in popup: EditorPopup, typed: String) {
        guard case .format(let selection, _) = popup.context else { return }
        popup.context = .format(selection: selection, typed: typed)
        popup.formatCommands = FormatCommand.matching(FormatCommand.all, typed: typed)
        popup.model.filter = typed
        popup.model.rows = popup.formatCommands.map {
            EditorPopupRow(symbol: $0.symbol, title: $0.name, detail: formatShortcut?($0.action))
        }
        popup.model.highlighted = 0
        placePopup(popup)
    }

    /// Applies a command from the formatting menu, to the selection it opened for.
    func runFormatCommand(_ command: FormatCommand) {
        hidePopup()
        breakUndoCoalescing()
        perform(command.action, with: self)
    }
}
#endif
