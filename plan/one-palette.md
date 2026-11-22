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
3. **Actions:** ⌘K and Tab on a result, with targets; the Move Note and Apply Template palettes go.
4. **Maybe later:** aliases (a typed "mv" straight to Move to…).
