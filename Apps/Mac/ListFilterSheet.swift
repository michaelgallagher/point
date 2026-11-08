import IndexKit
import SwiftUI
import VaultKit

/// What a list can be filtered by: where a note is, its tags, facts about it, or one of the
/// vault's properties.
enum ListFilterSubject: Hashable {
    case folder, tag, linksTo, hasWords
    case field(NoteQuery.Field)
    case property(String)

    var name: String {
        switch self {
        case .folder: "Folder"
        case .tag: "Tag"
        case .linksTo: "Links to"
        case .hasWords: "Has words"
        case .field(let field): ListDefinition.name(of: field).prefix(1).uppercased() + ListDefinition.name(of: field).dropFirst()
        case .property(let name): name
        }
    }
}

/// What kind of thing a property holds, so a filter on it compares and asks for values in
/// the way that suits it: dates on a calendar, choices from their menu, and so on.
enum ListValueKind: Equatable {
    case text, list, number, date, checkbox, tag, person, note, folder
    case choice([String])
    case rating(Int)

    var symbol: String {
        switch self {
        case .text: PropertyType.text.symbol
        case .list: PropertyType.list.symbol
        case .number: PropertyType.number.symbol
        case .date: PropertyType.date.symbol
        case .checkbox: PropertyType.checkbox.symbol
        case .tag: PropertyType.tags.symbol
        case .person: PointTypes.Kind.person.symbol
        case .note: PointTypes.Kind.note.symbol
        case .folder: "folder"
        case .choice: PointTypes.Kind.choice.symbol
        case .rating: PointTypes.Kind.rating.symbol
        }
    }

    var name: String {
        switch self {
        case .text: "Text"
        case .list: "List"
        case .number: "Number"
        case .date: "Date"
        case .checkbox: "Checkbox"
        case .tag: "Tags"
        case .person: "Person"
        case .note: "Link to note"
        case .folder: "Folder"
        case .choice: "Choice"
        case .rating: "Rating"
        }
    }

    var isNumeric: Bool {
        if case .rating = self { return true }
        return self == .number
    }

    /// Whether it holds several values, which a filter looks among.
    var isMany: Bool { [.list, .tag, .person].contains(self) }

    /// The comparisons that make sense for it, most useful first.
    var operators: [ListCondition.Operator] {
        switch self {
        case .text, .note: [.is, .isNot, .contains, .isSet, .isNotSet]
        case .list, .person: [.is, .isNot, .contains, .isSet, .isNotSet]
        case .tag, .folder: [.is, .isNot]
        case .choice: [.is, .isNot, .isSet, .isNotSet]
        case .number, .rating: [.is, .isNot, .greater, .less, .isSet, .isNotSet]
        case .date: [.is, .before, .after, .between, .thisPeriod, .inLastDays, .inNextDays, .isSet, .isNotSet]
        case .checkbox: [.is, .isNot]
        }
    }

    /// How a comparison reads for it.
    func label(_ op: ListCondition.Operator) -> String {
        switch op {
        case .is:
            switch self {
            case .checkbox: "is ticked"
            case .date: "is on"
            case .folder: "is in"
            default: isMany && self != .tag ? "includes" : "is"
            }
        case .isNot:
            switch self {
            case .checkbox: "isn't ticked"
            case .folder: "isn't in"
            default: isMany && self != .tag ? "doesn't include" : "isn't"
            }
        case .contains: "contains"
        case .isSet: "has a value"
        case .isNotSet, .isEmpty: "has no value"
        case .less: "is less than"
        case .greater: "is more than"
        case .before: "is before"
        case .after: "is after"
        case .between: "is between"
        case .thisPeriod: "is this"
        case .inLastDays: "is in the last"
        case .inNextDays: "is in the next"
        case .linksTo: "links to"
        case .hasWords: "has the words"
        }
    }
}

