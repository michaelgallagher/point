import EditorKit
import SwiftUI
import VaultKit

/// A note's properties, as the Mac edits them: each value edited to suit its type. Tap a
/// property's icon to change its type, its name to rename it, or swipe to delete it. Types are
/// the vault's, kept where Obsidian keeps them. In a group below them, adding one, or a
/// template's. Every change is an edit to the note's text, so it saves and undoes as typing does.
struct PropertiesSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @ObservedObject var session: NoteSession
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var renaming: String?
    @State private var name = ""

    private var properties: [Frontmatter.Property] { session.frontmatter?.properties ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let key = session.frontmatter?.repeatedKeys.first {
                        Label("“\(key)” is here more than once, so Obsidian can’t read these properties. Remove one in either app.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.multicolor)
                    }
                    ForEach(properties) { property in
                        PropertyRow(property: property, session: session) {
                            name = property.key
                            renaming = property.key
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { session.removeProperty(property.key) }
                        }
                    }
                }
                .fullWidthSeparators()
                Section {
                    Button("Add Property", systemImage: "plus") { isAdding = true }
                    TemplateMenu(session: session)
                }
                .fullWidthSeparators()
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isAdding) { AddPropertyScreen(session: session) }
            .alert("Rename Property", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Rename", action: rename)
            }
        }
        .presentationDetents([.medium, .large])
        // Solid: over the system's glass at the medium height, the white rows went grey.
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func rename() {
        guard let key = renaming else { return }
        renaming = nil
        let newKey = name.trimmingCharacters(in: .whitespaces)
        guard !newKey.isEmpty, !properties.contains(where: { $0.key == newKey }) else { return }
        store.renamePropertyType(key, to: newKey)
        session.renameProperty(key, to: newKey)
    }
}

private extension View {
    /// Separators the same length whatever a row holds: by default they start at a row's text.
    func fullWidthSeparators() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// Adds a property by picking its name: those the vault uses, most used first, narrowed by
/// typing. A name that isn't among them can be added too, once typed, which is the only way a
/// new name comes about.
private struct AddPropertyScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var name = ""
    @FocusState private var isFocused: Bool

