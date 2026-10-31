#if os(iOS)
import UIKit

/// The phone's text container. A tag wrapped to the start of a line starts in from the margin, to
/// keep its pill whole, as nothing before it on the line can make the room. (A tag starting a
/// paragraph is moved in by its paragraph's style.)
final class PhoneTextContainer: NSTextContainer {
    var tagSpace: CGFloat = 0

    override var isSimpleRectangularTextContainer: Bool { false }

    override func lineFragmentRect(forProposedRect proposedRect: CGRect, at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<CGRect>?) -> CGRect {
        var rect = super.lineFragmentRect(forProposedRect: proposedRect, at: characterIndex,
                                          writingDirection: baseWritingDirection, remaining: remainingRect)
        guard let storage = layoutManager?.textStorage, characterIndex > 0, characterIndex < storage.length,
              storage.attribute(.pointTag, at: characterIndex, effectiveRange: nil) != nil,
              (storage.string as NSString).character(at: characterIndex - 1) != 10 else { return rect }
        rect.origin.x += tagSpace
        rect.size.width -= tagSpace
        return rect
    }
}
#endif
