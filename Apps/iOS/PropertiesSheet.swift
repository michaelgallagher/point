import SwiftUI
import VaultKit

/// A note's properties, as the Mac edits them: each value edited to suit its type. Tap a
/// property's icon to change its type, its name to rename it, or swipe to delete it. Types are
/// the vault's, kept where Obsidian keeps them. Every change is an edit to the note's text, so
/// it saves and undoes as typing does.
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
                if let key = session.frontmatter?.repeatedKeys.first {
                    Label("“\(key)” is here more than once, so Obsidian can’t read these properties. Remove one in either app.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .symbolRenderingMode(.multicolor)
                }
                if !properties.isEmpty {
                    Section {
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
                }
                Section {
                    Button("Add Property", systemImage: "plus") {
                        name = ""
                        isAdding = true
                    }
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .alert("Add Property", isPresented: $isAdding) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Add", action: add)
            }
            .alert("Rename Property", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Rename", action: rename)
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Adds a property, of the vault's type for its name, or one suggested by the name.
    private func add() {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !properties.contains(where: { $0.key == key }) else { return }
        let type = store.propertyTypes.type(forKey: key) ?? PropertyType.suggested(forKey: key)
        store.setPropertyType(type, forKey: key)
        session.setProperty(key, to: [], isList: type.isList)
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

/// One property: its type, its name, and its value. Lists run below the name, to have the width.
private struct PropertyRow: View {
    @EnvironmentObject private var store: PhoneStore
    let property: Frontmatter.Property
    @ObservedObject var session: NoteSession
    let rename: () -> Void

    private var type: PropertyType { store.propertyTypes.type(of: property) }
    /// A value nested under the key, which isn't for editing here.
    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

    var body: some View {
        if type.isList, !isNested {
            VStack(alignment: .leading, spacing: 8) {
                name
                value
            }
        } else {
            HStack {
                name
                Spacer(minLength: 16)
                value
            }
        }
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
                    .frame(width: 24)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Type: \(type.name)")
            Button(property.key, action: rename)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var value: some View {
        if isNested {
            Text("Edit in the Mac app")
                .foregroundStyle(.tertiary)
        } else {
            switch type {
            case .list, .tags, .aliases:
                TokenEditor(items: Self.items(of: property, as: type), isTags: type == .tags, commit: set)
            case .checkbox:
                Toggle(property.key, isOn: Binding(
                    get: { property.values.first?.lowercased() == "true" },
                    set: { set([$0 ? "true" : "false"]) }
                ))
                .labelsHidden()
            case .date, .datetime:
                DateValue(property: property, hasTime: type == .datetime, set: set)
            case .text, .number:
                TextValue(property: property, isNumber: type == .number, set: set)
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

/// Text or a number, in a field, saved on Return or on leaving it.
private struct TextValue: View {
    let property: Frontmatter.Property
    let isNumber: Bool
    let set: ([String]) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var displayed: String { property.values.joined(separator: ", ") }

    var body: some View {
        TextField("Empty", text: $text)
            .multilineTextAlignment(.trailing)
            .keyboardType(isNumber ? .numbersAndPunctuation : .default)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onChange(of: property) { _, _ in if !isFocused { text = displayed } }
            .onAppear { text = displayed }
            .onDisappear(perform: commit)
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
/// comma adds an item. Tags offer matching tags from the vault while typing.
private struct TokenEditor: View {
    @EnvironmentObject private var store: PhoneStore
    let items: [String]
    let isTags: Bool
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
                        Button {
                            commit(items.filter { $0 != item })
                        } label: {
                            HStack(spacing: 4) {
                                Text(isTags ? "#" + item : item)
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(.primary)
                        .accessibilityHint("Removes it")
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
