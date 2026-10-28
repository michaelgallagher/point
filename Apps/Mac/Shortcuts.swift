import AppKit
import SwiftUI

/// A key and its modifiers, as a menu item's key equivalent: what's stored for a changed
/// shortcut, and shown as "⇧⌘1".
struct Shortcut: Codable, Hashable {
    /// The key: a character ("b", "1", "[") or a named key ("up", "tab").
    var key: String
    var command = false, shift = false, option = false, control = false

    /// Named keys, with how they're shown.
    private static let named: [String: (KeyEquivalent, String)] = [
        "up": (.upArrow, "↑"), "down": (.downArrow, "↓"), "left": (.leftArrow, "←"), "right": (.rightArrow, "→"),
        "tab": (.tab, "⇥"), "return": (.return, "↩"), "delete": (.delete, "⌫"), "space": (.space, "Space"),
        "escape": (.escape, "⎋"),
    ]

    init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    var keyboardShortcut: KeyboardShortcut? {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if let (equivalent, _) = Self.named[key] { return KeyboardShortcut(equivalent, modifiers: modifiers) }
        guard let character = key.first, key.count == 1 else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    /// As menus show it: modifiers in the system's order, then the key ("⌃⌥⇧⌘K").
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
            + (Self.named[key]?.1 ?? (key == "-" ? "−" : key.uppercased()))
    }

    /// A key pressed (while recording a new shortcut), or nil if it can't be one: it needs ⌘ or
    /// ⌃ (or is a function key), so typing in a note never sets it off.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let names: [UInt16: String] = [126: "up", 125: "down", 123: "left", 124: "right", 48: "tab", 36: "return", 51: "delete", 49: "space"]
        // The key itself, without Shift's effect (⇧1 is "1", not "!").
        guard let key = names[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased(),
              !key.isEmpty, key.count == 1 || names.values.contains(key) else { return nil }
        self.init(key, command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
        guard command || control else { return nil }
    }
}

/// Every menu command whose shortcut can be changed, with its menu, name and default.
enum ShortcutAction: String, CaseIterable, Identifiable {
    // File
    case newNote, newNoteFromTemplate, newFolder, newTab, newTabOnOtherSide, newWindow, todaysNote, applyTemplate,
         openVault, closeTab, renameNote, moveToFolder, addTag, toggleBookmark, showInFinder, moveToTrash
    // Edit
    case explorer, searchVault, searchInList, findInNote
    // View
    case toggleNoteList, biggerText, smallerText, actualSize, split, moveTabToOtherSide, nextTab, previousTab,
         tabList, switchToTab, showMarkdown, focus, reloadNotes
    // Go
    case enclosingFolder, topLevel, back, forward
    // Format
    case bold, italic, highlight, strikethrough, inlineCode, bodyText, heading1, heading2, heading3, heading4,
         heading5, heading6, bulletList, checklist, blockQuote, indent, outdent, moveLineUp, moveLineDown, fold,
         unfold, addCursorAbove, addCursorBelow, addNextMatch, addLink, addProperty
    // Format › Highlight List Item, by colour name (see `MarkdownTextView.colourName`).
    case highlightOrange, highlightRed, highlightYellow, highlightGreen, highlightTeal, highlightPurple,
         highlightGrey, highlightBrown, removeHighlight
    // Help
    case keyboardShortcuts

    var id: String { rawValue }

    /// The menu it's in, for grouping it in Settings and the shortcut list.
    var menu: String {
        switch self {
        case .newNote, .newNoteFromTemplate, .newFolder, .newTab, .newTabOnOtherSide, .newWindow, .todaysNote, .applyTemplate,
             .openVault, .closeTab, .renameNote, .moveToFolder, .addTag, .toggleBookmark, .showInFinder, .moveToTrash: "File"
        case .explorer, .searchVault, .searchInList, .findInNote: "Edit"
        case .toggleNoteList, .biggerText, .smallerText, .actualSize, .split, .moveTabToOtherSide, .nextTab, .previousTab,
             .tabList, .switchToTab, .showMarkdown, .focus, .reloadNotes: "View"
        case .enclosingFolder, .topLevel, .back, .forward: "Go"
        case .highlightOrange, .highlightRed, .highlightYellow, .highlightGreen, .highlightTeal, .highlightPurple,
             .highlightGrey, .highlightBrown, .removeHighlight: "Highlight List Item"
        case .keyboardShortcuts: "Help"
        default: "Format"
        }
    }

    static let menus = ["File", "Edit", "View", "Go", "Format", "Highlight List Item", "Help"]

