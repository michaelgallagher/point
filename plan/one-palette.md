# One palette

22 November 2026. Branch `palette-browse`, after [Browsing folders in the palette](palette-browse.md).

Point had a palette for each job: Search Vault, Run Command, Browse Folders, Move Note, Apply Template, and ⌃Tab's tabs. One palette that finds things and does things to them is easier to learn and to reach, and frees ⌘F for finding in the note.

## What the launchers do

- **Spotlight** (macOS 26): one field; ⌘1 to ⌘4 narrow it to apps, files, actions or the clipboard. Quick Keys, short typed codes, run an action at once.
- **Raycast:** one root search of everything; ⌘K shows the highlighted item's actions; aliases (exact short words) for commands; fallback commands when nothing matches.
- **Alfred:** one field; a keyword first narrows it; folders browsed in place; → shows the highlighted item's Universal Actions; fallback searches.
- **Tuna:** a command reads like a sentence, subject → action → target (a file, Move to…, a folder); Tab moves to the actions, ⌘K a menu of them; → goes into a folder and ← comes back to where you were; it learns what's picked for what's typed.

All four: one field for everything, ranked by what's picked; narrowing done inside the field; actions belong to the thing highlighted, asking for a target in the same field; something useful when nothing matches.

## Decided (with Mike, 22 November)

- **One palette, on ⌘E** (Edit › Search Vault). **⌘F is Find in Note** (was ⌥⌘F). Run Command and Browse Folders stay in the Edit menu with no keys of their own; `>` in the palette is only commands.
- **Commands stay mixed in** with notes as they're typed, a command first when its name is the clear match, as now.
- **Nothing typed:** open tabs, bookmarks, suggested notes and a few commands, as now.
- **Narrowing:** ⌘1 everything, ⌘2 notes, ⌘3 folders and tags, ⌘4 commands; `>` and `#` still work; the scope shows as a token at the start of the field (built as a bar under it instead; see step 2), and ⌫ with nothing typed takes it away.
- **Actions on any result, not only the open note:** ⌘K or Tab shows the highlighted result's actions; ← or Escape goes back out of them. Return still does the main thing (opens a note, goes into a folder), and → still goes into a folder (← up, when no actions are showing). → for actions was considered, but it already goes into folders.
  - A note: Open, Open in New Tab, Open on Other Side, Move to…, Apply Template…, Add Tag…, Bookmark, Mark as Read, Rename…, Copy Link, Insert Link Here, Move to Trash.
  - A folder: Browse, Show in Sidebar, New Note Here, Pin, Rename…
  - Move to… and Apply Template… ask for the folder or template in the same palette, which replaces the Move Note and Apply Template palettes.
- **⌃Tab stays its own switcher:** a hold-and-release gesture, as ⌘Tab is, not a search.
- **All on `palette-browse`,** merged with the folder browsing at the end.

## Steps

1. **Keys** (built 22 November): ⌘E opens the palette, ⌘F finds in the note; Run Command and Browse Folders have no default keys (a key set for them in Settings stays). The keyboard shortcuts sheet leads its Finding section with Find in Note. **Tried:** the debug build's menu test (`-PointShortcutTest`): ⌘E and ⌘F are menu keys, on Edit › Search Vault and Edit › Find in Note; Browse Folders and Run Command have none.
2. **Narrowing** (built 22 November): ⌘1 everything, ⌘2 notes, ⌘3 folders and tags (browsing, from where it was last left), ⌘4 commands. What's typed is kept. The same key again goes back to everything, as do ⌫ with nothing typed (at the vault's top, when browsing) and, on a start page, Escape. Run Command and Browse Folders open it narrowed. Narrowed to notes, it lists open tabs, bookmarks and notes, and a new note for a name no note has, and nothing else.
   - **A bar under the field,** All ⌘1, Notes ⌘2, Folders ⌘3, Commands ⌘4, the one in use marked, each clickable: it says what the palette is narrowed to and teaches the keys, as Spotlight's row of kinds does. **Changed from what was decided:** the scope was to show as a token at the start of the field too; built, it said the same thing twice, a few points above the bar, so it went. The field's symbol changes with the scope (a magnifying glass, a note, a folder, ⌘).
   - **The keys come before the menus** (⌘1 to ⌘4 are also Heading 1 to Heading 4): taken by a key monitor while the palette shows over the window, and on a start page only while its field is typed in, so a note on the other side of a split keeps them.
   - The keyboard shortcuts sheet lists ⌘1 … ⌘4 under Finding.
   - **Tried:** the debug build, opened through Launch Services so its window could be key, with ⌘1 to ⌘4 posted as real key presses: each narrows the palette, the same key twice goes back to everything, what's typed stays, and the note behind it is unchanged (before the keys were always taken over the window, a ⌘3 pressed as the palette opened reached the note as Heading 3). The start page's bar, by picture. Clicking the bar, ⌫ and Escape weren't tried by hand.
