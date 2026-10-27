import AppKit

/// Loaded by the Dock (not the app) while Point is kept in the Dock: shows the icon chosen in
/// Point's Settings, even while Point isn't running, and follows changes to the choice.
@objc(PointDockTilePlugIn)
final class PointDockTilePlugIn: NSObject, NSDockTilePlugIn {
    private var dockTile: NSDockTile?
    private var observer: NSObjectProtocol?

    func setDockTile(_ dockTile: NSDockTile?) {
        self.dockTile = dockTile
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        guard dockTile != nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: AppIconOptions.changed, object: nil, queue: .main) { [weak self] _ in
            self?.show()
        }
        show()
    }

    private func show() {
        guard let dockTile else { return }
        let name = AppIconOptions.chosen
        if name == AppIconOptions.standard {
            dockTile.contentView = nil // The app's own icon, as the Dock draws it.
        } else {
            // The icons are in the app's asset catalog: Point.app/Contents/PlugIns/<this>.
            let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let view = NSImageView()
            view.image = Bundle(url: app)?.image(forResource: name)
            view.imageScaling = .scaleProportionallyUpOrDown
            dockTile.contentView = view
        }
        dockTile.display()
    }
}
