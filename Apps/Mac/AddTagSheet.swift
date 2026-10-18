import SwiftUI
import VaultKit

extension Notification.Name {
    /// Asks the open note to add a tag: `userInfo` has "tag" and "noteID".
    static let imprintAddTag = Notification.Name("ImprintAddTag")
}

/// Adds a tag to a note's `tags` property, choosing from the vault's tags or typing a new one.
struct AddTagSheet: View {
    @EnvironmentObject private var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var text = ""

    /// Existing tags matching what's typed, most used first.
    private var suggestions: [TagTree.Entry] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return model.tagTree.entries
            .filter { query.isEmpty || $0.id.contains(query) }
            .sorted { $0.count > $1.count }
            .prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tag to “\(note.title)”")
                .font(.headline)
            TextField("Tag", text: $text, prompt: Text("work/imprint"))
                .onSubmit { add(text) }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions) { entry in
                        Button { add(entry.tag) } label: {
                            HStack {
                                Text("#" + entry.tag)
                                Spacer()
                                Text("\(entry.count)").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleaned(text).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// A tag as Obsidian allows it: no `#`, no spaces.
    private func cleaned(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .replacingOccurrences(of: " ", with: "-")
    }

    private func add(_ tag: String) {
        let tag = cleaned(tag)
        guard !tag.isEmpty else { return }
        if model.selection != note.id { model.selection = note.id }
        // The note's editor may only just be opening; give it a moment to listen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .imprintAddTag, object: nil, userInfo: ["tag": tag, "noteID": note.id])
        }
        dismiss()
    }
}
