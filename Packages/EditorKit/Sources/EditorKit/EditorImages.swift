import Foundation
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Images shown in notes: their sizes, read from their files' headers (quick enough to lay a
/// note out with), and their pictures, decoded off the main thread at the size they're shown,
/// and kept for a while.
final class EditorImages: @unchecked Sendable {
    static let shared = EditorImages()

    private let sizes = NSCache<NSString, NSValue>()
    private let pictures = NSCache<NSString, CGImage>()
    private let queue = DispatchQueue(label: "point.editor-images", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var waiting: [NSString: [(CGImage?) -> Void]] = [:]

    init() {
        pictures.totalCostLimit = 256 * 1024 * 1024
    }

    /// An image's size in points: its pixels, at its resolution (a Retina screenshot is half
    /// its pixels), the right way up. Nil if it isn't there or isn't an image.
    func size(of url: URL) -> CGSize? {
        let key = Self.key(url)
        if let cached = sizes.object(forKey: key) { return Self.cgSize(cached) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        // Points, at the image's own resolution (72 is one pixel a point; 144, two).
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let scale = dpi > 72 ? dpi / 72 : 1
        let size = CGSize(width: (width / scale).rounded(), height: (height / scale).rounded())
        sizes.setObject(Self.value(size), forKey: key)
        return size
    }

    /// The picture, decoded to fit `pixels` on its longer side, if it's been decoded already.
    func cachedPicture(of url: URL, pixels: Int) -> CGImage? {
        pictures.object(forKey: Self.key(url, pixels: pixels))
    }

    /// Decodes the picture to fit `pixels` on its longer side, off the main thread, and hands
    /// it over on the main thread (nil if it can't be read).
    func picture(of url: URL, pixels: Int, _ done: @escaping @MainActor (CGImage?) -> Void) {
        let key = Self.key(url, pixels: pixels)
        if let cached = pictures.object(forKey: key) {
            MainActor.assumeIsolated { done(cached) }
            return
        }
        let deliver: (CGImage?) -> Void = { image in DispatchQueue.main.async { MainActor.assumeIsolated { done(image) } } }
        lock.lock()
        if waiting[key] != nil {
            waiting[key]!.append(deliver)
            lock.unlock()
            return
        }
        waiting[key] = [deliver]
        lock.unlock()
        let name = key as String
        queue.async { [self] in
            let key = name as NSString
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            var image: CGImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            if let image { pictures.setObject(image, forKey: key, cost: image.bytesPerRow * image.height) }
            lock.lock()
            let callbacks = waiting.removeValue(forKey: key) ?? []
            lock.unlock()
            for callback in callbacks { callback(image) }
        }
    }

    /// Forgets what's known about an image whose file has changed.
    func forget(_ url: URL) {
        sizes.removeObject(forKey: Self.key(url))
    }

    private static func key(_ url: URL, pixels: Int? = nil) -> NSString {
        let path = url.standardizedFileURL.path
        return (pixels.map { "\(path)|\($0)" } ?? path) as NSString
    }

#if os(macOS)
    private static func value(_ size: CGSize) -> NSValue { NSValue(size: size) }
    private static func cgSize(_ value: NSValue) -> CGSize { value.sizeValue }
#else
    private static func value(_ size: CGSize) -> NSValue { NSValue(cgSize: size) }
    private static func cgSize(_ value: NSValue) -> CGSize { value.cgSizeValue }
#endif
}
