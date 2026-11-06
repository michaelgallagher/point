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

    var body: some View {
        let ids = store.noteIDs(matching: list.query)
        VStack(alignment: .leading, spacing: 10) {
            ListFilters(list: list, model: model, store: store, write: write)
            if let ids {
                ListResults(list: list, listID: session.note.id, ids: ids, limit: shownCount, moreLabel: "Show \(min(ids.count - shownCount, 200)) more",
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
    /// The filters window, while it's open: with a new condition to fill in, or not.
    @State private var sheet: SheetTarget?

    enum SheetTarget: String, Identifiable {
        case add, edit
        var id: String { rawValue }
    }

    var body: some View {
        ListFlow(spacing: 6) {
            ForEach(Array(list.folders.enumerated()), id: \.offset) { index, folder in
                ChipLabel(text: "In \(folder.isEmpty ? "the vault" : folder)", systemImage: "folder", open: { sheet = .edit }) {
                    var changed = list; changed.folders.remove(at: index); write(changed)
                }
            }
            ForEach(Array(list.tags.enumerated()), id: \.offset) { index, tag in
                ChipLabel(text: "Tagged #\(tag)", systemImage: "number", open: { sheet = .edit }) {
                    var changed = list; changed.tags.remove(at: index); write(changed)
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
                    .pointingHand()
                    .help(list.matchesAny ? "Notes meeting any of these: click for all" : "Notes meeting all of these: click for any")
                }
                ChipLabel(text: shown(condition), systemImage: store.listValueKind(of: subject(of: condition)).symbol,
                          open: { sheet = .edit }) {
                    var changed = list; changed.conditions.remove(at: index); write(changed)
                }
            }
            Button { sheet = .add } label: {
                Label("Add filter", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHand()
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 16)
            sortMenu
            columnsMenu
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .pointOpenListFilter)) { notification in
            sheet = (notification.userInfo?["target"] as? String) == "new" ? .add : .edit
        }
        #endif
        .sheet(item: $sheet) { _ in
            ListFiltersSheet(store: store, list: list) { changed in
                sheet = nil
                if let changed { write(changed) }
            }
        }
    }

    private func subject(of condition: ListCondition) -> ListFilterSubject {
        ListFilterRow(condition: condition).subject
    }

    /// A condition as its token reads: in the window's words ("read has no value").
    private func shown(_ condition: ListCondition) -> String {
        let kind = store.listValueKind(of: subject(of: condition))
        if condition.op.isAboutNote { return condition.written }
        var value = condition.value
        switch condition.op {
        case .inLastDays, .inNextDays:
            if let amount = condition.amount {
                value = "\(amount.count) " + (amount.count == 1 ? String(amount.unit.rawValue.dropLast()) : amount.unit.rawValue)
            }
        case .between:
            if let range = condition.range { value = "\(Self.shownDate(range.from)) and \(Self.shownDate(range.to))" }
        case .is, .before, .after:
            if kind == .date { value = Self.shownDate(value) }
        default: break
        }
        if kind == .checkbox { value = "" }
        return [condition.subject, kind.label(condition.op), condition.op.takesValue ? value : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A day as the Mac writes it (6 Nov 2026), for a day written in a list (2026-11-06).
    static func shownDate(_ written: String) -> String {
        PropertyDate.parse(written).map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? written
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

    /// The vault's properties, A to Z, less the list's own and any named like a note fact.
    private var columnProperties: [String] {
        var seen = Set(["title", "folder", "date edited", "date created"])
        return store.propertySummaries.map(\.name)
            .filter { !ListDefinition.isListKey($0) && seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func columnToggle(_ name: String) -> some View {
        Toggle(ListTable.heading(name), isOn: Binding(
            get: { list.columns.contains { $0.lowercased() == name.lowercased() } },
            set: { isOn in
                var changed = list
                changed.columns.removeAll { $0.lowercased() == name.lowercased() }
                if isOn { changed.columns.append(name) }
                write(changed)
            }))
    }

    /// Which columns show after the title.
    private var columnsMenu: some View {
        Menu {
            // Note facts, then properties A to Z; a tick by each shown. One kind of item
            // throughout, so each click reaches its own column.
            ForEach(["folder", "date edited", "date created"], id: \.self) { name in columnToggle(name) }
            Divider()
            ForEach(columnProperties, id: \.self) { name in columnToggle(name) }
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
    /// What a click on it does (opens it, to change it), if anything.
    var open: (() -> Void)?
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
        .onTapGesture { open?() }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // Darker, with a pointing hand, under the pointer: a click opens it.
        .background(Capsule().fill(Color.primary.opacity(isHovered && open != nil ? 0.16 : 0.07)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(isHovered && open != nil ? 0.18 : 0), lineWidth: 1))
        .contentShape(Capsule())
        .pointingHand()
        .animation(.easeOut(duration: 0.1), value: isHovered)
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
            ListResults(list: list, listID: listID, ids: ids, limit: Self.rows, moreLabel: "Show all \(ids.count)",
                        more: { model.open(listID, inPane: paneID, as: .here) },
                        model: model, store: store, paneID: paneID, write: nil)
                .font(.callout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// How tall it is for a list finding `count` notes.
    static func height(count: Int, hasColumns: Bool) -> CGFloat {
        ListResults.height(showing: min(count, rows), of: count) + 4
    }
}

// MARK: What it finds

/// The notes a list finds, as a table: the title, then a column for each property it shows.
/// A row opens its note (⌘-click in a new tab, ⌥-click on the other side).
struct ListResults: View {
    let list: ListDefinition
    /// The list's note, by which its columns' widths are remembered.
    let listID: Note.ID
    let ids: [Note.ID]
    /// How many rows show, and what shows the rest.
    let limit: Int
    let moreLabel: String
    let more: () -> Void
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let paneID: VaultModel.NotePane.ID
    /// Changes the list (sorting by a column, moving one); nil where it's shown in another
    /// note, which shows it as it is, its rows one line each.
    let write: ((ListDefinition) -> Void)?
    /// The shown rows' property values, from the index, as of these rows and columns.
    @State private var values: [Note.ID: [String: [String]]] = [:]
    @State private var tableHeight: CGFloat = ListTable.headerHeight

    var body: some View {
        let shown = Array(ids.prefix(limit)).compactMap { store.notesByID[$0] }
        VStack(alignment: .leading, spacing: 0) {
            Text(ids.count == 1 ? "1 note" : "\(ids.count) notes")
                .foregroundStyle(.secondary)
                .frame(height: Self.countHeight, alignment: .topLeading)
            if !shown.isEmpty {
                ListTable(columns: list.columns,
                          rows: shown.map { note in ListTable.Row(id: note.id, title: note.title, cells: list.columns.map { value(of: $0, for: note) }) },
                          sort: list.sort.first ?? NoteQuery.Sort(.modified, descending: true),
                          wraps: write != nil, listID: listID, height: $tableHeight,
                          open: { id, destination in model.open(id, inPane: paneID, as: destination) },
                          sortBy: write.map { write in { column, descending in
                              var changed = list
                              let key: NoteQuery.Sort.Key = column == ListTable.titleID ? .field(.title)
                                  : ListDefinition.field(named: column).map { .field($0) } ?? .property(column)
                              changed.sort = [NoteQuery.Sort(key, descending: descending)]
                              write(changed)
                          } },
                          reorder: write.map { write in { columns in
                              var changed = list
                              changed.columns = columns
                              write(changed)
                          } })
                    // Set by what it finds; one line a row where it's embedded, whose room is
                    // made before it's laid out.
                    .frame(height: write != nil ? tableHeight : Self.tableHeight(rows: shown.count))
            }
            if ids.count > shown.count {
                Button(moreLabel, action: more)
                    .buttonStyle(.link)
                    .frame(height: Self.moreHeight)
            }
        }
        .task(id: ValuesKey(columns: list.columns, ids: Array(ids.prefix(limit)), generation: store.indexGeneration)) {
            let properties = list.columns.filter { ListDefinition.field(named: $0) == nil }
            values = await store.propertyValues(properties, of: Array(ids.prefix(limit)))
        }
    }

    static let countHeight: CGFloat = 22, moreHeight: CGFloat = 26

    static func tableHeight(rows: Int) -> CGFloat {
        ListTable.headerHeight + CGFloat(rows) * (ListTable.rowHeight + ListTable.rowGap)
    }

    /// How tall it is embedded, showing `count` notes of `total`, a line each.
    static func height(showing count: Int, of total: Int) -> CGFloat {
        countHeight + (count > 0 ? tableHeight(rows: count) : 0) + (total > count ? moreHeight : 0)
    }

    private struct ValuesKey: Equatable {
        let columns: [String]
        let ids: [Note.ID]
        let generation: Int
    }

    private func value(of column: String, for note: Note) -> String {
        switch ListDefinition.field(named: column) {
        case .title: return note.title
        case .folder: return FolderTree.folder(of: note.id)
        case .created: return note.created.formatted(date: .abbreviated, time: .omitted)
        case .modified: return note.modified.formatted(date: .abbreviated, time: .omitted)
        case nil:
            let written = values[note.id]?[column.lowercased()] ?? []
            // Dates as the Mac writes them (6 Nov 2026).
            if store.listValueKind(ofProperty: column) == .date {
                return written.map(ListFilters.shownDate).joined(separator: ", ")
            }
            return written.map { value in
                // A link shows as its name.
                guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
                return String(value.dropFirst(2).dropLast(2).split(separator: "|").last ?? "")
            }.joined(separator: ", ")
        }
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
