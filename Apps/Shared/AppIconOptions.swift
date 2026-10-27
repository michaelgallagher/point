import Foundation

/// The app icons to choose from in Settings, and which is chosen. Shared by the app and its
/// Dock tile plug-in, which shows the chosen icon in the Dock while Point isn't running.
enum AppIconOptions {
    /// Each icon's name in the asset catalog (an Icon Composer file in `Resources/`), and its
    /// name in Settings. The first is the app's own icon.
    static let all: [(name: String, title: String)] = [
        ("AppIcon", "Point"),
        ("Ink", "Ink"),
        ("Sage", "Sage"),
    ]
    static let standard = "AppIcon"

    /// Kept in a preferences domain of its own, outside the app's sandbox (an entitlement
    /// allows it), so the Dock's plug-in can read it: the app's own settings are in its
    /// container, where the Dock can't.
    private static let domain = "org.mikegallagher.point.appicon"
    private static let key = "icon"
    /// Posted (between processes) when the choice changes, for the plug-in.
    static let changed = Notification.Name("org.mikegallagher.point.appIconChanged")

    /// The chosen icon's name: the app's own if none (or one no longer offered) is chosen.
    static var chosen: String {
        CFPreferencesAppSynchronize(domain as CFString)
        let name = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
        return name.flatMap { name in all.contains { $0.name == name } ? name : nil } ?? standard
    }

    static func choose(_ name: String) {
        CFPreferencesSetAppValue(key as CFString, name == standard ? nil : name as CFString, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, deliverImmediately: true)
    }
}
