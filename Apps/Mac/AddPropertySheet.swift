import SwiftUI
import VaultKit

extension Notification.Name {
    /// Asks the window to show the Add Property sheet for the open note.
    static let imprintAddProperty = Notification.Name("ImprintAddProperty")
    /// Asks the open note to set a property: `userInfo` has "key", "values" and "isList".
    static let imprintSetProperty = Notification.Name("ImprintSetProperty")
}

/// Adds a property to the open note, creating its frontmatter if it has none.
struct AddPropertySheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case text = "Text", list = "List", tags = "Tags", date = "Date"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = Kind.text
    @State private var text = ""
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Property")
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                    .onChange(of: name) { newName in
                        // Suggest the kind from familiar names.
                        if newName.lowercased() == "tags" { kind = .tags }
                        else if PropertyDate.names.contains(newName.lowercased()) { kind = .date }
                    }
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                switch kind {
                case .date:
                    DatePicker("Value", selection: $date, displayedComponents: .date)
                case .list, .tags:
                    TextField("Values", text: $text, prompt: Text(kind == .tags ? "work, ideas" : "one, two"))
                case .text:
                    TextField("Value", text: $text)
                }
            }
            .frame(width: 340)
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
        NotificationCenter.default.post(name: .imprintSetProperty, object: nil,
                                        userInfo: ["key": key, "values": values, "isList": kind == .list || kind == .tags])
        dismiss()
    }
}
