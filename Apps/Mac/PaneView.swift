import AppKit
import SwiftUI
import VaultKit

/// One side of the window: its top bar (title or tabs) above the current tab's note, or
/// for an empty tab, a start page. From macOS 26 the note scrolls up beneath the bar,
/// which has no background of its own: the system's hard scroll edge effect blurs what's
/// under it (see `WindowTabbing`).
struct PaneView: View {
    @EnvironmentObject private var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    /// Where a tab dragged over the page would go.
    @State private var dropZone: PaneDropZone?

    var body: some View {
        if let index = model.paneIndex(paneID) {
            let pane = model.panes[index]
            if model.isFocused {
                page(pane, index: index, underBar: 0)
            } else if #available(macOS 26, *) {
                page(pane, index: index, underBar: model.topBarHeight)
                    .overlay(alignment: .top) { PaneTopBar(pane: pane, paneIndex: index) }
            } else {
                VStack(spacing: 0) {
                    PaneTopBar(pane: pane, paneIndex: index)
                    page(pane, index: index, underBar: 0)
                }
            }
        }
    }

    /// The note or start page. `underBar` is how much of it the top bar covers: the note's
    /// scroll view runs up beneath the bar (and is inset by the window to match), anything
    /// else starts below it.
    private func page(_ pane: VaultModel.NotePane, index: Int, underBar: CGFloat) -> some View {
                Group {
                    if let note = model.note(pane.tab.noteID) {
                        NoteEditor(note: note, model: model, paneID: paneID, tabID: pane.tab.id, offersTemplates: note.id == model.freshNoteID)
                            .environment(\.topBarCover, underBar)
                            .id(paneID.uuidString + note.id)
                    } else {
                        // An empty tab is a start page: search, recent notes and the explorer.
                        CommandPalette(isPage: true)
                            .padding(.top, underBar)
                            .id(pane.tab.id) // A fresh page for each tab.
                    }
                }
                // A tab dragged onto one half of the page splits the window; onto the other
                // side's page, it moves there.
                .overlay { PaneDropHighlight(zone: dropZone) }
                .background(TabDropArea { id, point, size in
                    dropZone = id.flatMap { PaneDropZone(tab: $0, overPane: index, x: point.x, width: size.width, in: model) }
                    return dropZone != nil
                } drop: { id, point, size in
                    dropZone = nil
                    guard let zone = PaneDropZone(tab: id, overPane: index, x: point.x, width: size.width, in: model) else { return false }
                    zone.drop(id, onPane: index, in: model)
                    return true
                })
    }
}

extension EnvironmentValues {
    /// How much of a note's page the see-through top bar covers.
    @Entry var topBarCover: CGFloat = 0
}

/// The right side of a split, in a view of its own (so a layer of its own), which slides in
/// as the split opens: from the window's edge, or from where its note was.
struct SlidingSide<Content: View>: NSViewRepresentable {
    let slideOffset: CGFloat?
    let content: Content

    func makeNSView(context: Context) -> SideHostingView {
        let view = SideHostingView(rootView: AnyView(content))
        view.sizingOptions = []
        // Placed by the split, not inset for the title bar (the side draws its own bar there).
        if #available(macOS 13.3, *) { view.safeAreaRegions = [] }
        view.wantsLayer = true
        view.slideOffset = slideOffset
        return view
    }

    func updateNSView(_ view: SideHostingView, context: Context) {
        view.rootView = AnyView(content)
    }
}

