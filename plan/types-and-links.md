# Types, links and lists (8 November 2026, branch `links`)

Part of [the plan](../PLAN.md). Follows [Kinds of note](kinds.md).

**Why:** three questions were getting mixed up. Where a note lives is its folder; what it is, its `type`; how it's related to another note, the property the link is in. Mike found a person's note listed everything linking to it in one list, mostly the meetings they were in, so the articles they wrote were lost; the word "type" meant both a note's kind and a property's; types tied to one folder repeated the folder in the sidebar; and there was no way to see every list.

**Decided (Mike, 8 November):**
- Links are grouped by relation and narrowed by type, shown either at the side (a panel pushing the note over, as the sidebar does) or along the bottom (a strip growing up over the note), chosen in Settings.
- **Person** and **Project** are kinds, alongside Topic; working documents have no type. Notes stay in their folders. (The sorting of the real vault's topics is a draft for Mike, kept privately.)
- The types in the sidebar are chosen in Settings and sit under Bookmarks.
- Lists have a place of their own, and list notes are marked in note lists.

**Built:**
- **Links by relation** (`LinkGroups`, `LinkRelation` in IndexKit): each backlink says which properties it links from, its type and its date (`date`, `published` or `saved`, else when it was created), in the same query as before. Groups, in order: By (`author`, `creator`, `speaker`…), About (`topics`, `project`…), any other property by its name, With (`people`, `attendees`…), Mentioned (the text), then Not linked (unlinked mentions, with Link). Newest first in each; a group folds from its heading. Chips above narrow them to one type, with counts. A row is its title, type and date; only a mention in the text shows its line.
- **Where they show** (Settings › Notes › Links): at the side, the glass button at the note's bottom right ("21 links") opens a 320-point panel at the right, pushing the note over, and it stays open from note to note until closed; at the bottom, a strip along the note says how many and of what ("21 links · By 7 · About 1 · With 11 · Mentioned 2") and grows up over the note into the list, to 70% of its height, closing on Escape or a click elsewhere.
- **Person kind:** a property of the person kind suggests notes whose type is Person (or People), as well as those in the people folder and people already linked, on both. So Person means the same as a type and as a property's kind. The menu for a property's kind is now "Property type", on both.
- **The sidebar's top set:** All notes, Bookmarks, the types chosen in Settings › Sidebar › Types at the top (until chosen, those with no folder of their own, such as Meeting: a type kept in one folder is reached through it), Lists, then Tags, Types and Trash.
- **Lists** (`SidebarPlace.lists`, `SearchIndex.listNotes`): every note with `list-from`, `list-tags` or `list-where`. On the Mac in the sidebar (turned off in Settings); on the iPhone, a tile on home (in Settings too; four or more tiles show two by two).
- **List notes marked:** on the Mac, "List" at the row's right under date headings or with dates off, else a list symbol before the title; on the iPhone, "List" at the right.
- **Fixed in passing:** with wrapped titles, a note row's title left no room for the gap before its date, which squeezed the date onto two lines.

**Tried:** `groupsBacklinksByRelationAndType` (IndexKit), `PersonKindTests` (VaultKit). On the Mac, a Debug copy with its own bundle ID and settings, on a test vault, drawn by `-PointWindowSnapshot`: the side panel open, the bottom strip open, the sidebar's top set, and list notes in both date styles. (Snapshots don't draw Liquid Glass, so the panels' glass wasn't seen.) On the iPhone Simulator: home's Lists tile and its page.

**Not tried:** Mike's own copy, and so the real vault's numbers; the strip and panel by hand (clicks, Escape, folding, chips); the glass; links on the iPhone (still one list there).

**Next:**
- Mike checks the topics sorting; then `type` is written into those notes.
- Links grouped on the iPhone too.
- Maybe: "Save as list" from the links (a list of a person's articles), and a type of its own for organisations and products (the NHS App and the like), if Topic isn't enough.

## Second round (8 November 2026, branch `sidebar-and-links`)

**Mike's notes:** types only at the top of the sidebar, not again below the folders; type names plural there; properties out of the sidebar and into Settings; no explanations under Links and Images; the side panel beside the whole pane (tabs and menu included), with its own title and close button, resizable, sliding in, and not jumping when notes change; the strip's button in the note's bottom-left corner, sized to its summary, opening a plain (not glass) panel that slides up, can be resized and keeps its height; and the sidebar stuttering as it opens in a window too wide for the screen.

**Built:**
- **Sidebar:** the types chosen in Settings are the only place types show (the Types section and its option are gone; a type's place sits under All notes). Names are plural (`NoteKinds.plural`: Meetings, Daily notes, Reviews, People; Media unchanged). Properties are no longer in the sidebar.
- **Settings:** "Shown in the sidebar" lists Bookmarks, each type, Lists and Tags, each with its symbol. A Properties tab lists every property with its type, how many notes use it, and Rename… (the rename across the vault). Links and Images have no explanations.
- **Side panel:** part of the pane, beside the page and its tab bar, so the tabs and menu end at the panel. Its title sits in the bar, with a glass close button. 320 points to start, dragged wider or narrower from its edge (240–640), kept. It slides in from the right. Each note's links are kept by the window (the last twelve), so changing notes keeps the panel and its width, with no full-width note first.
- **Bottom strip:** a glass button in the note's bottom-left corner, inset like the sidebar's filter and sort buttons, with the count and summary, or the count alone when there isn't room. It opens a plain panel with a thin divider, sliding up over the note; its height (360 to start) is dragged from the divider and kept, so choosing a type doesn't change it.
- **The sidebar in a wide window:** when the screen can't take the whole sidebar, the notes give up part of their width. That used to happen at once: the sidebar opened at the notes' share, the notes jumped narrower and re-wrapped, then the rest slid in (and the reverse, with a jump at the end, on hiding). Now the sidebar's collapse animates with the window's frame, so the window, the sidebar and the notes move together.

**Tried:** traces of the sidebar opening and closing three times in a window of 1,700 points on a 1,800-point screen, and 1,000 points for comparison: each frame's positions move together with no jump, and the window ends exactly where it began. Snapshots of the side panel and strip (no glass in snapshots). The iPhone builds; VaultKit and IndexKit tests pass.

**Not tried:** the sidebar's opening watched on screen (by Mike, or a screen recording); dragging the panel's and strip's edges by hand.

**In a split (8 November 2026):** each side opens and closes its links panel on its own (kept per side by the window; the last choice is the default for a new side and the next launch). The panel never takes a side's note below 320 points, narrowing to 200 if it must, and a row keeps its type and date whole, its title wrapping instead. Seen in snapshots of a split with the panel on the left side only.

**The side panel's close button didn't take clicks (8 November 2026). Fixed and clicked:** from macOS 26 a scroll view reaches up under the title bar's strip whatever's above it, so the panel's list lay over its header and took the clicks (accessibility's press still worked, which hid it). The header now lies over the list, as a side's bar lies over its note. Mike also found the bottom strip's button missing after switching from the side; with real clicks in a test copy (panel open, then Settings › Notes › Links › Strip at the bottom) the button showed and the strip opened and closed, so that isn't reproduced yet.
