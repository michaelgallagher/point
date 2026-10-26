# Exploration: no visible tabs (branch `no-visible-tabs`)

Part of [the plan](../PLAN.md).

**The question** (Mike, 25 October 2026). Can Point keep several notes open without showing tabs at all? The header shows only where you are, and you reach the other open notes through the command palette and a small menu of tabs. The model doesn't change (windows, sides, tabs and their history); only how tabs are shown and reached does. Designed and built 25 October 2026 (see "Built" below).

**The header (one per side of a split, as now):**
1. **Left to right:** back and forward, then the note's path. On the right: the tab button (`square.stack`), then Split, or Close This Side with a split. The New Tab (+) button goes; New Tab moves into the tab menu (and ⌘T stays).
2. **The path** is the folders inside the vault, then the note's name: `Projects / Point / Tabs idea`, without `.md`. Folders are dimmed; the note's name is in full weight. A note at the vault's root shows only its name; a start page shows nothing (or "New Tab").
3. **When it doesn't fit,** the folders in the middle fold into `…` one at a time, keeping the first folder and the note's name (`Projects / … / Point / Tabs idea`, then `Projects / … / Tabs idea`). Only then is the note's name cut, in its middle.
4. **Renaming:** clicking the note's name in the header renames it, as the title at the top of the page does (Return or clicking away renames, Escape puts it back).
5. **Clicking a folder** in the path shows it: in the sidebar if it's showing, otherwise in the ⌘E explorer, opened at that folder.
6. **With a split,** each side's header shows its own note; the other side's is dimmed, as now.
7. **The page loses its path:** the path above the title at the top of each note (item 4 of the minimal exploration) goes, since the header shows it. The page starts with the title.