extension VaultStore {
    /// What a property holds: as Point's own kinds or the vault's types say, else as its
    /// values read.
    func listValueKind(ofProperty name: String) -> ListValueKind {
        if let definition = pointTypes.definition(forKey: name) {
            switch definition.type {
            case .choice: return .choice(definition.choices ?? propertyValueList(name).map(\.value))
            case .person: return .person
            case .rating: return .rating(definition.stars)
            case .note: return .note
            }
        }
        switch propertyTypes.type(forKey: name) ?? guessedType(ofProperty: name) {
        case .text:
            // A few values used again and again (a format, a status): chosen from a menu, like
            // the others, rather than typed.
            if let summary = propertySummaries.first(where: { $0.id == name.lowercased() }),
               summary.distinctValues > 0, summary.distinctValues <= 30, summary.valueCount >= summary.distinctValues * 3 {
                return .choice(propertyValueList(name).map(\.value))
            }
            return .text
        case .list, .aliases: return .list
        case .tags: return .tag
        case .number: return .number
        case .checkbox: return .checkbox
        case .date, .datetime: return .date
        }
    }

    /// A property's type when none is set: from how its values read across the vault.
    func guessedType(ofProperty name: String) -> PropertyType {
        if name.lowercased() == "tags" { return .tags }
        if name.lowercased() == "aliases" { return .aliases }
        guard let summary = propertySummaries.first(where: { $0.id == name.lowercased() }) else { return .text }
        if summary.listCount * 2 > summary.noteCount { return .list }
        if summary.valueCount > 0, summary.dateValues * 2 > summary.valueCount { return .date }
        if summary.valueCount > 0, summary.numberValues * 2 > summary.valueCount { return .number }
        let values = propertyValueList(name)
        if !values.isEmpty, values.allSatisfy({ ["true", "false"].contains($0.value.lowercased()) }) { return .checkbox }
        return .text
    }

    func listValueKind(of subject: ListFilterSubject) -> ListValueKind {
        switch subject {
        case .folder: .folder
        case .tag: .tag
        case .linksTo: .note
        case .hasWords: .text
        case .field(.title): .text
        case .field(.folder): .folder
        case .field: .date
        case .property(let name): listValueKind(ofProperty: name)
        }
    }
}

// MARK: The filters window

/// One condition in the filters window, as its controls hold it.
struct ListFilterRow: Identifiable, Equatable {
    let id = UUID()
    var subject: ListFilterSubject
    var op: ListCondition.Operator
    var text = ""
    var date = Calendar.current.startOfDay(for: Date())
    var endDate = Calendar.current.startOfDay(for: Date())
    var count = 7
    var unit: ListCondition.Unit = .days
    var period: ListCondition.Period = .year

    /// A new row about `subject`, comparing as suits its kind.
    init(subject: ListFilterSubject, kind: ListValueKind) {
        self.subject = subject
        switch subject {
        case .linksTo: op = .linksTo
        case .hasWords: op = .hasWords
        default: op = kind.operators.first ?? .is
        }
        if kind == .checkbox { text = "true" }
    }

    /// The row for a filter the list has.
    init(condition: ListCondition) {
        switch condition.op {
        case .linksTo: subject = .linksTo
        case .hasWords: subject = .hasWords
        default:
            let lowered = condition.subject.lowercased()
            if lowered == "folder" { subject = .folder } else if lowered == "tag" || lowered == "tags" { subject = .tag } else {
                subject = ListDefinition.field(named: condition.subject).map { .field($0) } ?? .property(condition.subject)
            }
        }
        op = condition.op == .isEmpty ? .isNotSet : condition.op
        text = condition.op == .linksTo ? ListFilterRow.unlinked(condition.value) : condition.value
        switch condition.op {
        case .is, .before, .after:
            if let parsed = PropertyDate.parse(condition.value)?.date { date = parsed }
        case .between:
            if let range = condition.range {
                date = PropertyDate.parse(range.from)?.date ?? date
                endDate = PropertyDate.parse(range.to)?.date ?? endDate
            }
        case .thisPeriod: period = ListCondition.Period(rawValue: condition.value) ?? .year
        case .inLastDays, .inNextDays:
            if let amount = condition.amount { count = amount.count; unit = amount.unit }
        default: break
        }
    }

