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

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(frontmatter.properties) { property in
                        row(for: property)
                            .opacity(dragging == property.key ? 0.4 : 1)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: RowFrames.self, value: [property.key: proxy.frame(in: .named(Self.space))])
                            })
                    }
                    HStack(spacing: 12) {
                        Color.clear.frame(width: keyWidth, height: 1)
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
        .padding(.top, 6)
        .padding(.bottom, 10)
        .padding(.leading, 5) // Lines up with the title and the text, which are inset a little.
        .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private static let space = "properties"
    private static let chevronWidth: CGFloat = 12
    /// Room around each row's text, inside its hover background.
    private static let rowInset: CGFloat = 6
    private static let rowPadding: CGFloat = 4

    /// The property under the pointer, shaded so it's clear it can be clicked.
    @State private var hoveredKey: String?
    /// The property whose name is being edited, and the name as typed.
    @State private var renamingKey: String?
    @State private var newName = ""
    @FocusState private var isRenaming: Bool

    /// The keys' column: as wide as the longest key, within reason.
    private var keyWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let widest = frontmatter.properties.map { ($0.key as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(max(ceil(widest) + 4, 60), 180)
    }

    /// One property: its name (click to rename, drag to reorder), then its value.
    private func row(for property: Frontmatter.Property) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
            .frame(width: keyWidth, alignment: .leading)
            PropertyField(property: property, session: session)
        }
        .padding(.horizontal, Self.rowInset)
        .padding(.vertical, Self.rowPadding)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hoveredKey == property.key && dragging == nil ? 0.05 : 0))
        }
        .onHover { hovering in
            if hovering { hoveredKey = property.key } else if hoveredKey == property.key { hoveredKey = nil }
        }
    }

    private func startRenaming(_ key: String) {
        newName = key
        renamingKey = key
        DispatchQueue.main.async { isRenaming = true }
    }

    private func finishRenaming() {
        guard let key = renamingKey else { return }
        renamingKey = nil
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

/// One editable value. Lists are edited as comma-separated text. Values Point doesn't
/// understand (nested YAML) are shown but can only be changed in raw Markdown.
private struct PropertyField: View {
    let property: Frontmatter.Property
    @ObservedObject var session: EditorSession
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isEditable: Bool { property.isList || property.values.count <= 1 && !isNested }
    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

    /// The value as a date, if it is one (or the property is named like one and is empty).
    private var date: PropertyDate.Value? {
        guard !property.isList, property.values.count <= 1 else { return nil }
        if let value = property.values.first { return PropertyDate.parse(value) }
        return PropertyDate.names.contains(property.key.lowercased()) ? PropertyDate.Value(date: Date(), hasTime: false, separator: "T", hasSeconds: false) : nil
    }

    var body: some View {
        Group {
            if isNested {
                Text("Edit in Markdown")
                    .foregroundStyle(.tertiary)
            } else if let date {
                DatePicker("", selection: Binding(
                    get: { date.date },
                    set: { newDate in
                        let style = property.values.isEmpty ? nil : date
                        session.setProperty(property.key, to: [PropertyDate.format(newDate, like: style)], isList: false)
                    }
                ), displayedComponents: date.hasTime ? [.date, .hourAndMinute] : [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Empty", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { focused in
                        if !focused { commit() }
                    }
                    .disabled(!isEditable)
            }
        }
        .onAppear { text = displayed }
        .onChange(of: property) { _ in
            if !isFocused { text = displayed }
        }
    }

    private var displayed: String {
        property.values.joined(separator: ", ")
    }

    private func commit() {
        guard text != displayed else { return }
        let values = property.isList
            ? text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : [text.trimmingCharacters(in: .whitespaces)]
        session.setProperty(property.key, to: values, isList: property.isList)
    }
}