    var title: String {
        switch self {
        case .newNote: "New Note"
        case .newNoteFromTemplate: "New Note from Template…"
        case .newFolder: "New Folder…"
        case .newTab: "New Tab"
        case .newTabOnOtherSide: "New Tab on Other Side"
        case .newWindow: "New Window"
        case .todaysNote: "Today’s Note"
        case .applyTemplate: "Apply Template…"
        case .openVault: "Open Vault…"
        case .closeTab: "Close Tab"
        case .renameNote: "Rename Note…"
        case .moveToFolder: "Move to Folder…"
        case .addTag: "Add Tag…"
        case .toggleBookmark: "Add or Remove Bookmark"
        case .showInFinder: "Show in Finder"
        case .moveToTrash: "Move to Trash"
        case .explorer: "Explorer"
        case .searchVault: "Search Vault"
        case .searchInList: "Search in List"
        case .findInNote: "Find in Note"
        case .toggleNoteList: "Show or Hide Note List"
        case .biggerText: "Bigger Text"
        case .smallerText: "Smaller Text"
        case .actualSize: "Actual Size"
        case .split: "Split, or Merge Split into Tabs"
        case .moveTabToOtherSide: "Move Tab to Other Side"
        case .nextTab: "Show Next Tab"
        case .previousTab: "Show Previous Tab"
        case .tabList: "Show Tab List"
        case .switchToTab: "Switch to Tab…"
        case .showMarkdown: "Show Markdown"
        case .focus: "Focus"
        case .reloadNotes: "Reload Notes"
        case .enclosingFolder: "Enclosing Folder"
        case .topLevel: "Top Level"
        case .back: "Back"
        case .forward: "Forward"
        case .bold: "Bold"
        case .italic: "Italic"
        case .highlight: "Highlight"
        case .strikethrough: "Strikethrough"
        case .inlineCode: "Inline Code"
        case .bodyText: "Body Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .heading5: "Heading 5"
        case .heading6: "Heading 6"
        case .bulletList: "Bulleted List"
        case .checklist: "Checklist"
        case .blockQuote: "Block Quote"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .moveLineUp: "Move Line Up"
        case .moveLineDown: "Move Line Down"
        case .fold: "Fold"
        case .unfold: "Unfold"
        case .addCursorAbove: "Add Cursor Above"
        case .addCursorBelow: "Add Cursor Below"
        case .addNextMatch: "Add Next Match"
        case .addLink: "Add Link…"
        case .addProperty: "Add Property…"
        case .highlightOrange: "Orange"
        case .highlightRed: "Red"
        case .highlightYellow: "Yellow"
        case .highlightGreen: "Green"
        case .highlightTeal: "Teal"
        case .highlightPurple: "Purple"
        case .highlightGrey: "Grey"
        case .highlightBrown: "Brown"
        case .removeHighlight: "No Highlight"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        }
    }

    /// The highlight colour's name, for the Highlight List Item commands.
    var highlightColour: String? {
        switch self {
        case .highlightOrange, .highlightRed, .highlightYellow, .highlightGreen, .highlightTeal, .highlightPurple,
             .highlightGrey, .highlightBrown: title
        default: nil
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .newNote: Shortcut("n")
        case .newFolder: Shortcut("n", shift: true)
        case .newTab: Shortcut("t")
        case .newTabOnOtherSide: Shortcut("t", control: true)
        case .newWindow: Shortcut("n", option: true)
        case .applyTemplate: Shortcut("t", option: true)
        case .openVault: Shortcut("o")
        case .closeTab: Shortcut("w")
        case .showInFinder: Shortcut("r", option: true)
        case .explorer: Shortcut("e")
        case .searchVault: Shortcut("f")
        case .searchInList: Shortcut("f", shift: true)
        case .findInNote: Shortcut("f", option: true)
        case .toggleNoteList: Shortcut("s")
        case .biggerText: Shortcut("=") // The ⌘+ key, without Shift.
        case .smallerText: Shortcut("-")
        case .split: Shortcut("s", shift: true)
        case .nextTab: Shortcut("]", shift: true)
        case .previousTab: Shortcut("[", shift: true)
        case .tabList: Shortcut("t", shift: true)
        case .switchToTab: Shortcut("tab", command: false, control: true)
        case .showMarkdown: Shortcut("m", shift: true)
        case .focus: Shortcut("\\", shift: true)
        case .reloadNotes: Shortcut("r")
        case .enclosingFolder: Shortcut("up")
        case .back: Shortcut("[")
        case .forward: Shortcut("]")
        case .bold: Shortcut("b")
        case .italic: Shortcut("i")
        case .highlight: Shortcut("u")
        case .strikethrough: Shortcut("x", shift: true)
        case .inlineCode: Shortcut("c", option: true)
        case .bodyText: Shortcut("0")
        case .heading1: Shortcut("1")
        case .heading2: Shortcut("2")
        case .heading3: Shortcut("3")
        case .heading4: Shortcut("4")
        case .heading5: Shortcut("5")
        case .heading6: Shortcut("6")
        case .bulletList: Shortcut("l")
        case .checklist: Shortcut("l", shift: true)
        case .blockQuote: Shortcut("'")
        // ⌘← and ⌘→ stay as the system's start and end of line.
        case .indent: Shortcut("right", option: true)
        case .outdent: Shortcut("left", option: true)
        case .moveLineUp: Shortcut("up", option: true)
        case .moveLineDown: Shortcut("down", option: true)
        case .fold: Shortcut("[", option: true)
        case .unfold: Shortcut("]", option: true)
        case .addCursorAbove: Shortcut("up", command: false, shift: true, control: true)
        case .addCursorBelow: Shortcut("down", command: false, shift: true, control: true)
        case .addNextMatch: Shortcut("d")
        case .addLink: Shortcut("k")
        // The two used most, the easiest to reach (⇧⌘3, 4 and 5 are the system's screenshots).
        case .highlightOrange: Shortcut("1", shift: true)
        case .highlightRed: Shortcut("2", shift: true)
        case .highlightYellow: Shortcut("3", control: true)
        case .highlightGreen: Shortcut("4", control: true)
        case .highlightTeal: Shortcut("5", control: true)
        case .highlightPurple: Shortcut("6", control: true)
        case .highlightGrey: Shortcut("7", control: true)
        case .highlightBrown: Shortcut("8", control: true)
        case .removeHighlight: Shortcut("0", control: true)
        case .keyboardShortcuts: Shortcut("/")
        default: nil
        }
    }
}

/// The shortcuts in use: the defaults, with any changed in Settings. Kept in the app's own
/// settings, so they're the same in every window and vault.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// Changed shortcuts by action; a nil value is a shortcut removed.
    @Published private(set) var changes: [ShortcutAction: Shortcut?] = [:]
    private static let key = "shortcuts"