    /// The condition it makes, if it's whole.
    func condition(kind: ListValueKind) -> ListCondition? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        switch subject {
        case .linksTo: return typed.isEmpty ? nil : ListCondition("", .linksTo, "[[\(typed)]]")
        case .hasWords: return typed.isEmpty ? nil : ListCondition("", .hasWords, typed)
        default: break
        }
        let name: String = switch subject {
        case .folder: "folder"
        case .tag: "tag"
        case .field(let field): ListDefinition.name(of: field)
        case .property(let name): name
        default: ""
        }
        guard op.takesValue else { return ListCondition(name, op) }
        let value: String
        switch op {
        case .between:
            let (from, to) = date <= endDate ? (date, endDate) : (endDate, date)
            value = "\(Self.day(from)) and \(Self.day(to))"
        case .thisPeriod: value = period.rawValue
        case .inLastDays, .inNextDays:
            guard count > 0 else { return nil }
            value = unit == .days ? String(count) : "\(count) \(unit.rawValue)"
        default:
            if kind == .checkbox { return ListCondition(name, op, "true") }
            value = kind == .date ? Self.day(date) : typed
        }
        guard !value.isEmpty else { return nil }
        if kind.isNumeric, op == .less || op == .greater, Double(value) == nil { return nil }
        return ListCondition(name, op, value)
    }

    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func unlinked(_ value: String) -> String {
        guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
        return String(value.dropFirst(2).dropLast(2))
    }
}

/// A list's filters, edited the way macOS edits rules (a Finder smart folder, a Mail rule):
/// "Show notes that match all of these conditions", then a row for each, each a line of
/// pop-up menus and fields, an ✕ to take it away, dragged by its handle to reorder (the others
/// moving aside as it passes); "Add condition" below.
struct ListFiltersSheet: View {
    @ObservedObject var store: VaultStore
    let list: ListDefinition
    let done: (ListDefinition?) -> Void

    @State private var rows: [ListFilterRow]
    @State private var matchesAny: Bool
    /// Note titles, for "Links to", gathered once.
    @State private var titles: [String] = []

    init(store: VaultStore, list: ListDefinition, done: @escaping (ListDefinition?) -> Void) {
        self.store = store
        self.list = list
        self.done = done
        var rows = list.folders.map { folder -> ListFilterRow in
            var row = ListFilterRow(subject: .folder, kind: .folder); row.text = folder; return row
        }
        rows += list.tags.map { tag -> ListFilterRow in
            var row = ListFilterRow(subject: .tag, kind: .tag); row.text = tag; return row
        }
        rows += list.conditions.map(ListFilterRow.init(condition:))
        _rows = State(initialValue: rows)
        _matchesAny = State(initialValue: list.matchesAny)
    }

