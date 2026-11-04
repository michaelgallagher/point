import IndexKit
import SwiftUI
import VaultKit

/// Search, shown in place of the page while the system's search field is in use: lists to pick
/// from, recent notes (which stand in for tabs) and bookmarks. Typing shows results in their
/// place. It's on the lists, not in a note, where the bottom bar finds in the note instead.
///
/// Its list is in the navigation stack's own view, over the pages and under the bars, not in
/// the page: the system moves the page by the bar's height as Search starts and ends, and in the
/// page the list moved with it, waited, and left the bar thinking the page was scrolled.
struct SearchScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    @State private var overlay = SearchOverlay()

    /// How long the system takes to put the page back under the bar as Search closes. The page
    /// waits for it, hidden, so it never slides into place.
    static let settle: TimeInterval = 0.2

    var body: some View {
        let dismiss = dismissSearch
        let overlay = overlay
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                SearchInstaller(overlay: overlay, list: AnyView(
                    SearchList(shows: isSearching, top: overlay.top) { overlay.opensNote = true; dismiss() }
                        .environmentObject(store)
                        .environmentObject(store.search)))
            }
            .onChange(of: isSearching) { _, searching in
                if searching { overlay.open() } else { overlay.close() }
            }
            // Over a note, Search is up as it appears. Once the list has its stack.
            .onAppear { if isSearching { DispatchQueue.main.async { overlay.open() } } }
            .onDisappear {
                // Over a note, Search goes as it closes.
                if !overlay.host.view.isHidden { overlay.close() }
                overlay.remove()
            }
    }
}

/// Search's list in the navigation stack's view, and the fades between it and the page.
@MainActor private final class SearchOverlay {
    weak var navigation: UINavigationController?
    let host = UIHostingController(rootView: AnyView(EmptyView()))
    /// Search is closing to open a note.
    var opensNote = false
    /// Room at the top of the list, for the clock.
    let top = TopInset()

    init() {
        host.view.backgroundColor = .clear
        host.view.isHidden = true
    }

    /// The stack's view, and its view of pages, which the list goes over.
    private var places: (stack: UIView, pages: UIView)? {
        guard let stack = navigation?.view, var pages = navigation?.topViewController?.view else { return nil }
        while let superview = pages.superview, superview !== stack { pages = superview }
        return pages.superview === stack ? (stack, pages) : nil
    }

    /// The page's list, found by looking: the biggest scroll view on the page.
    private var pageList: UIScrollView? {
        guard let page = navigation?.topViewController?.view else { return nil }
        var queue = [page], best: UIScrollView?
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scroll = view as? UIScrollView, scroll.bounds.height > (best?.bounds.height ?? 0) { best = scroll }
            queue += view.subviews
        }
        return best
    }

    /// How far the page's list was scrolled from its top as Search started.
    private var scrolled: CGFloat?

    /// The page's list where it was: the system puts the bar back a fraction of a point out, and
    /// the bar then showed its background, as if the page were scrolled.
    private func restoreScroll() {
        guard let scrolled, let list = pageList else { return }
        let y = scrolled - list.adjustedContentInset.top
        if abs(list.contentOffset.y - y) > 0.01 { list.contentOffset.y = y }
    }

    func open() {
        if let list = pageList { scrolled = list.contentOffset.y + list.adjustedContentInset.top }
        guard let (stack, pages) = places else { return }
        // The page goes at once, under a picture of it fading out: the system takes the bar out
        // of the page's safe area as Search starts, and the page jumped up.
        var below: UIView = pages
        if let page = navigation?.topViewController?.view, let still = page.snapshotView(afterScreenUpdates: false) {
            still.frame = page.convert(page.bounds, to: stack)
            still.isUserInteractionEnabled = false
            stack.insertSubview(still, aboveSubview: pages)
            below = still
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                still.alpha = 0
            } completion: { _ in
                still.removeFromSuperview()
            }
        }
        let list = host.view!
        stack.insertSubview(list, aboveSubview: below)
        list.frame = stack.bounds
        list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        list.isHidden = false
        // Not a child of any view controller, it has no safe area, and its list started under
        // the clock.
        top.inset = stack.safeAreaInsets.top
        list.alpha = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            list.alpha = 1
        }
        fadeBar(out: true)
    }

    func close() {
        // Once the bar is back, and again after the page has faded in, in case it was still moving.
        for delay in [SearchScreen.settle, SearchScreen.settle + 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.restoreScroll() }
        }
        let list = host.view!
        if opensNote {
            // A note is opening over it, and the bar is the note's.
            opensNote = false
            list.isHidden = true
            fadeBar(out: false, after: 0)
            return
        }
        // A picture of the list, as it was, stays until the page is back, and they cross: the
        // list itself empties at once.
        if let stack = list.superview, let still = list.snapshotView(afterScreenUpdates: false) {
            still.frame = list.frame
            still.isUserInteractionEnabled = false
            stack.insertSubview(still, aboveSubview: list)
            UIView.animate(withDuration: 0.25, delay: SearchScreen.settle, options: .curveEaseOut) {
                still.alpha = 0
            } completion: { _ in
                still.removeFromSuperview()
            }
        }
        list.isHidden = true
        fadeBar(out: false)
    }

    /// Takes the list out. The bar comes back now, if closing isn't bringing it back already.
    func remove() {
        host.view.removeFromSuperview()
        host.view.isHidden = true
        fadeBar(out: false, after: 0)
    }

    /// The bar's contents (title, Back, Settings) fade out with the page, in place, and back.
    private func fadeBar(out: Bool, after delay: TimeInterval = SearchScreen.settle) {
        guard let navigationBar = navigation?.navigationBar, navigationBar.alpha != (out ? 0 : 1) else { return }
        UIView.animate(withDuration: 0.25, delay: out ? 0 : delay, options: [.curveEaseOut, .beginFromCurrentState]) {
            navigationBar.alpha = out ? 0 : 1
        }
    }
}