3. **Actions** (built 22 November): ⌘K or Tab on a highlighted note, folder or tag lists what can be done to it, in the same list, under a trail (the note's title, then each step after, with a back button); ← or Escape goes back out to the results, with what was typed and the highlight as they were. Typing filters the actions. Return does the main thing, as before; → still goes into a folder. The bar under the field says "Actions ⌘K".
   - **A note:** Open, Open in New Tab, Open on Other Side, Move to…, Apply Template… (when the vault has templates), Add Tag…, Add or Remove Bookmark, Mark as Read or Unread (where read state applies), Rename…, Copy Link, Insert Link (into the note being viewed, at its cursor, when it's another note), Show in Finder, Move to Trash.
   - **A folder or tag:** Browse, Show in Sidebar, New Note Here (folders), New List of These, Pin or Unpin, Rename Tag… (tags), Show in Finder (folders). Rename for folders wasn't built: the sidebar has no folder rename to share.
   - **Targets in the same palette:** Move to… lists folders and Apply Template… lists templates, as a step after the note. File › Move to Folder… and Apply Template… (⇧⌘T) from the menus open the palette straight at that step, for the note being viewed, and Escape there closes it. Their own palettes went.
   - **A template applied to a note that isn't open** is written to its file (`Templates.applied` merges the template's properties into the note's and puts its body after them), not only to an open editor.
   - **The field takes the keyboard as it joins its window,** not a moment after it's made: opened from ⇧⌘T, the field sometimes hadn't got focus, so Escape went nowhere.
   - **Tried:** the debug build, by posted key presses: ⌘K and Tab on a note and a folder, ← and Escape back out, Move to… moving a closed note, Apply Template… on a closed note (its file checked: properties merged, body after). VaultKit's `AppliedTemplateTests`. Mike, by hand: ⇧⌘T then Escape closes the palette, since the focus fix. **Not tried:** Insert Link, Copy Link and Show in Finder by hand.
4. **Maybe later:** aliases (a typed "mv" straight to Move to…).

## After a day of use (23 November)

Mike's notes, and what was done:

- **It learns which commands are used.** Each command run from the palette is remembered (`VaultStore.commandHistory`, a `SearchHistory` kept by command name, in `Point/History/commands.json`, for every vault on this Mac). The commands run most, and most lately, come first; a command run once drops back after about a month. One picked after typing something comes first for that text again, and before the notes if no note was picked for it. A command named for what it'll do now (Show or Hide Markdown, Add or Remove Bookmark) is learned under one name. Forget What Search Has Learned forgets these too.
- **The usual commands first,** until it's learned otherwise: New Note, Move Note…, Show in Finder, Insert List, New List, Insert Table, Add or Remove Bookmark, Enclosing Folder; then the rest by name.
- **Not every command at once:** narrowed to commands (⌘4) with nothing typed, the first 8, then Show All N Commands. Typing still finds any of them. With everything (⌘1), the first 4, as before.
- **Bookmarks by how often they're opened,** most first; those never opened on this Mac keep their bookmarked order, after.
- **Narrowed to notes (⌘2),** the suggested notes come before bookmarks.
- **No bookmarks section with everything (⌘1):** a bookmark comes up among the suggestions and results as any note does.
- **The field says "Search"** with everything, not "Search or use commands".
- **More room between the field and the bar under it,** in both the palette and the start page.
- **A start page has the line under its field and bar,** as the palette does.
- **Tried:** the debug build's pictures (`-PointSnapshots`) of the palette and the start page. **Not tried:** the ⌘4 list and the learning by hand.
