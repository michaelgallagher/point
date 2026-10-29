import SwiftUI
import VaultKit

/// A note's frontmatter, shown as a one-line summary that expands into editable properties.
struct PropertiesStrip: View {
    @EnvironmentObject private var model: VaultModel
    let frontmatter: Frontmatter
    @ObservedObject var session: EditorSession
    /// Open or closed for this note only (two notes side by side open and close on their
    /// own). A note not seen yet this session starts the way properties were last left.
    @State private var isExpanded: Bool
    @AppStorage("propertiesExpanded") private var lastExpanded = false

    init(frontmatter: Frontmatter, session: EditorSession, isExpanded: Bool) {
        self.frontmatter = frontmatter
        self.session = session
        _isExpanded = State(initialValue: isExpanded)
    }
    /// The property being dragged to a new place, and where the pointer is.
    @State private var dragging: String?
    @State private var dragY: CGFloat = 0
    /// Where each property's row is, to work out where a dragged one would land.
    @State private var rowFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                model.store.propertiesOpen[session.note.id] = isExpanded
                lastExpanded = isExpanded
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: Self.chevronWidth)
                    Text(summary)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide properties" : "Show properties")

            if let key = frontmatter.repeatedKeys.first {
                Label("“\(key)” is here more than once, so Obsidian can’t read these properties. Remove one in either app.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(frontmatter.properties) { property in
                        row(for: property)
                            .opacity(dragging == property.key ? 0.4 : 1)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: RowFrames.self, value: [property.key: proxy.frame(in: .named(Self.space))])
                            })
                    }
                    HStack(spacing: Self.columnSpacing) {
                        Color.clear.frame(width: Self.iconWidth + Self.columnSpacing + keyWidth - Self.columnSpacing, height: 1)
                        Button {
                            NotificationCenter.default.post(name: .pointAddProperty, object: model)
                        } label: {
                            Label("Add Property", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Self.rowInset)
                    .padding(.vertical, Self.rowPadding)
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                // A selected row takes the keyboard: ⌫ deletes it, Escape lets it go.
                .background {
                    if let key = selectedKey {
                        PropertyKeys(delete: { delete(key) }, deselect: { selectedKey = nil })
                    }
                }
                .onChange(of: frontmatter.properties.map(\.key)) { keys in
                    if let selectedKey, !keys.contains(selectedKey) { self.selectedKey = nil }
                }
                .overlay(alignment: .topLeading) { dropIndicator }
                .overlay(alignment: .topLeading) { draggedRow }
                // The rows' backgrounds reach into the margin; their text lines up with the summary.
                .padding(.leading, -Self.rowInset)
            }
            // Drawn like a horizontal rule in the note: one point, the separator colour.
            if isExpanded {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .font(.callout)
        // Opens to show a property being highlighted.
        .onChange(of: session.revealedProperty) { key in
            if key != nil, !isExpanded { withAnimation(.easeOut(duration: 0.15)) { isExpanded = true } }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .padding(.leading, 5) // Lines up with the title and the text, which are inset a little.
        .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private static let space = "properties"
    private static let chevronWidth: CGFloat = 12
    /// The type icon's column, and the gap between columns.
    private static let iconWidth: CGFloat = 18
    private static let columnSpacing: CGFloat = 8
    /// Room around each row's text, inside its hover background.
    private static let rowInset: CGFloat = 6
    private static let rowPadding: CGFloat = 4

    /// The property under the pointer, shaded so it's clear it can be clicked.
    @State private var hoveredKey: String?
    /// The property picked by clicking its row (not a field in it): ⌫ deletes it.
    @State private var selectedKey: String?
    /// The property whose name is being edited, and the name as typed.
    @State private var renamingKey: String?
    @State private var newName = ""
    @FocusState private var isRenaming: Bool

    /// The keys' column, with the space after it: as wide as the longest key, within reason.
    /// (The space was taken out of the key's own width, which cut long keys short.)
    private var keyWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let widest = frontmatter.properties.map { ($0.key as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(max(ceil(widest) + 4, 60), 240) + Self.columnSpacing
    }

    /// One property: its type (click to change it), its name (click to rename, drag to
    /// reorder), its value, edited to suit its type, and a menu on hover. Click the row's
    /// empty space to select it, and ⌫ deletes it.
    private func row(for property: Frontmatter.Property) -> some View {
        let type = model.store.propertyTypes.type(of: property)
        let isSelected = selectedKey == property.key
        return HStack(alignment: .firstTextBaseline, spacing: Self.columnSpacing) {
            Menu {
                typePicker(for: property, current: type)
            } label: {
                Image(systemName: type.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconWidth)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(type.name): click to change the type")
            Group {
                if renamingKey == property.key {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.plain)
                        .focused($isRenaming)
                        .onSubmit { finishRenaming() }
                        .onExitCommand { renamingKey = nil }
                        .onChange(of: isRenaming) { renaming in
                            if !renaming { finishRenaming() }
                        }
                } else {
                    Text(property.key)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentShape(Rectangle())
                        .gesture(reorderGesture(for: property.key))
                        .onTapGesture { startRenaming(property.key) }
                        .help("Click to rename, drag to reorder")
                }
            }
            .frame(width: keyWidth - Self.columnSpacing, alignment: .leading)
            PropertyValue(property: property, type: type, session: session)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Rename") { startRenaming(property.key) }
                Menu("Change Type") { typePicker(for: property, current: type) }
                Divider()
                Button("Delete", role: .destructive) { delete(property.key) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .opacity(hoveredKey == property.key || isSelected ? 1 : 0)
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.vertical, Self.rowPadding)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15)
                      : Color.primary.opacity(hoveredKey == property.key && dragging == nil ? 0.05 : 0))
            // A link here just followed from another note: highlighted, as a place in the
            // text is (the system's find highlight colour).
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .findHighlightColor).opacity(session.revealedProperty == property.key ? 0.8 : 0))
                .animation(.easeOut(duration: session.revealedProperty == property.key ? 0.1 : 0.6), value: session.revealedProperty)
        }
        // The row's empty space (fields take their own clicks) selects it.
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = isSelected ? nil : property.key }
        .onHover { hovering in
            if hovering { hoveredKey = property.key } else if hoveredKey == property.key { hoveredKey = nil }
        }
        .contextMenu {
            Button("Rename") { startRenaming(property.key) }
            Menu("Change Type") { typePicker(for: property, current: type) }
            Divider()
            Button("Delete") { delete(property.key) }
        }
    }

    /// The types to choose from, the current one ticked.
    /// The types to choose from, the current one ticked. (A picker, as menus show its ticks;
    /// a checkmark image on a button didn't show.)
    @ViewBuilder private func typePicker(for property: Frontmatter.Property, current: PropertyType) -> some View {
        Picker("Type", selection: Binding(get: { current }, set: { changeType(of: property, from: current, to: $0) })) {
            ForEach(PropertyType.choosable) { type in
                Text(type.name).tag(type)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    /// Sets a property's type for the vault (as Obsidian keeps it), and carries this note's
    /// value over to it.
    private func changeType(of property: Frontmatter.Property, from old: PropertyType, to type: PropertyType) {
        guard type != old else { return }
        model.store.setPropertyType(type, forKey: property.key)
        session.setProperty(property.key, to: type.convert(PropertyValue.items(of: property, as: old), from: old), isList: type.isList)
    }

    private func delete(_ key: String) {
        if selectedKey == key { selectedKey = nil }
        withAnimation(.easeOut(duration: 0.15)) { session.removeProperty(key) }
    }

    private func startRenaming(_ key: String) {
        newName = key
        renamingKey = key
        DispatchQueue.main.async { isRenaming = true }
    }

    private func finishRenaming() {
        guard let key = renamingKey else { return }
        renamingKey = nil
        model.store.renamePropertyType(key, to: newName.trimmingCharacters(in: .whitespaces))
        session.renameProperty(key, to: newName)
    }

    /// Drags a property, by its name, to a new place among the others.
    private func reorderGesture(for key: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragging == nil { NSCursor.closedHand.push() }
                dragging = key
                dragY = value.location.y
            }
            .onEnded { _ in
                NSCursor.pop()
                if let destination = dropDestination, let dragging {
                    withAnimation(.easeOut(duration: 0.15)) { session.moveProperty(dragging, to: destination) }
                }
                dragging = nil
            }
    }

    /// Where the dragged property would go, as an index before the move; nil if it
    /// would stay where it is.
    private var dropDestination: Int? {
        guard let dragging, let source = frontmatter.properties.firstIndex(where: { $0.key == dragging }) else { return nil }
        let destination = frontmatter.properties.firstIndex { (rowFrames[$0.key]?.midY ?? .infinity) > dragY } ?? frontmatter.properties.count
        return destination == source || destination == source + 1 ? nil : destination
    }

    /// A copy of the property being dragged, lifted and following the pointer.
    @ViewBuilder private var draggedRow: some View {
        if let dragging, let property = frontmatter.properties.first(where: { $0.key == dragging }) {
            let height = rowFrames[dragging]?.height ?? 22
            HStack(spacing: 12) {
                Text(property.key)
                    .foregroundStyle(.secondary)
                Text(property.values.isEmpty ? "Empty" : property.values.joined(separator: ", "))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: height + 8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .offset(x: -10, y: dragY - (height + 8) / 2)
            .allowsHitTesting(false)
        }
    }

    /// A line between the rows where the dragged property would land.
    @ViewBuilder private var dropIndicator: some View {
        if let destination = dropDestination {
            let properties = frontmatter.properties
            let y = destination < properties.count
                ? (rowFrames[properties[destination].key]?.minY ?? 0) - 3
                : (rowFrames[properties[properties.count - 1].key]?.maxY ?? 0) + 3
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }

    /// "3 properties · #imprint #idea"
    private var summary: String {
        let count = frontmatter.properties.count
        var parts = ["\(count) \(count == 1 ? "property" : "properties")"]
        let tags = frontmatter.tags
        if !tags.isEmpty { parts.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }
}

/// The frames of the property rows, by key.
private struct RowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One property's value, edited to suit its type: text or a number in a field, a checkbox,
/// a date picker, or a list (tags included) as tokens. Values Point doesn't understand
/// (nested YAML) are shown but can only be changed in raw Markdown.
private struct PropertyValue: View {
    @EnvironmentObject private var model: VaultModel
    let property: Frontmatter.Property
    let type: PropertyType
    @ObservedObject var session: EditorSession

    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

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

    var body: some View {
        if isNested {
            Text("Edit in Markdown")
                .foregroundStyle(.tertiary)
        } else {
            switch type {
            case .list, .tags, .aliases:
                TokenEditor(items: Self.items(of: property, as: type), isTags: type == .tags,
                            suggestions: { typed, items in type == .tags ? model.store.tagSuggestions(for: typed, excluding: items) : [] },
                            noteTitles: model.titleSuggestions(for:), link: link, commit: { set($0) })
            case .checkbox:
                Toggle("", isOn: Binding(
                    get: { property.values.first?.lowercased() == "true" },
                    set: { set([$0 ? "true" : "false"]) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            case .date, .datetime:
                DateValue(property: property, hasTime: type == .datetime, set: set)
            case .text, .number:
                TextValue(property: property, isNumber: type == .number, link: link,
                          noteTitles: type == .number ? { _ in [] } : model.titleSuggestions(for:), set: set)
            }
        }
    }

    private func set(_ values: [String]) {
        session.setProperty(property.key, to: values, isList: type.isList)
    }

    /// A value that is a wikilink (`[[Note]]`, `[[Note|label]]`) or a web address, shown as a
    /// link to follow.
    private func link(_ value: String) -> PropertyLink? {
        PropertyLink(value, from: session.note.id, resolver: model.store.linkResolver) { target in
            let pane = model.panes.first { $0.tab.noteID == session.note.id } ?? model.panes[model.activePane]
            model.open(.note(target), from: session.note.id, inPane: pane.id)
        }
    }
}

/// A property value that is a single wikilink, as Obsidian writes links in properties: shown
/// without its brackets, coloured as links are in the note (paler when there's no such note).
/// Or a web address (`https://…`), which opens in the browser.
struct PropertyLink {
    let target: String
    let label: String
    let exists: Bool
    let open: (String) -> Void
    /// Set for a web address, which opens there instead of as a note.
    var url: URL?

    init?(_ value: String, from sourceID: Note.ID, resolver: LinkResolver, open: @escaping (String) -> Void) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let url = Self.webAddress(trimmed) {
            target = trimmed
            label = trimmed
            exists = true
            self.url = url
            self.open = { _ in NSWorkspace.shared.open(url) }
            return
        }
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return nil }
        let inside = trimmed.dropFirst(2).dropLast(2)
        guard !inside.contains("[["), !inside.contains("]]") else { return nil }
        let parts = inside.split(separator: "|", maxSplits: 1).map(String.init)
        target = parts[0]
        label = parts.count > 1 ? parts[1] : parts[0]
        exists = resolver.resolve(wikiTarget: target, from: sourceID) != nil
        self.open = open
    }

    /// A whole value that's a web address: http or https, with somewhere to go, and no spaces.
    static func webAddress(_ value: String) -> URL? {
        guard !value.contains(where: \.isWhitespace), let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    @MainActor var text: some View {
        Text(label)
            .foregroundStyle(Color(nsColor: exists ? .linkColor : .linkColor.withAlphaComponent(0.5)))
            .lineLimit(1)
            .truncationMode(url == nil ? .tail : .middle)
            .onTapGesture { open(target) }
            .pointingHand()
            .help(url != nil ? "Open \(target)" : exists ? "Open “\(target)”" : "Create “\(target)”")
    }
}

/// A field's placeholder ("Empty"), drawn over it while it's empty: the field's own was
/// darker until clicked into, then the system's lighter grey, which looked like it moved.
private struct PropertyPlaceholder: ViewModifier {
    let text: String
    let isShown: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if isShown {
                Text(text)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A `[[wikilink]]` being typed at the end of a field: where its `[[` starts, and the title
/// typed so far (none once it's closed with `]]` or has a `|` label).
func wikiLinkBeingTyped(in text: String) -> (start: String.Index, partial: String)? {
    guard let open = text.range(of: "[[", options: .backwards) else { return nil }
    let partial = text[open.upperBound...]
    guard !partial.contains("]") && !partial.contains("|") else { return nil }
    return (open.lowerBound, String(partial))
}

/// Suggestions under a field, as outlined capsules to click: tags from the vault, or the
/// titles of notes for a `[[link]]` being typed.
private struct SuggestionChips: View {
    let suggestions: [String]
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button { pick(suggestion) } label: {
                    Text(suggestion)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Tab takes the first suggestion, while there are any (macOS 14 and later).
private struct TakesFirstSuggestion: ViewModifier {
    let suggestions: [String]
    let pick: (String) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onKeyPress(.tab) {
                guard let first = suggestions.first else { return .ignored }
                pick(first)
                return .handled
            }
        } else {
            content
        }
    }
}

/// Text, or a number, in a field: Return or clicking away saves it.
private struct TextValue: View {
    let property: Frontmatter.Property
    let isNumber: Bool
    let link: (String) -> PropertyLink?
    /// Note titles for a `[[link]]` being typed, best first.
    let noteTitles: (String) -> [String]
    let set: ([String]) -> Void
    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var displayed: String { property.values.joined(separator: ", ") }

    var body: some View {
        // A web address stays an ordinary field, to select and edit (in the link colour while
        // it isn't being edited), with the arrow notes put after web links, which opens it.
        if let shownLink = link(displayed), let url = shownLink.url {
            let address = field.foregroundStyle(isFocused ? Color.primary : Color(nsColor: .linkColor))
            let open = Button { NSWorkspace.shared.open(url) } label: {
                Image(systemName: "arrow.up.right.circle")
                    .foregroundStyle(Color(nsColor: .linkColor))
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Open \(url.absoluteString)")
            // The arrow just after the address; at the row's end for one too long to fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    address.fixedSize()
                    open
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    address
                    open
                }
            }
        // A link to a note shows as one until clicked beside to edit it. The field isn't there
        // under it meanwhile: its text cursor won over the link's pointing hand.
        } else if !isEditing, !isFocused, let shownLink = link(displayed) {
            HStack(spacing: 0) {
                shownLink.text
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { edit() }
            }
            .onAppear { text = displayed }
            .onChange(of: property) { _ in text = displayed }
        } else {
            field
        }
    }

    private func edit() {
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    /// Notes whose titles fit a `[[link]]` being typed.
    private var linkSuggestions: [String] {
        guard isFocused, let typing = wikiLinkBeingTyped(in: text) else { return [] }
        return Array(noteTitles(typing.partial).prefix(8))
    }

    /// Finishes the `[[link]]` being typed with a note's title.
    private func finishLink(_ title: String) {
        guard let typing = wikiLinkBeingTyped(in: text) else { return }
        text = String(text[..<typing.start]) + "[[" + title + "]]"
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 4) {
            plainField
                .modifier(TakesFirstSuggestion(suggestions: linkSuggestions, pick: finishLink))
            if !linkSuggestions.isEmpty {
                SuggestionChips(suggestions: linkSuggestions, pick: finishLink)
            }
        }
    }

    private var plainField: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .modifier(PropertyPlaceholder(text: "Empty", isShown: text.isEmpty))
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    isEditing = false
                    commit()
                }
            }
            .onAppear { text = displayed }
            .onChange(of: property) { _ in
                if !isFocused { text = displayed }
            }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value != displayed else { return }
        // A number must read as one; anything else goes back to what it was.
        if isNumber, !value.isEmpty, Double(value) == nil {
            NSSound.beep()
            text = displayed
            return
        }
        set(value.isEmpty ? [] : [value])
    }
}

/// A date, or a date and time, in the system's compact picker. An empty one shows a button
/// that sets it to today.
private struct DateValue: View {
    let property: Frontmatter.Property
    let hasTime: Bool
    let set: ([String]) -> Void

    private var value: PropertyDate.Value? { property.values.first.flatMap { PropertyDate.parse($0) } }

    var body: some View {
        if let value {
            DatePicker("", selection: Binding(
                get: { value.date },
                set: { set([PropertyDate.format($0, like: PropertyDate.Value(date: $0, hasTime: hasTime, separator: value.separator, hasSeconds: value.hasSeconds))]) }
            ), displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize()
        } else {
            Button(property.values.first ?? "Empty") {
                let now = Date()
                set([PropertyDate.format(now, like: PropertyDate.Value(date: now, hasTime: hasTime))])
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Set to now")
        }
    }
}

/// A list's items as tokens, each with a remove button, then a field to add more: Return or
/// a comma adds what's typed. Tags complete from the vault's tags.
private struct TokenEditor: View {
    let items: [String]
    let isTags: Bool
    let suggestions: (String, [String]) -> [String]
    /// Note titles for a `[[link]]` being typed as an item, best first.
    var noteTitles: (String) -> [String] = { _ in [] }
    var link: (String) -> PropertyLink? = { _ in nil }
    let commit: ([String]) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Token(text: item, isTag: isTags, link: isTags ? nil : link(item)) {
                        commit(items.enumerated().filter { $0.offset != index }.map(\.element))
                    }
                }
                field
            }
            // Matching tags from the vault while typing one, or notes while typing a link.
            if !matches.isEmpty {
                SuggestionChips(suggestions: matches, pick: pick)
            }
        }
    }

    /// What to suggest for what's typed: notes for a `[[link]]`, otherwise tags (for tags).
    private var matches: [String] {
        guard isFocused else { return [] }
        if !isTags, let typing = wikiLinkBeingTyped(in: draft) {
            return Array(noteTitles(typing.partial).prefix(8))
        }
        return suggestions(draft, items)
    }

    /// Adds a suggestion as an item: a note as a link to it.
    private func pick(_ suggestion: String) {
        let isLink = !isTags && wikiLinkBeingTyped(in: draft) != nil
        draft = ""
        commit(items + [isLink ? "[[" + suggestion + "]]" : suggestion])
    }

    @ViewBuilder private var field: some View {
        let base = TextField("", text: $draft)
            .textFieldStyle(.plain)
            .modifier(PropertyPlaceholder(text: items.isEmpty ? "Empty" : "Add…", isShown: draft.isEmpty))
            .modifier(TakesFirstSuggestion(suggestions: matches, pick: pick))
            .frame(minWidth: 60, maxWidth: 160)
            .fixedSize(horizontal: false, vertical: true)
            .focused($isFocused)
            .onSubmit { add() }
            .onChange(of: draft) { text in
                if text.contains(",") { add() }
            }
            .onChange(of: isFocused) { focused in
                if !focused { add() }
            }
        if #available(macOS 14, *) {
            // ⌫ in an empty field removes the last item.
            base.onKeyPress(.delete) {
                guard draft.isEmpty, !items.isEmpty else { return .ignored }
                commit(Array(items.dropLast()))
                return .handled
            }
        } else {
            base
        }
    }

    /// Adds what's typed (several, if commas separate them), skipping any already there.
    private func add() {
        let typed = draft.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { isTags && $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        draft = ""
        let new = typed.filter { item in !items.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }
        guard !new.isEmpty else { return }
        commit(items + new)
    }
}

/// One item of a list: a rounded label with a remove button.
private struct Token: View {
    let text: String
    let isTag: Bool
    var link: PropertyLink?
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            if let link {
                link.text
            } else {
                Text(text)
                    .lineLimit(1)
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0.5)
            .help("Remove")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(isTag ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07)))
        .onHover { isHovering = $0 }
    }
}

/// Lays its views out in rows, left to right, wrapping when a row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// While a property is selected, takes the keyboard: ⌫ or ⌦ deletes it, Escape (or clicking
/// elsewhere) lets it go. Every other key, and Select All, Cut, Copy and Paste, stop here: the
/// strip is inside the note's text view, so anything passed on went to the note's text (a
/// letter typed over its selection, ⌘A selecting all of it).
private struct PropertyKeys: NSViewRepresentable {
    let delete: () -> Void
    let deselect: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.delete = delete
        view.deselect = deselect
    }

    final class KeyView: NSView {
        var delete: () -> Void = {}
        var deselect: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51, 117: delete() // ⌫, ⌦
            case 53: deselect() // Escape
            default: break
            }
        }

        override func selectAll(_ sender: Any?) {}
        @objc func cut(_ sender: Any?) {}
        @objc func copy(_ sender: Any?) {}
        @objc func paste(_ sender: Any?) {}
        @objc func delete(_ sender: Any?) { delete() }

        override func resignFirstResponder() -> Bool {
            DispatchQueue.main.async { [weak self] in self?.deselect() }
            return true
        }
    }
}

extension View {
    /// The pointing hand over something clickable that isn't a button.
    @ViewBuilder func pointingHand() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
    }
}