/// Finds the navigation stack of the page it's on, for Search's list, and keeps the list's view
/// up to date.
private struct SearchInstaller: UIViewRepresentable {
    let overlay: SearchOverlay
    let list: AnyView

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.overlay = overlay
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        overlay.host.rootView = list
    }

    final class FinderView: UIView {
        weak var overlay: SearchOverlay?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { KeyboardWarmUp.soon(in: window) }
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let navigation = (next as? UIViewController)?.navigationController {
                    overlay?.navigation = navigation
                    return
                }
                responder = next
            }
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

/// Search's list. Grouped, on the page's own background, as the lists below it are.
@Observable private final class TopInset {
    var inset: CGFloat = 0
}

private struct SearchList: View {
    @EnvironmentObject private var store: PhoneStore
    @EnvironmentObject private var search: PhoneSearch
    let shows: Bool
    let top: TopInset
    let dismissSearch: () -> Void

    private var query: String { search.text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            if shows {
                if query.isEmpty {
                    lists
                } else {
                    results
                }
            }
        }
        .contentMargins(.top, top.inset, for: .scrollContent)
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
            dismissSearch()
            store.linkedRoute = .note(id)
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

/// The page, which fades out as Search starts (a picture of it fades instead: see
/// `SearchOverlay`), and back as it ends.
///
/// While Search is up, the system takes the navigation bar out of the page's safe area, and
/// puts it back as Search closes, moving the page. So, closing, the page waits, hidden, for it
/// to settle before fading in.
struct PageOverSearch<Content: View>: View {
    @Environment(\.isSearching) private var isSearchingHere
    /// Whether Search is up, when it isn't the page's own (a note's is beside it).
    private let searchingBeside: Bool?
    private let content: Content

    init(searching: Bool? = nil, @ViewBuilder content: () -> Content) {
        searchingBeside = searching
        self.content = content()
    }

    private var isSearching: Bool { searchingBeside ?? isSearchingHere }

    @State private var hidden = false
    /// Whether Search is up, for the delayed fade-in to check: it may have opened again.
    @State private var searching = false

    var body: some View {
        content
            // At once as Search starts: Search shows a picture of it fading out instead.
            .opacity(isSearching || hidden ? 0 : 1)
            // Also keeps the system from moving the page's list under Search as it starts.
            .allowsHitTesting(!(isSearching || hidden))
            .accessibilityHidden(isSearching || hidden)
            .onChange(of: isSearching) { _, searching in
                self.searching = searching
                if searching {
                    hidden = true
                } else {
                    // Not an animation's delay: with one, the page showed at once, for a frame
                    // or two, before fading in.
                    DispatchQueue.main.asyncAfter(deadline: .now() + SearchScreen.settle) {
                        guard !self.searching else { return }
                        withAnimation(.easeOut(duration: 0.25)) { hidden = false }
                    }
                }
            }
    }
}
