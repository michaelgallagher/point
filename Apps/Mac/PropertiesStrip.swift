import SwiftUI
import VaultKit

/// A note's frontmatter, shown as a one-line summary that expands into editable properties.
struct PropertiesStrip: View {
    @EnvironmentObject private var model: VaultModel
    let frontmatter: Frontmatter
    @ObservedObject var session: EditorSession
    @AppStorage("propertiesExpanded") private var isExpanded = false
    /// The property being dragged to a new place, and where the pointer is.
    @State private var dragging: String?
    @State private var dragY: CGFloat = 0
    /// Where each property's row is, to work out where a dragged one would land.
    @State private var rowFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(summary)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide properties" : "Show properties")

            if isExpanded {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(frontmatter.properties) { property in
                        GridRow {
                            Text(property.key)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                                .contentShape(Rectangle())
                                .gesture(reorderGesture(for: property.key))
                                .onHover { hovering in
                                    guard dragging == nil else { return }
                                    if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                                }
                                .help("Drag to reorder")
                            PropertyField(property: property, session: session)
                        }
                        .opacity(dragging == property.key ? 0.4 : 1)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: RowFrames.self, value: [property.key: proxy.frame(in: .named(Self.space))])
                        })
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Button {
                            NotificationCenter.default.post(name: .imprintAddProperty, object: model)
                        } label: {
                            Label("Add Property", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                .overlay(alignment: .topLeading) { dropIndicator }
                .overlay(alignment: .topLeading) { draggedRow }
                .padding(.leading, 18)
            }
            // Only while open: a line, the text's width, between the properties and the text.
            // It fades in as they open.
            if isExpanded {
                Divider()
                    .opacity(0.5)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .font(.callout)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private static let space = "properties"

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

/// One editable value. Lists are edited as comma-separated text. Values Imprint doesn't
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