    /// The row being dragged, faded where it sits while the others move round it.
    @State private var dragging: ListFilterRow.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.title3.weight(.semibold))
            // Rounded groups, as System Settings has, but with standard pop-up menus (always
            // drawn), since each condition is three choices in a row, not one.
            HStack {
                Text("Show notes that match")
                Spacer()
                PopUp(items: [.init("All conditions", false), .init("Any condition", true)], selection: $matchesAny)
                    .fixedSize()
            }
            .padding(.horizontal, Self.inset)
            .frame(height: Self.rowHeight)
            .modifier(SettingsGroup())
            VStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty {
                    Text("No conditions: the list shows every note.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Self.inset)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                        .modifier(SettingsGroup())
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array($rows.enumerated()), id: \.element.id) { index, $row in
                                if index > 0 { Divider().padding(.leading, Self.inset + 26) }
                                FilterRowView(row: $row, store: store, titles: titles,
                                              remove: { withAnimation(.snappy) { rows.removeAll { $0.id == row.id } } },
                                              startDrag: { dragging = row.id })
                                    .padding(.horizontal, Self.inset)
                                    .frame(height: Self.rowHeight)
                                    .opacity(dragging == row.id ? 0.35 : 1)
                                    .onDrop(of: [.text], delegate: RowDrop(target: row.id, rows: $rows, dragging: $dragging))
                            }
                        }
                    }
                    .frame(height: min(CGFloat(rows.count) * (Self.rowHeight + 1), 400))
                    .modifier(SettingsGroup())
                    // A drag let go outside the rows: the pointer moving again with no button down.
                    .onContinuousHover { _ in
                        if dragging != nil, NSEvent.pressedMouseButtons == 0 { dragging = nil }
                    }
                }
                // Smaller than Cancel and OK, and square-cornered like them, as in macOS's settings.
                Button { add() } label: { Label("Add condition", systemImage: "plus") }
                    .buttonBorderShape(.roundedRectangle)
            }
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { done(made) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isWhole)
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle)
            .padding(.top, 4)
        }
        .padding(Self.margin)
        .frame(width: Self.width)
        // Nothing has the focus ring until the keyboard is used.
        .background(NoInitialFocus())
        .onAppear {
            titles = store.notes.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    static let rowHeight: CGFloat = 44, inset: CGFloat = 12, margin: CGFloat = 24

    /// As wide as a row's controls: the handle, the three columns, the ✕, and the space
    /// between, inside the group's insets and the window's margins.
    static let width: CGFloat = {
        let row = FilterRowView.handleWidth + FilterRowView.subjectWidth + FilterRowView.operatorWidth
            + FilterRowView.valueWidth + FilterRowView.removeWidth + FilterRowView.spacing * 4 + 24
        return row + inset * 2 + margin * 2
    }()

    private func add() {
        withAnimation(.snappy) { rows.append(ListFilterRow(subject: .folder, kind: .folder)) }
    }

    private var isWhole: Bool {
        rows.allSatisfy { $0.condition(kind: store.listValueKind(of: $0.subject)) != nil }
    }

    /// The list with these filters: a folder or tag it's in goes in `list-from` or
    /// `list-tags`, the rest in `list-where`. Its order and columns stay.
    private var made: ListDefinition {
        var changed = list
        changed.folders = []
        changed.tags = []
        changed.conditions = []
        changed.matchesAny = matchesAny && rows.count > 1
        for row in rows {
            guard let condition = row.condition(kind: store.listValueKind(of: row.subject)) else { continue }
            if row.subject == .folder, row.op == .is {
                changed.folders.append(ListDefinition.folderName(condition.value))
            } else if row.subject == .tag, row.op == .is {
                changed.tags.append(condition.value.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
            } else {
                changed.conditions.append(condition)
            }
        }
        return changed
    }
}

/// One condition's controls: what it's about, how it compares, with what.
private struct FilterRowView: View {
    @Binding var row: ListFilterRow
    @ObservedObject var store: VaultStore
    let titles: [String]
    let remove: () -> Void
    let startDrag: () -> Void

    /// The columns' widths, so each row's menus line up with the rows above and below.
    static let subjectWidth: CGFloat = 180, operatorWidth: CGFloat = 150, valueWidth: CGFloat = 200, spacing: CGFloat = 10,
        handleWidth: CGFloat = 16, removeWidth: CGFloat = 16

    var body: some View {
        let kind = store.listValueKind(of: row.subject)
        HStack(spacing: Self.spacing) {
            handle
            // The first two menus are set widths, so they line up down the rows.
            subjectPicker
                .frame(width: Self.subjectWidth)
            Group {
                if row.subject != .linksTo, row.subject != .hasWords {
                    PopUp(items: (kind.operators.contains(row.op) ? kind.operators : kind.operators + [row.op]).map { .init(kind.label($0), $0) },
                          selection: $row.op)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: Self.operatorWidth)
            // The value takes what's left, so the ✕ keeps its place on every row.
            HStack(spacing: 6) { value(kind) }
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .frame(width: Self.removeWidth)
            .help("Remove this condition")
        }
        .textFieldStyle(.roundedBorder)
    }

    /// What a row is dragged by: an open hand under the pointer, and the row itself, lifted, as
    /// it moves.
    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(width: Self.handleWidth, height: 28)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
            .onDrag {
                startDrag()
                return NSItemProvider(object: row.id.uuidString as NSString)
            } preview: {
                Label(row.subject.name, systemImage: store.listValueKind(of: row.subject).symbol)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 260, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 6, y: 2)
            }
            .help("Drag to reorder")
    }

    /// What it's about: the note's own facts, then the vault's properties, A to Z.
    private var subjectPicker: some View {
        let facts: [ListFilterSubject] = [.folder, .tag, .field(.title), .field(.created), .field(.modified), .linksTo, .hasWords]
        var items = facts.map { PopUp.Item($0.name, $0, symbol: store.listValueKind(of: $0).symbol) }
        items.append(.separator)
        items += properties.map { PopUp.Item($0.name, $0, symbol: store.listValueKind(of: $0).symbol) }
        // One written by hand that the vault doesn't use (yet).
        if case .property = row.subject, !properties.contains(row.subject) {
            items.append(PopUp.Item(row.subject.name, row.subject, symbol: "questionmark"))
        }
        return PopUp(items: items, selection: Binding(get: { row.subject }, set: { subject in
            guard subject != row.subject else { return }
            row = ListFilterRow(subject: subject, kind: store.listValueKind(of: subject))
        }))
    }

    private var properties: [ListFilterSubject] {
        store.propertySummaries
            .filter { $0.id != "tags" && !ListDefinition.isListKey($0.name) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { .property($0) }
    }

    @ViewBuilder private func value(_ kind: ListValueKind) -> some View {
        switch (kind, row.op) {
        case (_, .isSet), (_, .isNotSet), (_, .isEmpty), (.checkbox, _):
            EmptyView()
        case (.date, .between):
            datePicker($row.date)
            Text("and")
            datePicker($row.endDate)
        case (.date, .thisPeriod):
            PopUp(items: ListCondition.Period.allCases.map { .init($0.rawValue, $0) }, selection: $row.period)
                .frame(width: Self.valueWidth)
        case (.date, .inLastDays), (.date, .inNextDays):
            TextField("", value: $row.count, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
            PopUp(items: ListCondition.Unit.allCases.map { .init($0.rawValue, $0) }, selection: $row.unit)
                .frame(width: Self.valueWidth - 50 - 6)
        case (.date, _):
            datePicker($row.date)
        case (.folder, _):
            PopUp(items: (row.text.isEmpty ? [.init("Choose a folder", "")] : []) + folders.map { .init($0, $0, symbol: "folder") },
                  selection: $row.text)
                .frame(width: Self.valueWidth)
        case (.choice(let choices), _):
            PopUp(items: (row.text.isEmpty ? [.init("Choose", "")] : [])
                    + (choices.contains(row.text) || row.text.isEmpty ? choices : choices + [row.text]).map { .init($0, $0) },
                  selection: $row.text)
                .frame(width: Self.valueWidth)
        case (.rating(let stars), _):
            PopUp(items: (row.text.isEmpty ? [.init("Choose", "")] : []) + (1...stars).map { .init(String(repeating: "★", count: $0), String($0)) },
                  selection: $row.text)
                .frame(width: Self.valueWidth)
        case (.number, _):
            TextField("Number", text: $row.text)
                .frame(width: Self.valueWidth)
        default:
            ComboBox(text: $row.text, items: suggestions, placeholder: placeholder)
                .frame(width: Self.valueWidth)
        }
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: .date)
            .datePickerStyle(.field)
            .labelsHidden()
            .fixedSize()
    }

    private var placeholder: String {
        switch row.subject {
        case .tag: "Tag"
        case .linksTo: "Note"
        case .hasWords: "Words"
        default: "Value"
        }
    }

    private var folders: [String] {
        store.folderTree.noteCounts.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// What the vault uses, to pick from or complete: tags, note titles, or the property's
    /// values (a link by its name).
    private var suggestions: [String] {
        switch row.subject {
        case .tag: store.tagTree.entries.map(\.tag)
        case .linksTo: titles
        case .property(let name): store.propertyValueList(name).map { ListFilterRow.unlinked($0.value) }
        default: []
        }
    }
}

/// A Mac combo box: type a value, with the choices given completed as you type and listed
/// in its menu.
private struct ComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    var placeholder = ""

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = true
        box.completes = true
        box.numberOfVisibleItems = 12
        box.dataSource = context.coordinator
        box.delegate = context.coordinator
        box.placeholderString = placeholder
        box.stringValue = text
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        let changed = context.coordinator.items != items
        context.coordinator.parent = self
        context.coordinator.items = items
        if changed { box.reloadData() }
        if box.stringValue != text, box.currentEditor() == nil { box.stringValue = text }
        box.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        var parent: ComboBox
        var items: [String]

        init(parent: ComboBox) {
            self.parent = parent
            items = parent.items
        }

        /// The choices listed: those fitting what's typed, the first 300.
        private var shown: [String] {
            let typed = parent.text.trimmingCharacters(in: .whitespaces).lowercased()
            let fitting = typed.isEmpty || items.contains(where: { $0.lowercased() == typed }) ? items : items.filter { $0.lowercased().contains(typed) }
            return Array(fitting.prefix(300))
        }

        func numberOfItems(in comboBox: NSComboBox) -> Int { shown.count }

        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            let shown = shown
            return shown.indices.contains(index) ? shown[index] : nil
        }

        func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
            let lowered = string.lowercased()
            return items.first { $0.lowercased().hasPrefix(lowered) }
        }

        func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
            shown.firstIndex { $0.lowercased() == string.lowercased() } ?? NSNotFound
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            parent.text = box.stringValue
            box.reloadData()
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0 else { return }
            let shown = shown
            if shown.indices.contains(box.indexOfSelectedItem) { parent.text = shown[box.indexOfSelectedItem] }
        }
    }
}

