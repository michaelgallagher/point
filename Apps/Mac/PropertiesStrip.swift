import SwiftUI
import VaultKit

/// A note's frontmatter, shown as a one-line summary that expands into editable properties.
struct PropertiesStrip: View {
    @EnvironmentObject private var model: VaultModel
    let frontmatter: Frontmatter
    @ObservedObject var session: EditorSession
    /// The side it's on, for opening what came before it there.
    let paneID: VaultModel.NotePane.ID
    /// Open or closed for this note only (two notes side by side open and close on their
    /// own). A note not seen yet this session starts the way properties were last left.
    @State private var isExpanded: Bool
    @AppStorage("propertiesExpanded") private var lastExpanded = false

    init(frontmatter: Frontmatter, session: EditorSession, paneID: VaultModel.NotePane.ID, isExpanded: Bool) {
        self.frontmatter = frontmatter
        self.session = session
        self.paneID = paneID
        _isExpanded = State(initialValue: isExpanded)
    }
    /// The property being dragged to a new place, and where the pointer is.
    @State private var dragging: String?
    @State private var dragY: CGFloat = 0
    /// Where each property's row is, to work out where a dragged one would land.
    @State private var rowFrames: [String: CGRect] = [:]
    /// The property whose field has suggestions showing below it, over the rows beneath.
    @State private var suggestingKey: String?

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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(frontmatter.properties) { property in
                        row(for: property)
                            // While suggestions float over the rows, only the row they're for
                            // takes clicks: the fields beneath, AppKit's, took the clicks on them.
                            .onPreferenceChange(ShowsSuggestions.self) { shows in
                                if shows { suggestingKey = property.key } else if suggestingKey == property.key { suggestingKey = nil }
                            }
                            .allowsHitTesting(suggestingKey == nil || suggestingKey == property.key)
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
                            Label("Add property", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: Self.lineHeight)
                    .padding(.horizontal, Self.rowInset)
                    .padding(.vertical, Self.rowPadding)
                    .allowsHitTesting(suggestingKey == nil)
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                .overlayPreferenceValue(FloatingSuggestionsKey.self) { floating in
                    if let floating { FloatingSuggestionsPanel(floating: floating) }
                }
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
            // What's related to it, and what came before: under the summary, or the rows when open.
            RelatedReadout(connections: model.connections(for: session.note), model: model, paneID: paneID)
            // Drawn like a horizontal rule in the note: one point, the separator colour.
            if isExpanded {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .font(.body)
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
        .sheet(isPresented: Binding(get: { editingChoices != nil }, set: { if !$0 { editingChoices = nil } })) {
            if let key = editingChoices { ChoicesSheet(key: key) }
        }
    }

    private static let space = "properties"
    static let chevronWidth: CGFloat = 12
    /// The type icon's column, and the gap between columns.
    private static let iconWidth: CGFloat = 18
    private static let columnSpacing: CGFloat = 8
    /// Room around each row's text, inside its hover background.
    private static let rowInset: CGFloat = 6
    private static let rowPadding: CGFloat = 2
    /// A row's height inside its padding: the compact date picker's, or a token's, if taller.
    private static let lineHeight: CGFloat = 24

    /// The property under the pointer, shaded so it's clear it can be clicked.
    @State private var hoveredKey: String?
    /// The property picked by clicking its row (not a field in it): ⌫ deletes it.
    @State private var selectedKey: String?
    /// The property whose name is being edited, and the name as typed.
    @State private var renamingKey: String?
    @State private var newName = ""
    /// The choice property whose choices are being edited, while that sheet shows.
    @State private var editingChoices: String?
    @FocusState private var isRenaming: Bool

    /// The keys' column, with the space after it: as wide as the longest key, within reason.
    /// (The space was taken out of the key's own width, which cut long keys short.)
    private var keyWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let widest = frontmatter.properties.map { ($0.key as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(max(ceil(widest) + 4, 60), 240) + Self.columnSpacing
    }

    /// One property: its type (click to change it), its name (click to rename, drag to
    /// reorder), its value, edited to suit its type, and a menu on hover. Click the row's
    /// empty space to select it, and ⌫ deletes it.
    private func row(for property: Frontmatter.Property) -> some View {
        let type = model.store.propertyTypes.type(of: property)
        let kind = model.store.pointTypes.definition(forKey: property.key)
        let isSelected = selectedKey == property.key
        return HStack(alignment: .firstTextBaseline, spacing: Self.columnSpacing) {
            Menu {
                typePicker(for: property, current: type)
            } label: {
                Image(systemName: kind?.type.symbol ?? type.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconWidth)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(kind?.type.name ?? type.name): click to change the type")
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
            PropertyValue(property: property, type: type, kind: kind, session: session)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Rename") { startRenaming(property.key) }
                Menu("Change Type") { typePicker(for: property, current: type) }
                if kind?.type == .choice {
                    Button("Edit Choices…") { editingChoices = property.key }
                }
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
        // Every row as tall as the tallest one-line value, so a row doesn't jump as a date
        // picker or a token takes the place of text.
        .frame(minHeight: Self.lineHeight)
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
            if kind?.type == .choice {
                Button("Edit Choices…") { editingChoices = property.key }
            }
            Divider()
            Button("Delete") { delete(property.key) }
        }
    }

    /// The types to choose from, the current one ticked.
    /// The types to choose from, the current one ticked. (A picker, as menus show its ticks;
    /// a checkmark image on a button didn't show.)
    @ViewBuilder private func typePicker(for property: Frontmatter.Property, current: PropertyType) -> some View {
        let kind = model.store.pointTypes.definition(forKey: property.key)?.type
        let chosen = kind.map(ChosenType.point) ?? .base(current)
        Picker("Property type", selection: Binding(get: { chosen }, set: { changeType(of: property, from: current, to: $0) })) {
            ForEach(PropertyType.choosable) { type in
                Text(type.name).tag(ChosenType.base(type))
            }
            Divider()
            ForEach(PointTypes.Kind.allCases) { kind in
                Text(kind.name).tag(ChosenType.point(kind))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    /// One of Obsidian's types, or one of Point's own kinds.
    private enum ChosenType: Hashable {
        case base(PropertyType)
        case point(PointTypes.Kind)
    }

    /// Sets a property's type for the vault (as Obsidian keeps it, and Point's own kinds in
    /// Point's file), and carries this note's value over to it.
    private func changeType(of property: Frontmatter.Property, from old: PropertyType, to chosen: ChosenType) {
        switch chosen {
        case .base(let type):
            model.store.setPointType(nil, forKey: property.key)
            guard type != old else { return }
            model.store.setPropertyType(type, forKey: property.key)
            session.setProperty(property.key, to: type.convert(PropertyValue.items(of: property, as: old), from: old), isList: type.isList)
        case .point(let kind):
            var definition = PointTypes.Definition(type: kind)
            switch kind {
            // The choices start as what the vault gives it already, most used first.
            case .choice: definition.choices = Array(model.store.propertyValueList(property.key).prefix(12).map(\.value))
            case .rating: definition.max = 5
            case .person, .note: break
            }
            if let existing = model.store.pointTypes.definition(forKey: property.key), existing.type == kind { return }
            model.store.setPointType(definition, forKey: property.key)
            let type = kind.baseType
            var values = type.convert(PropertyValue.items(of: property, as: old), from: old)
            // People are links to their notes.
            if kind == .person { values = values.map { PropertyLink.linkedName($0) == nil ? "[[\($0)]]" : $0 } }
            if type != old || kind == .person { session.setProperty(property.key, to: values, isList: type.isList) }
        }
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
                    // Among all the note's properties, a hidden `title:` included.
                    let all = session.frontmatter?.properties ?? frontmatter.properties
                    let target = destination < frontmatter.properties.count
                        ? all.firstIndex { $0.key == frontmatter.properties[destination].key } ?? destination : all.count
                    withAnimation(.easeOut(duration: 0.15)) { session.moveProperty(dragging, to: target) }
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
    /// One of Point's own kinds, if it has one.
    let kind: PointTypes.Definition?
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
        } else if let kind {
            switch kind.type {
            case .choice:
                ChoiceValue(value: property.values.first ?? "",
                            choices: kind.choices ?? model.store.propertyValueList(property.key).map(\.value), set: set)
            case .person:
                TokenEditor(items: Self.items(of: property, as: .list), isTags: false,
                            suggestions: { typed, items in model.store.peopleSuggestions(for: typed, excluding: items).map { "[[\(model.store.linkText(forTitle: $0))]]" } },
                            noteTitles: { model.store.peopleSuggestions(for: $0) + model.titleSuggestions(for: $0) },
                            link: link, commit: { items in set(items.map { PropertyLink.linkedName($0) == nil ? "[[\($0)]]" : $0 }) })
            case .rating:
                RatingValue(value: property.values.first.flatMap { Double($0) }.map { Int($0.rounded()) } ?? 0, stars: kind.stars) { stars in
                    set(stars == 0 ? [] : [String(stars)])
                }
            case .note:
                TextValue(property: property, isNumber: false, link: link,
                          noteTitles: { model.store.noteSuggestions(inFolder: kind.folder, typed: $0) },
                          suggestions: { typed in model.store.noteSuggestions(inFolder: kind.folder, typed: typed).map { "[[\(model.store.linkText(forTitle: $0))]]" } },
                          set: set)
            }
        } else {
            switch type {
            case .list, .tags, .aliases:
                TokenEditor(items: Self.items(of: property, as: type), isTags: type == .tags,
                            suggestions: { typed, items in
                                type == .tags ? model.store.tagSuggestions(for: typed, excluding: items)
                                    : model.store.propertySuggestions(forKey: property.key, typed: typed, excluding: items)
                            },
                            noteTitles: noteTitles, link: link, commit: { set($0) })
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
                          noteTitles: type == .number ? { _ in [] } : noteTitles,
                          suggestions: { typed in
                              type == .number ? [] : model.store.propertySuggestions(forKey: property.key, typed: typed, excluding: [typed])
                          }, set: set)
            }
        }
    }

    private func set(_ values: [String]) {
        session.setProperty(property.key, to: values, isList: type.isList)
    }

    /// Notes for a `[[link]]` being typed: those linked in this field in other notes first
    /// (people in `people`), then the rest.
    private func noteTitles(_ partial: String) -> [String] {
        let used = model.store.propertySuggestions(forKey: property.key, typed: partial)
            .filter { $0.hasPrefix("[[") && $0.hasSuffix("]]") }
            .map { String($0.dropFirst(2).dropLast(2)).components(separatedBy: "|")[0] }
        var seen = Set<String>()
        return (used + model.titleSuggestions(for: partial)).filter { seen.insert($0.lowercased()).inserted }
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

    /// The note a value links to, if it's just one wikilink (`[[Sam Lee]]` gives "Sam Lee").
    static func linkedName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]"), trimmed.count > 4 else { return nil }
        let inside = trimmed.dropFirst(2).dropLast(2)
        guard !inside.contains("[["), !inside.contains("]]") else { return nil }
        return inside.split(separator: "|", maxSplits: 1).first.map(String.init)
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

/// Suggestions under a field, as outlined capsules to click: tags from the vault, what's been
/// put in the field in other notes, or the titles of notes for a `[[link]]` being typed. A
/// link shows as the note's name, without its brackets.
private struct SuggestionChips: View {
    let suggestions: [String]
    let pick: (String) -> Void

    /// The first is the one Tab takes (macOS 14 and later), and is marked as it.
    private var tabTakesFirst: Bool {
        if #available(macOS 14, *) { true } else { false }
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(suggestions, id: \.self) { suggestion in
                let isTabs = tabTakesFirst && suggestion == suggestions.first
                Button { pick(suggestion) } label: {
                    Text(suggestion.hasPrefix("[[") && suggestion.hasSuffix("]]") ? String(suggestion.dropFirst(2).dropLast(2)) : suggestion)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        // Tab's, in the accent colour; the rest outlined. The same size either
                        // way, so nothing moves as the first changes.
                        .background(Capsule().fill(Color.accentColor.opacity(isTabs ? 0.15 : 0)))
                        .overlay(Capsule().strokeBorder(isTabs ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.4)))
                        .foregroundStyle(isTabs ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isTabs ? "Press Tab to use this" : "")
            }
        }
    }
}

/// Suggestions for a field, floating just below it over the rows beneath, like a menu, rather
/// than in the strip's layout: there, every keystroke that changed how many there were moved
/// everything below up or down. The field reports where it is and the strip draws them: drawn
/// by the field's row, outside the row, they showed but took no clicks (a row takes clicks only
/// inside its own shape).
private struct FloatingSuggestions: ViewModifier {
    let suggestions: [String]
    let pick: (String) -> Void

    func body(content: Content) -> some View {
        content
            .preference(key: ShowsSuggestions.self, value: !suggestions.isEmpty)
            .anchorPreference(key: FloatingSuggestionsKey.self, value: .bounds) { bounds in
                suggestions.isEmpty ? nil : FloatingField(field: bounds, suggestions: suggestions, pick: pick)
            }
    }
}

/// The field with suggestions showing, if any: where it is, and what to suggest.
private struct FloatingSuggestionsKey: PreferenceKey {
    static var defaultValue: FloatingField? { nil }
    static func reduce(value: inout FloatingField?, nextValue: () -> FloatingField?) { value = value ?? nextValue() }
}

private struct FloatingField {
    let field: Anchor<CGRect>
    let suggestions: [String]
    let pick: (String) -> Void
}

/// The suggestions, in a panel as wide as the field, just below it, its chips lined up with
/// what's typed.
private struct FloatingSuggestionsPanel: View {
    let floating: FloatingField

    var body: some View {
        GeometryReader { proxy in
            let field = proxy[floating.field]
            SuggestionChips(suggestions: floating.suggestions, pick: floating.pick)
                .padding(5)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .frame(width: field.width + 5, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: field.minX - 5, y: field.maxY + 4)
        }
    }
}

/// Whether a field in a row has suggestions floating below it.
private struct ShowsSuggestions: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
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
    @EnvironmentObject private var model: VaultModel
    let property: Frontmatter.Property
    let isNumber: Bool
    let link: (String) -> PropertyLink?
    /// Note titles for a `[[link]]` being typed, best first.
    let noteTitles: (String) -> [String]
    /// What's been put in this field in other notes, for what's typed.
    let suggestions: (String) -> [String]
    let set: ([String]) -> Void
    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool
    /// Worked out when what's typed changes, not each time the view is: it can mean going
    /// through every note's title.
    @State private var suggested: [String] = []

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

    /// Notes whose titles fit a `[[link]]` being typed, otherwise what's been put in this
    /// field before that fits what's typed.
    private func suggest() {
        let new = fieldSuggestions
        if new != suggested { suggested = new }
    }

    private var fieldSuggestions: [String] {
        guard isFocused else { return [] }
        if let typing = wikiLinkBeingTyped(in: text) { return Array(noteTitles(typing.partial).prefix(8)) }
        return suggestions(text)
    }

    /// Finishes the `[[link]]` being typed with a note's title, or takes a value used before.
    private func pick(_ suggestion: String) {
        if let typing = wikiLinkBeingTyped(in: text) {
            text = String(text[..<typing.start]) + "[[" + model.store.linkText(forTitle: suggestion) + "]]"
        } else {
            text = suggestion
            commit()
        }
    }

    private var field: some View {
        plainField
            .modifier(TakesFirstSuggestion(suggestions: suggested, pick: pick))
            .modifier(FloatingSuggestions(suggestions: suggested, pick: pick))
            .onChange(of: text) { _ in suggest() }
            .onChange(of: isFocused) { _ in suggest() }
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

/// A date, or a date and time, in the system's compact picker, with a button on hover that
/// sets it to today (or now). One written in a way Point doesn't read is shown as written,
/// with the same button. An empty one shows a button that sets it to today.
private struct DateValue: View {
    let property: Frontmatter.Property
    let hasTime: Bool
    let set: ([String]) -> Void
    @State private var isHovering = false

    private var value: PropertyDate.Value? { property.values.first.flatMap { PropertyDate.parse($0) } }

    var body: some View {
        if let value {
            HStack(spacing: 6) {
                DatePicker("", selection: Binding(
                    get: { value.date },
                    set: { set(formatted($0, like: value)) }
                ), displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                // Not for a date that's already today.
                setToToday(like: value, isShown: hasTime || !Calendar.current.isDateInToday(value.date))
            }
            .onHover { isHovering = $0 }
        } else if let text = property.values.first, !text.isEmpty {
            HStack(spacing: 6) {
                Text(text)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                setToToday(like: nil, isShown: true)
            }
            .onHover { isHovering = $0 }
        } else {
            Button("Empty") { set(formatted(Date(), like: nil)) }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(hasTime ? "Set to now" : "Set to today")
        }
    }

    /// Shown on hover; always there, hidden, so the row doesn't move as it shows.
    private func setToToday(like value: PropertyDate.Value?, isShown: Bool) -> some View {
        let isVisible = isHovering && isShown
        return Button(hasTime ? "Set to now" : "Set to today") { set(formatted(Date(), like: value)) }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isShown)
    }

    /// `date`, written the way the property's date is (its separator, seconds and so on), or
    /// the usual way.
    private func formatted(_ date: Date, like value: PropertyDate.Value?) -> [String] {
        [PropertyDate.format(date, like: PropertyDate.Value(date: date, hasTime: hasTime, separator: value?.separator ?? "T", hasSeconds: value?.hasSeconds ?? false))]
    }
}

/// A list's items as tokens, each with a remove button, then a field to add more: Return or
/// a comma adds what's typed. Tags complete from the vault's tags.
private struct TokenEditor: View {
    @EnvironmentObject private var model: VaultModel
    let items: [String]
    let isTags: Bool
    let suggestions: (String, [String]) -> [String]
    /// Note titles for a `[[link]]` being typed as an item, best first.
    var noteTitles: (String) -> [String] = { _ in [] }
    var link: (String) -> PropertyLink? = { _ in nil }
    let commit: ([String]) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    /// Worked out when what's typed changes, not each time the view is: it can mean going
    /// through every note's title.
    @State private var matches: [String] = []

    var body: some View {
        // The field fills the rest of its line, so a click anywhere beside the tokens goes
        // into it, not only one on what's typed (it was no wider than that).
        FlowLayout(spacing: 4, fillsLast: true) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Token(text: item, isTag: isTags, link: isTags ? nil : link(item)) {
                    commit(items.enumerated().filter { $0.offset != index }.map(\.element))
                }
            }
            field
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matching tags from the vault while typing one, or notes while typing a link.
        .modifier(FloatingSuggestions(suggestions: matches, pick: pick))
    }

    private func match() {
        let new = suggestedMatches
        if new != matches { matches = new }
    }

    /// What to suggest for what's typed: notes for a `[[link]]`, otherwise tags (for tags).
    private var suggestedMatches: [String] {
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
        commit(items + [isLink ? "[[" + model.store.linkText(forTitle: suggestion) + "]]" : suggestion])
    }

    @ViewBuilder private var field: some View {
        let base = TextField("", text: $draft)
            .textFieldStyle(.plain)
            .modifier(PropertyPlaceholder(text: items.isEmpty ? "Empty" : "Add…", isShown: draft.isEmpty))
            .modifier(TakesFirstSuggestion(suggestions: matches, pick: pick))
            .frame(minWidth: 60, maxWidth: .infinity)
            // As tall as a token, focused or not, typed in or not, so the row's height never
            // changes while an item is added (it went shorter while typing, then back).
            .frame(height: Token.height)
            .focused($isFocused)
            .onSubmit { add() }
            .onChange(of: draft) { text in
                if text.contains(",") { add() }
                match()
            }
            .onChange(of: isFocused) { focused in
                if !focused { add() }
                match()
            }
            .onChange(of: items) { _ in match() }
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
    /// Every token's height, and the field's beside them: room around the text, which was
    /// tight to it, and the same in every row.
    static let height: CGFloat = 21
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
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: Self.height)
        .background(Capsule().fill(isTag ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07)))
        .onHover { isHovering = $0 }
    }
}

/// Lays its views out in rows, left to right, wrapping when a row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    /// The last view takes the rest of its row.
    var fillsLast = false

    /// Each view's size, measured once a layout pass rather than in each step of it (a text
    /// field is slow to measure, and the strip is laid out anew for each note opened).
    func makeCache(subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func updateCache(_ cache: inout [CGSize], subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let rows = arrange(cache, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        var y = bounds.minY
        for row in arrange(cache, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                var size = cache[index]
                if fillsLast, index == subviews.count - 1 { size.width = max(size.width, bounds.maxX - x) }
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += cache[index].width + spacing
            }
            y += row.height + spacing
        }
    }

    /// The first row's baseline, so the property's name beside it lines up with the text in
    /// it. Every item is a line of the strip's text centred in its row, so it's where that
    /// line's baseline falls. (Without it, SwiftUI took the layout's bottom edge for its
    /// baseline, and the name sat high beside tokens; nor can the items' own be trusted: a
    /// link token's comes from its remove button, and a text field's is below its text.)
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout [CGSize]) -> CGFloat? {
        guard guide == .firstTextBaseline, let row = arrange(cache, width: bounds.width).first else { return nil }
        return bounds.minY + row.height / 2 + (Self.font.ascender + Self.font.descender) / 2
    }

    nonisolated(unsafe) private static let font = NSFont.preferredFont(forTextStyle: .body)

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ sizes: [CGSize], width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, size) in sizes.enumerated() {
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


/// A choice property's value: a menu of its choices, and None.
private struct ChoiceValue: View {
    let value: String
    let choices: [String]
    let set: ([String]) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button { set([choice]) } label: {
                    if choice.lowercased() == value.lowercased() { Label(choice, systemImage: "checkmark") } else { Text(choice) }
                }
            }
            if !choices.isEmpty { Divider() }
            Button("None") { set([]) }
        } label: {
            Text(value.isEmpty ? "Choose" : value)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(choices.contains { $0.lowercased() == value.lowercased() } || value.isEmpty ? "Choose" : "Not one of the choices")
    }
}

/// A rating: stars to click. Clicking the rating it has clears it.
private struct RatingValue: View {
    let value: Int
    let stars: Int
    let set: (Int) -> Void
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...stars, id: \.self) { star in
                Image(systemName: star <= (hovered ?? value) ? "star.fill" : "star")
                    .foregroundStyle(star <= (hovered ?? value) ? Color.accentColor : Color.secondary.opacity(0.6))
                    .contentShape(Rectangle())
                    .onTapGesture { set(star == value ? 0 : star) }
                    .onHover { inside in if inside { hovered = star } else if hovered == star { hovered = nil } }
                    .accessibilityLabel("\(star) of \(stars)")
            }
        }
        .help(value == 0 ? "No rating" : "\(value) of \(stars)")
    }
}

/// The choices a choice property offers, one per line.
struct ChoicesSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let key: String
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choices for \(key)")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(width: 280, height: 160)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            Text("One per line, in the order they’re offered.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var seen = Set<String>()
                    let choices = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                    model.store.setPointType(PointTypes.Definition(type: .choice, choices: choices), forKey: key)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            text = (model.store.pointTypes.definition(forKey: key)?.choices ?? []).joined(separator: "\n")
        }
    }
}
