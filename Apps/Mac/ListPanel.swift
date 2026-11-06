import IndexKit
import SwiftUI
import VaultKit

/// Under a list note's properties: what the list takes in (folders, tags, conditions), how
/// it's sorted and what it shows, each changed with a menu, then the notes it finds, as a
/// table. It's all kept in the note's `list-` properties (see `ListDefinition`), so the list
/// reads the same in Obsidian, as properties.
struct ListPanel: View {
    let list: ListDefinition
    @ObservedObject var session: EditorSession
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let paneID: VaultModel.NotePane.ID

    /// How many rows show, before "Show more": a list of thousands mustn't slow the note.
    @State private var shownCount = Self.firstRows
    private static let firstRows = 50
    /// The condition being edited (or added, when nil and `isAdding`), in its popover.
    @State private var editingCondition: Int?
    @State private var isAddingCondition = false

    var body: some View {
        let ids = store.noteIDs(matching: list.query)
        VStack(alignment: .leading, spacing: 10) {
            ListFilters(list: list, model: model, store: store, write: write,
                        editingCondition: $editingCondition, isAddingCondition: $isAddingCondition)
            if let ids {
                ListResults(list: list, ids: ids, limit: shownCount, moreLabel: "Show \(min(ids.count - shownCount, 200)) more",
                            more: { shownCount += 200 }, model: model, store: store, paneID: paneID, write: write)
            } else {
                Text("Finding notes…")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
            }
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.top, 2)
        }
        .font(.callout)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .padding(.leading, 5) // Lines up with the title and the text, which are inset a little.
        .frame(maxWidth: store.textColumnWidth, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .onChange(of: list.query) { _ in shownCount = Self.firstRows }
    }

    private func write(_ changed: ListDefinition) {
        session.writeList(changed)
    }
}

// MARK: What it takes in

/// The list's choices as a line of buttons: "In Sources", "Tagged #reading", "format is
/// Book", "Add filter", then its order and columns.
private struct ListFilters: View {
    let list: ListDefinition
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let write: (ListDefinition) -> Void
    @Binding var editingCondition: Int?
    @Binding var isAddingCondition: Bool

    var body: some View {
        ListFlow(spacing: 6) {
            ForEach(list.folders, id: \.self) { folder in
                ChipLabel(text: "In \(folder.isEmpty ? "the vault" : folder)", systemImage: "folder") {
                    var changed = list; changed.folders.removeAll { $0 == folder }; write(changed)
                }
            }
            ForEach(list.tags, id: \.self) { tag in
                ChipLabel(text: "Tagged #\(tag)", systemImage: "number") {
                    var changed = list; changed.tags.removeAll { $0 == tag }; write(changed)
                }
            }
            ForEach(Array(list.conditions.enumerated()), id: \.offset) { index, condition in
                if index > 0 {
                    // "and" or "or" between conditions: click to change which.
                    Button(list.matchesAny ? "or" : "and") {
                        var changed = list; changed.matchesAny.toggle(); write(changed)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(list.matchesAny ? "Notes meeting any of these: click for all" : "Notes meeting all of these: click for any")
                }
                Button { editingCondition = index } label: {
                    ChipLabel(text: condition.written, systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { editingCondition == index }, set: { if !$0 { editingCondition = nil } })) {
                    ConditionEditor(condition: condition, store: store, isNew: false) { edited in
                        editingCondition = nil
                        var changed = list
                        if let edited { changed.conditions[index] = edited } else { changed.conditions.remove(at: index) }
                        write(changed)
                    }
                }
            }
            addMenu
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 16)
            sortMenu
            columnsMenu
        }
    }

    /// Add a folder, a tag or a condition.
    private var addMenu: some View {
        Menu {
            Menu("Folder") {
                ForEach(folders, id: \.self) { folder in
                    Button(folder) { var changed = list; changed.folders.append(folder); write(changed) }
                }
            }
            Menu("Tag") {
                ForEach(store.tagTree.entries.filter { !list.tags.contains($0.tag) }) { entry in
                    Button("#\(entry.tag)") { var changed = list; changed.tags.append(entry.tag); write(changed) }
                }
            }
            Button("Condition…") { isAddingCondition = true }
        } label: {
            Label("Add filter", systemImage: "plus")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $isAddingCondition) {
            ConditionEditor(condition: ListCondition("", .is), store: store, isNew: true) { added in
                isAddingCondition = false
                guard let added else { return }
                var changed = list; changed.conditions.append(added); write(changed)
            }
        }
    }

