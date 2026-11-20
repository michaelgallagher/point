import Foundation
import MarkdownKit

/// A command in the slash menu: what typing `/` in a note offers to put in or do there. The
/// same on the Mac and the iPhone; each app says which it can do, and does the few the editor
/// can't (templates, properties, daily notes).
public struct SlashCommand: Identifiable, Equatable, Sendable {
    public enum ID: String, CaseIterable, Sendable {
        case list, table, callout, codeBlock, divider
        case linkToNote, embedNote, image
        case date, time, todaysNote, tomorrowsNote
        case template, property, tag
        case heading1, heading2, heading3, bulletList, numberedList, checklist, quote
    }

    public let id: ID
    public let name: String
    /// Other names it's found by: `/rule` finds Divider.
    public let otherNames: [String]
    /// Its SF Symbol.
    public let symbol: String
    /// Its kinds, chosen next: a callout's type, a code block's language. Typing the command's
    /// name and a space narrows them.
    public let choices: [String]
    /// The kind chosen, for a command offered as one of another's choices.
    public let choice: String?

    public init(_ id: ID, _ name: String, symbol: String, otherNames: [String] = [], choices: [String] = [], choice: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.otherNames = otherNames
        self.choices = choices
        self.choice = choice
    }

    /// Every command, in the menu's order with nothing typed.
    public static let all: [SlashCommand] = [
        SlashCommand(.list, "List", symbol: "list.bullet.rectangle", otherNames: ["query", "notes list", "list of notes"]),
        SlashCommand(.table, "Table", symbol: "tablecells", otherNames: ["grid"]),
        SlashCommand(.callout, "Callout", symbol: "exclamationmark.bubble", otherNames: ["admonition", "aside"],
                     choices: ["note", "tip", "info", "important", "warning", "caution", "question", "example", "quote", "abstract", "todo", "success", "failure", "danger", "bug"]),
        SlashCommand(.codeBlock, "Code block", symbol: "curlybraces", otherNames: ["fence", "snippet"],
                     choices: ["none", "swift", "python", "javascript", "typescript", "json", "yaml", "shell", "html", "css", "sql", "markdown", "ruby", "go", "rust"]),
        SlashCommand(.divider, "Divider", symbol: "minus", otherNames: ["rule", "horizontal rule", "hr", "line", "separator"]),
        SlashCommand(.linkToNote, "Link to a note", symbol: "link", otherNames: ["wikilink", "note link"]),
        SlashCommand(.embedNote, "Embed a note", symbol: "rectangle.on.rectangle", otherNames: ["transclude", "include"]),
        SlashCommand(.image, "Image", symbol: "photo", otherNames: ["picture", "photo"]),
        SlashCommand(.date, "Today's date", symbol: "calendar", otherNames: ["date", "today"]),
        SlashCommand(.time, "The time", symbol: "clock", otherNames: ["time", "now"]),
        SlashCommand(.todaysNote, "Today's note", symbol: "calendar.day.timeline.left", otherNames: ["daily note", "today"]),
        SlashCommand(.tomorrowsNote, "Tomorrow's note", symbol: "calendar.badge.plus", otherNames: ["daily note"]),
        SlashCommand(.template, "Template", symbol: "doc.text", otherNames: ["apply template"]),
        SlashCommand(.property, "Property", symbol: "list.bullet.indent", otherNames: ["frontmatter", "metadata", "field"]),
        SlashCommand(.tag, "Tag", symbol: "number", otherNames: ["hashtag"]),
        SlashCommand(.heading1, "Heading 1", symbol: "textformat.size.larger", otherNames: ["h1", "title"]),
        SlashCommand(.heading2, "Heading 2", symbol: "textformat.size", otherNames: ["h2", "subheading"]),
        SlashCommand(.heading3, "Heading 3", symbol: "textformat.size.smaller", otherNames: ["h3"]),
        SlashCommand(.bulletList, "Bulleted list", symbol: "list.bullet", otherNames: ["bullets", "unordered list", "ul"]),
        SlashCommand(.numberedList, "Numbered list", symbol: "list.number", otherNames: ["ordered list", "ol"]),
        SlashCommand(.checklist, "Checklist", symbol: "checklist", otherNames: ["todo", "task", "checkbox"]),
        SlashCommand(.quote, "Quote", symbol: "text.quote", otherNames: ["blockquote"]),
    ]

