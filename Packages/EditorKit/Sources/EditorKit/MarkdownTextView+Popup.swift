#if canImport(AppKit)
import AppKit
import MarkdownKit
import SwiftUI

/// What's being typed that the popup can finish: a slash command, a `[[link`, a `#tag` or an
/// `@mention`.
enum EditorPopupContext: Equatable {
    case slash(SlashQuery)
    /// After `[[`, up to the cursor.
    case note(MarkdownEditing.Completion)
    /// After `#`, up to the cursor.
    case tag(MarkdownEditing.Completion)
    /// The name after `@`, up to the cursor.
    case person(NSRange)

    /// Where it starts (the `/`, `[[`, `#` or `@`): Escape closes the popup for it, until
    /// another is typed.
    var anchor: Int {
        switch self {
        case .slash(let query): query.slash
        case .note(let completion): completion.range.location - 2
        case .tag(let completion): completion.range.location - 1
        case .person(let range): range.location - 1
        }
    }
}

/// One line in the popup: a symbol, a name, and at its end, a shortcut.
struct EditorPopupRow: Equatable {
    var symbol: String?
    var title: String
    var detail: String?
}

/// The popup showing, if it is: what it's for, what it offers, and its view.
@MainActor
final class EditorPopup {
    var context: EditorPopupContext
    /// The slash commands offered, or the titles, tags or people.
    var commands: [SlashCommand] = []
    var choices: [String] = []
    let model = EditorPopupModel()
    let view: NSHostingView<EditorPopupList>

    init(context: EditorPopupContext) {
        self.context = context
        view = NSHostingView(rootView: EditorPopupList(model: model))
    }

    var count: Int { model.rows.count }
}

/// The popup's rows and which is highlighted, for its SwiftUI view.
@MainActor
final class EditorPopupModel: ObservableObject {
    @Published var rows: [EditorPopupRow] = []
    @Published var highlighted = 0
    var pick: (Int) -> Void = { _ in }
    /// Where the mouse first was over the popup, and whether it's moved since: only a mouse
    /// moving over the rows highlights one.
    var mouseAtRest: CGPoint?
    var mouseMoved = false
}

/// One popup, in glass, under the cursor, for everything typed that can be finished from a
/// list: slash commands, links to notes, tags and people. Typing narrows it; Return or Tab, or
/// a click, puts in the one highlighted; up and down choose; Escape, moving away, or typing what
/// matches nothing closes it (Escape again, or ⌥Escape, opens it again).
extension MarkdownTextView {
    static let popupWidth: CGFloat = 280
    static let popupRowHeight: CGFloat = 26
    static let popupVisibleRows = 9
    static let popupCornerRadius: CGFloat = 12

    /// Shows, narrows or closes the popup for the cursor where it is now.
    func updatePopup() {
        let selection = selectedRange()
        let context = selection.length == 0 && !hasMarkedText() && !hasMultipleCursors && window?.firstResponder === self
            ? popupContext(at: selection.location) : nil
        if dismissedPopup != nil, context?.anchor != dismissedPopup { dismissedPopup = nil }
        guard let context, context.anchor != dismissedPopup else { return hidePopup() }
        // Asked again only when what's typed changed (the cursor moved within it, say).
        if let shown = self.popup, shown.context == context { return }
        let popup = self.popup ?? makePopup(context)
        let previous = popup.model.rows.map(\.title)
        popup.context = context
        switch context {
        case .slash(let query):
            popup.commands = SlashMenu.matching(slashCommands, typed: query.typed)
            popup.choices = []
            popup.model.rows = popup.commands.map { EditorPopupRow(symbol: $0.symbol, title: $0.name, detail: slashShortcut?($0.id)) }
        case .note(let completion):
            popup.choices = completeNoteTitle?(completion.partial) ?? []
            popup.model.rows = popup.choices.map { EditorPopupRow(symbol: "doc.text", title: $0) }
        case .tag(let completion):
            popup.choices = completeTag?(completion.partial) ?? []
            popup.model.rows = popup.choices.map { EditorPopupRow(symbol: "number", title: $0) }
        case .person(let range):
            popup.choices = completePerson?((string as NSString).substring(with: range)) ?? []
            popup.model.rows = popup.choices.map { EditorPopupRow(symbol: "person", title: $0) }
        }
        guard popup.count > 0 else { return hidePopup() }
        if popup.model.rows.map(\.title) != previous { popup.model.highlighted = 0 }
        placePopup(popup)
    }

    private func makePopup(_ context: EditorPopupContext) -> EditorPopup {
        let popup = EditorPopup(context: context)
        popup.model.pick = { [weak self] in self?.choosePopupRow($0) }
        self.popup = popup
        addSubview(popup.view)
        return popup
    }

    func hidePopup() {
        popup?.view.removeFromSuperview()
        popup = nil
    }

