import IndexKit
import SwiftUI
import VaultKit

/// A folder's or tag's page, where notes open (with the tree and folder pages layout, a
/// trial): its name, the folders or tags inside it, then its notes as a list note's table. Each
/// opens where it is (⌘-click in a new tab, ⌥-click on the other side, as links do). Opened in
/// a tab like a note, so back and forward go through pages as well.
struct FolderPage: View {
    let place: SidebarPlace
    @ObservedObject var model: VaultModel
    @ObservedObject var store: VaultStore
    let paneID: VaultModel.NotePane.ID

    /// How many notes show, before "Show more": a folder of thousands mustn't slow the page.
    @State private var shownCount = Self.firstRows
    private static let firstRows = 100

    var body: some View {
        let subplaces = model.subplaces(of: place)
        let ids = model.notes(in: place).map(\.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.pageTitle(place))
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                if !subplaces.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(subplaces, id: \.key) { subplace in
                            SubplaceRow(place: subplace, model: model) { destination in
                                model.open(subplace.pageID, inPane: paneID, as: destination)
                            }
                        }
                    }
                }
                if ids.isEmpty {
                    if subplaces.isEmpty {
                        Text("No notes here.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ListResults(list: Self.list, listID: place.pageID, ids: ids, limit: shownCount,
                                moreLabel: "Show \(min(ids.count - shownCount, 500)) more", more: { shownCount += 500 },
                                model: model, store: store, paneID: paneID, write: nil)
                        .font(.callout)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: store.textColumnWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: place) { _ in shownCount = Self.firstRows }
    }

    /// The table's columns: the title, and when each note was last edited.
    private static let list = ListDefinition(columns: ["date edited"])
}

/// A folder or tag inside a page's place: its icon, name and how many notes it holds.
private struct SubplaceRow: View {
    let place: SidebarPlace
    @ObservedObject var model: VaultModel
    let open: (VaultModel.LinkDestination) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbol(for: place))
                .foregroundStyle(place.isTag ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 18)
            Text(model.title(for: place))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(model.noteCount(of: place))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? TopBar.selectedTabColor : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags.intersection([.command, .option])
            open(modifiers.contains(.option) ? .otherSide : modifiers.contains(.command) ? .newTab : .here)
        }
    }
}