/// Moves the dragged row to where the pointer is, as it passes each row, so the others slide
/// aside and the gap shows where it will land.
private struct RowDrop: DropDelegate {
    let target: ListFilterRow.ID
    @Binding var rows: [ListFilterRow]
    @Binding var dragging: ListFilterRow.ID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = rows.firstIndex(where: { $0.id == dragging }),
              let to = rows.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            rows.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A rounded group, as System Settings draws one.
private struct SettingsGroup: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A Mac pop-up menu button: always drawn with its outline, as wide as it's given (or as its
/// longest choice, where it's given no width), its choices with symbols and separators.
struct PopUp<Value: Hashable>: NSViewRepresentable {
    struct Item {
        let title: String
        let value: Value?
        let symbol: String?

        init(_ title: String, _ value: Value, symbol: String? = nil) {
            self.title = title
            self.value = value
            self.symbol = symbol
        }

        private init() { title = ""; value = nil; symbol = nil }
        static var separator: Item { Item() }
    }

    let items: [Item]
    @Binding var selection: Value

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.chose(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let signature = items.map { "\($0.title)|\($0.symbol ?? "")|\($0.value == nil)" }
        if signature != context.coordinator.signature {
            context.coordinator.signature = signature
            let menu = NSMenu()
            for item in items {
                guard item.value != nil else { menu.addItem(.separator()); continue }
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                if let symbol = item.symbol { menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                menu.addItem(menuItem)
            }
            button.menu = menu
        }
        if let index = items.firstIndex(where: { $0.value == selection }), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSPopUpButton, context: Context) -> CGSize? {
        let fitting = button.intrinsicContentSize
        return CGSize(width: proposal.width ?? fitting.width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject {
        var parent: PopUp
        var signature: [String] = []

        init(parent: PopUp) { self.parent = parent }

        @objc func chose(_ button: NSPopUpButton) {
            let index = button.indexOfSelectedItem
            guard parent.items.indices.contains(index), let value = parent.items[index].value else { return }
            parent.selection = value
        }
    }
}

/// Leaves its window with nothing focused when it opens, so no control shows a focus ring until
/// Tab is pressed.
private struct NoInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Clearing() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Clearing: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.initialFirstResponder = nil
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
        }
    }
}