    /// YAML keys can't contain a colon; Obsidian also trims spaces.
    private var key: String {
        name.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// The names on the note already, in lower case: Obsidian ignores case in them.
    private var taken: Set<String> {
        Set((session.frontmatter?.properties ?? []).map { $0.key.lowercased() })
    }

    /// The vault's name for what's typed, if it has one, in the vault's spelling.
    private var known: String? {
        store.suggestedPropertyNames.first { $0.name.lowercased() == key.lowercased() }?.name
    }

    /// Those not on the note that match what's typed: the name itself, then names starting
    /// with it, then names containing it, each most used first.
    private var suggestions: [(name: String, count: Int)] {
        let query = key.lowercased()
        let names = store.suggestedPropertyNames.filter { !taken.contains($0.name.lowercased()) }
        guard !query.isEmpty else { return names }
        func rank(_ name: String) -> Int {
            name == query ? 0 : name.hasPrefix(query) ? 1 : 2
        }
        return names.filter { $0.name.lowercased().contains(query) }
            .enumerated()
            .sorted { (rank($0.element.name.lowercased()), $0.offset) < (rank($1.element.name.lowercased()), $1.offset) }
            .map(\.element)
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit { add(known ?? key) }
            } footer: {
                if taken.contains(key.lowercased()) {
                    Text("“\(key)” is on this note already.")
                }
            }
            if !suggestions.isEmpty {
                Section(key.isEmpty ? "In This Vault" : "Matching") {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            add(suggestion.name)
                        } label: {
                            HStack {
                                Label(suggestion.name, systemImage: type(of: suggestion.name).symbol)
                                Spacer()
                                if suggestion.count > 0 {
                                    Text("\(suggestion.count)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .fullWidthSeparators()
            }
            if !key.isEmpty, known == nil, !taken.contains(key.lowercased()) {
                Section {
                    Button("Add “\(key)” as a New Property", systemImage: type(of: key).symbol) { add(key) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Add Property")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { isFocused = true }
    }

    /// The vault's type for a name, or one suggested by the name.
    private func type(of name: String) -> PropertyType {
        store.propertyTypes.type(forKey: name) ?? PropertyType.suggested(forKey: name)
    }

    private func add(_ key: String) {
        guard !key.isEmpty, !taken.contains(key.lowercased()) else { return }
        let type = type(of: key)
        store.setPropertyType(type, forKey: key)
        session.setProperty(key, to: [], isList: type.isList)
        dismiss()
    }
}

/// A value that is a single wikilink, as Obsidian writes links in properties (`[[Note]]`,
/// `[[Note|label]]`): shown as a link, without its brackets, as on the Mac.
private struct WikiLink {
    let target: String
    let label: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return nil }
        let inside = trimmed.dropFirst(2).dropLast(2)
        guard !inside.contains("[["), !inside.contains("]]") else { return nil }
        let parts = inside.split(separator: "|", maxSplits: 1).map(String.init)
        target = parts[0]
        label = parts.count > 1 ? parts[1] : parts[0]
    }
}

/// One property: its type, its name, and its value. Lists run below the name, to have the width.
private struct PropertyRow: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    let property: Frontmatter.Property
    @ObservedObject var session: NoteSession
    let rename: () -> Void
    /// A single line's height, whatever's in it: the tallest control, the date picker, sets it.
    @ScaledMetric private var lineHeight: CGFloat = 36

    private var type: PropertyType { store.propertyTypes.type(of: property) }
    /// A value nested under the key, which isn't for editing here.
    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

    var body: some View {
        Group {
            if type.isList, !isNested {
                VStack(alignment: .leading, spacing: 0) {
                    name
                        .frame(minHeight: lineHeight)
                    value
                        .padding(.bottom, 8)
                }
            } else {
                HStack {
                    name
                    Spacer(minLength: 16)
                    value
                }
                .frame(minHeight: lineHeight)
            }
        }
        // The rest of the system's row height: a taller control would otherwise add to it.
        .listRowInsets(.vertical, 8)
    }

    private var name: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(PropertyType.choosable) { choice in
                    Button {
                        changeType(to: choice)
                    } label: {
                        if choice == type { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                    }
                }
            } label: {
                Image(systemName: type.symbol)
                    .frame(minWidth: 24)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Type: \(type.name)")
            Button(property.key, action: rename)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
    }

    /// Follows a link: from behind the sheet, so the sheet goes first.
    private func open(_ target: String) {
        dismiss()
        session.open(.note(target))
    }

    @ViewBuilder private var value: some View {
        if isNested {
            Text("Edit in the Mac app")
                .foregroundStyle(.tertiary)
        } else {
            switch type {
            case .list, .tags, .aliases:
                TokenEditor(items: Self.items(of: property, as: type), isTags: type == .tags, open: open, commit: set)
            case .checkbox:
                Toggle(property.key, isOn: Binding(
                    get: { property.values.first?.lowercased() == "true" },
                    set: { set([$0 ? "true" : "false"]) }
                ))
                .labelsHidden()
            case .date, .datetime:
                DateValue(property: property, hasTime: type == .datetime, set: set)
            case .text, .number:
                TextValue(property: property, isNumber: type == .number, open: open, set: set)
            }
        }
    }

    private func set(_ values: [String]) {
        // A field saves on leaving, which may be its property being deleted.
        guard session.frontmatter?.properties.contains(where: { $0.key == property.key }) == true else { return }
        session.setProperty(property.key, to: values, isList: type.isList)
    }

    /// Sets a property's type for the vault, and carries this note's value over to it.
    private func changeType(to new: PropertyType) {
        let old = type
        guard new != old else { return }
        let values = new.convert(Self.items(of: property, as: old), from: old)
        store.setPropertyType(new, forKey: property.key)
        session.setProperty(property.key, to: values, isList: new.isList)
    }

    /// The items of a list, however the note writes it: tags written on one line (`tags: a b`)
    /// or as one comma-separated value are split into their items.
    static func items(of property: Frontmatter.Property, as type: PropertyType) -> [String] {
        guard type.isList, !property.isList else { return property.values }
        let separators: Set<Character> = type == .tags ? [",", " "] : [","]
        return property.values.flatMap { $0.split(whereSeparator: { separators.contains($0) }) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { type == .tags && $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }
}

/// Text or a number, in a field, saved on Return or on leaving it. A link to a note shows as one
/// until tapped beside to edit it.
private struct TextValue: View {
    let property: Frontmatter.Property
    let isNumber: Bool
    let open: (String) -> Void
    let set: ([String]) -> Void
    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var displayed: String { property.values.joined(separator: ", ") }

    var body: some View {
        if !isEditing, !isFocused, let link = WikiLink(displayed) {
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: edit)
                Button(link.label) { open(link.target) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(.link))
                    .lineLimit(1)
            }
            .onAppear { text = displayed }
            .onChange(of: property) { _, _ in text = displayed }
        } else {
            TextField("Empty", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(isNumber ? .numbersAndPunctuation : .default)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        isEditing = false
                        commit()
                    }
                }
                .onChange(of: property) { _, _ in if !isFocused { text = displayed } }
                .onAppear { text = displayed }
                .onDisappear(perform: commit)
        }
    }

    private func edit() {
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value != displayed else { return }
        // A number must read as one; anything else goes back to what it was.
        if isNumber, !value.isEmpty, Double(value) == nil {
            text = displayed
            return
        }
        set(value.isEmpty ? [] : [value])
    }
}

/// A date, or a date and time, in the system's compact picker. An empty one offers to set it
/// to now.
private struct DateValue: View {
    let property: Frontmatter.Property
    let hasTime: Bool
    let set: ([String]) -> Void

    private var value: PropertyDate.Value? { property.values.first.flatMap { PropertyDate.parse($0) } }

    var body: some View {
        if let value {
            DatePicker(property.key, selection: Binding(
                get: { value.date },
                set: { set([PropertyDate.format($0, like: PropertyDate.Value(date: $0, hasTime: hasTime, separator: value.separator, hasSeconds: value.hasSeconds))]) }
            ), displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            .labelsHidden()
        } else {
            Button(property.values.first ?? "Set to Now") {
                let now = Date()
                set([PropertyDate.format(now, like: PropertyDate.Value(date: now, hasTime: hasTime))])
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// A list's items as tokens, each with a remove button, then a field to add more: Return or a
/// comma adds an item. Links to notes open from their token. Tags offer matching tags from the
/// vault while typing.
private struct TokenEditor: View {
    @EnvironmentObject private var store: PhoneStore
    let items: [String]
    let isTags: Bool
    let open: (String) -> Void
    let commit: ([String]) -> Void
    @State private var text = ""

    private var suggestions: [String] {
        guard isTags else { return [] }
        return Array(store.tagSuggestions(for: text).filter { !items.contains($0) }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                TokenLayout {
                    ForEach(items, id: \.self) { item in
                        token(item)
                    }
                }
            }
            TextField(isTags ? "Add a tag" : "Add an item", text: $text)
                .autocorrectionDisabled(isTags)
                .textInputAutocapitalization(isTags ? .never : .sentences)
                .onSubmit(add)
                .onChange(of: text) { _, new in if new.contains(",") { add() } }
                .onDisappear(perform: add)
            if !text.isEmpty, !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { tag in
                            Button("#" + tag) {
                                text = ""
                                commit(items + [tag])
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func token(_ item: String) -> some View {
        let link = WikiLink(item)
        let title = link?.label ?? (isTags ? "#" + item : item)
        return HStack(spacing: 6) {
            if let link {
                Button(title) { open(link.target) }
                    .foregroundStyle(Color(.link))
            } else {
                Text(title)
            }
            Button {
                commit(items.filter { $0 != item })
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Remove \(title)")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }

    private func add() {
        let new = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { isTags && $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && !items.contains($0) }
        text = ""
        if !new.isEmpty { commit(items + new) }
    }
}

/// Tokens in lines, wrapping as words do.
private struct TokenLayout: Layout {
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
