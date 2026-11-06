#if os(iOS)
import MarkdownKit
import UIKit

/// Draws an image embedded in a note, in the room the styler made above its line (see
/// `ImageDecoration`), as the Mac's `ImageEmbedView` does. Taps go to the text view, which
/// opens the image.
final class PhoneImageView: UIView {
    private(set) var url: URL?
    private var pixels = 0
    /// The embed it shows, in the note's text.
    var range = NSRange(location: NSNotFound, length: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 6
        layer.masksToBounds = true
        layer.contentsGravity = .resizeAspect
        backgroundColor = UIColor.tertiarySystemFill
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// Shows the image at `url`, decoded for this size on this screen, once it's ready.
    func show(_ url: URL, size: CGSize, name: String) {
        let scale = window?.screen.scale ?? 3
        let wanted = Int((max(size.width, size.height) * scale).rounded(.up))
        guard url != self.url || wanted > pixels else { return }
        let isNew = url != self.url
        self.url = url
        pixels = wanted
        accessibilityLabel = name
        if let cached = EditorImages.shared.cachedPicture(of: url, pixels: wanted) {
            layer.contents = cached
            return
        }
        if isNew { layer.contents = nil }
        EditorImages.shared.picture(of: url, pixels: wanted) { [weak self] image in
            guard let self, self.url == url, self.pixels == wanted else { return }
            self.layer.contents = image
        }
    }
}

/// Images, and the app's own blocks (an embedded list), drawn over the room the styler makes
/// for them above their lines, as on the Mac.
extension PhoneTextView {
    /// Says where the vault's images are (`a.png`, or a path, from the note being shown), which
    /// turns images on. Nil, and embeds show as they're written.
    public var imageURL: ((String) -> URL?)? {
        get { styler.imageURL }
        set {
            styler.imageURL = newValue
            styler.theme.rendersImages = newValue != nil || styler.blockEmbedHeight != nil
            restyle(NSRange(location: 0, length: textStorage.length))
        }
    }

    /// How tall a block the app draws for an embed of a note (`![[Books to read]]`) alone on
    /// its line, if it draws one, and the view it draws (`makeBlockEmbedView`).
    public var blockEmbedHeight: ((String) -> CGFloat?)? {
        get { styler.blockEmbedHeight }
        set {
            styler.blockEmbedHeight = newValue
            styler.theme.rendersImages = newValue != nil || styler.imageURL != nil
            restyle(NSRange(location: 0, length: textStorage.length))
        }
    }

    /// Restyles the note's embeds, as when an image has arrived or a list's results changed.
    public func restyleEmbeds() {
        restyle(NSRange(location: 0, length: textStorage.length))
        syncEmbedViews()
    }

    /// Keeps images as wide as the text, at most.
    func noteTextWidth() {
        let width = bounds.width - textContainerInset.left - textContainerInset.right - textContainer.lineFragmentPadding * 2
        guard width > 0, abs(width - styler.theme.textWidth) > 0.5 else { return }
        styler.theme.textWidth = width
        guard styler.theme.rendersImages, textStorage.length > 0 else { return }
        restyle(NSRange(location: 0, length: textStorage.length))
    }

    /// Puts a view over the room above each image and block embed, where its line is laid out.
    func syncEmbedViews() {
        let manager = pointLayoutManager
        var images = 0, blocks = 0
        let origin = CGPoint(x: textContainerInset.left + textContainer.lineFragmentPadding, y: textContainerInset.top)
        if styler.theme.rendersImages, !styler.showsMarkdown, textStorage.length > 0 {
            let text = textStorage.string as NSString
            let all = NSRange(location: 0, length: textStorage.length)
            textStorage.enumerateAttribute(.pointImage, in: all) { value, range, _ in
                guard let decoration = value as? ImageDecoration, range.length > 0 else { return }
                let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
                guard line.height > decoration.size.height else { return }
                let indent = (textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
                let view: PhoneImageView
                if images < imageViews.count {
                    view = imageViews[images]
                } else {
                    view = PhoneImageView(frame: .zero)
                    insertSubview(view, at: 0)
                    imageViews.append(view)
                }
                images += 1
                let frame = CGRect(x: origin.x + indent + decoration.x, y: origin.y + line.minY + decoration.spaceAbove,
                                   width: decoration.size.width, height: decoration.size.height)
                if view.frame != frame { view.frame = frame }
                view.range = range
                view.show(decoration.url, size: decoration.size, name: text.substring(with: range))
            }
            if let make = makeBlockEmbedView {
                textStorage.enumerateAttribute(.pointBlockEmbed, in: all) { value, range, _ in
                    guard let decoration = value as? BlockEmbedDecoration, range.length > 0 else { return }
                    let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
                    guard line.height > decoration.height else { return }
                    let indent = (textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
                    if blocks < blockEmbedViews.count, blockEmbedViews[blocks].target != decoration.target {
                        blockEmbedViews[blocks].view.removeFromSuperview()
                        blockEmbedViews.remove(at: blocks)
                    }
                    let view: UIView
                    if blocks < blockEmbedViews.count {
                        view = blockEmbedViews[blocks].view
                    } else {
                        view = make(decoration.target)
                        addSubview(view)
                        blockEmbedViews.insert((decoration.target, view), at: blocks)
                    }
                    blocks += 1
                    let frame = CGRect(x: origin.x + indent, y: origin.y + line.minY + decoration.spaceAbove,
                                       width: max(styler.theme.textWidth - indent, 100), height: decoration.height)
                    if view.frame != frame { view.frame = frame }
                }
            }
        }
        while imageViews.count > images { imageViews.removeLast().removeFromSuperview() }
        while blockEmbedViews.count > blocks { blockEmbedViews.removeLast().view.removeFromSuperview() }
        embedsSyncedHeight = contentSize.height
    }

    /// The image drawn at a point in the view, if any: its file.
    func image(at point: CGPoint) -> URL? {
        imageViews.first { $0.frame.contains(point) }?.url
    }
}
#endif
