// The few things the styler and the layout manager need that AppKit and UIKit name or shape
// differently, so both platforms share them.
#if os(macOS)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
typealias PlatformBezierPath = NSBezierPath
typealias PlatformImage = NSImage

extension NSFont {
    /// The font with `italic` (or bold) added to its traits, or itself if there's no such font.
    func adding(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)), size: pointSize) ?? self
    }
}

enum PlatformTraits {
    static let italic = NSFontDescriptor.SymbolicTraits.italic
    static let bold = NSFontDescriptor.SymbolicTraits.bold
}

/// An SF Symbol drawn in the given colours (palette order), at a point size.
func symbolImage(_ name: String, pointSize: CGFloat, colors: [NSColor], description: String) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(configuration)
}

typealias PlatformFontTraits = NSFontDescriptor.SymbolicTraits

/// Text attributes with the pointing hand added, over something clickable (the Mac only).
func pointing(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
    attributes.merging([.cursor: NSCursor.pointingHand]) { kept, _ in kept }
}

extension NSImage {
    /// Drawn the right way up in a flipped view, such as a text view.
    func drawFlipped(in rect: CGRect) {
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

#else
import UIKit

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
typealias PlatformBezierPath = UIBezierPath
typealias PlatformImage = UIImage

extension UIColor {
    // AppKit's names, for the shared code.
    static var textColor: UIColor { .label }
    static var labelColor: UIColor { .label }
    static var secondaryLabelColor: UIColor { .secondaryLabel }
    static var separatorColor: UIColor { .separator }
    static var linkColor: UIColor { .link }
    static var textBackgroundColor: UIColor { .systemBackground }
    static var selectedTextBackgroundColor: UIColor { .systemBlue.withAlphaComponent(0.3) }

    /// This colour mixed with `fraction` of another, as AppKit's `blended(withFraction:of:)`.
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor? {
        var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1), other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        return UIColor(red: r1 + (r2 - r1) * fraction, green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction, alpha: a1 + (a2 - a1) * fraction)
    }
}

extension UIBezierPath {
    convenience init(roundedRect rect: CGRect, xRadius: CGFloat, yRadius: CGFloat) {
        self.init(roundedRect: rect, cornerRadius: min(xRadius, yRadius))
    }

    func line(to point: CGPoint) { addLine(to: point) }
}

extension UIFont {
    func adding(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}

enum PlatformTraits {
    static let italic = UIFontDescriptor.SymbolicTraits.traitItalic
    static let bold = UIFontDescriptor.SymbolicTraits.traitBold
}

func symbolImage(_ name: String, pointSize: CGFloat, colors: [UIColor], description: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        .applying(UIImage.SymbolConfiguration(paletteColors: colors))
    return UIImage(systemName: name, withConfiguration: configuration)
}
typealias PlatformFontTraits = UIFontDescriptor.SymbolicTraits

/// No pointer to change on the iPhone.
func pointing(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] { attributes }

extension UIImage {
    func drawFlipped(in rect: CGRect) { draw(in: rect) }
}

extension UIColor {
    static var controlAccentColor: UIColor { .tintColor }
    static var tertiaryLabelColor: UIColor { .tertiaryLabel }
}
#endif