/// Starts its slide once it has its size, before it's first drawn. Draws the dividing line
/// at its leading edge, so the line slides in with it: a layer above everything in it (drawn
/// by SwiftUI, the line went under the note's editor).
final class SideHostingView: NSHostingView<AnyView> {
    var slideOffset: CGFloat?
    private let line: CALayer = {
        let line = CALayer()
        line.zPosition = 1000
        return line
    }()

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colorLine()
    }

    private func colorLine() {
        effectiveAppearance.performAsCurrentDrawingAppearance { line.backgroundColor = NSColor.separatorColor.cgColor }
    }

    override func layout() {
        super.layout()
        if let layer, line.superlayer !== layer {
            layer.addSublayer(line)
            colorLine()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.frame = NSRect(x: 0, y: 0, width: 1, height: bounds.height)
        CATransaction.commit()
        guard let offset = slideOffset, bounds.width > 0, let layer else { return }
        slideOffset = nil
        if abs(offset) > 1 { layer.add(SidebarSplitController.slide(from: offset), forKey: "splitOpened") }
    }
}

/// Two views side by side with a divider to drag between them. Unlike HSplitView, it
/// takes only the width it's offered, so it never squeezes the sidebar.
struct SideBySide<Main: View, Side: View>: View {
    let main: Main
    let side: Side
    /// How much of the width the left side gets.
    @AppStorage private var fraction: Double
    /// The narrowest each side can be.
    private let minimumWidths: (main: CGFloat, side: CGFloat)
    /// False for the left side alone, filling the width: the same view as when there are two,
    /// so the left side's views stay as they are when the right side closes.
    private let showsSide: Bool
    /// The side draws the dividing line at its leading edge (so the line moves with it, as the
    /// notes' right side slides in); here there's only the grip to drag.
    private let sideDrawsDivider: Bool
    /// The left side's width when the divider was picked up.
    @State private var dragStart: CGFloat = 0

    /// Kept as a fraction of the width under `key` (`fraction` until dragged), so each side
    /// keeps its share as the whole grows or shrinks.
    init(key: String = "sideBySideFraction", fraction: Double = 0.5, minimumWidths: (main: CGFloat, side: CGFloat) = (240, 240),
         showsSide: Bool = true, sideDrawsDivider: Bool = false, @ViewBuilder main: () -> Main, @ViewBuilder side: () -> Side) {
        self.main = main()
        self.side = side()
        _fraction = AppStorage(wrappedValue: fraction, key)
        self.minimumWidths = minimumWidths
        self.showsSide = showsSide
        self.sideDrawsDivider = sideDrawsDivider
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let mainWidth = showsSide ? clamp(width * fraction, in: width) : width
            HStack(spacing: 0) {
                main
                    .frame(width: mainWidth)
                if showsSide {
                    // The line (unless the side draws it, so it moves with the side).
                    Divider()
                        .opacity(sideDrawsDivider ? 0 : 1)
                        .frame(width: sideDrawsDivider ? 0 : nil)
                    side
                        .frame(maxWidth: .infinity)
                }
            }
            // The grip, over the line and either side of it, above everything (an AppKit view,
            // so the editors either side don't take the pointer, as they did from a SwiftUI one).
            .overlay(alignment: .topLeading) {
                if showsSide {
                    ResizeGripView { distance, isStart in
                        if isStart { dragStart = mainWidth }
                        guard width > 0 else { return }
                        fraction = clamp(dragStart + distance, in: width) / width
                    }
                    .frame(width: ResizeGrip.width)
                    .frame(maxHeight: .infinity)
                    .offset(x: mainWidth - ResizeGrip.width / 2)
                }
            }
        }
    }

    /// The left side's width in a split of the notes (as last dragged).
    static func mainWidth(in width: CGFloat, minimumWidths: (main: CGFloat, side: CGFloat)) -> CGFloat {
        let fraction = UserDefaults.standard.object(forKey: "sideBySideFraction") as? Double ?? 0.5
        return clamp(width * fraction, in: width, minimumWidths: minimumWidths)
    }

    private func clamp(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        Self.clamp(x, in: width, minimumWidths: minimumWidths)
    }

    private static func clamp(_ x: CGFloat, in width: CGFloat, minimumWidths: (main: CGFloat, side: CGFloat)) -> CGFloat {
        let total = minimumWidths.main + minimumWidths.side
        guard width > total else { return width * minimumWidths.main / total }
        return min(max(x, minimumWidths.main), width - minimumWidths.side).rounded()
    }
}