    /// One of a command's choices, as a command of its own: "Callout: Warning".
    func choosing(_ choice: String) -> SlashCommand {
        SlashCommand(id, choice.prefix(1).uppercased() + choice.dropFirst(), symbol: symbol, choice: choice)
    }
}

/// The `/` being typed at the cursor, and what's typed after it.
public struct SlashQuery: Equatable, Sendable {
    /// The `/` and what follows it up to the cursor: what a command takes the place of.
    public let range: NSRange
    /// What's typed after the `/`.
    public let typed: String
    /// Where the `/` is.
    public var slash: Int { range.location }
}

/// Where the slash menu opens, and what it offers for what's typed.
public enum SlashMenu {
    /// How much can be typed after a `/` before it's taken to be just a slash.
    static let longest = 32

    /// The `/` being typed at `cursor`, if the menu can open there: at the start of a line or
    /// after a space, never in the middle of a word (`and/or`), and not in code, a link, a web
    /// address, the properties or a table.
    public static func query(in text: String, tokens: [MarkdownToken], at cursor: Int) -> SlashQuery? {
        let text = text as NSString
        guard cursor <= text.length else { return nil }
        let lineStart = text.lineRange(for: NSRange(location: cursor, length: 0)).location
        var slash = cursor - 1
        while slash >= lineStart, text.character(at: slash) != 47 { // "/"
            guard cursor - slash <= longest else { return nil }
            slash -= 1
        }
        guard slash >= lineStart else { return nil }
        // At a line's start or after a space or tab.
        if slash > lineStart {
            let before = text.character(at: slash - 1)
            guard before == 32 || before == 9 else { return nil }
        }
        let typed = text.substring(with: NSRange(location: slash + 1, length: cursor - slash - 1))
        guard !typed.hasPrefix(" "), !typed.contains("\t") else { return nil }
        guard !tokens.contains(where: { token in
            switch token.kind {
            case .frontmatter, .codeBlock, .code, .link, .url, .wikiLink, .embed, .image, .table, .escape:
                return NSLocationInRange(slash, token.range)
            default:
                return false
            }
        }) else { return nil }
        return SlashQuery(range: NSRange(location: slash, length: cursor - slash), typed: typed)
    }