    /// What can be finished at the cursor, if anything: cheap, as it's asked each time the
    /// cursor moves.
    private func popupContext(at location: Int) -> EditorPopupContext? {
        if !slashCommands.isEmpty, let query = SlashMenu.query(in: string, tokens: tokens, at: location) {
            return .slash(query)
        }
        if completeNoteTitle != nil, let range = wikiLinkPartialRange() {
            let partial = (string as NSString).substring(with: range)
            return .note(MarkdownEditing.Completion(kind: .note, partial: partial, range: range))
        }
        if completePerson != nil, let range = mentionPartialRange() { return .person(range) }
        // A tag once a letter's typed after the `#` (a `#` alone may be a heading's start), and
        // not in code, a link or a heading's marker.
        if completeTag != nil, let completion = MarkdownEditing.completion(in: string, at: location),
           completion.kind == .tag, !completion.partial.isEmpty,
           !tokens.contains(where: { token in
               switch token.kind {
               case .code, .codeBlock, .wikiLink, .embed, .link, .url, .frontmatter: NSLocationInRange(completion.range.location - 1, token.range)
               default: false
               }
           }) {
            return .tag(completion)
        }
        return nil
    }

    /// Under the line where it starts, at its start; above it if there's no room below.
    private func placePopup(_ popup: EditorPopup) {
        guard let layoutManager, let textContainer else { return }
        let anchor = min(max(popup.context.anchor, 0), max((string as NSString).length - 1, 0))
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: anchor, length: 1), actualCharacterRange: nil)
        var line = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        line.origin.x += textContainerOrigin.x
        line.origin.y += textContainerOrigin.y
        let rows = min(popup.count, Self.popupVisibleRows)
        let height = CGFloat(rows) * Self.popupRowHeight + 12
        let visible = visibleRect
        var y = line.maxY + 4
        if y + height > visible.maxY, line.minY - height - 4 > visible.minY { y = line.minY - height - 4 }
        let x = min(max(line.minX - 8, visible.minX + 4), visible.maxX - Self.popupWidth - 4)
        popup.view.frame = NSRect(x: x, y: y, width: Self.popupWidth, height: height)
    }

    /// Up, down, Return, Tab and Escape, while the popup shows. Whether the key was for it.
    func handlePopupKey(_ selector: Selector) -> Bool {
        guard let popup, popup.count > 0 else { return false }
        switch selector {
        case #selector(moveUp(_:)):
            popup.model.highlighted = (popup.model.highlighted - 1 + popup.count) % popup.count
        case #selector(moveDown(_:)):
            popup.model.highlighted = (popup.model.highlighted + 1) % popup.count
        case #selector(insertNewline(_:)), #selector(insertTab(_:)):
            choosePopupRow(min(popup.model.highlighted, popup.count - 1))
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            dismissedPopup = popup.context.anchor
            hidePopup()
        default:
            return false
        }
        return true
    }

    /// Escape (or ⌥Escape) where the popup was closed opens it again; elsewhere, the system's
    /// own word completion.
    public override func complete(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, popupContext(at: selection.location) != nil {
            dismissedPopup = nil
            updatePopup()
            return
        }
        super.complete(sender)
    }

    /// Puts in the row chosen: a slash command, or finishes the link, tag or mention.
    func choosePopupRow(_ index: Int) {
        guard let popup else { return }
        let context = popup.context
        switch context {
        case .slash:
            guard popup.commands.indices.contains(index) else { return }
            runSlashCommand(popup.commands[index])
            return
        case .note(let completion):
            guard popup.choices.indices.contains(index) else { return }
            let title = popup.choices[index]
            finish(MarkdownEditing(text: string, tokens: tokens, selection: selectedRange()).complete(completion, with: linkTextForTitle?(title) ?? title))
        case .tag(let completion):
            guard popup.choices.indices.contains(index) else { return }
            let tag = popup.choices[index].hasPrefix("#") ? String(popup.choices[index].dropFirst()) : popup.choices[index]
            finish(MarkdownEditing(text: string, tokens: tokens, selection: selectedRange()).complete(completion, with: tag))
        case .person(let range):
            guard popup.choices.indices.contains(index) else { return }
            // The `@` and the name typed become a link to the person's note.
            let whole = NSRange(location: range.location - 1, length: range.length + 1)
            let link = "[[\(popup.choices[index])]]"
            hidePopup()
            breakUndoCoalescing()
            replace(whole, with: link)
            updatePopup()
        }
    }

    private func finish(_ edit: MarkdownEdit) {
        hidePopup()
        breakUndoCoalescing()
        apply(edit)
        updatePopup()
    }
}

/// The popup's list: each row's symbol, name and shortcut, the highlighted one in the accent
/// colour, on glass.
struct EditorPopupList: View {
    @ObservedObject var model: EditorPopupModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                        line(row, highlighted: index == model.highlighted)
                            .id(index)
                            .onTapGesture { model.pick(index) }
                            .onContinuousHover(coordinateSpace: .global) { phase in
                                // Only when the mouse moves: one resting where the popup
                                // opens would take the highlight from the first row.
                                guard case .active(let point) = phase else { return }
                                if !model.mouseMoved {
                                    guard let rest = model.mouseAtRest else { model.mouseAtRest = point; return }
                                    guard point != rest else { return }
                                    model.mouseMoved = true
                                }
                                model.highlighted = index
                            }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .onChange(of: model.highlighted) { _, index in proxy.scrollTo(index) }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: MarkdownTextView.popupCornerRadius))
    }

    private func line(_ row: EditorPopupRow, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            if let symbol = row.symbol {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let detail = row.detail {
                Text(detail)
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: MarkdownTextView.popupRowHeight)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
#endif
