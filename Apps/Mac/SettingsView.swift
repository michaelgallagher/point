import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Point's Settings window (⌘,): its sections in a list down the left, each section's
/// settings beside it, in full-width rows as in the system's and Xcode's settings.
struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("settingsPage") private var page = Page.sidebar

    enum Page: String, CaseIterable, Identifiable {
        case sidebar, notes, templates, shortcuts, appIcon
        var id: Self { self }

        var title: String {
            switch self {
            case .sidebar: "Sidebar"
            case .notes: "Notes"
            case .templates: "Templates"
            case .shortcuts: "Shortcuts"
            case .appIcon: "App Icon"
            }
        }

        var symbol: String {
            switch self {
            case .sidebar: "sidebar.left"
            case .notes: "doc.text"
            case .templates: "doc.on.doc"
            case .shortcuts: "keyboard"
            case .appIcon: "app.badge"
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
            Group {
                switch page {
                case .sidebar: sidebarPage
                case .notes: notesPage
                case .templates: scrolling { TemplatesSettings() }
                case .shortcuts: ShortcutSettings()
                case .appIcon: scrolling { appIconPage }
                }
            }
            .formStyle(.grouped)
            .labeledContentStyle(SettingsRowStyle())
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

    /// A page that isn't a form of rows.
    private func scrolling<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(28)
                // The whole page, however short, so a click anywhere off a control lands
                // on the background below.
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                // A click away from a field (or anything else with the keyboard) lets go
                // of it, as elsewhere on the Mac: it kept its focus ring until another
                // control was clicked.
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                )
            }
        }
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

    private var sidebarPage: some View {
        Form {
            Section {
                Picker("Layout", selection: $store.browsingStyle) {
                    Text("One Column").tag(VaultModel.BrowsingStyle.singleColumn)
                    Text("Two Columns").tag(VaultModel.BrowsingStyle.twoColumns)
                }
                Picker("Density", selection: $store.sidebarDensity) {
                    Text("Comfortable").tag(VaultModel.SidebarDensity.comfortable)
                    Text("Compact").tag(VaultModel.SidebarDensity.compact)
                }
                Picker("Folders and tags", selection: $store.treeLayout) {
                    Text("Folders Above Tags").tag(VaultModel.TreeLayout.stacked)
                    Text("One at a Time").tag(VaultModel.TreeLayout.toggle)
                }
            }

            Section("Showing and hiding") {
                Toggle("Swipe sideways with two fingers to show and hide", isOn: $store.swipesSidebar)
                Toggle("Hide when the window is narrow", isOn: $store.autoHidesSidebar)
                LabeledContent("Narrower than") {
                    HStack(spacing: 6) {
                        TextField("Width", value: $store.sidebarAutoHideWidth, format: .number)
                            .labelsHidden()
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                        Stepper("Width", value: $store.sidebarAutoHideWidth, in: 600...2400, step: 20)
                            .labelsHidden()
                        Text("points")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!store.autoHidesSidebar)
            }

            Section("Sorting") {
                Picker("Folders and tags", selection: $store.tagOrder) {
                    Text("Name").tag(VaultModel.TagOrder.name)
                    Text("Date Modified").tag(VaultModel.TagOrder.modified)
                }
                Picker("Notes", selection: $store.sort) {
                    Text("Date Edited").tag(NoteSort.modified)
                    Text("Date Created").tag(NoteSort.created)
                    Text("Title").tag(NoteSort.title)
                }
            }

            Section("Note list") {
                Picker("Dates", selection: $store.listDateStyle) {
                    Text("In Groups").tag(VaultModel.ListDateStyle.groups)
                    Text("Beside Titles").tag(VaultModel.ListDateStyle.beside)
                    Text("Hidden").tag(VaultModel.ListDateStyle.off)
                }
                // Beside each title. (Groups follow the date the notes are sorted by.)
                Picker("Date shown", selection: $store.listDate) {
                    Text("Date Edited").tag(VaultModel.ListDate.edited)
                    Text("Date Created").tag(VaultModel.ListDate.created)
                }
                .disabled(store.listDateStyle != .beside)
                Toggle("Show tags", isOn: $store.showsTagsInList)
            }

            Section("Trash") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Keep deleted notes for")
                        Spacer()
                        TextField("Days", value: $store.trashRetentionDays, format: .number)
                            .labelsHidden()
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Stepper("Days", value: $store.trashRetentionDays, in: 1...365)
                            .labelsHidden()
                        Text(store.trashRetentionDays == 1 ? "day" : "days")
                            .foregroundStyle(.secondary)
                    }
                    Text("Notes you delete in Point go to the vault's .trash folder, which Obsidian uses too, and are removed for good after this. Notes Obsidian put there stay until you empty the trash.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var appIconPage: some View {
            Setting("Icon", isHeading: true) {
                AppIconPicker()
            }
    }

    private var notesPage: some View {
        Form {
            Section {
                LabeledContent("Text size") {
                    HStack {
                        Text("\(Int((store.textScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("Text size", onIncrement: store.makeTextBigger, onDecrement: store.makeTextSmaller)
                            .labelsHidden()
                        Button("Reset") { store.textScale = 1 }
                            .disabled(store.textScale == 1)
                    }
                }
                LabeledContent("Maximum line width") {
                    HStack {
                        Slider(value: $store.textColumnWidth, in: VaultStore.textColumnWidths, step: 20)
                            .labelsHidden()
                            .frame(width: 180)
                        Text("\(Int(store.textColumnWidth)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                        Button("Reset") { store.textColumnWidth = 720 }
                            .disabled(store.textColumnWidth == 720)
                    }
                }
            }
            TypographySettings(typography: $store.typography)
        }
    }
}

/// The Notes page's typography: the body's size and line height, and each heading's size,
/// weight and slant, each shown in its own style.
private struct TypographySettings: View {
    @Binding var typography: Typography

    var body: some View {
        Section("Body text") {
            LabeledContent("Size") {
                HStack {
                    Text("\(Int(typography.bodySize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Size", value: $typography.bodySize, in: 10...28, step: 1)
                        .labelsHidden()
                }
            }
            LabeledContent("Line height") {
                HStack {
                    Text(typography.lineHeight.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Line height", value: $typography.lineHeight, in: 1...2.2, step: 0.05)
                        .labelsHidden()
                }
            }
            Text("The quick brown fox jumps over the lazy dog, and the line after it shows the spacing between lines of a paragraph.")
                .font(.system(size: typography.bodySize))
                .lineSpacing(typography.bodySize * (typography.lineHeight - 1))
                .foregroundStyle(.secondary)
        }

        Section("Headings") {
            ForEach(0..<6, id: \.self) { index in
                LabeledContent {
                    HStack {
                        HStack(spacing: 4) {
                            Text("\(Int(points(index).rounded())) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("Size", onIncrement: { setPoints(index, points(index) + 1) },
                                    onDecrement: { setPoints(index, points(index) - 1) })
                                .labelsHidden()
                        }
                        Picker("Weight", selection: $typography.headings[index].weight) {
                            ForEach(Typography.Weight.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .frame(width: 104, alignment: .trailing) // So the rows' controls line up.
                        Toggle("Italic", isOn: $typography.headings[index].italic)
                            .toggleStyle(.checkbox)
                    }
                } label: {
                    Text("Heading \(index + 1)")
                        .font(font(for: index))
                        .lineLimit(1)
                }
            }
        }

        Section {
            LabeledContent("Body text and headings") {
                Button("Restore Defaults") { typography = Typography() }
                    .disabled(typography == Typography())
            }
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

/// The vault's templates, kept in Obsidian's settings so both apps use the same ones: where
/// they are, which one daily notes start from, the templates themselves, and what can go in them.
private struct TemplatesSettings: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        let settings = store.settings
        let templates = store.templates
        // The settings are the headings, as on the Sidebar page.
        VStack(alignment: .leading, spacing: 20) {
            Setting("Location", isHeading: true) {
                Picker("Location", selection: Binding(get: { settings.templatesFolder },
                                                    set: { store.setObsidianSetting(.templatesFolder, to: $0) })) {
                    Text("None").tag("")
                    ForEach(store.folderPaths, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if !settings.templatesFolder.isEmpty {
                Setting("Current templates", isHeading: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        if templates.isEmpty {
                            Text("No templates yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(templates, id: \.url) { template in
                            HStack {
                                Text(template.name)
                                Spacer()
                                Button("Open") { open(template.url) }
                                    .buttonStyle(.link)
                            }
                            .frame(maxWidth: 320)
                        }
                        Button("New Template") { store.createTemplate() }
                            .padding(.top, 4)
                    }
                }
            }
            Setting("Daily notes start from", isHeading: true) {
                Picker("Daily notes start from", selection: Binding(get: { settings.dailyNotesTemplate },
                                                                    set: { store.setObsidianSetting(.dailyNotesTemplate, to: $0) })) {
                    Text("Nothing (an empty note)").tag("")
                    ForEach(templates, id: \.url) { template in
                        Text(template.name).tag(Self.path(of: template.url, in: store.root))
                    }
                    // One set in Obsidian outside the templates folder, kept.
                    if !settings.dailyNotesTemplate.isEmpty,
                       !templates.contains(where: { Self.path(of: $0.url, in: store.root) == settings.dailyNotesTemplate }) {
                        Text(settings.dailyNotesTemplate).tag(settings.dailyNotesTemplate)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Setting("Template variables", isHeading: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        variable("{{title}}", "The note's name")
                        variable("{{date}}", MomentFormat(settings.templatesDateFormat).string(from: Date()))
                        variable("{{time}}", MomentFormat(settings.templatesTimeFormat).string(from: Date()))
                        variable("{{date:dddd D MMMM}}", MomentFormat("dddd D MMMM").string(from: Date()))
                        variable("{{time:h:mm A}}", MomentFormat("h:mm A").string(from: Date()))
                    }
                    Setting("Date format, for {{date}}") {
                        FormatField(value: settings.templatesDateFormat, placeholder: "YYYY-MM-DD") {
                            store.setObsidianSetting(.templatesDateFormat, to: $0)
                        }
                    }
                    Setting("Time format, for {{time}}") {
                        FormatField(value: settings.templatesTimeFormat, placeholder: "HH:mm") {
                            store.setObsidianSetting(.templatesTimeFormat, to: $0)
                        }
                    }
                }
            }
        }
    }

    private func variable(_ name: String, _ example: String) -> some View {
        GridRow {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text(example)
                .foregroundStyle(.secondary)
        }
    }

    /// A template's path as Obsidian keeps it: from the vault, without ".md".
    static func path(of url: URL, in root: URL?) -> String {
        guard let root else { return url.deletingPathExtension().lastPathComponent }
        let full = url.deletingPathExtension().standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.deletingPathExtension().lastPathComponent
    }

    private func open(_ url: URL) {
        guard let window = store.activeWindow, let note = store.notes.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return NSSound.beep() }
        window.selection = note.id
        window.window?.makeKeyAndOrderFront(nil)
    }
}

/// A date or time format, saved when Return is pressed.
private struct FormatField: View {
    let value: String
    let placeholder: String
    let save: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField(placeholder, text: $draft)
            .frame(maxWidth: 200)
            .font(.system(.body, design: .monospaced))
            .onAppear { draft = value }
            .onChange(of: value) { draft = $0 }
            .onSubmit { save(draft) }
    }
}

/// A row's label and controls, centred on each other: the form's own style lines them up by
/// baseline, which leaves a label high beside a taller control, or a larger heading. The form
/// pads a row like this more than a toggle's, so the padding is taken back to match.
private struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            configuration.content
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, -4)
    }
}

/// One setting: its label, with its options below.
private struct Setting<Content: View>: View {
    let label: String
    /// A page's own heading (bold, in the text colour), on a page without sections.
    var isHeading = false
    @ViewBuilder let content: Content

    init(_ label: String, isHeading: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.isHeading = isHeading
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(isHeading ? .body.weight(.bold) : nil)
                .foregroundStyle(isHeading ? .primary : .secondary)
            content
        }
    }
}
