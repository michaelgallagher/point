import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Point's Settings window (⌘,): its sections in a list down the left, each section's
/// settings beside it, each with its label above its options.
struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("settingsPage") private var page = Page.sidebar

    enum Page: String, CaseIterable, Identifiable {
        case sidebar, notes, text, typography
        var id: Self { self }

        var title: String {
            switch self {
            case .sidebar: "Sidebar"
            case .notes: "Notes"
            case .text: "Text"
            case .typography: "Typography"
            }
        }

        var symbol: String {
            switch self {
            case .sidebar: "sidebar.left"
            case .notes: "list.bullet"
            case .text: "doc.text"
            case .typography: "textformat.size"
            }
        }
    }

    /// Pages visited before and after this one, for the back and forward buttons.
    @State private var backPages: [Page] = []
    @State private var forwardPages: [Page] = []

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding(get: { page }, set: { if let new = $0 { go(to: new) } })) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(190)
            .modifier(NoSidebarToggle())
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .sidebar: sidebarPage
                    case .notes: notesPage
                    case .text: textPage
                    case .typography: TypographySettings(typography: $store.typography)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Back and forward, then the page's name, large, as in System Settings.
            // Back and forward, joined in one capsule, then the page's name, as in System
            // Settings. One item, so they stay in that order; no glass behind the item itself,
            // so the name isn't in a pill.
            .toolbar {
                if #available(macOS 26, *) {
                    ToolbarItem(placement: .navigation) { navigation }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) { navigation }
                }
            }
        }
        .frame(width: 780, height: 560)
        // No "Point Settings" in the title bar: the page's name is in the toolbar instead.
        .background(SettingsWindowStyle())
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            let pair = HStack(spacing: 0) {
                arrow("chevron.left", label: "Back", enabled: !backPages.isEmpty) { travel(back: true) }
                arrow("chevron.right", label: "Forward", enabled: !forwardPages.isEmpty) { travel(back: false) }
            }
            if #available(macOS 26, *) {
                pair
                    .padding(.horizontal, 4)
                    .frame(height: 36)
                    .glassEffect(.regular, in: Capsule())
            } else {
                pair
            }
            Text(page.title)
                .font(.title3.weight(.semibold))
                .fixedSize()
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }

    private func go(to new: Page) {
        guard new != page else { return }
        backPages.append(page)
        forwardPages.removeAll()
        page = new
    }

    private func travel(back: Bool) {
        if back, let previous = backPages.popLast() {
            forwardPages.append(page)
            page = previous
        } else if !back, let next = forwardPages.popLast() {
            backPages.append(page)
            page = next
        }
    }

    @ViewBuilder private var sidebarPage: some View {
            SettingsSection("Sidebar") {
                Setting("Layout") {
                    Picker("Layout", selection: $store.browsingStyle) {
                        Text("One column: folders, tags and notes in one list").tag(VaultModel.BrowsingStyle.singleColumn)
                        Text("Two columns: folders and tags beside the notes").tag(VaultModel.BrowsingStyle.twoColumns)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Setting("Density") {
                    Picker("Density", selection: $store.sidebarDensity) {
                        Text("Comfortable").tag(VaultModel.SidebarDensity.comfortable)
                        Text("Compact").tag(VaultModel.SidebarDensity.compact)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Setting("Folders and tags, in two columns") {
                    Picker("Folders and tags, in two columns", selection: $store.treeLayout) {
                        Text("Together, folders above tags").tag(VaultModel.TreeLayout.stacked)
                        Text("One at a time, with a switch").tag(VaultModel.TreeLayout.toggle)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .disabled(store.browsingStyle != .twoColumns)
                Toggle("Swipe sideways with two fingers to show and hide it", isOn: $store.swipesSidebar)
                HStack(spacing: 6) {
                    Toggle("Hide it when the window is narrower than", isOn: $store.autoHidesSidebar)
                    TextField("Width", value: $store.sidebarAutoHideWidth, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        .disabled(!store.autoHidesSidebar)
                    Stepper("Width", value: $store.sidebarAutoHideWidth, in: 600...2400, step: 20)
                        .labelsHidden()
                        .disabled(!store.autoHidesSidebar)
                    Text("points")
                        .foregroundStyle(.secondary)
                }
            }

    }

    @ViewBuilder private var notesPage: some View {
            SettingsSection("Sorting") {
                HStack(alignment: .top, spacing: 32) {
                    Setting("Folders and tags") {
                        Picker("Folders and tags", selection: $store.tagOrder) {
                            Text("Name").tag(VaultModel.TagOrder.name)
                            Text("Date Modified").tag(VaultModel.TagOrder.modified)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Setting("Notes") {
                        Picker("Notes", selection: $store.sort) {
                            Text("Date Edited").tag(NoteSort.modified)
                            Text("Date Created").tag(NoteSort.created)
                            Text("Title").tag(NoteSort.title)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            Divider()

            SettingsSection("Note list") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show dates", isOn: $store.showsDateInList)
                    Picker("Date shown", selection: $store.listDate) {
                        Text("Date edited").tag(VaultModel.ListDate.edited)
                        Text("Date created").tag(VaultModel.ListDate.created)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .padding(.leading, 20)
                    .disabled(!store.showsDateInList)
                    Toggle("Show tags", isOn: $store.showsTagsInList)
                }
            }

            Divider()

            SettingsSection("Trash") {
                HStack(spacing: 6) {
                    Text("Keep deleted notes for")
                    TextField("Days", value: $store.trashRetentionDays, format: .number)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                    Stepper("Days", value: $store.trashRetentionDays, in: 1...365)
                        .labelsHidden()
                    Text(store.trashRetentionDays == 1 ? "day" : "days")
                }
                Text("Deleted notes go to the vault's .trash folder, which Obsidian uses too, and are removed for good after this.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

    }

    @ViewBuilder private var textPage: some View {
            SettingsSection("Text") {
                Setting("Size") {
                    HStack {
                        Text("\(Int((store.textScale * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                        Stepper("Text size", onIncrement: store.makeTextBigger, onDecrement: store.makeTextSmaller)
                            .labelsHidden()
                        Button("Reset") { store.textScale = 1 }
                            .disabled(store.textScale == 1)
                    }
                }
                Setting("Maximum line width") {
                    HStack {
                        Slider(value: $store.textColumnWidth, in: VaultStore.textColumnWidths, step: 20)
                            .frame(width: 200)
                        Text("\(Int(store.textColumnWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .leading)
                        Button("Reset") { store.textColumnWidth = 720 }
                            .disabled(store.textColumnWidth == 720)
                    }
                }
            }
    }
}

/// The Typography page: the body's size and line height, and each heading's size, weight
/// and slant, each shown in its own style.
private struct TypographySettings: View {
    @Binding var typography: Typography

    var body: some View {
        SettingsSection("Body text") {
            HStack(alignment: .top, spacing: 32) {
                Setting("Size") {
                    HStack {
                        Text("\(Int(typography.bodySize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                        Stepper("Size", value: $typography.bodySize, in: 10...28, step: 1)
                            .labelsHidden()
                    }
                }
                Setting("Line height") {
                    HStack {
                        Text(typography.lineHeight.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                        Stepper("Line height", value: $typography.lineHeight, in: 1...2.2, step: 0.05)
                            .labelsHidden()
                    }
                }
            }
            Text("The quick brown fox jumps over the lazy dog, and the line after it shows the spacing between lines of a paragraph.")
                .font(.system(size: typography.bodySize))
                .lineSpacing(typography.bodySize * (typography.lineHeight - 1))
                .frame(maxWidth: 420, alignment: .leading)
                .foregroundStyle(.secondary)
        }

        Divider()

        SettingsSection("Headings") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    GridRow {
                        Text("Heading \(index + 1)")
                            .font(font(for: index))
                            .lineLimit(1)
                            .frame(width: 200, alignment: .leading)
                        HStack(spacing: 4) {
                            Text("\(Int(points(index).rounded())) pt")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                            Stepper("Size", onIncrement: { setPoints(index, points(index) + 1) },
                                    onDecrement: { setPoints(index, points(index) - 1) })
                                .labelsHidden()
                        }
                        Picker("Weight", selection: $typography.headings[index].weight) {
                            ForEach(Typography.Weight.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Toggle("Italic", isOn: $typography.headings[index].italic)
                    }
                }
            }
            Button("Restore Defaults") { typography = Typography() }
                .disabled(typography == Typography())
        }
    }

    /// A heading's size in points, at the body size chosen.
    private func points(_ index: Int) -> Double { typography.headings[index].size * typography.bodySize }

    private func setPoints(_ index: Int, _ points: Double) {
        let points = min(max(points.rounded(), 8), 60)
        typography.headings[index].size = points / typography.bodySize
    }

    private func font(for index: Int) -> Font {
        let style = typography.headings[index]
        let weight: Font.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        let font = Font.system(size: min(points(index), 30), weight: weight)
        return style.italic ? font.italic() : font
    }
}

/// Hides the sidebar button a split view adds to the toolbar, from macOS 14.
private struct NoSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

/// The Settings window without its title: a unified toolbar, its window buttons set in
/// from the corner like the main window's.
private struct SettingsWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowFinder() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class WindowFinder: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
        }
    }
}

/// A titled group of settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

/// One setting: its label, with its options below.
private struct Setting<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            content
        }
    }
}
