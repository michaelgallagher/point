import Foundation

/// The vault settings Point shares with Obsidian, read from `.obsidian/`.
/// Missing files or keys fall back to Obsidian's own defaults.
public struct ObsidianSettings: Sendable, Equatable {
    public enum TrashOption: String, Sendable {
        /// The system trash (Obsidian's default).
        case system
        /// The vault's own `.trash` folder.
        case local
        /// Permanent deletion. Point treats this as `system`, to stay recoverable.
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

    /// Settings files Point writes, and the keys it writes in them.
    public enum Key: Sendable {
        case templatesFolder, templatesDateFormat, templatesTimeFormat, dailyNotesTemplate

        var file: String {
            switch self {
            case .templatesFolder, .templatesDateFormat, .templatesTimeFormat: "templates.json"
            case .dailyNotesTemplate: "daily-notes.json"
            }
        }

        var name: String {
            switch self {
            case .templatesFolder: "folder"
            case .templatesDateFormat: "dateFormat"
            case .templatesTimeFormat: "timeFormat"
            case .dailyNotesTemplate: "template"
            }
        }
    }

    /// Sets one setting in its `.obsidian` file (removing it for nil or empty, so Obsidian's
    /// default applies), keeping everything else in the file as it was.
    public static func set(_ key: Key, to value: String?, vault root: URL) throws {
        let folder = root.appendingPathComponent(".obsidian")
        let url = folder.appendingPathComponent(key.file)
        var object = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty { object[key.name] = value } else { object[key.name] = nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
