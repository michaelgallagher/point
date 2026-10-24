import Foundation

/// How note text is set: the body's size and line height, and each heading's size and style.
/// Chosen in Settings; ⌘+ and ⌘− scale it all.
public struct Typography: Equatable, Codable, Sendable {
    /// Body text size in points, at normal scale.
    public var bodySize: Double = 15
    /// Line height as a multiple of the font's own.
    public var lineHeight: Double = 1.3
    /// Headings 1 to 6.
    public var headings: [HeadingStyle] = HeadingStyle.defaults

    public init() {}

    public enum Weight: String, Codable, CaseIterable, Sendable {
        case regular, medium, semibold, bold

        public var name: String { rawValue.capitalized }
    }

    public struct HeadingStyle: Equatable, Codable, Sendable {
        /// Size relative to body text: 1 is the same size.
        public var size: Double
        public var weight: Weight
        public var italic: Bool

        public init(size: Double, weight: Weight, italic: Bool = false) {
            self.size = size
            self.weight = weight
            self.italic = italic
        }

        /// H1 26pt bold, H2 18pt semibold, H3 body size bold, H4 to H6 body size italic (for
        /// 15pt text), as in Apple Notes.
        public static let defaults: [HeadingStyle] = [
            HeadingStyle(size: 26.0 / 15, weight: .bold),
            HeadingStyle(size: 18.0 / 15, weight: .semibold),
            HeadingStyle(size: 1, weight: .bold),
            HeadingStyle(size: 1, weight: .regular, italic: true),
            HeadingStyle(size: 1, weight: .regular, italic: true),
            HeadingStyle(size: 1, weight: .regular, italic: true),
        ]
    }

    public func heading(_ level: Int) -> HeadingStyle {
        headings.indices.contains(level - 1) ? headings[level - 1] : HeadingStyle.defaults[min(max(level, 1), 6) - 1]
    }
}