    /// Every folder, in order, but those already chosen.
    private var folders: [String] {
        store.folderTree.noteCounts.keys.filter { !list.folders.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The order: note facts, then the vault's properties, most used first.
    private var sortMenu: some View {
        let current = list.sort.first ?? NoteQuery.Sort(.modified, descending: true)
        return Menu {
            ForEach(sortChoices, id: \.self) { name in
                Button {
                    let key: NoteQuery.Sort.Key = ListDefinition.field(named: name).map { .field($0) } ?? .property(name)
                    // Dates newest first, at first; words from A.
                    let descending = key == .field(.modified) || key == .field(.created)
                    var changed = list; changed.sort = [NoteQuery.Sort(key, descending: descending)]; write(changed)
                } label: {
                    if Self.name(of: current.key).lowercased() == name.lowercased() { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button(current.descending ? "Ascending" : "Descending") {
                var changed = list; changed.sort = [NoteQuery.Sort(current.key, descending: !current.descending)]; write(changed)
            }
        } label: {
            Label("Sorted by \(Self.name(of: current.key))", systemImage: current.descending ? "arrow.down" : "arrow.up")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    static func name(of key: NoteQuery.Sort.Key) -> String {
        switch key {
        case .field(let field): ListDefinition.name(of: field)
        case .property(let name): name
        }
    }

    private var sortChoices: [String] {
        ["title", "date edited", "date created"] + store.propertySummaries.prefix(40).map(\.name)
    }

    /// Which columns show after the title.
    private var columnsMenu: some View {
        Menu {
            ForEach(["folder", "date edited", "date created"] + store.propertySummaries.prefix(40).map(\.name), id: \.self) { name in
                let shown = list.columns.contains { $0.lowercased() == name.lowercased() }
                Button {
                    var changed = list
                    if shown { changed.columns.removeAll { $0.lowercased() == name.lowercased() } } else { changed.columns.append(name) }
                    write(changed)
                } label: {
                    if shown { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            Label("Columns", systemImage: "tablecells")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A filter, drawn as a token.
private struct ChipLabel: View {
    let text: String
    let systemImage: String
    /// With a button to take it away, if given.
    var remove: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .lineLimit(1)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .contentShape(Capsule())
    }
}

/// Picks what a condition is about, how it compares and with what.
private struct ConditionEditor: View {
    @ObservedObject var store: VaultStore
    let isNew: Bool
    /// Done, with the condition, or nil to remove it (or, new, to add nothing).
    let done: (ListCondition?) -> Void
    @State private var subject: String
    @State private var op: ListCondition.Operator
    @State private var value: String

    init(condition: ListCondition, store: VaultStore, isNew: Bool, done: @escaping (ListCondition?) -> Void) {
        self.store = store
        self.isNew = isNew
        self.done = done
        _subject = State(initialValue: condition.subject)
        _op = State(initialValue: condition.op)
        _value = State(initialValue: condition.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if !op.isAboutNote {
                    TextField("Property", text: $subject)
                        .frame(width: 140)
                    Menu {
                        ForEach(["title", "folder", "date created", "date edited"] + store.propertySummaries.prefix(40).map(\.name), id: \.self) { name in
                            Button(name) { subject = name }
                        }
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
                Picker("", selection: $op) {
                    ForEach(ListCondition.Operator.allCases, id: \.self) { op in
                        Text(op == .inLastDays ? "in last … days" : op == .inNextDays ? "in next … days" : op.words).tag(op)
                    }
                }
                .labelsHidden()
                .fixedSize()
                if op.takesValue {
                    TextField(placeholder, text: $value)
                        .frame(width: 160)
                        .onSubmit(finish)
                }
            }
            HStack {
                if !isNew {
                    Button("Remove") { done(nil) }
                }
                Spacer()
                Button("Cancel") { isNew ? done(nil) : dismissUnchanged() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Done", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(made == nil)
            }
        }
        .padding(14)
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissUnchanged() { dismiss() }

    private var placeholder: String {
        switch op {
        case .inLastDays, .inNextDays: "Days"
        case .linksTo: "Note"
        case .hasWords: "Words"
        case .before, .after: "Date"
        default: "Value"
        }
    }

    /// The condition as it stands, if it's whole.
    private var made: ListCondition? {
        let subject = op.isAboutNote ? "" : subject.trimmingCharacters(in: .whitespaces)
        let value = op.takesValue ? value.trimmingCharacters(in: .whitespaces) : ""
        guard op.isAboutNote || !subject.isEmpty, !op.takesValue || !value.isEmpty else { return nil }
        if op == .inLastDays || op == .inNextDays, Int(value) == nil { return nil }
        let linked = op == .linksTo && !value.hasPrefix("[[") ? "[[\(value)]]" : value
        return ListCondition(subject, op, linked)
    }

    private func finish() {
        guard let made else { return }
        done(made)
    }
}

// MARK: Embedded in a note

/// A list embedded in another note (`![[Books to read]]` alone on a line): the first notes it
/// finds, drawn above the embed, with a way to open the list for the rest.
struct ListEmbed: View {
    let listID: Note.ID
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let paneID: VaultModel.NotePane.ID
    static let rows = 10

    var body: some View {
        if let list = store.listDefinition(of: listID), let ids = store.noteIDs(matching: list.query) {
            ListResults(list: list, ids: ids, limit: Self.rows, moreLabel: "Show all \(ids.count)",
                        more: { model.open(listID, inPane: paneID, as: .here) },
                        model: model, store: store, paneID: paneID, write: nil)
                .font(.callout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// How tall it is for a list finding `count` notes.
    static func height(count: Int, hasColumns: Bool) -> CGFloat {
        ListResults.height(showing: min(count, rows), of: count, hasColumns: hasColumns) + 4
    }
}

// MARK: What it finds

/// The notes a list finds, as a table: the title, then a column for each property it shows.
/// A row opens its note (⌘-click in a new tab, ⌥-click on the other side).
struct ListResults: View {
    let list: ListDefinition
    let ids: [Note.ID]
    /// How many rows show, and what shows the rest.
    let limit: Int
    let moreLabel: String
    let more: () -> Void
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let paneID: VaultModel.NotePane.ID
    /// Changes the list (sorting by a column clicked); nil where it's shown in another note.
    let write: ((ListDefinition) -> Void)?
    /// The shown rows' property values, from the index, as of these rows and columns.
    @State private var values: [Note.ID: [String: [String]]] = [:]
    @State private var hovered: Note.ID?

    var body: some View {
        let shown = Array(ids.prefix(limit)).compactMap { store.notesByID[$0] }
        VStack(alignment: .leading, spacing: 0) {
            Text(ids.count == 1 ? "1 note" : "\(ids.count) notes")
                .foregroundStyle(.secondary)
                .frame(height: Self.countHeight, alignment: .topLeading)
            if !shown.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 0) {
                    if !list.columns.isEmpty {
                        GridRow {
                            header("Title", key: .field(.title))
                            ForEach(list.columns, id: \.self) { column in
                                header(column, key: ListDefinition.field(named: column).map { .field($0) } ?? .property(column))
                            }
                        }
                        .frame(height: Self.rowHeight)
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                    ForEach(shown) { note in
                        GridRow {
                            Text(note.title)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(list.columns, id: \.self) { column in
                                Text(value(of: column, for: note))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 180, alignment: .leading)
                            }
                        }
                        .frame(height: Self.rowHeight)
                        .background(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(hovered == note.id ? 0.06 : 0))
                                .padding(.horizontal, -5)
                        }
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hovered = note.id } else if hovered == note.id { hovered = nil }
                        }
                        .onTapGesture { open(note.id) }
                        .help("Open “\(note.title)”")
                    }
                }
            }
            if ids.count > shown.count {
                Button(moreLabel, action: more)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(height: Self.rowHeight)
            }
        }
        .task(id: ValuesKey(columns: list.columns, ids: Array(ids.prefix(limit)), generation: store.indexGeneration)) {
            let properties = list.columns.filter { ListDefinition.field(named: $0) == nil }
            values = await store.propertyValues(properties, of: Array(ids.prefix(limit)))
        }
    }

    static let rowHeight: CGFloat = 24, countHeight: CGFloat = 22

    /// How tall it is, showing `count` notes of `total`.
    static func height(showing count: Int, of total: Int, hasColumns: Bool) -> CGFloat {
        countHeight + (count > 0 && hasColumns ? rowHeight + 1 : 0) + CGFloat(count) * rowHeight + (total > count ? rowHeight : 0)
    }

    private struct ValuesKey: Equatable {
        let columns: [String]
        let ids: [Note.ID]
        let generation: Int
    }

    /// A column's heading: click to sort by it, again to reverse.
    private func header(_ name: String, key: NoteQuery.Sort.Key) -> some View {
        let current = list.sort.first
        let isSorted = current?.key == key || (current == nil && key == .field(.modified))
        let descending = current?.descending ?? true
        return Button {
            var changed = list
            changed.sort = [NoteQuery.Sort(key, descending: isSorted ? !descending : false)]
            write?(changed)
        } label: {
            HStack(spacing: 3) {
                Text(name.prefix(1).uppercased() + name.dropFirst())
                if isSorted { Image(systemName: descending ? "chevron.down" : "chevron.up").font(.caption2) }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(write != nil)
        .help(write == nil ? "" : "Sort by \(name)")
    }

    private func value(of column: String, for note: Note) -> String {
        switch ListDefinition.field(named: column) {
        case .title: return note.title
        case .folder: return FolderTree.folder(of: note.id)
        case .created: return note.created.formatted(date: .abbreviated, time: .omitted)
        case .modified: return note.modified.formatted(date: .abbreviated, time: .omitted)
        case nil:
            let written = values[note.id]?[column.lowercased()] ?? []
            return written.map { value in
                // A link shows as its name.
                guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
                return String(value.dropFirst(2).dropLast(2).split(separator: "|").last ?? "")
            }.joined(separator: ", ")
        }
    }

    private func open(_ id: Note.ID) {
        let flags = NSEvent.modifierFlags
        model.open(id, inPane: paneID, as: flags.contains(.command) ? .newTab : flags.contains(.option) ? .otherSide : .here)
    }
}

/// Lays its views out in rows, wrapping as they fill the width.
private struct ListFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews.map { $0.sizeThatFits(.unspecified) }, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in arrange(sizes, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - sizes[index].height) / 2), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ sizes: [CGSize], width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, size) in sizes.enumerated() {
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
