import SwiftUI
import VaultKit

extension Notification.Name {
    /// Asks the window to show the Add Property sheet for the open note.
    static let pointAddProperty = Notification.Name("PointAddProperty")
    /// Asks the open note to set a property: `userInfo` has "key", "values" and "isList".
    static let pointSetProperty = Notification.Name("PointSetProperty")
    /// Asks a note's editor to do a Format menu command: `userInfo` has "noteID" and
    /// "action" (the command's selector, by name).
    static let pointEditorCommand = Notification.Name("PointEditorCommand")
}

/// Adds a property to the open note, creating its frontmatter if it has none.
struct AddPropertySheet: View {
    @EnvironmentObject private var model: VaultModel
    enum Kind: String, CaseIterable, Identifiable {
        case text = "Text", list = "List", tags = "Tags", date = "Date"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = Kind.text
    @State private var text = ""
    @State private var date = Date()

    /// The fields' width: the window hugs them, with no empty space beside them.
    private static let fieldWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Property")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    label("Name")
                    TextField("Name", text: $name, prompt: Text("status"))
                        .labelsHidden()
                        .frame(width: Self.fieldWidth)
                        .onChange(of: name) { newName in
                            // Suggest the kind from familiar names.
                            if newName.lowercased() == "tags" { kind = .tags }
                            else if PropertyDate.names.contains(newName.lowercased()) { kind = .date }
                        }
                }
                GridRow {
                    label("Kind")
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: Self.fieldWidth, alignment: .leading)
                }
                GridRow {
                    label(kind == .list || kind == .tags ? "Values" : "Value")
                    Group {
                        switch kind {
                        case .date:
                            DatePicker("Value", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .fixedSize()
                        case .list, .tags:
                            TextField("Values", text: $text, prompt: Text(kind == .tags ? "work, ideas" : "one, two"))
                                .labelsHidden()
                        case .text:
                            TextField("Value", text: $text)
                                .labelsHidden()
                        }
                    }
                    .frame(width: Self.fieldWidth, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.isEmpty)
            }
        }
        .padding(20)
        .fixedSize()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// YAML keys can't contain a colon; Obsidian also trims spaces.
    private var key: String {
        name.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
    }

    private func add() {
        let values: [String]
        switch kind {
        case .date: values = [PropertyDate.format(date, like: nil)]
        case .list, .tags:
            values = text.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { kind == .tags && $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                .filter { !$0.isEmpty }
        case .text: values = [text.trimmingCharacters(in: .whitespaces)]
        }
        NotificationCenter.default.post(name: .pointSetProperty, object: nil,
                                        userInfo: ["key": key, "values": values, "isList": kind == .list || kind == .tags,
                                                   "noteID": model.selection ?? ""])
        dismiss()
    }
}
