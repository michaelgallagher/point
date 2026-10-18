import Foundation

/// The vault settings Imprint shares with Obsidian, read from `.obsidian/`.
/// Missing files or keys fall back to Obsidian's own defaults.
public struct ObsidianSettings: Sendable, Equatable {
    public enum TrashOption: String, Sendable {
        /// The system trash (Obsidian's default).
        case system
        /// The vault's own `.trash` folder.
        case local
        /// Permanent deletion. Imprint treats this as `system`, to stay recoverable.
        case none
    }

    public var attachmentFolder: String = ""
    public var trashOption: TrashOption = .system
    public var dailyNotesFolder: String = ""
    public var dailyNotesFormat: String = "YYYY-MM-DD"
    public var dailyNotesTemplate: String = ""
    public var templatesFolder: String = ""
    public var templatesDateFormat: String = "YYYY-MM-DD"
    public var templatesTimeFormat: String = "HH:mm"

    public init() {}

    public static func load(vault root: URL) -> ObsidianSettings {
        var settings = ObsidianSettings()
        let folder = root.appendingPathComponent(".obsidian")
        func json(_ name: String) -> [String: Any] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return object
        }
        func string(_ value: Any?) -> String? {
            guard let value = value as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return value
        }

        let app = json("app.json")
        settings.attachmentFolder = string(app["attachmentFolderPath"]) ?? ""
        settings.trashOption = string(app["trashOption"]).flatMap(TrashOption.init) ?? .system

        let daily = json("daily-notes.json")
        settings.dailyNotesFolder = string(daily["folder"]) ?? ""
        settings.dailyNotesFormat = string(daily["format"]) ?? "YYYY-MM-DD"
        settings.dailyNotesTemplate = string(daily["template"]) ?? ""

        let templates = json("templates.json")
        settings.templatesFolder = string(templates["folder"]) ?? ""
        settings.templatesDateFormat = string(templates["dateFormat"]) ?? "YYYY-MM-DD"
        settings.templatesTimeFormat = string(templates["timeFormat"]) ?? "HH:mm"
        return settings
    }
}
