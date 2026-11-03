#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Measures how tall a table cell's text is, wrapped in its column, laid out just as the grid's
/// cell views lay it out (the same layout manager, and no padding inside the line).
final class TableCellMeasurer {
    private let storage = NSTextStorage()
    private let layoutManager = PointLayoutManager()
    private let container = NSTextContainer(size: CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))

    init() {
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    /// An empty cell is as tall as a line of text with `emptyAttributes`.
    func height(of text: NSAttributedString, width: CGFloat, theme: EditorTheme, emptyAttributes: [NSAttributedString.Key: Any]) -> CGFloat {
        layoutManager.theme = theme
        container.size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        storage.setAttributedString(text.length > 0 ? text : NSAttributedString(string: " ", attributes: emptyAttributes))
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height.rounded(.up)
    }
}
