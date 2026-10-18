import SwiftUI
import VaultKit

/// A note's frontmatter, shown as a one-line summary that expands into editable properties.
struct PropertiesStrip: View {
    let frontmatter: Frontmatter
    @ObservedObject var session: EditorSession
    @AppStorage("propertiesExpanded") private var isExpanded = false

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
                            PropertyField(property: property, session: session)
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .font(.callout)
        .padding(.vertical, 10)
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
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

/// One editable value. Lists are edited as comma-separated text. Values Imprint doesn't
/// understand (nested YAML) are shown but can only be changed in raw Markdown.
private struct PropertyField: View {
    let property: Frontmatter.Property
    @ObservedObject var session: EditorSession
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isEditable: Bool { property.isList || property.values.count <= 1 && !isNested }
    private var isNested: Bool { !property.isList && property.values.isEmpty && property.range.length > property.key.count + 3 }

    var body: some View {
        Group {
            if isNested {
                Text("Edit in Markdown")
                    .foregroundStyle(.tertiary)
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
