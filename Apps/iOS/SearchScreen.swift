import IndexKit
import SwiftUI
import VaultKit

/// Search: Point's own, not the system's `.searchable`. The bar's search field (`SearchCapsule`)
/// opens Search (`SearchLayer`) over everything, in place: its field opens out from the bar's and
/// rides up with the keyboard, and its lists (recent notes and bookmarks, or results as you type)
/// fade in over the page. Nothing under it moves. With the system's field, iOS moved the field
/// from the bar to over the keyboard and took the bar out of the page's safe area as Search
/// started and ended, moving the page, and hiding that meant cuts and waits.
///
/// Search's field is focused before it starts to open, and it opens once the keyboard is on its
/// way: bringing up the keyboard holds up the main thread, where SwiftUI animates.

/// How Search opens and closes.
private enum SearchMotion {
    static let open = Animation.smooth(duration: 0.3)
    /// The field's going back into the bar's, as long as the fade out, so Search goes once
    /// both are done.
    static let close = Animation.smooth(duration: 0.4)
    /// Softer than the field's movement: longer, and the fade out easing in and out.
    static let fadeIn = Animation.easeOut(duration: 0.55)
    static let fadeOut = Animation.easeInOut(duration: 0.4)
    /// The field's height, the system's.
    static let fieldHeight: CGFloat = 48
    /// Search's field's room at each side, beside its X and over the keyboard, as the system's.
    static let margin: CGFloat = 12
    /// The room the bar leaves between its glass and an item in it.
    static let barInset: CGFloat = 5

    /// The bar's measurements, the system's, as measured from its own search field: its room
    /// at each side, its round buttons, and the space between them.
    private static var barMargin: CGFloat { isIOS27 ? 27.67 : 28 }
    private static var barButton: CGFloat { isIOS27 ? 48.67 : 48 }
    private static var barGap: CGFloat { isIOS27 ? 11.33 : 12 }

    /// The width of the bar's field's contents, inside the bar's glass, filling the bar.
    static func barFieldWidth(in windowWidth: CGFloat, besides: Int) -> CGFloat {
        let glass = windowWidth - 2 * barMargin - CGFloat(besides) * (barButton + barGap)
        return max(0, glass - 2 * barInset)
    }

    /// The room inside a search field before its magnifying glass, and after it.
    static var fieldPadding: CGFloat { isIOS27 ? 12.33 : 18 }
    static var iconGap: CGFloat { isIOS27 ? 8.67 : 8 }
    static var iconWeight: Font.Weight { isIOS27 ? .medium : .regular }

    /// The system's search field's colours: its magnifying glass black on iOS 27, grey before.
    static var iconColor: Color { isIOS27 ? Color(.label) : Color(.secondaryLabel) }
    static var placeholderColor: Color {
        isIOS27 ? Color(UIColor { $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(white: 0.612, alpha: 1) })
            : Color(.secondaryLabel)
    }

    private static let isIOS27: Bool = {
        if #available(iOS 27, *) { return true }
        return false
    }()
}

/// A search field's look: the system's, a capsule of Liquid Glass with a magnifying glass. The
/// bar's and Search's are the same, so one opens out from the other. The bar's glass is the
/// bar's own, as the system's field's was; Search's is its own.
private struct SearchFieldLook<Content: View>: View {
    var glass = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: SearchMotion.iconGap) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(SearchMotion.iconWeight))
                .imageScale(.medium)
                .foregroundStyle(SearchMotion.iconColor)
            content
        }
        // The bar puts its own room around its items, its glass's edge beyond them.
        .padding(.horizontal, glass ? SearchMotion.fieldPadding : SearchMotion.fieldPadding - SearchMotion.barInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: glass ? SearchMotion.fieldHeight : SearchMotion.fieldHeight - 2 * SearchMotion.barInset)
        .contentShape(Capsule())
        .glassEffect(glass ? .regular.interactive() : .identity, in: .capsule)
    }
}

