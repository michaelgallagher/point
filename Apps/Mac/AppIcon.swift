import AppKit
import SwiftUI

/// The app's icon, as chosen in Settings: shown in the Dock (and the app switcher) while Point
/// runs. While it isn't running, the Dock tile plug-in shows it, if Point is kept in the Dock.
/// Finder and Launchpad always show the app's own icon: changing that would mean changing
/// the app's files, which breaks its signature.
@MainActor
enum AppIcon {
    static func applyChosen() {
        let name = AppIconOptions.chosen
        // The app's own icon is left to the system, which draws it for light and dark.
        NSApplication.shared.applicationIconImage = name == AppIconOptions.standard ? nil : NSImage(named: name)
    }

    static func choose(_ name: String) {
        AppIconOptions.choose(name)
        applyChosen()
    }

    static func image(_ name: String) -> NSImage {
        NSImage(named: name) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

/// The icons side by side, the chosen one ringed.
struct AppIconPicker: View {
    @State private var chosen = AppIconOptions.chosen

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(AppIconOptions.all, id: \.name) { option in
                Button {
                    AppIcon.choose(option.name)
                    chosen = option.name
                } label: {
                    VStack(spacing: 6) {
                        Image(nsImage: AppIcon.image(option.name))
                            .resizable()
                            .frame(width: 72, height: 72)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(chosen == option.name ? Color.accentColor : .clear, lineWidth: 3))
                        Text(option.title)
                            .font(.callout)
                            .foregroundStyle(chosen == option.name ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(NoFocusRing()) // The chosen icon is ringed already.
                .accessibilityAddTraits(chosen == option.name ? .isSelected : [])
            }
        }
    }
}

private struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) { content.focusEffectDisabled() } else { content }
    }
}