    init() {
        let saved = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        for (id, value) in saved {
            guard let action = ShortcutAction(rawValue: id) else { continue }
            changes[action] = value.isEmpty ? .some(nil) : (try? JSONDecoder().decode(Shortcut.self, from: Data(value.utf8))).map { .some($0) } ?? nil
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        if let changed = changes[action] { return changed }
        return action.defaultShortcut
    }

    func keyboardShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcut(for: action)?.keyboardShortcut
    }

    /// As menus show it ("⇧⌘1"), or nil if it has none.
    func label(for action: ShortcutAction) -> String? {
        shortcut(for: action)?.label
    }

    func isChanged(_ action: ShortcutAction) -> Bool { changes[action] != nil }

    /// The action already using a shortcut, if any.
    func action(using shortcut: Shortcut, except action: ShortcutAction? = nil) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.shortcut(for: $0) == shortcut }
    }

    /// Gives an action a shortcut (nil for none). An action already using it loses it, and is
    /// returned, so the change can be explained.
    @discardableResult
    func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        var displaced: ShortcutAction?
        if let shortcut, let other = self.action(using: shortcut, except: action) {
            record(nil, for: other)
            displaced = other
        }
        record(shortcut, for: action)
        save()
        return displaced
    }

    func reset(_ action: ShortcutAction) {
        changes[action] = nil
        // Back to its default: anything else using that default loses it.
        if let shortcut = action.defaultShortcut, let other = self.action(using: shortcut, except: action) { record(nil, for: other) }
        save()
    }

    func resetAll() {
        changes = [:]
        save()
    }

    private func record(_ shortcut: Shortcut?, for action: ShortcutAction) {
        changes[action] = shortcut == action.defaultShortcut ? nil : .some(shortcut)
    }

    private func save() {
        var saved: [String: String] = [:]
        for (action, shortcut) in changes {
            saved[action.rawValue] = shortcut.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        UserDefaults.standard.set(saved, forKey: Self.key)
        DispatchQueue.main.async { Self.updateMenus(NSApp.mainMenu) }
    }

    /// SwiftUI gives a menu's items their new shortcuts only as the menu opens, so until then
    /// the old keys would still work and the new ones wouldn't: each menu is asked to update.
    private static func updateMenus(_ menu: NSMenu?) {
        for item in menu?.items ?? [] {
            guard let submenu = item.submenu else { continue }
            submenu.delegate?.menuNeedsUpdate?(submenu)
            updateMenus(submenu)
        }
    }
}

extension View {
    /// The shortcut set for an action (its default, or as changed in Settings).
    @MainActor func shortcut(_ action: ShortcutAction, in store: ShortcutStore) -> some View {
        keyboardShortcut(store.keyboardShortcut(for: action))
    }
}
