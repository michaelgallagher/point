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
    /// The choice property whose choices are being edited, or the link-to-note property whose
    /// note is being picked.
    @State private var editingChoices: String?
    @State private var pickingNote: String?

    /// The note's properties, less `title:` for a note Point named and a list's own keys.
    private var properties: [Frontmatter.Property] { session.shownProperties }

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
                        PropertyRow(property: property, session: session, rename: {
                            name = property.key
                            renaming = property.key
                        }, editChoices: { editingChoices = property.key }, pickNote: { pickingNote = property.key })
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { session.removeProperty(property.key) }
                        }
                    }
                }
                .fullWidthSeparators()
                Section {
                    Button("Add property", systemImage: "plus") { isAdding = true }
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
            .navigationDestination(isPresented: Binding(get: { editingChoices != nil }, set: { if !$0 { editingChoices = nil } })) {
                if let key = editingChoices { ChoicesScreen(key: key) }
            }
            .navigationDestination(isPresented: Binding(get: { pickingNote != nil }, set: { if !$0 { pickingNote = nil } })) {
                if let key = pickingNote { NotePickerScreen(key: key, session: session) }
            }
            .task { await store.loadPropertyValues() }
            .alert("Rename property", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
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
                Section(key.isEmpty ? "In this vault" : "Matching") {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            add(suggestion.name)
                        } label: {
                            HStack {
                                Label(suggestion.name, systemImage: symbol(of: suggestion.name))
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
                    Button("Add “\(key)” as a new property", systemImage: symbol(of: key)) { add(key) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Add property")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { isFocused = true }
    }

    /// The symbol for a name's kind, Point's own if it has one.
    private func symbol(of name: String) -> String {
        store.pointTypes.definition(forKey: name)?.type.symbol ?? type(of: name).symbol
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
    let editChoices: () -> Void
    let pickNote: () -> Void
    /// A single line's height, whatever's in it: the tallest control, the date picker, sets it.
    @ScaledMetric private var lineHeight: CGFloat = 36

    private var type: PropertyType { store.propertyTypes.type(of: property) }
    /// One of Point's own kinds, if it has one.
    private var kind: PointTypes.Definition? { store.pointTypes.definition(forKey: property.key) }
    /// Whether its value is a list, so runs below its name: Point's person kind is one.
    private var isList: Bool { kind?.type.baseType.isList ?? type.isList }
    /// A value nested under the key, which isn't for editing here.
    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

    var body: some View {
        Group {
            if isList, !isNested {
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
                // First, where it's seen: below the types it was off the bottom of the menu.
                if kind?.type == .choice {
                    Button("Edit choices", systemImage: "pencil", action: editChoices)
                    Divider()
                }
                Picker("Property type", selection: Binding(get: { chosen }, set: changeType)) {
                    ForEach(PropertyType.choosable) { choice in
                        Label(choice.name, systemImage: choice.symbol).tag(ChosenType.base(choice))
                    }
                }
                Picker("Point’s own", selection: Binding(get: { chosen }, set: changeType)) {
                    ForEach(PointTypes.Kind.allCases) { choice in
                        Label(choice.name, systemImage: choice.symbol).tag(ChosenType.point(choice))
                    }
                }
            } label: {
                Image(systemName: kind?.type.symbol ?? type.symbol)
                    .frame(minWidth: 24)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Type: \(kind?.type.name ?? type.name)")
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
        } else if let kind {
            switch kind.type {
            case .choice:
                ChoiceValue(value: property.values.first ?? "",
                            choices: kind.choices ?? store.propertyValueList(property.key), set: set)
            case .rating:
                RatingValue(value: property.values.first.flatMap { Double($0) }.map { Int($0.rounded()) } ?? 0, stars: kind.stars) { stars in
                    set(stars == 0 ? [] : [String(stars)])
                }
            case .person:
                TokenEditor(items: Self.items(of: property, as: .list), placeholder: "Add a person", open: open,
                            suggest: { typed, items in store.peopleSuggestions(for: typed, excluding: items).map { "[[\($0)]]" } },
                            commit: { set($0.map(PropertyLinks.linked)) })
            case .note:
                NoteValue(value: property.values.first ?? "", open: open, pick: pickNote)
            }
        } else {
            switch type {
            case .list, .tags, .aliases:
                TokenEditor(items: Self.items(of: property, as: type), isTags: type == .tags,
                            placeholder: type == .tags ? "Add a tag" : "Add an item", open: open,
                            suggest: { typed, items in
                                type == .tags ? (typed.isEmpty ? [] : store.tagSuggestions(for: typed).filter { !items.contains($0) })
                                    : store.propertySuggestions(forKey: property.key, typed: typed, excluding: items)
                            }, commit: set)
            case .checkbox:
                Toggle(property.key, isOn: Binding(
                    get: { property.values.first?.lowercased() == "true" },
                    set: { set([$0 ? "true" : "false"]) }
                ))
                .labelsHidden()
            case .date, .datetime:
                DateValue(property: property, hasTime: type == .datetime, set: set)
            case .text, .number:
                TextValue(property: property, isNumber: type == .number, open: open,
                          suggest: { typed in
                              type == .number ? [] : store.propertySuggestions(forKey: property.key, typed: typed, excluding: property.values)
                          }, set: set)
            }
        }
    }

    private func set(_ values: [String]) {
        // A field saves on leaving, which may be its property being deleted.
        guard session.frontmatter?.properties.contains(where: { $0.key == property.key }) == true else { return }
        session.setProperty(property.key, to: values, isList: isList)
    }

    /// One of Obsidian's types, or one of Point's own kinds.
    private enum ChosenType: Hashable {
        case base(PropertyType)
        case point(PointTypes.Kind)
    }

    private var chosen: ChosenType { kind.map { .point($0.type) } ?? .base(type) }

    /// Sets a property's type for the vault (Obsidian's, and Point's own kinds in Point's
    /// file), and carries this note's value over to it, as the Mac does.
    private func changeType(to new: ChosenType) {
        let old = type
        guard new != chosen else { return }
        switch new {
        case .base(let type):
            store.setPointType(nil, forKey: property.key)
            guard type != old else { return }
            store.setPropertyType(type, forKey: property.key)
            session.setProperty(property.key, to: type.convert(Self.items(of: property, as: old), from: old), isList: type.isList)
        case .point(let kind):
            var definition = PointTypes.Definition(type: kind)
            switch kind {
            // The choices start as what the vault gives it already, most used first.
            case .choice: definition.choices = Array(store.propertyValueList(property.key).prefix(12))
            case .rating: definition.max = 5
            case .person, .note: break
            }
            store.setPointType(definition, forKey: property.key)
            let type = kind.baseType
            var values = type.convert(Self.items(of: property, as: old), from: old)
            // People are links to their notes.
            if kind == .person { values = values.map(PropertyLinks.linked) }
            if type != old || kind == .person { session.setProperty(property.key, to: values, isList: type.isList) }
        }
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
    /// Values to offer, as chips under the field while it's in use.
    var suggest: (String) -> [String] = { _ in [] }
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
            VStack(alignment: .trailing, spacing: 6) {
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
                if isFocused {
                    // What's typed, unless it's the value already: what to offer for it.
                    let suggestions = suggest(text == displayed ? "" : text)
                    if !suggestions.isEmpty {
                        SuggestionChips(suggestions: suggestions) { picked in
                            text = picked
                            commit()
                            isFocused = false
                        }
                    }
                }
            }
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
            Button(property.values.first ?? "Set to now") {
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
    let items: [String]
    var isTags = false
    let placeholder: String
    let open: (String) -> Void
    /// What to offer for what's typed, less the items there already: tags, or people as links.
    let suggest: (String, [String]) -> [String]
    let commit: ([String]) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        Array(suggest(text, items).prefix(6))
    }

    /// A suggestion as it shows: a tag with its #, a link without its brackets.
    private func label(of suggestion: String) -> String {
        isTags ? "#" + suggestion : WikiLink(suggestion)?.label ?? suggestion
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
            TextField(placeholder, text: $text)
                .autocorrectionDisabled(isTags)
                .textInputAutocapitalization(isTags ? .never : .sentences)
                .focused($isFocused)
                .onSubmit(add)
                .onChange(of: text) { _, new in if new.contains(",") { add() } }
                .onDisappear(perform: add)
            // While typing, or as soon as the field's in use: the most used, to tap.
            if isFocused || !text.isEmpty, !suggestions.isEmpty {
                SuggestionChips(suggestions: suggestions, label: label) { suggestion in
                    text = ""
                    commit(items + [suggestion])
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

/// Suggestions under a field, as capsules to tap, scrolling sideways: the Mac's chips. A link
/// shows without its brackets.
private struct SuggestionChips: View {
    let suggestions: [String]
    var label: (String) -> String = { WikiLink($0)?.label ?? $0 }
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { pick(suggestion) } label: {
                        Text(label(suggestion))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

/// One of a choice property's choices, from a menu. A value that isn't among them still shows.
private struct ChoiceValue: View {
    let value: String
    let choices: [String]
    let set: ([String]) -> Void

    var body: some View {
        Menu {
            Picker(value, selection: Binding(get: { value.lowercased() }, set: { picked in
                set(picked.isEmpty ? [] : [choices.first { $0.lowercased() == picked } ?? picked])
            })) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice).tag(choice.lowercased())
                }
                if !value.isEmpty, !choices.contains(where: { $0.lowercased() == value.lowercased() }) {
                    Text(value).tag(value.lowercased())
                }
            }
            Divider()
            Button("None") { set([]) }
        } label: {
            HStack(spacing: 4) {
                Text(value.isEmpty ? "Choose" : value)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(value.isEmpty ? .secondary : .primary)
        }
    }
}

/// A rating: stars to tap. Tapping the rating it has clears it.
private struct RatingValue: View {
    let value: Int
    let stars: Int
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...stars, id: \.self) { star in
                Button {
                    set(star == value ? 0 : star)
                } label: {
                    Image(systemName: star <= value ? "star.fill" : "star")
                        .foregroundStyle(star <= value ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) of \(stars)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(value == 0 ? "No rating" : "\(value) of \(stars)")
    }
}

/// A link to a note: the note, tapped to open, and a button to pick another.
private struct NoteValue: View {
    let value: String
    let open: (String) -> Void
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let link = WikiLink(value) {
                Button(link.label) { open(link.target) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(.link))
                    .lineLimit(1)
            } else if !value.isEmpty {
                Text(value)
                    .lineLimit(1)
            }
            Button(value.isEmpty ? "Choose" : "Change", action: pick)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }
}

/// Picks the note a link-to-note property links to: notes in its folder (any, if it has none),
/// narrowed by searching.
private struct NotePickerScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    let key: String
    @ObservedObject var session: NoteSession
    @State private var query = ""

    private var folder: String? { store.pointTypes.definition(forKey: key)?.folder }

    private var current: String? {
        session.frontmatter?.properties.first { $0.key == key }?.values.first.flatMap(PropertyLinks.linkedName)
    }

    var body: some View {
        List {
            ForEach(store.noteSuggestions(inFolder: folder, typed: query, limit: 200), id: \.self) { title in
                Button {
                    set(["[[\(title)]]"])
                } label: {
                    HStack {
                        Text(title)
                        Spacer()
                        if title.lowercased() == current?.lowercased() {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            if current != nil {
                Section {
                    Button("None", role: .destructive) { set([]) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: folder.map { "Notes in \($0)" } ?? "Notes")
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func set(_ values: [String]) {
        session.setProperty(key, to: values, isList: false)
        dismiss()
    }
}

/// The choices a choice property offers, in order: reordered by dragging, removed with the
/// delete button, and added at the end. Saved for the vault as they change.
private struct ChoicesScreen: View {
    @EnvironmentObject private var store: PhoneStore
    let key: String
    @State private var choices: [String] = []
    @State private var new = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        List {
            Section {
                ForEach(choices, id: \.self) { choice in
                    Text(choice)
                }
                .onDelete { choices.remove(atOffsets: $0); save() }
                .onMove { choices.move(fromOffsets: $0, toOffset: $1); save() }
                TextField("Add a choice", text: $new)
                    .focused($isAdding)
                    .submitLabel(.done)
                    .onSubmit(add)
            } footer: {
                Text("Offered in this order, in every note.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Choices for \(key)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            choices = store.pointTypes.definition(forKey: key)?.choices ?? []
            if choices.isEmpty { isAdding = true }
        }
        .onDisappear(perform: add)
    }

    private func add() {
        let choice = new.trimmingCharacters(in: .whitespaces)
        new = ""
        guard !choice.isEmpty, !choices.contains(where: { $0.lowercased() == choice.lowercased() }) else { return }
        choices.append(choice)
        save()
        isAdding = true
    }

    private func save() {
        guard var definition = store.pointTypes.definition(forKey: key), definition.type == .choice else { return }
        definition.choices = choices
        store.setPointType(definition, forKey: key)
    }
}
