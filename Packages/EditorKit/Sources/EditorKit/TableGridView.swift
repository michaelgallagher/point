#if canImport(AppKit)
import AppKit
import MarkdownKit

/// A table, drawn as a grid over its hidden Markdown in the editor (see
/// `MarkdownStyler.layOutTable`, which makes room for it). Each cell is a small text view
/// showing its cell's text from the note. Typing in one changes the note, and the cell is then
/// updated from the note, so the note's text stays the only copy (see +TableGrid).
final class TableGridView: NSView {
    weak var editor: MarkdownTextView?
    /// The table's Markdown.
    private(set) var range = NSRange()
    private(set) var decoration = TableDecoration(columnEdges: [0], columnWidths: [], rowHeights: [], alignments: [])
    /// Each row's cells, the header first. A row short of cells has fewer.
    private(set) var cells: [[TableCellView]] = []
    /// Set while the cells are updated from the note, which isn't their being edited.
    private(set) var isUpdating = false

    init(editor: MarkdownTextView) {
        self.editor = editor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Where a cell's text goes, in the grid.
    func textFrame(row: Int, column: Int, theme: EditorTheme) -> CGRect {
        let top = decoration.rowTops[row]
        return CGRect(x: decoration.columnEdges[column] + theme.tableCellPadding, y: top + theme.tableRowPadding,
                      width: decoration.columnWidths[column], height: decoration.rowHeights[row] - theme.tableRowPadding * 2)
    }

    /// Shows the table as the note now has it: each row's cells' text, where it is in the note,
    /// and how it looks. The cell being typed in keeps its text when only spaces typed after it
    /// differ (the note counts them as padding until something follows them), and its cursor.
    func update(range: NSRange, decoration: TableDecoration, contents: [[(range: NSRange, text: NSAttributedString)]],
                styler: MarkdownStyler, selection: NSRange) {
        isUpdating = true
        defer { isUpdating = false }
        if decoration != self.decoration { needsDisplay = true }
        self.range = range
        self.decoration = decoration
        let focused = window?.firstResponder as? TableCellView

        var kept: [[TableCellView]] = []
        for (r, row) in contents.enumerated() {
            var views: [TableCellView] = []
            for (c, content) in row.enumerated() where c < decoration.columnWidths.count {
                let view = r < cells.count && c < cells[r].count ? cells[r][c] : makeCell()
                view.row = r
                view.column = c
                view.range = content.range
                view.frame = textFrame(row: r, column: c, theme: styler.theme)
                var typing = styler.emptyCellAttributes(header: r == 0)
                typing[.paragraphStyle] = styler.tableCellParagraphStyle(decoration.alignments[c])
                view.show(content.text, typing: typing, isFocused: view === focused, noteSelection: selection)
                views.append(view)
            }
            kept.append(views)
        }
        let views = Set(kept.joined().map(ObjectIdentifier.init))
        for view in cells.joined() where !views.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
        cells = kept
    }

    private func makeCell() -> TableCellView {
        let view = TableCellView(grid: self)
        addSubview(view)
        return view
    }

    // MARK: Drawing

    /// A rounded border, a line under each row and between the columns, and the header shaded.
    override func draw(_ dirtyRect: NSRect) {
        let width = decoration.width, height = decoration.height
        guard width > 0, height > 0 else { return }
        let border = CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        let shape = NSBezierPath(roundedRect: border, xRadius: 6, yRadius: 6)
        withSavedGraphicsState {
            shape.addClip()
            NSColor.textColor.withAlphaComponent(0.05).setFill()
            NSRect(x: 0, y: 0, width: width, height: decoration.rowHeights.first ?? 0).fill()
        }
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath()
        for top in decoration.rowTops.dropFirst() {
            lines.move(to: CGPoint(x: 0, y: top.rounded() - 0.5))
            lines.line(to: CGPoint(x: width, y: top.rounded() - 0.5))
        }
        for edge in decoration.columnEdges.dropFirst().dropLast() {
            lines.move(to: CGPoint(x: edge.rounded() + 0.5, y: 0))
            lines.line(to: CGPoint(x: edge.rounded() + 0.5, y: height))
        }
        lines.lineWidth = 1
        lines.stroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    // MARK: The mouse

    /// A click in a cell's padding goes into the cell.
    override func mouseDown(with event: NSEvent) {
        guard let editor else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = decoration.rowTops.lastIndex { $0 <= point.y } ?? 0
        let column = decoration.columnEdges.dropLast().lastIndex { $0 <= point.x } ?? 0
        guard row < cells.count, !cells[row].isEmpty else { return }
        let cell = cells[row][min(column, cells[row].count - 1)]
        editor.focus(cell, at: point.x < cell.frame.minX ? 0 : cell.string.utf16.count)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = decoration.rowTops.lastIndex { $0 <= point.y } ?? 0
        guard row < cells.count, let cell = cells[row].last(where: { $0.frame.minX - 20 <= point.x }) ?? cells[row].first else { return nil }
        return editor?.tableMenu(at: cell.range.location, adding: NSMenu())
    }
}

/// One of a table's cells, editing the note's text for it (see +TableGrid). Its text, and what
/// it looks like, come from the note.
final class TableCellView: NSTextView {
    weak var grid: TableGridView?
    var row = 0
    var column = 0
    /// Where the cell's text is in the note.
    var range = NSRange()

    convenience init(grid: TableGridView) {
        let storage = NSTextStorage()
        let layoutManager = PointLayoutManager()
        if let theme = grid.editor?.styler.theme { layoutManager.theme = theme }
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        self.grid = grid
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false // The note's undo takes back what's typed here.
        isRichText = true
        importsGraphics = false
        usesFindBar = false
        focusRingType = .none
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = grid.editor?.isContinuousSpellCheckingEnabled ?? false
    }

    private var editor: MarkdownTextView? { grid?.editor }

    /// Shows `text`. The cell being typed in keeps what it has, with only how it looks changed,
    /// unless the note's text for it is different (beyond spaces typed at its end); then it
    /// takes the note's text, and the cursor goes where the note's is.
    func show(_ text: NSAttributedString, typing: [NSAttributedString.Key: Any], isFocused: Bool, noteSelection: NSRange) {
        // Not while a character is being composed (with an input method), which the note has as
        // it goes but which would be lost by restyling it here.
        guard let storage = textStorage, !(isFocused && hasMarkedText()) else { return }
        func trimmed(_ string: String) -> Substring {
            var string = Substring(string)
            while string.last == " " { string.removeLast() }
            return string
        }
        if isFocused, trimmed(storage.string) == trimmed(text.string), text.length <= storage.length {
            storage.beginEditing()
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, part, _ in
                storage.setAttributes(attributes, range: part)
            }
            storage.endEditing()
        } else if !storage.isEqual(to: text) {
            storage.setAttributedString(text)
            if isFocused {
                let start = min(max(noteSelection.location - range.location, 0), text.length)
                let end = min(max(NSMaxRange(noteSelection) - range.location, start), text.length)
                setSelectedRange(NSRange(location: start, length: end - start))
            }
        }
        if storage.length == 0 { typingAttributes = typing }
    }

    // MARK: Editing the note

    @objc func undo(_ sender: Any?) { editor?.undo(sender) }
    @objc func redo(_ sender: Any?) { editor?.redo(sender) }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let editor, editor.cellWillChange(self, replacing: affectedCharRange, with: replacementString) else { return false }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func didChangeText() {
        super.didChangeText()
        editor?.cellDidChange(self)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if !stillSelecting, ranges.count == 1, ranges[0].rangeValue.length == 0 {
            let location = ranges[0].rangeValue.location
            ranges = [NSValue(range: NSRange(location: snapped(location, forward: location >= selectedRange().location), length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting, grid?.isUpdating == false, window?.firstResponder === self { editor?.cellSelectionChanged(self) }
    }

    /// Never inside hidden markers (`**`, `[[`), as in the note, so every arrow press visibly
    /// moves the cursor: past them going forward, before them going back.
    private func snapped(_ location: Int, forward: Bool) -> Int {
        guard let storage = textStorage else { return location }
        func isHidden(_ index: Int) -> Bool {
            index >= 0 && index < storage.length && storage.attribute(.pointHidden, at: index, effectiveRange: nil) != nil
        }
        var location = location
        if forward {
            while isHidden(location) { location += 1 }
        } else {
            while isHidden(location - 1) { location -= 1 }
        }
        return location
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.cellDidTakeFocus(self) }
        return accepted
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    // MARK: Moving about

    override func insertTab(_ sender: Any?) { editor?.cellCommand(self, .next) }
    override func insertBacktab(_ sender: Any?) { editor?.cellCommand(self, .previous) }
    override func insertNewline(_ sender: Any?) { editor?.cellCommand(self, .down) }
    override func insertLineBreak(_ sender: Any?) {}
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {}

    override func moveUp(_ sender: Any?) {
        isOnLine(first: true) ? editor?.moveOutOfCell(self, .up) : super.moveUp(sender)
    }

    override func moveDown(_ sender: Any?) {
        isOnLine(first: false) ? editor?.moveOutOfCell(self, .down) : super.moveDown(sender)
    }

    override func moveLeft(_ sender: Any?) {
        isAtEdge(start: true) ? editor?.moveOutOfCell(self, .left) : super.moveLeft(sender)
    }

    override func moveRight(_ sender: Any?) {
        isAtEdge(start: false) ? editor?.moveOutOfCell(self, .right) : super.moveRight(sender)
    }

    /// Whether the cursor is at the start of the cell's text, or its end, with only hidden
    /// markers (if anything) between.
    private func isAtEdge(start: Bool) -> Bool {
        let selection = selectedRange()
        guard selection.length == 0, let storage = textStorage else { return false }
        let rest = start ? NSRange(location: 0, length: selection.location)
            : NSRange(location: selection.location, length: storage.length - selection.location)
        var visible = false
        storage.enumerateAttribute(.pointHidden, in: rest) { value, _, stop in
            if value == nil {
                visible = true
                stop.pointee = true
            }
        }
        return !visible
    }

    /// Whether the cursor is on the cell's first line, or its last.
    private func isOnLine(first: Bool) -> Bool {
        guard let layoutManager, let textContainer, selectedRange().length == 0 else { return false }
        let length = string.utf16.count
        guard length > 0 else { return true }
        let location = selectedRange().location
        let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let used = layoutManager.usedRect(for: textContainer)
        return first ? line.minY <= used.minY + 0.5 : line.maxY >= used.maxY - 0.5
    }

    // MARK: Menus and finding

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        return editor?.tableMenu(at: range.location + min(index, range.length), adding: super.menu(for: event) ?? NSMenu())
    }

    /// Find looks in the whole note.
    override func performTextFinderAction(_ sender: Any?) {
        guard let editor else { return }
        window?.makeFirstResponder(editor)
        editor.performTextFinderAction(sender)
    }

    override func performFindPanelAction(_ sender: Any?) { performTextFinderAction(sender) }
}

/// A table's row or column being dragged, lifted off the table under the pointer.
final class TableDragGhostView: NSView {
    let image: NSImage
    /// The space around the image for its shadow.
    static let margin: CGFloat = 12

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        withSavedGraphicsState {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        }
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()
    }
}
#endif