    /// The commands for what's typed after the `/`, best first: those whose name starts with it,
    /// then those with every word typed starting one of their name's words, then those found by
    /// another name; each in the menu's order. A command with choices, its name typed and a
    /// space, offers its choices. Nothing typed: all of them.
    public static func matching(_ commands: [SlashCommand], typed: String) -> [SlashCommand] {
        let typed = typed.lowercased()
        // A command's choices, after its name and a space: "callout w" offers Warning.
        for command in commands where !command.choices.isEmpty {
            for name in [command.name] + command.otherNames {
                let prefix = name.lowercased() + " "
                guard typed.hasPrefix(prefix) else { continue }
                let rest = String(typed.dropFirst(prefix.count))
                return command.choices.filter { rest.isEmpty || $0.hasPrefix(rest.trimmingCharacters(in: .whitespaces)) }
                    .map(command.choosing)
            }
        }
        let words = Self.words(typed)
        guard !words.isEmpty else { return typed.isEmpty ? commands : [] }
        func matches(_ name: String) -> Bool {
            let nameWords = Self.words(name)
            return words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
        }
        let scored = commands.enumerated().compactMap { offset, command -> (Int, Int, SlashCommand)? in
            let name = command.name.lowercased()
            if name.hasPrefix(typed) { return (0, offset, command) }
            if matches(name) { return (1, offset, command) }
            if command.otherNames.contains(where: { $0.hasPrefix(typed) || matches($0) }) { return (2, offset, command) }
            return nil
        }
        return scored.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Today's date, as daily notes are named and dates are written in properties.
    public static func dateText(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The time, as 24-hour hours and minutes.
    public static func timeText(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: What the commands write

extension MarkdownEditing {
    /// What a command writes at the cursor (the `/` and what was typed after it already gone),
    /// for the commands the editor does itself; nil for those the app does, or the list, which
    /// each editor puts in its own way.
    public func slashEdit(_ command: SlashCommand) -> MarkdownEdit? {
        switch command.id {
        case .table:
            let table = MarkdownTable.blank(columns: 3, bodyRows: 2).markdown()
            // "Column 1", after the first `| `, selected to type over.
            return insertingBlock(table, selecting: NSRange(location: 2, length: 8))
        case .callout:
            let line = "> [!\(command.choice ?? "note")] "
            return insertingBlock(line, selecting: NSRange(location: (line as NSString).length, length: 0))
        case .codeBlock:
            // With a language, the cursor inside; without one, after the opening fence to type
            // one (Return then goes inside).
            let language = command.choice == "none" ? "" : command.choice
            let block = "```\(language ?? "")\n\n```"
            let cursor = language == nil ? 3 : 3 + (language! as NSString).length + 1
            return insertingBlock(block, selecting: NSRange(location: cursor, length: 0))
        case .divider:
            return insertingBlock("---", selecting: nil)
        case .linkToNote:
            return inserting("[[]]").movingCursor(by: -2)
        case .embedNote:
            return inserting("![[]]").movingCursor(by: -2)
        case .tag:
            return inserting("#")
        case .date:
            return inserting(SlashMenu.dateText())
        case .time:
            return inserting(SlashMenu.timeText())
        case .heading1: return setHeading(1)
        case .heading2: return setHeading(2)
        case .heading3: return setHeading(3)
        case .bulletList: return toggleBulletList()
        case .numberedList: return toggleNumberedList()
        case .checklist: return toggleChecklist()
        case .quote: return toggleBlockQuote()
        case .list, .image, .todaysNote, .tomorrowsNote, .template, .property:
            return nil
        }
    }

    /// Puts `block` on lines of its own, where the cursor is: in place of a blank line, or
    /// after the line it's on, with a blank line before it (after text) and after it (before
    /// text), so it's never read as part of a paragraph. `selecting` is where the selection
    /// goes, within the block; nil, the line after it.
    public func insertingBlock(_ block: String, selecting: NSRange?) -> MarkdownEdit {
        func isBlank(_ range: NSRange) -> Bool {
            text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: NSMaxRange(selection), length: 0))
        let target: NSRange, prefix: String
        if isBlank(NSRange(location: start, length: contentsEnd - start)) {
            target = NSRange(location: start, length: contentsEnd - start)
            let previousIsBlank = start == 0 || isBlank(text.lineRange(for: NSRange(location: start - 1, length: 0)))
            prefix = previousIsBlank ? "" : "\n"
        } else {
            target = NSRange(location: contentsEnd, length: 0)
            prefix = "\n\n"
        }
        let next = target.location == contentsEnd && end > contentsEnd ? end : NSMaxRange(target)
        let hasNext = next < text.length
        let nextIsBlank = hasNext && isBlank(text.lineRange(for: NSRange(location: next, length: 0)))
        // Before text, a blank line between; with nothing after, a line to go on writing on.
        let lineBreak = end > contentsEnd ? "" : "\n"
        let suffix = hasNext && !nextIsBlank ? "\n" : (selecting == nil && !hasNext ? lineBreak : "")
        let replacement = prefix + block + suffix
        let blockStart = target.location + (prefix as NSString).length
        let selection: NSRange
        if let selecting {
            selection = NSRange(location: blockStart + selecting.location, length: selecting.length)
        } else {
            // The line after the block.
            selection = NSRange(location: blockStart + (block as NSString).length + 1, length: 0)
        }
        return MarkdownEdit(range: target, replacement: replacement, selection: selection)
    }
}

extension MarkdownEdit {
    func movingCursor(by offset: Int) -> MarkdownEdit {
        MarkdownEdit(range: range, replacement: replacement, selection: NSRange(location: selection.location + offset, length: 0))
    }
}
