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

/// Adds a property to the open note, creating its frontmatter if it has none. Its type is
/// the vault's for that name, if it has one (as Obsidian keeps it), and is recorded for the
/// vault if not.
struct AddPropertySheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = PropertyType.text
    @State private var text = ""
    @State private var isOn = false
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
                            // The vault's type for the name, or one suggested by it.
                            let key = newName.trimmingCharacters(in: .whitespaces)
                            type = model.store.propertyTypes.type(forKey: key) ?? PropertyType.suggested(forKey: key)
                        }
                }
                GridRow {
                    label("Type")
                    Picker("Type", selection: $type) {
                        ForEach(PropertyType.choosable) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: Self.fieldWidth, alignment: .leading)
                }
                GridRow {
                    label(type.isList ? "Values" : "Value")
                    Group {
                        switch type {
                        case .date, .datetime:
                            DatePicker("Value", selection: $date, displayedComponents: type == .datetime ? [.date, .hourAndMinute] : .date)
                                .labelsHidden()
                                .fixedSize()
                        case .checkbox:
                            Toggle("", isOn: $isOn)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                        case .list, .tags, .aliases:
                            TextField("Values", text: $text, prompt: Text(type == .tags ? "work, ideas" : "one, two"))
                                .labelsHidden()
                        case .text, .number:
                            TextField("Value", text: $text, prompt: Text(type == .number ? "0" : ""))
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
                    .disabled(key.isEmpty || type == .number && !text.isEmpty && Double(text.trimmingCharacters(in: .whitespaces)) == nil)
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
        switch type {
        case .date, .datetime: values = [PropertyDate.format(date, like: PropertyDate.Value(date: date, hasTime: type == .datetime))]
        case .checkbox: values = [isOn ? "true" : "false"]
        case .list, .tags, .aliases: values = type.convert([text], from: .text)
        case .text, .number:
            let value = text.trimmingCharacters(in: .whitespaces)
            values = value.isEmpty ? [] : [value]
        }
        if model.store.propertyTypes.type(forKey: key) == nil { model.store.setPropertyType(type, forKey: key) }
        NotificationCenter.default.post(name: .pointSetProperty, object: nil,
                                        userInfo: ["key": key, "values": values, "isList": type.isList,
                                                   "noteID": model.selection ?? ""])
        dismiss()
    }
}
