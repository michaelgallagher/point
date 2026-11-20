import IndexKit
import SwiftUI
import VaultKit

/// A list's filters, its order and its columns, on the phone: what the Mac's tokens, filters
/// window and menus do, as a sheet. The conditions, a row each, as they read ("format is
/// Book"), swiped away, reordered with Edit, each opened on a page of its own to change it;
/// all or any of them; the order; the columns. Done gives back the changed list, for the note
/// to write as one edit; Cancel leaves it as it was.
struct ListFiltersSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    let list: ListDefinition
    let done: (ListDefinition) -> Void

    @State private var rows: [ListFilterRow]
    @State private var matchesAny: Bool
    @State private var sort: [NoteQuery.Sort]
    @State private var columns: [String]
    /// The condition open on its own page, by its place in `rows`.
    @State private var path: [Int] = []

    init(list: ListDefinition, done: @escaping (ListDefinition) -> Void) {
        self.list = list
        self.done = done
        _rows = State(initialValue: ListFilterRow.rows(of: list))
        _matchesAny = State(initialValue: list.matchesAny)
        _sort = State(initialValue: list.sort)
        _columns = State(initialValue: list.columns)
    }

    var body: some View {
        let vocabulary = store.listVocabulary
        NavigationStack(path: $path) {
            List {
                if rows.count > 1 {
                    Section("Show notes that match") {
                        Picker("Match", selection: $matchesAny) {
                            Text("All conditions").tag(false)
                            Text("Any condition").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                Section {
                    if rows.isEmpty {
                        Text("No conditions: the list shows every note.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: index) { ConditionLabel(row: row, vocabulary: vocabulary) }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add condition", systemImage: "plus") {
                        rows.append(ListFilterRow(subject: .folder, kind: .folder))
                        path.append(rows.count - 1)
                    }
                } header: {
                    HStack {
                        Text("Conditions")
                        Spacer()
                        if rows.count > 1 || columns.count > 1 { EditButton().font(.subheadline) }
                    }
                }
                Section("Order") {
                    Picker("Sort by", selection: sortName) {
                        ForEach(sortChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Order", selection: descending) {
                        Text("Ascending").tag(false)
                        Text("Descending").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section {
                    ForEach(columns, id: \.self) { Text($0) }
                        .onDelete { columns.remove(atOffsets: $0) }
                        .onMove { columns.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        ForEach(["folder", "date edited", "date created"].filter(isNotShown), id: \.self) { name in
                            Button(name) { columns.append(name) }
                        }
                        Divider()
                        ForEach(columnProperties.filter(isNotShown), id: \.self) { name in
                            Button(name) { columns.append(name) }
                        }
                    } label: {
                        Label("Add column", systemImage: "plus")
                    }
                } header: {
                    Text("Columns")
                } footer: {
                    if columns.isEmpty { Text("Each note shows its title only.") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { index in
                if rows.indices.contains(index) {
                    ListConditionScreen(row: $rows[index])
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        let changed = made(vocabulary)
                        if changed != list { done(changed) }
                        dismiss()
                    }
                    .disabled(!rows.allSatisfy { $0.condition(kind: vocabulary.kind(of: $0.subject)) != nil })
                }
            }
        }
        // What the vault's properties hold and their values, for the conditions and the order.
        .task { await store.loadPropertyValues() }
    }

    /// The list as changed here: its filters, its order (left unwritten if never chosen),
    /// its columns.
    private func made(_ vocabulary: ListVocabulary) -> ListDefinition {
        var changed = list.filtered(by: rows, matchingAny: matchesAny, kind: vocabulary.kind(of:))
        changed.sort = sort
        changed.columns = columns
        return changed
    }

    // MARK: The order

    private var current: NoteQuery.Sort { sort.first ?? NoteQuery.Sort(.field(.modified), descending: true) }

    private static func name(of key: NoteQuery.Sort.Key) -> String {
        switch key {
        case .field(let field): ListDefinition.name(of: field)
        case .property(let name): name
        }
    }

    /// The order chosen by name: dates newest first, at first; words from A.
    private var sortName: Binding<String> {
        Binding(get: { Self.name(of: current.key) }, set: { name in
            guard name != Self.name(of: current.key) else { return }
            let key: NoteQuery.Sort.Key = ListDefinition.field(named: name).map { .field($0) } ?? .property(name)
            sort = [NoteQuery.Sort(key, descending: key == .field(.modified) || key == .field(.created))]
        })
    }

    private var descending: Binding<Bool> {
        Binding(get: { current.descending }, set: { sort = [NoteQuery.Sort(current.key, descending: $0)] })
    }

    /// Note facts, then the vault's properties, most used first.
    private var sortChoices: [String] {
        var seen = Set<String>()
        let names = ["title", "date edited", "date created"]
            + store.propertySummaries.prefix(40).map(\.name).filter { !ListDefinition.isListKey($0) }
            + [Self.name(of: current.key)]
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Columns

    /// The vault's properties, A to Z, less the list's own and any named like a note fact.
    private var columnProperties: [String] {
        var seen = Set(["title", "folder", "date edited", "date created"])
        return store.propertySummaries.map(\.name)
            .filter { !ListDefinition.isListKey($0) && seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isNotShown(_ name: String) -> Bool {
        !columns.contains { $0.lowercased() == name.lowercased() }
    }
}

/// A condition as it reads, with its kind's symbol: "In Reading", "Tagged #later", "format is
/// Book"; one not finished, by what it's about, marked so.
private struct ConditionLabel: View {
    let row: ListFilterRow
    let vocabulary: ListVocabulary

    var body: some View {
        let kind = vocabulary.kind(of: row.subject)
        if let condition = row.condition(kind: kind) {
            Label(reading(condition), systemImage: kind.symbol)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.subject.name)
                    Text("Not finished").font(.footnote).foregroundStyle(.orange)
                }
            } icon: {
                Image(systemName: kind.symbol)
            }
        }
    }

    private func reading(_ condition: ListCondition) -> String {
        switch (row.subject, row.op) {
        case (.folder, .is): "In " + ListDefinition.folderName(condition.value)
        case (.tag, .is): "Tagged #" + condition.value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        case (.property, _): vocabulary.reading(condition)
        // About the note itself ("Links to [[A talk]]", "Date edited is…"), capitalised as "In"
        // and "Tagged" are; a property keeps its own spelling.
        default: vocabulary.reading(condition).prefix(1).uppercased() + vocabulary.reading(condition).dropFirst()
        }
    }
}

// MARK: A condition

/// One condition, on its own page: what it's about, how it compares, and its value, asked
/// for in the way that suits its kind.
struct ListConditionScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Binding var row: ListFilterRow
    @FocusState private var isTyping: Bool

    var body: some View {
        let vocabulary = store.listVocabulary
        let kind = vocabulary.kind(of: row.subject)
        Form {
            Section {
                Picker("About", selection: subject(vocabulary)) {
                    Section {
                        ForEach(Self.facts, id: \.self) { subject in
                            Label(subject.name, systemImage: vocabulary.kind(of: subject).symbol).tag(subject)
                        }
                    }
                    // The vault's properties, set apart by the gap (a heading would show as a row).
                    Section {
                        ForEach(properties, id: \.self) { subject in
                            Label(subject.name, systemImage: vocabulary.kind(of: subject).symbol).tag(subject)
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                if row.subject != .linksTo, row.subject != .hasWords {
                    Picker("Comparison", selection: $row.op) {
                        ForEach(kind.operators.contains(row.op) ? kind.operators : kind.operators + [row.op], id: \.self) { op in
                            Text(kind.label(op)).tag(op)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            value(kind)
        }
        .navigationTitle(row.subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    /// What it's about: a new one starts afresh, comparing as suits its kind.
    private func subject(_ vocabulary: ListVocabulary) -> Binding<ListFilterSubject> {
        Binding(get: { row.subject }, set: { subject in
            guard subject != row.subject else { return }
            row = ListFilterRow(subject: subject, kind: vocabulary.kind(of: subject))
        })
    }

    private static let facts: [ListFilterSubject] = [.folder, .tag, .field(.title), .field(.created), .field(.modified), .linksTo, .hasWords]

    /// The vault's properties, A to Z, with one written by hand the vault doesn't use (yet).
    private var properties: [ListFilterSubject] {
        var names = store.propertySummaries
            .filter { $0.id != "tags" && !ListDefinition.isListKey($0.name) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if case .property(let name) = row.subject, !names.contains(name) { names.append(name) }
        return names.map { .property($0) }
    }

    @ViewBuilder private func value(_ kind: ListValueKind) -> some View {
        switch (kind, row.op) {
        case (_, .isSet), (_, .isNotSet), (_, .isEmpty), (.checkbox, _):
            EmptyView()
        case (.date, .between):
            Section {
                DatePicker("From", selection: $row.date, displayedComponents: .date)
                DatePicker("To", selection: $row.endDate, displayedComponents: .date)
            }
        case (.date, .thisPeriod):
            Section {
                Picker("Period", selection: $row.period) {
                    ForEach(ListCondition.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        case (.date, .inLastDays), (.date, .inNextDays):
            Section {
                Stepper(value: $row.count, in: 1...999) {
                    Text("\(row.count)").monospacedDigit()
                }
                Picker("Unit", selection: $row.unit) {
                    ForEach(ListCondition.Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        case (.date, _):
            Section {
                DatePicker("Date", selection: $row.date, displayedComponents: .date)
            }
        case (.folder, _):
            Section {
                Picker("Folder", selection: $row.text) {
                    if row.text.isEmpty { Text("Choose").tag("") }
                    ForEach(store.folders, id: \.self) { Label($0, systemImage: "folder").tag($0) }
                }
                .pickerStyle(.navigationLink)
            }
        case (.choice(let choices), _):
            Section {
                Picker("Value", selection: $row.text) {
                    if row.text.isEmpty { Text("Choose").tag("") }
                    ForEach(choices.contains(row.text) || row.text.isEmpty ? choices : choices + [row.text], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.navigationLink)
            }
        case (.rating(let stars), _):
            Section {
                Picker("Rating", selection: $row.text) {
                    if row.text.isEmpty { Text("Choose").tag("") }
                    ForEach(1...max(stars, 1), id: \.self) { Text(String(repeating: "★", count: $0)).tag(String($0)) }
                }
                .pickerStyle(.navigationLink)
            }
        case (.number, _):
            Section {
                TextField("Number", text: $row.text)
                    .keyboardType(.decimalPad)
                    .focused($isTyping)
            }
        default:
            Section {
                TextField(placeholder, text: $row.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isTyping)
                    .onAppear { if row.text.isEmpty { isTyping = true } }
            }
            let fitting = suggestions
            if !fitting.isEmpty {
                Section("Suggestions") {
                    ForEach(fitting, id: \.self) { suggestion in
                        Button(suggestion) {
                            row.text = suggestion
                            isTyping = false
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var placeholder: String {
        switch row.subject {
        case .tag: "Tag"
        case .linksTo: "Note"
        case .hasWords: "Words"
        default: "Value"
        }
    }

    /// What the vault uses, fitting what's typed, the first 30: tags, note titles, or the
    /// property's values (a link by its name).
    private var suggestions: [String] {
        let all: [String] = switch row.subject {
        case .tag: store.tags.map(\.tag)
        case .linksTo: store.notes.map(\.title)
        case .property(let name): store.propertyValueList(name).map(ListFilterRow.unlinked)
        default: []
        }
        let typed = row.text.trimmingCharacters(in: .whitespaces).lowercased()
        let fitting = typed.isEmpty ? all : all.filter { $0.lowercased().contains(typed) && $0.lowercased() != typed }
        return Array(fitting.prefix(30))
    }
}
