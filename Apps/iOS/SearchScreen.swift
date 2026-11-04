import IndexKit
import SwiftUI
import VaultKit

/// Search, shown in place of the page while the system's search field is in use: lists to pick
/// from, recent notes (which stand in for tabs) and bookmarks. Typing shows results in their
/// place. It's on the lists, not in a note, where the bottom bar finds in the note instead.
///
/// It's behind the page, which fades to show it (`PageOverSearch`), and its list is hosted on
/// its own: in the page's view, the navigation bar went with whichever list was in front or put
/// in last, so the page lost its place under the bar and jumped.
struct SearchScreen: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    @State private var bar = WeakBar()
    @State private var host = WeakHost()
    /// Search's list settles under the bar too, as Search starts, so it comes in once it has.
    @State private var listShown = false

    /// How long the system takes to put the page back under the bar as Search closes. The page
    /// waits for it, hidden, so it never slides into place.
    static let settle: TimeInterval = 0.2

    var body: some View {
        let dismiss = dismissSearch
        let host = host
        SeparatelyHosted(content: SearchList(shows: isSearching, dismissSearch: { host.opensNote = true; dismiss() }).environmentObject(store), host: host)
            .ignoresSafeArea()
            .opacity(listShown ? 1 : 0)
            .accessibilityHidden(!isSearching)
            .background { NavigationBarFinder(bar: bar) }
            // The page's navigation bar (its title, Back, Settings) fades out in step, and back,
            // in its place, so nothing under Search moves.
            .onChange(of: isSearching) { _, searching in
                if searching {
                    fadeOutPage()
                    listShown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) {
                        withAnimation(.easeOut(duration: 0.2)) { listShown = true }
                    }
                    fadeBar(out: true)
                } else if host.opensNote {
                    // A note is opening over it: no picture to stay behind, and the bar is the note's.
                    host.opensNote = false
                    fadeBar(out: false, after: 0)
                } else {
                    fadeOutList()
                    fadeBar(out: false)
                }
            }
            .onDisappear { fadeBar(out: false, after: 0) }
    }

    /// The page, as it was, fading out as Search starts: the system takes the bar out of the
    /// page's safe area at once, and the page jumped up. The page itself goes at once, under this.
    private func fadeOutPage() {
        guard let navigationBar = bar.value, let stack = navigationBar.superview,
              let page = bar.navigation?.topViewController?.view,
              let still = page.snapshotView(afterScreenUpdates: false) else { return }
        still.frame = page.convert(page.bounds, to: stack)
        still.isUserInteractionEnabled = false
        stack.insertSubview(still, belowSubview: navigationBar)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            still.alpha = 0
        } completion: { _ in
            still.removeFromSuperview()
        }
    }

    /// Search's list, closing, as it was, fading out as the page fades back in: the system moves
    /// what's under the bar as it puts the bar back, and the list jumped.
    private func fadeOutList() {
        guard let view = host.value?.view, let navigationBar = bar.value, let stack = navigationBar.superview,
              let still = view.snapshotView(afterScreenUpdates: false) else { return }
        // In the navigation stack's view, under its bars, not beside the list: the system moves
        // the page and Search together.
        still.frame = view.convert(view.bounds, to: stack)
        still.isUserInteractionEnabled = false
        stack.insertSubview(still, belowSubview: navigationBar)
        UIView.animate(withDuration: 0.25, delay: Self.settle, options: .curveEaseOut) {
            still.alpha = 0
        } completion: { _ in
            still.removeFromSuperview()
        }
    }

    private func fadeBar(out: Bool, after delay: TimeInterval = Self.settle) {
        guard let navigationBar = bar.value, navigationBar.alpha != (out ? 0 : 1) else { return }
        UIView.animate(withDuration: 0.25, delay: out ? 0 : delay, options: [.curveEaseOut, .beginFromCurrentState]) {
            navigationBar.alpha = out ? 0 : 1
        }
    }
}

/// Search's list. Grouped, on the page's own background, as the lists below it are.
private struct SearchList: View {
    @EnvironmentObject private var store: PhoneStore
    let shows: Bool
    let dismissSearch: () -> Void

    private var query: String { store.searchText.trimmingCharacters(in: .whitespaces) }

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
        if let results = store.searchResults {
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

/// The page, over Search, which fades out to show it, and back. Search is behind it because the
/// large title goes with the list in front: Search's, put over the page, took it, and the page
/// jumped up without it. This way the title stays, and fades with the page.
///
/// While Search is up, the system takes the navigation bar out of the page's safe area, and
/// puts it back as Search closes, moving the page. So, closing, the page waits, hidden, for it
/// to settle before fading in.
struct PageOverSearch<Content: View>: View {
    @Environment(\.isSearching) private var isSearching
    @ViewBuilder let content: Content

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

/// A view in a hosting controller of its own.
private struct SeparatelyHosted<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let host: WeakHost

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        host.value = controller
        return controller
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        host.rootView = content
    }
}

/// Search's hosting controller.
private final class WeakHost {
    weak var value: UIViewController?
    /// Search is closing to open a note.
    var opensNote = false
}

/// The navigation bar of the page Search is under.
private final class WeakBar {
    weak var navigation: UINavigationController?
    var value: UINavigationBar? { navigation?.navigationBar }
}

/// Finds the navigation bar of the page it's on.
private struct NavigationBarFinder: UIViewRepresentable {
    let bar: WeakBar

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.bar = bar
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {}

    final class FinderView: UIView {
        var bar: WeakBar?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let navigation = (next as? UIViewController)?.navigationController {
                    bar?.navigation = navigation
                    return
                }
                responder = next
            }
        }
    }
}
