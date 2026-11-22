# Browsing folders in the palette

22 November 2026. Branch `palette-browse`.

The ⌘E explorer was a second palette, two columns of places and notes, used mostly to browse folders with the sidebar hidden. It's now part of the ⌘F palette, one list at a time, and the palette is wider.

## How it works

- **Browse Folders (⌘E,** or Browse Folders in the palette's suggestions) opens the palette at the place last browsed. A trail under the field shows where (vault › Projects › Work), each part a click away.
- **At the vault's top:** Pinned, Types, Folders (Templates and Attachments first, as in the sidebar), Tags (unless the sidebar hides them), then the notes at the top level.
- **In a folder:** its folders, then its notes, in the list's order. **In a tag:** the tags under it, then its notes. A type or a pinned place: its notes.
- **Keys:** ↑↓ move; Return (or → at the end of what's typed) goes into a place, and opens a note (⌘Return in a new tab); ← at the start (or ⌫ with nothing typed) goes up a level, the place just left highlighted. Escape closes. Each place shows its count and a chevron.
- **Typing filters the place,** finding folders and tags anywhere inside it, not only those directly in it; one found deeper shows the folders between under its name (Clients, under it Work).
- **In Search Vault (⌘F),** folders whose names match come up in their own section, up to three, with where they are. A folder whose name matches better than any note's title comes first, so typing a folder's name and Return goes into it. → goes into a highlighted folder too.
- **A folder clicked in a note's path,** or a tag clicked in a note, with the sidebar hidden, opens the palette browsing it, as the explorer did.
- **On a start page,** ⌘E and ⌘F switch the page between searching and browsing, as before; ← at the vault's top goes back to searching.

## Wider

- The floating palette is up to 680 points wide (was 540), and the start page's column too (was 600).
- It's never wider than the side of a split it's over, less 40 points, nor the window; but it keeps at least 420 points where the window has them, so a very narrow side doesn't make it unusable.

## Dropped

- **Dragging** notes and folders onto folders in the explorer. Several notes can now be picked in the list and moved together (⌘-click, then Move to Folder or a drag), and Move Note… in the palette moves the note being viewed.
- **Two columns,** and the notes of the highlighted place showing beside it. One list leaves more room for long names and works in a narrow side.

## Kept

- The shortcut's ID in Settings is unchanged (`searchVault`), so a shortcut changed there still works; the menu item is now Edit › Browse Folders.

## Tried

The debug build on a test vault with nested folders and a nested tag: browsing the top, a folder two levels down, filtering a folder for one deeper inside it, searching for a folder from ⌘F (first, and under the notes before it was moved up), and the palette over one side of a split, fitting it. Keys can't be pressed in a window launched from the shell; they weren't tried by hand.
