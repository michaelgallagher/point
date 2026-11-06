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
        case .text: return .text
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
/// pop-up menus and fields, with − and + to take one away or add one after it.
struct ListFiltersSheet: View {
    @ObservedObject var store: VaultStore
    let list: ListDefinition
    let done: (ListDefinition?) -> Void

    @State private var rows: [ListFilterRow]
    @State private var matchesAny: Bool
    /// Note titles, for "Links to", gathered once.
    @State private var titles: [String] = []

    init(store: VaultStore, list: ListDefinition, addsRow: Bool, done: @escaping (ListDefinition?) -> Void) {
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
        if addsRow || rows.isEmpty { rows.append(ListFilterRow(subject: .folder, kind: .folder)) }
        _rows = State(initialValue: rows)
        _matchesAny = State(initialValue: list.matchesAny)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.headline)
            HStack(spacing: 6) {
                Text("Show notes that match")
                Picker("", selection: $matchesAny) {
                    Text("all").tag(false)
                    Text("any").tag(true)
                }
                .labelsHidden()
                .fixedSize()
                Text("of these conditions:")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($rows) { $row in
                        FilterRowView(row: $row, store: store, titles: titles,
                                      remove: { rows.removeAll { $0.id == row.id } },
                                      add: { add(after: row.id) })
                    }
                    if rows.isEmpty {
                        HStack {
                            Text("No conditions: the list shows every note.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button { add(after: nil) } label: { Image(systemName: "plus") }
                                .help("Add a condition")
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { done(made) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isWhole)
            }
        }
        .padding(20)
        .frame(width: 720)
        .onAppear {
            titles = store.notes.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    private func add(after id: ListFilterRow.ID?) {
        let index = id.flatMap { id in rows.firstIndex { $0.id == id } }.map { $0 + 1 } ?? rows.count
        rows.insert(ListFilterRow(subject: .folder, kind: .folder), at: index)
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
    let add: () -> Void

    var body: some View {
        let kind = store.listValueKind(of: row.subject)
        HStack(spacing: 8) {
            subjectPicker
                .frame(width: 170, alignment: .leading)
            // The comparisons line up in a column, as do the values after them.
            Group {
                if row.subject != .linksTo, row.subject != .hasWords {
                    Picker("", selection: $row.op) {
                        ForEach(kind.operators.contains(row.op) ? kind.operators : kind.operators + [row.op], id: \.self) { op in
                            Text(kind.label(op)).tag(op)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .frame(width: 150, alignment: .leading)
            value(kind)
            Spacer(minLength: 0)
            Button(action: remove) { Image(systemName: "minus") }
                .help("Remove this condition")
            Button(action: add) { Image(systemName: "plus") }
                .help("Add a condition")
        }
        .controlSize(.regular)
    }

    /// What it's about: the note's own facts, then the vault's properties, A to Z.
    private var subjectPicker: some View {
        Picker("", selection: Binding(get: { row.subject }, set: { subject in
            guard subject != row.subject else { return }
            row = ListFilterRow(subject: subject, kind: store.listValueKind(of: subject))
        })) {
            ForEach([ListFilterSubject.folder, .tag, .field(.title), .field(.created), .field(.modified), .linksTo, .hasWords], id: \.self) { subject in
                Label(subject.name, systemImage: store.listValueKind(of: subject).symbol).tag(subject)
            }
            Divider()
            ForEach(properties, id: \.self) { subject in
                Label(subject.name, systemImage: store.listValueKind(of: subject).symbol).tag(subject)
            }
            // One written by hand that the vault doesn't use (yet).
            if case .property = row.subject, !properties.contains(row.subject) {
                Label(row.subject.name, systemImage: "questionmark").tag(row.subject)
            }
        }
        .labelsHidden()
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
            Picker("", selection: $row.period) {
                ForEach(ListCondition.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case (.date, .inLastDays), (.date, .inNextDays):
            TextField("", value: $row.count, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
            Picker("", selection: $row.unit) {
                ForEach(ListCondition.Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case (.date, _):
            datePicker($row.date)
        case (.folder, _):
            Picker("", selection: $row.text) {
                if row.text.isEmpty { Text("Choose a folder").tag("") }
                ForEach(folders, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case (.choice(let choices), _):
            Picker("", selection: $row.text) {
                if row.text.isEmpty { Text("Choose").tag("") }
                ForEach(choices.contains(row.text) || row.text.isEmpty ? choices : choices + [row.text], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case (.rating(let stars), _):
            Picker("", selection: $row.text) {
                if row.text.isEmpty { Text("Choose").tag("") }
                ForEach(1...stars, id: \.self) { count in Text(String(repeating: "★", count: count)).tag(String(count)) }
            }
            .labelsHidden()
            .fixedSize()
        case (.number, _):
            TextField("Number", text: $row.text)
                .frame(width: 90)
        default:
            ComboBox(text: $row.text, items: suggestions, placeholder: placeholder)
                .frame(minWidth: 160, maxWidth: 260)
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
