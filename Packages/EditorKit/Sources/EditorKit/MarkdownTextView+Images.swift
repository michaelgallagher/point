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
    /// The embed it shows, in the note's text.
    var range = NSRange(location: NSNotFound, length: 0)

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
            // Only the picture last asked for: a smaller one asked for earlier (before the note
            // was laid out at its width) that arrives later mustn't replace it, blurred.
            guard let self, self.url == url, self.pixels == wanted else { return }
            self.layer?.contents = image
        }
    }
}

extension MarkdownTextView {
    /// Captions are file names, not words: no spelling marks on them.
    public override func setSpellingState(_ value: Int, range charRange: NSRange) {
        guard value != 0, let storage = textStorage, NSMaxRange(charRange) <= storage.length, charRange.length > 0 else {
            return super.setSpellingState(value, range: charRange)
        }
        var touchesImage = false
        storage.enumerateAttribute(.pointImage, in: charRange) { found, _, stop in
            if found != nil { touchesImage = true; stop.pointee = true }
        }
        if !touchesImage { super.setSpellingState(value, range: charRange) }
    }

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
                let frame = CGRect(x: origin.x + container.lineFragmentPadding + indent + decoration.x,
                                   y: origin.y + line.minY + decoration.spaceAbove,
                                   width: decoration.size.width, height: decoration.size.height)
                if view.frame != frame { view.frame = frame }
                view.range = range
                view.show(decoration.url, size: decoration.size, name: text.substring(with: range))
            }
        }
        while imageViews.count > count {
            imageViews.removeLast().removeFromSuperview()
        }
    }

    // MARK: An image's commands

    /// The image drawn at a point in the view, with its embed.
    private func image(at point: NSPoint) -> (view: ImageEmbedView, target: String, isWeb: Bool)? {
        guard let view = imageViews.first(where: { $0.frame.contains(point) }), view.range.location != NSNotFound,
              let token = tokens.first(where: { $0.range == view.range }),
              let embed = MarkdownStyler.imageEmbed(token, in: string as NSString) else { return nil }
        let isWeb = embed.target.lowercased().hasPrefix("http://") || embed.target.lowercased().hasPrefix("https://")
        return (view, embed.target, isWeb)
    }

    /// Opens an image as a link to it would: in its viewer (or a web image's page).
    private func openImage(_ target: String, isWeb: Bool) {
        if isWeb, let url = URL(string: target) { onOpenLink?(.web(url)); return }
        onOpenLink?(.note(target))
    }

    /// A double-click on an image opens it. Returns whether it was one.
    func openImageOnDoubleClick(_ event: NSEvent, at point: NSPoint) -> Bool {
        guard event.clickCount == 2, let found = image(at: point) else { return false }
        openImage(found.target, isWeb: found.isWeb)
        return true
    }

    /// Right-clicking an image: open, replace, copy, show or remove it.
    func imageMenu(at point: NSPoint) -> NSMenu? {
        guard let found = image(at: point) else { return nil }
        let menu = NSMenu()
        let range = found.view.range, url = found.view.url
        menu.addItem(ImageMenuItem("Open Image") { [weak self] in self?.openImage(found.target, isWeb: found.isWeb) })
        if saveImage != nil {
            menu.addItem(ImageMenuItem("Replace Image…") { [weak self] in self?.replaceImage(at: range) })
        }
        menu.addItem(ImageMenuItem("Copy Image") {
            guard let url, let image = NSImage(contentsOf: url) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        })
        if found.isWeb {
            menu.addItem(ImageMenuItem("Copy Image Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(found.target, forType: .string)
            })
        } else if let url {
            menu.addItem(ImageMenuItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        menu.addItem(.separator())
        menu.addItem(ImageMenuItem("Remove Image") { [weak self] in self?.removeImage(at: range) })
        return menu
    }

    /// Asks for an image and puts it in place of the one embedded at `range`, as wide as that
    /// one was asked to be. The old image stays in the vault (Find Unused Images finds it).
    private func replaceImage(at range: NSRange) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to show here instead"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let file = panel.url, let data = try? Data(contentsOf: file),
                  let name = saveImage?(data, UTType(filenameExtension: file.pathExtension)),
                  NSMaxRange(range) <= (string as NSString).length else { return }
            let old = (string as NSString).substring(with: range)
            let width = old.hasPrefix("![[") ? old.dropFirst(3).dropLast(2).split(separator: "|", maxSplits: 1).dropFirst().first.map { "|" + $0 } ?? "" : ""
            insertText("![[\(name)\(width)]]", replacementRange: range)
        }
    }

    /// Takes the embed out of the note, and its line if it had one to itself.
    private func removeImage(at range: NSRange) {
        let text = string as NSString
        guard NSMaxRange(range) <= text.length else { return }
        let line = text.lineRange(for: range)
        let alone = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == text.substring(with: range)
        insertText("", replacementRange: alone ? line : range)
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
/// A menu item that runs a closure.
final class ImageMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runCommand), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func runCommand() { run() }
}
#endif