**The tab menu (`square.stack`):**
1. **Always shown,** but dimmed and disabled with only one tab on that side, so the header never shifts.
2. **Lists that side's tabs only,** in tab order (the order ⇧⌘[ / ⇧⌘] follow, set by dragging rows), the current one marked. Clicking a row goes to that tab.
3. **Closing:** an × on each row on hover. Right-click a row: Close Tab, Close Other Tabs, Move to Other Side, Merge Both Sides into Tabs (the actions the tabs' own menu has today).
4. **A New Tab row** at the bottom.
5. **Dragging rows:** drag a row up or down to reorder the tabs. Drag it out of the menu onto the page or onto the other side's header to split or move it, as dragging a tab does today (an unsplit window's left or right half splits, the other side's page takes it as its current tab, a side left without tabs closes).
6. **Keyboard:** ⇧⌘T opens it (⇧⌘O at first; changed 25 October 2026, and Today's Note lost ⇧⌘T) for the active side. ↑↓ move, Return goes to the tab, ⌫ or ⌘W closes the highlighted tab, Escape closes the menu.

**The command palette:**
1. **Unchanged:** open tabs are listed first, marked "Open".
2. **Tabs only:** ⌃Tab opens the palette listing just the open tabs (both sides), most recent first, with the one before the current note highlighted, so ⌃Tab then Return flips between two notes. Typing filters. (⌃Tab normally moves the keyboard out of a text view; Point takes it over, as Safari does.)
3. **Closing from the palette:** ⌘⌫ on an "Open" row closes that tab, and the palette stays open.

**Unchanged:** ⇧⌘[ / ⇧⌘] move to the previous and next tab; ⌘W, ⌘T, ⌃⌘T and ⌘Z (reopen the tab just closed) work as now.

**Settled (25 October 2026):** the page's own path goes (header item 7); the header's folders open in the sidebar or explorer (header item 5); the tab menu keeps tab order rather than most recent first (tab menu item 2).

**Built (25 October 2026, uncommitted on `no-visible-tabs`):**
- **Where:** `TopBars.swift` (`PaneTopBar`, `PanePath`, `TabListButton`, `TabMenu`); `VaultModel` (`tabMenuPane`, `toggleTabMenu`, `recentTabs`, `goToTab(of:)`, `closeTab(of:)`, `reveal(folder:)`, palette mode `.tabs`); `CommandPalette` (the tabs list, ⌘⌫). The tab row (`NoteTabs`) and `NotePath` are gone, and so is the Show File Path setting (Settings, View menu, palette).
- **Small additions:** a start page's header says "New Tab", dimmed. "…" shows the folded folders as a tooltip. The list closes itself when a side is down to one tab, so ⌫ can't go on to close the window. Reordering in the list doesn't change the note shown. View has Show Tab List (⇧⌘T) and Switch to Tab… (⌃Tab); both are in the palette and the shortcuts sheet.
- **Checked in the app** (debug build, a test vault with deep folders): the path folding as the window and sidebar change; clicking a folder (opens the explorer there with the sidebar hidden); renaming from the header; the list by mouse (click, ×, drag to reorder, drag onto the page to split) and by keys (⇧⌘T, arrows, Return, ⌫); ⌃Tab (opens on the note before, again moves down) and ⌘⌫ in it; the other side's path dimmed in a split.
- **Fixed along the way:** a crash when closing a tab before the current one (the recent-tabs record read a side mid-change); the list's × now takes clicks through the row's AppKit mouse area, because a SwiftUI button there missed them; after a drag, rows checked the pointer against the whole list's visible area, which left every row shaded.
- **Not checked yet:** clicking a folder with the sidebar showing, right-click menus on rows, dragging a row onto the other side's bar, macOS before 26.

**Mike's notes (25 October 2026), built the same day:**
- **Properties:** the summary's chevron no longer hangs in the margin; it lines up with the title.
- **Sidebar sections fold per place:** folding Notes at the top level leaves it open inside a folder. Saved as place and section (`folder:Projects|Notes`); a plain name from before counts as the top level.
- **Folders and tags unfold from a chevron after their name,** like the section labels, so their icons line up with the section label. There's no arrow column any more. The table works out where the chevron is from the name's width, since it takes the clicks.
- **Folder icons are blue** (the accent colour), as in Finder, in both sidebar layouts; tags stay grey.
- **Header buttons:** Split, Close This Side and the tab button are 36 points, like the back and forward capsule and the sidebar button. The tab button shows how many tabs the side has (a small badge, from two).
- **⇧⌘T** shows the tab list; Today's Note has no shortcut for now.
- **Gaps in the header:** with the sidebar hidden, the sidebar button and the back and forward arrows are as far apart as the bar's own buttons (about 7.5 points), measured from pictures of the window. With the sidebar hidden, a side's bar starts 8 points past the system's sidebar button, measured where it actually is (its round toolbar platter, found by class; it sits in different places in different windows, so a fixed offset was right in one window and 4 points off in another). It's measured again when the window resizes, the sidebar shows or hides, or the button moves; if it can't be found, the bar starts 45 points past the window buttons. Beside the sidebar it starts 8 points past its edge, so the arrows never touch it (Mike's choice); that leaves about 16 points to the system's sidebar button, which sits inside the sidebar.
- **The edge under the bars:** the hairline and the blur show only once the note scrolls under the bar. The hairline is one device pixel of the separator colour. The blur is now a real one: a Core Image Gaussian blur (radius 8) on what's behind a view inside the scroll view, clipped to the bar (unclipped, it blurred the whole page), under the page's colour at 45%. The within-window material it replaces either hid the text or, faded, showed it unblurred (`MarkdownScrollView`).
- **Checked:** in pictures of the debug build (the sidebar, the badge, folding per place, the scrolled edge). Not tried by hand: clicking the new chevrons, the blur's strength against the system's.

**Mike's list (25 October 2026, third), built the same day:**
- **Bookmarks:** a bookmark button joined with the tab button in one glass capsule (filled and blue when set), File › Add Bookmark, the palette, and a note's right-click menu. Kept per vault by note ID (`VaultStore.bookmarks`), following renames and moves; a note gone is just not listed. Bookmarks is a place like All Notes and Trash (`SidebarPlace.bookmarks`), second of the three at the top of both sidebar layouts, listing the bookmarked notes with a count (a section at first; Mike preferred a folder-like place).
- **The palette in sections:** Open Tabs, Bookmarks, Suggested (recent notes; Notes when searching), Tags, Commands, each labelled, in that order, a note listed only in the first that holds it. Typing a new name with nothing matching still puts New Note first. The tabs-only palette (⌃Tab) has no labels.
- **Markdown mode** hides the properties strip: the properties are in the text there.
- **List guides:** a thin vertical line (one point, the separator colour) under each item that has items nested beneath it, centred on its marker (`PointLayoutManager.drawListGuides`). Bullets and checkboxes are centred on one axis (`markerAxis`, 8 points into the marker column) so guides line up; bullets used to sit at the column's start, and their text starts 2 points later to keep the same gap after the dot as after a checkbox. A guide starts 4 points below its item's marker and stops 4 points above the next item's marker after the nested ones, or where that marker would be if the list ends.
- **Two-column tree focus (fixed the same day):** picking a folder or tag in the tree after a note in the list left the keyboard in the list, so the tree's selection stayed grey: the row's drag handling (folders can be dragged) takes the click before the list does. Picking something in the tree now gives the tree the keyboard (`PlaceTreeColumn.focusTree`), so it's blue and the note's row goes grey. Checked with a debug hook (`-PointClickTree YES`) tracing the keyboard.
- **Sidebar selection:** the open note's row is blue whenever the window is in front, whether the keyboard is in the list or the note; grey only when another list (the two-column tree) has the keyboard (`SidebarTableRowView`). Before, the table's own rule made it grey whenever the note was being edited. Text and icons on the blue go white, in both layouts (the tree from macOS 14).
- **Two-column tree:** its own folding instead of the system's outline: chevrons after the name, rows lining up with the section labels; unfolded folders are shared with the one-column sidebar.
- **Maximum line width:** Settings › Text, 480 to 1200 points (720 by default), for the text, the title and the properties. Its own setting rather than part of Typography, whose saved form would otherwise fail to load.
- **Checked:** in pictures of the debug build (bookmarks in both layouts, the joined capsule, the palette's sections, list guides). Not tried by hand: the selection colour as focus moves (pictures are taken with the window in the background), the line width slider, unfolding from the tree's chevrons.
