import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// One side of the window: its top bar above the current tab's note, or for an empty tab, a
/// start page. From macOS 26 the note scrolls up beneath the bar, which has no background of
/// its own: the note blurs what's under it (see `BarEdgeScrollView`).
struct PaneView: View {
    @EnvironmentObject private var model: VaultModel
    let paneID: VaultModel.NotePane.ID
    /// Where a tab dragged over the page would go.
    @State private var dropZone: PaneDropZone?
    /// This side's width, so the links panel leaves the note room.
    @State private var paneWidth: CGFloat = 0

    @AppStorage(LinksPlacement.key) private var linksPlacement = LinksPlacement.defaultValue

    var body: some View {
        if let index = model.paneIndex(paneID) {
            let pane = model.panes[index]
            if model.isFocused {
                page(pane, index: index, underBar: 0)
            } else {
                let linksNote = linksPanelNote(pane)
                // With the links panel open, this side is narrower, its bar and all, so the
                // note is laid out at its width from the start, even moving from note to note.
                HStack(spacing: 0) {
                    if #available(macOS 26, *) {
                        page(pane, index: index, underBar: TopBar.cover(for: pane, in: model))
                            .overlay(alignment: .top) { PaneTabBar(pane: pane, paneIndex: index) }
                    } else {
                        VStack(spacing: 0) {
                            PaneTabBar(pane: pane, paneIndex: index)
                            page(pane, index: index, underBar: 0)
                        }
                    }
                    if let linksNote {
                        LinksSidePanel(connections: model.connections(for: linksNote), paneID: paneID, roomBeside: paneWidth)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            paneWidth = geometry.size.width
                            model.paneFrames[paneID] = geometry.frame(in: .global)
                        }
                        .onChange(of: geometry.size.width) { paneWidth = $0 }
                        .onChange(of: geometry.frame(in: .global)) { model.paneFrames[paneID] = $0 }
                })
                .animation(LinksSidePanel.animation, value: linksNote != nil)
            }
        }
    }

    /// The note whose links show beside this side, if the panel's open: only for a note.
    private func linksPanelNote(_ pane: VaultModel.NotePane) -> Note? {
        guard linksPlacement == .side, model.isLinksPanelOpen(paneID) else { return nil }
        return model.note(pane.tab.noteID)
    }

    /// The note or start page. `underBar` is how much of it the top bar covers: the note's
    /// scroll view runs up beneath the bar (and is inset to match), anything else starts
    /// below it.
    private func page(_ pane: VaultModel.NotePane, index: Int, underBar: CGFloat) -> some View {
                Group {
                    if let note = model.note(pane.tab.noteID) {
                        NoteEditor(note: note, model: model, paneID: paneID, tabID: pane.tab.id, offersTemplates: note.id == model.freshNoteID)
                            .environment(\.topBarCover, underBar)
                            .id(paneID.uuidString + note.id)
                    } else if let image = model.store.image(pane.tab.noteID) {
                        ImageViewer(image: image)
                            .padding(.top, underBar)
                            .id(paneID.uuidString + image.path)
                    } else {
                        // An empty tab is a start page: search, recent notes and the explorer.
                        CommandPalette(isPage: true, paneID: paneID)
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
    /// How much of a note's page the see-through top bars cover.
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

/// An image opened from the list: shown as big as fits, with what it is, the notes that show
/// it (each opens with a click), and what can be done with it.
struct ImageViewer: View {
    @EnvironmentObject private var model: VaultModel
    let image: VaultImage
    @State private var picture: CGImage?
    @State private var pixels: CGSize?
    @State private var showing: [Note]?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(image.name)
                    .font(.system(size: 28, weight: .bold))
                    .textSelection(.enabled)
                Text(details)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }
                    Button("Open in Preview") { NSWorkspace.shared.open(image.url) }
                    Button("Rename…") {
                        newName = (image.name as NSString).deletingPathExtension
                        isRenaming = true
                    }
                    Button("Move to Trash") { isConfirmingTrash = true }
                }
                .controlSize(.small)
                Group {
                    if let picture {
                        Image(decorative: picture, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: pixels.map { $0.width } ?? .infinity, maxHeight: 640, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if !image.isDownloaded {
                        Label("In iCloud, not yet on this Mac", systemImage: "icloud.and.arrow.down")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shown in")
                        .font(.headline)
                    if let showing, showing.isEmpty {
                        Text("No note shows this image.")
                            .foregroundStyle(.secondary)
                    } else if let showing {
                        ForEach(showing) { note in
                            Button(note.title) { model.selection = note.id }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .frame(maxWidth: model.store.textColumnWidth, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .task(id: image.url) {
            pixels = EditorImages.shared.size(of: image.url)
            if !image.isDownloaded { try? FileManager.default.startDownloadingUbiquitousItem(at: image.url) }
            picture = await withCheckedContinuation { done in
                EditorImages.shared.picture(of: image.url, pixels: 2400) { done.resume(returning: $0) }
            }
        }
        .task(id: image.path + "\(model.store.indexGeneration)") { showing = await model.store.notesShowing(image) }
        .sheet(isPresented: $isRenaming) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename image").font(.headline)
                TextField("Name", text: $newName)
                    .frame(width: 320)
                    .onSubmit(rename)
                Text(showing.map { $0.isEmpty ? "No note shows it." : "Its embeds in \($0.count == 1 ? "1 note" : "\($0.count) notes") are renamed too." } ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { isRenaming = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename", action: rename)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
        .confirmationDialog("Move “\(image.name)” to the Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) { model.store.trashImage(image) }
        } message: {
            Text(showing.map { $0.isEmpty ? "No note shows it." : "\($0.count == 1 ? "1 note shows" : "\($0.count) notes show") it, and won’t any more." } ?? "")
        }
    }

    private func rename() {
        isRenaming = false
        model.store.renameImage(image, to: newName)
    }

    /// Its size in pixels, on disk, and its folder.
    private var details: String {
        var parts: [String] = []
        if let pixels { parts.append("\(Int(pixels.width)) × \(Int(pixels.height))") }
        if let bytes = try? image.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        let folder = (image.path as NSString).deletingLastPathComponent
        parts.append(folder.isEmpty ? "Top of the vault" : folder)
        return parts.joined(separator: " · ")
    }
}
