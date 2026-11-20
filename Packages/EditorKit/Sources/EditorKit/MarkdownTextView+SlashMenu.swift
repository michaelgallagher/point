#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the slash menu is showing: for which `/`, what it offers, and which is chosen.
@MainActor
final class SlashMenuState {
    var query: SlashQuery
    var commands: [SlashCommand]
    let model = SlashMenuModel()
    let view: NSHostingView<SlashMenuList>

    init(query: SlashQuery, commands: [SlashCommand]) {
        self.query = query
        self.commands = commands
        view = NSHostingView(rootView: SlashMenuList(model: model))
        model.commands = commands
    }
}

/// The menu's rows and which is highlighted, for its SwiftUI view.
@MainActor
final class SlashMenuModel: ObservableObject {
    @Published var commands: [SlashCommand] = []
    @Published var highlighted = 0
    var shortcut: (SlashCommand.ID) -> String? = { _ in nil }
    var pick: (SlashCommand) -> Void = { _ in }
}

/// The slash menu on the Mac: typing `/` at a line's start or after a space shows what can be
/// put in there, in a small list under the cursor, like link completion's. Typing narrows it;
/// Return or Tab, or a click, puts in the one chosen in place of the `/` and what was typed;
/// up and down choose; Escape, moving away, or typing what matches nothing closes it.
extension MarkdownTextView {
    static let slashMenuWidth: CGFloat = 260
    static let slashRowHeight: CGFloat = 26
    static let slashVisibleRows = 9

    /// Shows, narrows or closes the menu for the cursor where it is now.
    func updateSlashMenu() {
        guard !slashCommands.isEmpty else { return }
        let selection = selectedRange()
        let query = selection.length == 0 && !hasMarkedText() && !hasMultipleCursors && window?.firstResponder === self
            ? SlashMenu.query(in: string, tokens: tokens, at: selection.location) : nil
        if dismissedSlash != nil, query?.slash != dismissedSlash { dismissedSlash = nil }
        guard let query, query.slash != dismissedSlash else { return hideSlashMenu() }
        let commands = SlashMenu.matching(slashCommands, typed: query.typed)
        guard !commands.isEmpty else { return hideSlashMenu() }
        if let menu = slashMenu {
            if menu.commands.map(\.name) != commands.map(\.name) { menu.model.highlighted = 0 }
            menu.query = query
            menu.commands = commands
            menu.model.commands = commands
            placeSlashMenu(menu)
        } else {
            let menu = SlashMenuState(query: query, commands: commands)
            menu.model.shortcut = { [weak self] in self?.slashShortcut?($0) }
            menu.model.pick = { [weak self] in self?.runSlashCommand($0) }
            slashMenu = menu
            addSubview(menu.view)
            placeSlashMenu(menu)
        }
    }

    func hideSlashMenu() {
        slashMenu?.view.removeFromSuperview()
        slashMenu = nil
    }

    /// Under the line the `/` is on, at the `/`; above it if there's no room below.
    private func placeSlashMenu(_ menu: SlashMenuState) {
        guard let layoutManager, let textContainer else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: menu.query.slash, length: 1), actualCharacterRange: nil)
        var line = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        line.origin.x += textContainerOrigin.x
        line.origin.y += textContainerOrigin.y
        let rows = min(menu.commands.count, Self.slashVisibleRows)
        let height = CGFloat(rows) * Self.slashRowHeight + 12
        let visible = visibleRect
        var y = line.maxY + 4
        if y + height > visible.maxY, line.minY - height - 4 > visible.minY { y = line.minY - height - 4 }
        let x = min(max(line.minX - 8, visible.minX + 4), visible.maxX - Self.slashMenuWidth - 4)
        menu.view.frame = NSRect(x: x, y: y, width: Self.slashMenuWidth, height: height)
    }

    /// Up, down, Return, Tab and Escape, while the menu shows. Whether the key was for it.
    func handleSlashMenuKey(_ selector: Selector) -> Bool {
        guard let menu = slashMenu else { return false }
        switch selector {
        case #selector(moveUp(_:)):
            menu.model.highlighted = (menu.model.highlighted - 1 + menu.commands.count) % menu.commands.count
        case #selector(moveDown(_:)):
            menu.model.highlighted = (menu.model.highlighted + 1) % menu.commands.count
        case #selector(insertNewline(_:)), #selector(insertTab(_:)):
            runSlashCommand(menu.commands[min(menu.model.highlighted, menu.commands.count - 1)])
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            dismissedSlash = menu.query.slash
            hideSlashMenu()
        default:
            return false
        }
        return true
    }

    /// Puts in a command in place of the `/` and what was typed after it, as one step to undo,
    /// back to the `/` as typed. A command with choices (a callout's type) offers them first.
    func runSlashCommand(_ command: SlashCommand) {
        guard let query = slashMenu?.query ?? SlashMenu.query(in: string, tokens: tokens, at: selectedRange().location) else { return }
        if !command.choices.isEmpty, command.choice == nil {
            // Its name and a space, after the `/`: the menu offers its choices.
            replace(query.range, with: "/" + command.name.lowercased() + " ")
            return
        }
        hideSlashMenu()
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        replace(query.range, with: "")
        performSlash(command)
        // Named for the command, not its choice: Undo Callout, not Undo Warning.
        undoManager?.setActionName(SlashCommand.all.first { $0.id == command.id }?.name ?? command.name)
        undoManager?.endUndoGrouping()
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
            if command.id == .linkToNote || command.id == .embedNote { suggestCompletionsIfInWikiLink() }
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

/// The slash menu's list: each command's symbol, name and shortcut, the chosen one highlighted.
struct SlashMenuList: View {
    @ObservedObject var model: SlashMenuModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.commands.enumerated()), id: \.offset) { index, command in
                        row(command, highlighted: index == model.highlighted)
                            .id(index)
                            .onTapGesture { model.pick(command) }
                            .onHover { if $0 { model.highlighted = index } }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .onChange(of: model.highlighted) { _, index in proxy.scrollTo(index) }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private func row(_ command: SlashCommand, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: command.symbol)
                .frame(width: 18)
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Text(command.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut = model.shortcut(command.id) {
                Text(shortcut)
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: MarkdownTextView.slashRowHeight)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
}
#endif