/// The bar's search field, at rest: tapping it opens Search, from where it is. Hidden while
/// Search is up, whose field takes its place.
struct SearchCapsule: View {
    @EnvironmentObject private var search: PhoneSearch
    /// How many buttons are beside it in the bar.
    let besides: Int
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            search.present(from: frame)
        } label: {
            SearchFieldLook(glass: false) {
                Text("Search")
                    // The bar's items are semibold; a search field's placeholder isn't.
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(SearchMotion.placeholderColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The system's field filled the bar; an item of Point's own is only as wide as
            // its contents on iOS 27, so it's given the room.
            .frame(width: search.windowWidth > 0 ? SearchMotion.barFieldWidth(in: search.windowWidth, besides: besides) : nil)
        }
        .buttonStyle(.plain)
        .opacity(search.isShown ? 0 : 1)
        // Where the bar's glass is, for Search's field to open out from.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global).insetBy(dx: -SearchMotion.barInset, dy: -SearchMotion.barInset)
        } action: { frame = $0 }
        .accessibilityLabel("Search")
        .accessibilityAddTraits(.isSearchField)
    }
}

/// Search, over the whole app while it's up. Watches search alone, so typing redraws only this.
struct SearchLayerHost: View {
    @EnvironmentObject private var search: PhoneSearch

    var body: some View {
        ZStack {
            if search.isShown { SearchLayer() }
        }
        // The window's size, while empty too (it takes no touches then).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Touches go through to the app: a UIKit view in SwiftUI takes them otherwise.
        .background { WindowFinder().allowsHitTesting(false) }
        // The window's width, for the bar's field.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { search.windowWidth = $0 }
    }
}

/// Search's field, its X, and its lists, opening out from the bar's field and closing back
/// into it.
private struct SearchLayer: View {
    @EnvironmentObject private var store: PhoneStore
    @EnvironmentObject private var search: PhoneSearch
    @State private var expanded = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let origin = geometry.frame(in: .global).origin
            // The keyboard is up when it's in the safe area's bottom.
            let keyboardUp = insets.bottom > 100
            // The screen's width and height.
            let width = origin.x + geometry.size.width + insets.trailing
            let height = keyboardUp ? 0 : origin.y + geometry.size.height + insets.bottom
            let from = search.from ?? defaultFrame(width: width, height: height)
            ZStack(alignment: .bottom) {
                SearchList(close: close)
                    .opacity(expanded ? 1 : 0)
                    // The page's own background, under the status bar too.
                    .background(Color(.systemGroupedBackground).opacity(expanded ? 1 : 0).ignoresSafeArea())
                    // The fade, longer than the field's movement going in, so it's gentle.
                    .animation(expanded ? SearchMotion.fadeIn : SearchMotion.fadeOut, value: expanded)
                HStack(spacing: expanded ? SearchMotion.margin : 0) {
                    field
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .imageScale(.large)
                            .frame(width: SearchMotion.fieldHeight, height: SearchMotion.fieldHeight)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .scaleEffect(expanded ? 1 : 0.2)
                    .frame(width: expanded ? SearchMotion.fieldHeight : 0)
                    .opacity(expanded ? 1 : 0)
                    .accessibilityLabel("Close Search")
                }
                .padding(.leading, expanded ? SearchMotion.margin : from.minX - origin.x)
                .padding(.trailing, expanded ? SearchMotion.margin : width - from.maxX - insets.trailing)
                // At rest, where the bar's field is, measured from the safe area's bottom (the
                // keyboard's top when it's up); with the keyboard, just above it.
                .offset(y: keyboardUp ? -SearchMotion.margin : from.maxY - (origin.y + geometry.size.height))
                .opacity(search.from == nil && !expanded ? 0 : 1)
            }
        }
        .onAppear(perform: open)
        // The keyboard is about to move: its work is done, and its animation committed.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            DispatchQueue.main.async { expand() }
        }
    }

    private var field: some View {
        SearchFieldLook {
            TextField("Search", text: $search.text, prompt: Text("Search").foregroundStyle(SearchMotion.placeholderColor))
                .focused($focused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .onSubmit { focused = false }
            if !search.text.isEmpty {
                Button {
                    search.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
    }

    /// Where the field is at rest when Search opens from elsewhere (a note's map): full width,
    /// where the bar is. It fades in there instead.
    private func defaultFrame(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: SearchMotion.margin, y: height - 28 - SearchMotion.fieldHeight,
               width: width - 3 * SearchMotion.margin - SearchMotion.fieldHeight, height: SearchMotion.fieldHeight)
    }

    /// The keyboard first, then Search's movement. SwiftUI animates on the main thread, and
    /// bringing up the keyboard holds the main thread up (about 150 ms on an iPhone 13): begun
    /// first, the fade and the field stopped part way while it did, and jumped on. So Search
    /// waits, looking just like the bar, until the keyboard has done that work, and then the
    /// field, the fade and the keyboard all move together.
    private func open() {
        focused = true
        // Without a keyboard to wait for (a hardware keyboard), not for long.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expand() }
    }

    private func expand() {
        guard !expanded, search.isShown else { return }
        withAnimation(SearchMotion.open) { expanded = true }
    }

    private func close() {
        focused = false
        withAnimation(SearchMotion.close) {
            expanded = false
        } completion: {
            search.isShown = false
            search.text = ""
        }
    }
}

/// Finds the app's window, for the keyboard's warm-up.
private struct WindowFinder: UIViewRepresentable {
    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {}

    final class FinderView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { KeyboardWarmUp.soon(in: window) }
        }
    }
}

