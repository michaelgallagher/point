#if canImport(AppKit)
import AppKit
import MarkdownKit
import UniformTypeIdentifiers

/// Draws an image embedded in a note, in the room the styler made above its line (see
/// `ImageDecoration`). Clicks go through to the text, so the image's line is edited as any
/// other: its Markdown is the caption under it.
final class ImageEmbedView: NSView {
    private(set) var url: URL?
    private var pixels = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    /// Shows the image at `url`, decoded for this size on this screen, once it's ready.
    func show(_ url: URL, size: CGSize, name: String) {
        let scale = window?.backingScaleFactor ?? 2
        let wanted = Int((max(size.width, size.height) * scale).rounded(.up))
        // Decoded again only when it's shown much bigger than it was decoded for.
        guard url != self.url || wanted > pixels else { return }
        let isNew = url != self.url
        self.url = url
        pixels = wanted
        setAccessibilityLabel(name)
        if let cached = EditorImages.shared.cachedPicture(of: url, pixels: wanted) {
            layer?.contents = cached
            return
        }
        if isNew { layer?.contents = nil }
        EditorImages.shared.picture(of: url, pixels: wanted) { [weak self] image in
            guard let self, self.url == url else { return }
            self.layer?.contents = image
        }
    }
}

extension MarkdownTextView {
    /// Puts a view over the room above each image embed, where its line is laid out.
    func syncImageViews() {
        guard let storage = textStorage, let layoutManager, let container = textContainer else { return }
        var count = 0
        let origin = textContainerOrigin
        if styler.theme.rendersImages, !styler.showsMarkdown {
            let text = storage.string as NSString
            storage.enumerateAttribute(.pointImage, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let decoration = value as? ImageDecoration, range.length > 0 else { return }
                let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
                let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                // Folded away, or not laid out yet.
                guard line.height > decoration.size.height else { return }
                let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let view: ImageEmbedView
                if count < imageViews.count {
                    view = imageViews[count]
                } else {
                    view = ImageEmbedView(frame: .zero)
                    addSubview(view, positioned: .below, relativeTo: nil)
                    imageViews.append(view)
                }
                count += 1
                let indent = style?.firstLineHeadIndent ?? 0
                let frame = CGRect(x: origin.x + container.lineFragmentPadding + indent,
                                   y: origin.y + line.minY + decoration.spaceAbove,
                                   width: decoration.size.width, height: decoration.size.height)
                if view.frame != frame { view.frame = frame }
                view.show(decoration.url, size: decoration.size, name: text.substring(with: range))
            }
        }
        while imageViews.count > count {
            imageViews.removeLast().removeFromSuperview()
        }
    }

    // MARK: Pasting and dropping images

    /// The kinds of image the pasteboard can hold, best first.
    private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                                                                               NSPasteboard.PasteboardType(UTType.heic.identifier),
                                                                               NSPasteboard.PasteboardType(UTType.gif.identifier)]

    /// Images on the pasteboard, to be saved: image files (dragged from the Finder, say), else
    /// image data (a screenshot copied). Empty when it holds text too, but no image files:
    /// text copied from a web page brings an image of itself along.
    func pastedImages(from pasteboard: NSPasteboard) -> [(data: Data, type: UTType?)] {
        guard saveImage != nil, !styler.showsMarkdown else { return [] }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter { url in
                UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            }
            if !images.isEmpty {
                return images.compactMap { url in
                    (try? Data(contentsOf: url)).map { ($0, UTType(filenameExtension: url.pathExtension)) }
                }
            }
            if !urls.isEmpty { return [] }
        }
        guard pasteboard.string(forType: .string) == nil, pasteboard.string(forType: .html) == nil else { return [] }
        for type in Self.imagePasteboardTypes {
            if let data = pasteboard.data(forType: type) { return [(data, UTType(type.rawValue))] }
        }
        return []
    }

    /// Saves images for the note and embeds them where the cursor is, each on a line of its
    /// own. Returns whether any were.
    @discardableResult
    public func insertImages(_ images: [(data: Data, type: UTType?)]) -> Bool {
        guard let saveImage else { return false }
        let names = images.compactMap { saveImage($0.data, $0.type) }
        guard !names.isEmpty else { return false }
        let selection = selectedRange()
        let text = string as NSString
        let atLineStart = selection.location == 0 || text.character(at: selection.location - 1) == 10
        let atLineEnd = NSMaxRange(selection) >= text.length || text.character(at: NSMaxRange(selection)) == 10
        let embeds = names.map { "![[\($0)]]" }.joined(separator: "\n")
        // Ending the note, it ends with a line break, as a well-formed file does.
        let atEnd = NSMaxRange(selection) >= text.length
        insertText((atLineStart ? "" : "\n") + embeds + (atLineEnd && !atEnd ? "" : "\n"), replacementRange: selection)
        return true
    }

    public override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let images = pastedImages(from: pboard)
        if !images.isEmpty, insertImages(images) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    public override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        var types = super.acceptableDragTypes
        guard saveImage != nil else { return types }
        for type in Self.imagePasteboardTypes + [.fileURL] where !types.contains(type) { types.append(type) }
        return types
    }

    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        guard saveImage != nil else { return types }
        for type in Self.imagePasteboardTypes.reversed() where !types.contains(type) { types.insert(type, at: 0) }
        return types
    }
}
#endif