/// The keyboard, loaded once, out of sight, soon after launch: the first time it's needed, iOS
/// loads it then, and Search took far longer to open the first time than after.
@MainActor private enum KeyboardWarmUp {
    private static var done = false

    static func soon(in window: UIWindow) {
        guard !done else { return }
        done = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak window] in
            guard let window, UIApplication.shared.applicationState == .active,
                  !window.containsFirstResponder else { return }
            let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
            field.alpha = 0
            field.autocorrectionType = .no
            window.addSubview(field)
            // Taken away again before the keyboard can be drawn.
            field.becomeFirstResponder()
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
    }
}

private extension UIView {
    var containsFirstResponder: Bool { isFirstResponder || subviews.contains { $0.containsFirstResponder } }
}

/// Search's lists. Grouped, on the page's own background, as the lists below it are.
private struct SearchList: View {
    @EnvironmentObject private var store: PhoneStore
    @EnvironmentObject private var search: PhoneSearch
    let close: () -> Void

    private var query: String { search.text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            if query.isEmpty {
                lists
            } else {
                results
            }
        }
        .scrollDismissesKeyboard(.immediately)
        // Room for the search field, over the keyboard.
        .contentMargins(.bottom, 72, for: .scrollContent)
    }

    @ViewBuilder private var lists: some View {
        let recent = store.recentlyOpened(limit: 5, excluding: nil)
        if !recent.isEmpty {
            Section("Recent") {
                ForEach(recent) { note in row(note.id) { NoteRow(title: note.title) } }
            }
        }
        if !store.bookmarks.isEmpty {
            Section("Bookmarks") {
                ForEach(store.bookmarks, id: \.path) { bookmark in
                    if let note = store.note(bookmark.path) {
                        row(note.id) { NoteRow(title: bookmark.title ?? note.title) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if let results = search.results {
            Section {
                ForEach(results) { result in row(result.id, searchedFor: query) { SearchRow(result: result) } }
            }
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// A note to open, found by searching for `query` if given (search learns from it).
    private func row<Label: View>(_ id: Note.ID, searchedFor query: String? = nil, @ViewBuilder label: () -> Label) -> some View {
        Button {
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty { store.resultPicked(id, for: query) }
            store.linkedRoute = .note(id)
            close()
        } label: { label() }
            .foregroundStyle(.primary)
    }
}

/// A search result: its title, and the matching text with the matches in bold.
private struct SearchRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .fontWeight(result.matchedTitle ? .semibold : .regular)
            if let snippet = result.snippet {
                // On as few lines as it fits: a line break in the note would leave a line empty.
                Text(Self.marked(snippet.split(whereSeparator: \.isNewline).joined(separator: " ")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// The snippet with each match (between `SearchResult.matchStart` and `matchEnd`) bold.
    static func marked(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var bold = false
        var run = ""
        func flush() {
            var part = AttributedString(run)
            if bold { part.inlinePresentationIntent = .stronglyEmphasized }
            result += part
            run = ""
        }
        for character in snippet {
            if character == SearchResult.matchStart || character == SearchResult.matchEnd {
                flush()
                bold = character == SearchResult.matchStart
            } else {
                run.append(character)
            }
        }
        flush()
        return result
    }
}
