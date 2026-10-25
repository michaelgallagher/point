# Point — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. It works directly on an Obsidian vault.

## Principles

1. **The file is the truth.** Notes are plain `.md` files in a folder that is also an Obsidian vault. Every unchanged byte stays unchanged, including frontmatter key order, whitespace, and syntax we don't render.
2. **Never see Markdown.** Editing feels like rich text. Markdown decides what formatting is possible. A raw-source toggle exists for emergencies.
3. **Little filing.** Search, links and tags do most of the finding. Folders exist for the few broad areas that need them (as in Obsidian), but filing is never required.
4. **Capture is instant.** One press on the iPhone gets you to a blank note with the keyboard up.
5. **Fast software is good software.** Open instantly, and stay responsive with 10,000 notes. Speed wins over features that would slow things down.
6. **Native.** Use platform conventions and the system's own controls.
7. **As minimal as possible, but no more.** Show as little interface as we can, without making common actions hard to do.
8. **Know what you need to know.** Half of the app's job is managing knowledge: surfacing what matters, connecting related notes and making it easy to find things again, not just storing text.
9. **The command palette is the main way to do things.** Every action is reachable from it. Menus, buttons and shortcuts are secondary ways to get there.

## Decisions so far

### Platforms

| Machine | OS | Role |
|---|---|---|
| M3 MacBook Pro | macOS 26 | Primary. Full experience. |
| 2017 Intel MacBook Pro | macOS 13.7.8 | Occasional use. Simpler experience is fine: no semantic search, no AI features, no Liquid Glass. |
| iPhone 13 | iOS 26 | Full experience except generated AI text: the iPhone 13 can't run Apple Intelligence. iPad is not in scope. |

- **Builds:** made on the M3. Xcode 26 doesn't run on macOS 13, so builds are copied to the old Mac to test. The first launch there needs right-click and Open.
- **Audience:** just Mike for now.
- **Developer account:** none yet. Start Mac-first, and buy the paid account when the iPhone milestone begins. Free-account iPhone builds expire after 7 days and can't use extensions.
- **Involvement:** Mike reviews at milestone boundaries.

### Vault, storage and sync

- **Location:** the existing Obsidian vault moves into iCloud Drive. Turn off Obsidian Sync for it, because two sync engines on one folder cause conflicts.
- **Access:** the user picks the vault folder once, and the app keeps a security-scoped bookmark to it. On iPhone the folder is picked through the Files app. This needs no iCloud entitlement.
- **Folders:** real folders on disk, shared with Obsidian. The sidebar browses them (see "Sidebar navigation"). New notes go to the folder you're in, or the vault root.
- **Dot-folders:** `.obsidian/` and other dot-folders are ignored, except for the Obsidian settings we read (below).
- **Attachments:** follow Obsidian's configured attachment folder (`.obsidian/app.json`).
- **Daily notes:** compatible with Obsidian. Read the folder, date format and template from `.obsidian/daily-notes.json`.
- **Templates:** compatible with Obsidian's core Templates plugin. Read the template folder from `.obsidian/templates.json`, and support `{{title}}`, `{{date}}` and `{{time}}`, including custom date formats. New notes and daily notes can start from a template.
- **Note names:** the title is the filename. An untitled note gets a timestamp name until it has a first line, and is renamed to that first line when you leave the note. Never rename while typing.
- **Links:** `[[wikilinks]]` everywhere. New links are always wikilinks.
- **Renames:** update all `[[links]]` to the note across the vault, honouring Obsidian's link-format settings.
- **Side by side with Obsidian:** Obsidian edits the same files concurrently. The app watches the vault and reloads externally changed notes without losing your cursor. iCloud conflict versions are surfaced, never silently dropped.

### Editor

- **Display:** a custom native text view. The underlying string is always the exact Markdown. Rendering hides syntax characters and applies styles. We never convert to rich text and serialise back, which is what makes byte-for-byte preservation possible.
- **Commands:** formatting commands edit the Markdown directly. For example, ⌘B wraps the selection in `**`.
- **Syntax visibility:** never shown. A menu command toggles raw source.
- **Rich editing in v1:** headings, bold, italic, highlight, links, wiki links, tags, lists, checklists, quotes, images, code blocks, callouts.
- **Rendered but read-only in v1:** tables, `![[embeds]]` and footnotes. You change these through the raw toggle. Their contents are always preserved.
- **Frontmatter:** a collapsed strip under the title, such as `3 properties · #work #ideas`, that expands into a key/value editor. Unknown keys and their formatting are preserved.
  - **Adding properties:** a note without frontmatter needs a visible way to add one ("Add Property"). Typing YAML into the note doesn't create frontmatter, because `---` on its own line is a horizontal rule until the closing `---` exists.
  - **Dates:** date properties get a date picker, so dates never have to be typed.
- **Headings:** H1 26pt bold. H2 18pt semibold. H3 body size, bold. H4 body size, italic, not bold. H5 and H6 match H4.
- **Links:** wikilinks look as they do now. Web links get a small `arrow.up.right.circle` symbol after them, so the two are easy to tell apart. The symbol takes up space in the line, which slightly changes how text flows.
- **Tags:** shown as pills: a background tinted with the system highlight colour, with fully rounded ends.
- **Tags:** read from both inline `#tags` and the frontmatter `tags:` property, and treated as one set. New tags go inline.
- **Pasting links:** pasting a URL over selected text makes that text a link.

### Sidebar navigation (decided October 2026)

A single flat list of notes won't scale, so the sidebar browses folders and tags.

- **One list at a time:** the sidebar stays one column.
- **Start view, the vault's top level:** pinned folders and tags first, then the top-level folders, then a collapsible Tags section, then only the notes that aren't in a folder. Changed 18 October 2026: the top level used to list every note. Thin dividers separate folders, tags and notes.
- **Inside a folder:** its subfolders, then the notes directly in it. A back arrow and the folder's name at the top go back up (also ⌘↑).
- **Inside a tag:** its nested tags, then every note with that tag or a tag under it.
- **Tags:** nested tags (`work/imprint`) are indented under their parent, so the hierarchy is clear. A parent appears even if only its children are used.
- **Pins:** folders and tags can be pinned (right-click), such as the NHS, Sources and Personal folders. Pins are stored in Point's settings, per vault, never in the vault.
- **New notes:** ⌘N inside a folder creates the note there. Elsewhere, it goes to the vault root.
- **Moving notes:** drag a note onto a folder, or use "Move to Folder…". Links that spell out a path are updated, and so are the moved note's own relative links.
- **Search** always covers the whole vault, wherever you are in the sidebar.

### Note list

- **Rows:** the filename is the main thing. No preview line.
- **Sort:** most recently edited first by default. Can switch to alphabetical, or to date created.
- **Optional row details:** a date (last edited by default, or date created) and tags. Both are off unless turned on.

### Focus mode (Mac)

- A near-blank window with almost all interface chrome hidden.
- Keeps a button to show the note list. A few other icons may stay; which ones is to be decided.

### Search and connections

- **Search:** handles typos and partial words, word forms (run, running, ran), filters by tag, date and links without a query language, and meaning (semantic search).
- **Connections:** backlinks, unlinked mentions (one click to link), a related-notes panel, and tag suggestions. No graph view.

### AI (on-device only)

- **Outputs:** a weekly digest, topics over time, and clusters of related but unlinked notes.
- **Embeddings** (Natural Language framework; macOS 14+ and iOS 17+, so the M3 and the iPhone 13). These power semantic search, related notes, tag suggestions (from the tags of similar notes) and clusters.
- **Generated text** (Apple Foundation Models; needs Apple Intelligence, so **the M3 only**). This writes the weekly digest and names topics and clusters. The iPhone 13 and the 2017 Mac can't run it.
- **Storage:** the M3 writes digests and topic summaries as ordinary Markdown notes in the vault, so every device sees them. Each has a deterministic filename (for example `Digest 2026-W42.md`) so a note is never written twice.

### Quick capture (iPhone)

- **Entry points:** a Lock Screen and Control Center control (also usable on the Action button), Siri phrases and dictation, the share sheet, and Apple Watch.
- **Destination:** each capture is a new note, and a link to it is added to today's daily note.
- **Mac:** no global hotkey for now.

### Mac keyboard shortcuts

| Keys | Action |
|---|---|
| ⌘F | Command palette: search notes, all tags, commands (branch `minimalist`; was ⌘E) |
| ⌘E | Command palette as the two-column explorer (branch `minimalist`; was ⇧⌘E) |
| ⇧⌘F | The note list's search field, in the sidebar layouts (branch `minimalist`; was ⌘F) |
| ⌥⌘F | Find within the note |
| ⌘B / ⌘I / ⌘U | Bold / italic / highlight |
| ⌘1 … ⌘6 | Heading level |
| ⌘K | Link selected text |
| ⌘L | List |
| ⌥⌘→ / ⌥⌘← | Indent / outdent. (⌘→ / ⌘← are back to the system default: end and start of line.) |
| Tab / ⇧Tab | Indent / outdent in lists |
| ⌘[ / ⌘] | Back / forward through visited notes |
| ⌘↑ | Up to the enclosing folder or parent tag |
| ⌥⌘↑ / ⌥⌘↓ | Move the line up / down (branch `minimalist`; was previous / next note in the list) |
| ⌘+ / ⌘− | Bigger / smaller note text |
| ⌘S | Hide or show the note list |
| ⌘T | New tab |
| ⇧⌘N | New folder, inside the folder being browsed (also "New Folder Inside…" on a folder's right-click menu) |
| ⇧⌘T | Show the tab list (Today's Note has no shortcut for now; 25 October 2026) |
| ⌘-click | Open a note or link in a new tab |
| ⌘, | Settings |

All shortcuts will be remappable.

## Architecture

```
Point.xcodeproj
├─ Point (macOS app, deployment target 13.0)
├─ Point (iOS app, 26.0)            + share extension, controls/intents, watchOS app
└─ Packages/
   ├─ VaultKit     folder access, file watching/coordination, Obsidian settings,
   │               note model, wiki-link resolution, rename-with-link-update
   ├─ MarkdownKit  fast, lossless, incremental parser (CommonMark + GFM + Obsidian
   │               extensions: wiki links, embeds, tags, callouts, highlights,
   │               frontmatter, block ids) producing ranges for styling
   ├─ IndexKit     SQLite (GRDB): FTS5 with porter (word forms) and trigram (partial words)
   │               tables, fuzzy title matching, tags, links, backlinks; per-device,
   │               stored outside the vault; incremental by modification time + hash
   ├─ EditorKit    the text view: AppKit on Mac, UIKit on iOS, sharing styling logic
   └─ InsightKit   embeddings, related notes, tag suggestions, digests
                   (only active on macOS 26 / iOS 26)
```

- **UI:** SwiftUI shell (split view on Mac, navigation stack on iPhone) with the editor wrapped from AppKit or UIKit.
- **macOS 13 support:** SwiftUI is limited to macOS 13 APIs, using `ObservableObject` instead of `@Observable`. Newer features are gated with `#available`.
- **Text engine:** TextKit 1 (decided in M1). It is mature on macOS 13, and its glyph-generation hook hides Markdown markers cleanly while the text stays exactly as on disk. Still to confirm on the 2017 Mac.
- **Parser:** our own. Off-the-shelf parsers don't round-trip losslessly or know Obsidian syntax, and the editor needs exact ranges for every token.

## Milestones

Each milestone ends with a build for Mike to try and review.

**Safety rule:** until the round-trip tests pass in milestone 1, the app only ever opens a *copy* of the vault.

### M0 — Skeleton
- Xcode project, packages and test targets.
- Mac app opens a vault folder and lists every note (flat, sorted by modified date), with a read-only preview.
- Runs on both Macs.

### M1 — Editor prototype (the big risk)
- Markdown parser.
- Syntax hiding, styles, cursor and selection behaviour around hidden characters.
- Formatting shortcuts.
- Round-trip test: open and save every note in a copy of Mike's vault, and assert the files are byte-identical.
- Performance test on the largest note.
- Decide TextKit 1 vs TextKit 2 after testing on the 2017 Mac.

### M2 — Mac daily driver
- Create, rename and delete notes.
- Wiki links with autocomplete, tags, the frontmatter strip, daily notes and templates.
- Note list sorting and optional date and tag details.
- External change handling (Obsidian, iCloud) and conflict surfacing.
- Raw toggle, focus mode (hide all chrome), back and forward, link pasting.

### M3 — Search and palette
- Index, fuzzy and word-form search, filters.
- ⌘E palette with tags and commands.
- Backlinks and unlinked mentions.

### M3.5 — Mac refinements (October 2026)
Mike's review after using M3, done before the iPhone app. In three parts, not all at once.

**A. Editor fixes and polish** (small, well-defined). Done 18 October 2026.
- Bug: you can't type on a new, empty list item. The cursor jumps to the next line. Cause found: an empty item (`- `) is a line whose text is all hidden, so the cursor skips it as if it were a code fence. Fix: only skip lines that are actually collapsed.
- Shortcuts: ⌘←/→ back to the system default, and ⌥⌘←/→ to indent and outdent.
- Heading sizes and styles, as listed under Editor.
- Tag pills, and the symbol after web links.
- Frontmatter: "Add Property" for notes without frontmatter, and a date picker for dates.
- Follow-up: Obsidian users sometimes write dates as links (`created: [[2026-10-18]]`). These don't get the date picker yet.

**B. Sidebar navigation** (the big one, which needs decisions first). Done 18 October 2026.
- Folders, tags as a hierarchy, and pinned areas, as described under "Sidebar navigation".

**C. Investigation: daily notes as the home for meetings**
- See "Topics for investigation". Not started.

**D. Sidebar and window polish** (Mike's review, 18 October 2026). Built 18 October 2026: all twelve items. To confirm by hand: item 1 (the delay), the swipe (item 11, needs a trackpad), and the reading of item 12.

Bugs:
1. **Details under note names appear about a second late after opening a folder or tag.** Still unfixed after two attempts.
   - Tried: removing the list's animation, caching the folder tree, reserving a fixed tags line, and setting the list's row height up front.
   - Finding: a debug trace (`-PointTrace <file>`) shows the rows, with their tags and dates, are built 0.2 s after the click, so the data isn't late. The delay is in how SwiftUI's `List` lays out and draws rows. It can't be seen from Claude's tools.
   - Done: the sidebar is now an AppKit table (`SidebarTable.swift`). Mike confirmed details appear straight away when moving between folders.
   - At launch, tags now come from the search index, which keeps them between launches, so they're ready in about 0.1 s rather than after every file is read (5.6 s on the 5,000-note test vault). Rows that gain or lose a tags line animate their height.
   - Earlier plan: replace the sidebar's SwiftUI `List` with an AppKit table (`NSTableView`). That gives exact row heights straight away, slide animations between folders, and keyboard control. It also fixes item 2 and helps with items 3 and 6.
2. **The note list is too spaced out.** This was caused by reserving a tags line in every row while trying to fix item 1. Rows without tags should be one line high.

Features:
3. Moving into or out of a folder or tag animates: the list slides in from the right going in, and from the left coming back.
4. Command palette: "Move to Folder…" (it exists as "Move Note to Folder…" when a note is open; make it easy to find) and "Add Tag…".
5. "Show in Finder" in the note list's right-click menu.
6. ⌥⌘↑ / ⌥⌘↓ move to the previous or next note in the list.
7. At the top level, list only the notes that aren't in a folder (see "Sidebar navigation").
8. Dividers between the folders, tags and notes sections.
9. ⌘+ / ⌘− make note text bigger or smaller.
10. ⌘S hides and shows the note list.
11. A two-finger swipe left closes the note list. Done: it uses Apple's swipe tracking (`trackSwipeEvent`), because macOS gives a sideways two-finger swipe to its "swipe between pages" gesture and an app otherwise sees only the first event. It fires a tenth of the way into the swipe, and the list and window animate in 0.15 s. Mike confirmed it feels fast enough.
    Later (19 October 2026): off by default, turned on in Settings › Sidebar, because sideways scrolling in the tab row set it off by accident. It never acts on swipes over the top bars.
12. When the note list closes, the window keeps the text panel's width and gets narrower, so the text panel slides over rather than growing to fill the window. (That's the reading of "the text panel should just slide over"; confirm when trying it.)

**E. File views, settings and tabs** (Mike's review, 18 October 2026)

1. **Two ways to browse, chosen in Settings:**
   - **Single column** (the default, as now): folders, tags and the current folder's notes in one list. Clicking a folder or tag moves in one level.
   - **Two columns:**
     - **Left column:** folders and tags only, no notes. Folders form a tree you can expand and collapse. A toggle switches the left column to tags, which also nest like folders. Tags sort alphabetically by default, or by date modified (the most recently edited note with that tag).
     - **Right column:** the notes in whatever is selected on the left.
2. **A Settings window (⌘,):** it starts with the browsing choice. Other settings move there over time (text size, list details, sort order).
3. **Tabs:** several notes open at once, as native macOS window tabs (decided 18 October 2026). They work like Finder and Safari: a tab bar in the title bar, and a tab can be dragged out into its own window. Each tab has its own note, folder, search and history.
   - **Opening a note in a new tab:** ⌘-click a note or link, right-click > Open in New Tab, or ⌘Return in the ⌘E palette.
   - **Shortcuts:** ⌘T becomes New Tab, so Today's Note moves to ⇧⌘T.
   - **Prerequisite:** the app model must be split first. A shared vault part (notes, index, watcher, settings) and a per-window part (selection, sidebar place, search, history, focus).
4. **Order:** the Settings window and the two-column view first, then the model split, then tabs.
   - Status, 18 October 2026: all built and checked in the app.
     - **The split:** `VaultStore` (shared: vault, notes, index, tags, pins, file operations, display settings) and `VaultModel` (one per window or tab: note, folder, search, history, sheets). It passes the store through, so views kept their API. Menus act on the front window (`@FocusedObject`).
     - **Tabs:** native tabs at first; replaced on 18 October 2026 by Point's own tabs inside each side of a split (see Part F, "Panes and tabs"). ⌘T is New Tab, and Today's Note moved to ⇧⌘T.
     - **Opening a note in a new tab:** ⌘-click (on a note or link), right-click > Open in New Tab and ⌘Return in the palette. Mike confirmed they work.
   - **How two columns is built:** the tree and the notes sit side by side inside one sidebar, with a draggable divider. SwiftUI's three-column split view on the Mac wouldn't hide both side columns from code, so swiping and ⌘S hid the wrong thing. Hiding narrows the window by exactly the sidebar's measured width, and showing widens it back first.
5. **Two-column view, pins:** pinned folders and tags stay at the top of the left column, above the tree.

**F. More file views and editor polish** (Mike's review, 18 October 2026)

1. **The Folders/Tags toggle:** full width of the left column, with rounder ends.
2. **Two-column left column, a setting:** by default it shows folders and tags stacked, like the single column. Switching between them with the toggle becomes a choice in Settings.
3. **Two notes side by side:** the note area splits into two editors with a divider, each with its own note. Open a note on the right with ⌥⌘-click or right-click > Open to the Side, and close the split to go back to one. (Decided 18 October 2026.)
4. **Reorder properties by dragging** in the properties strip. Only the moved property's lines change.
5. **Top level of the single-column list:** only notes in the vault's top folder, not all notes. This is already how it works; the test vault really has about 1,250 notes at its top level. To confirm with Mike.
6. **Sorting:** folders and tags sort by name or by date modified (the most recently edited note inside first), in both layouts. Notes keep their own sort order.
7. **Quotes:** text in the normal colour, and the bar black (white in dark mode).
8. **Command palette:** a white background (the page colour in dark mode).
9. **Browsing files from the command palette (a bigger project):** navigate folders, tags and notes inside the palette, without opening the sidebar. Reached by an "Explorer" command or ⇧⌘E.
   - **Keys:** ↑↓ move, → or Return goes into a folder or tag, ← goes up, Return opens a note (⌘Return in a new tab). Typing filters what's at the current level.
   - **Start place:** where you last were in the palette.
10. **Order of work:** the small polish (items 1, 2, 6, 7, 8) first, then reordering properties, then the palette browser, then the split view.

**Status (18 October 2026):** items 1–4 and 6–9 are built and checked in the app; all tests and the MG notes round trip pass. Item 5 waits for Mike to confirm. How they were built:
- **Toggle and setting:** Settings > "Two-column folders and tags": Together (the default) or One at a time, with a switch. Switching to one at a time shows what was last chosen in that tree.
- **Sorting:** a "Sort by" menu under the tree, Settings, View > Sort Folders and Tags By, and the right-click menu on the single column's headers.
- **Reordering properties:** drag a property by its name. Only the lines between its old and new place are rewritten, each exactly as it was; comments and nested values stay put. It's an ordinary edit, so ⌘Z undoes it. (A drag gesture, not drag and drop, which wouldn't deliver a drop inside the strip.)
- **Explorer (⇧⌘E, or "Explorer" in the palette):** the vault's level shows its folders, then Tags, then its notes. ← at the start of the filter (or ⌫ with nothing typed) goes up and highlights where you came from; → at the end of the filter goes in. A breadcrumb shows where you are.
- **Side by side:** ⌥⌘-click a note in the list or a link, or right-click > Open to the Side. The side note has a small bar with its title, "Open Here Instead" and Close (also Go > Close Side Note and in the palette; no shortcut, since ⌥⌘W is Close All Windows). Links clicked in the side note open there. The divider position is remembered. The window widens first if the notes would be narrower than 760 points together, and narrows back on close. The same note can't be open on both sides, and choosing the side note on the left closes the side.

**Follow-up from Mike's check (18 October 2026), built:**
- **List focus:** picking a note in the list keeps the keyboard in the list (blue highlight, arrows keep moving through notes); Return or Tab moves into the note. Before, the editor took the keyboard, so the list blinked grey and the tree's highlight stayed blue.
- **Split view, equal notes:** both notes have the same title bar with a close button; the window title shows the vault's name. Closing the left note leaves the right one as the window's note. Menu commands (rename, move, templates…) still act on the left note; acting on whichever note has the cursor is a possible later step.
- **Dragging properties:** an open hand over a property's name, and while dragging, a lifted copy of the property follows the pointer, with a line where it will land.
- **Swipes and Settings:** swipes only act on the note window they happen in, and the window resizing acts on that window (it used to resize whichever window was in front, such as Settings).
- **Settings:** wider (560 points), in sections (Sidebar, Sorting, Note list, Text), each label above its options. The note list's date (edited or created) is now there too.
- **New Note button** in the toolbar, beside the button that hides the sidebar. (Removed 19 October 2026: ⌘N and the palette are enough.)

**Panes and tabs (decided 18 October 2026, built and checked in the app):**
- **Decisions:** the split sits at the top of the note area, and each side has its own tabs (like Xcode or VS Code editor groups). These replace macOS window tabs, which are turned off. The window never resizes itself: hiding the list or splitting gives the space to the notes, whose text column (with its maximum width) recentres. The old approach widened and narrowed the window by remembered amounts, which drifted whenever a resize was cut short (minimum width, screen edge, full screen) and could leave the window wider than the screen.
- **Model:** a window has one or two panes; a pane has tabs; a tab has a note (or none) and its own back/forward history. The active pane is the one last typed or clicked in; the list, palette, Go menu and note commands act on it. A note is open in at most one tab per window, so opening it again goes to that tab.
- **Keys and menus:** ⇧⌘S splits, with an empty side that gets the next note picked; pressed again, it merges both sides back into one side's tabs. ⌘T new tab, ⌘W close tab (a side's last tab closes the side; the window's last closes the window), ⇧⌘[ / ⇧⌘] previous and next tab, ⌥⌘N new window. View > Move Tab to Other Side (or to a new split). ⌥⌘-click and Open to the Side open a note on the other side.
- **Top bar and properties line (19 October 2026):** from macOS 26 the page runs up beneath the top bar (see below for its background). Before 26, the bar keeps the page's colour and a hairline. The line under the properties is gone; a line the text's width shows only while the properties are open, fading in as they open.
- **Back and forward, fixed (24 October 2026):** they never worked because the window's toolbar had an invisible item (there to give the top row its height) sitting exactly where the arrows are, taking their clicks; found by sending real mouse events through the window in a debug run (`-PointClickBack YES`). The item is gone: the sidebar button the split view adds already gives the toolbar its height, which the bars now measure again once the window has its toolbar. The arrows are the glass capsule again, their clicks taken by AppKit views under them (`ClickArea`), as the tabs' are. In Settings, back and forward are one joined capsule with the page's name after it, in one toolbar item.
- **History, and more follow-ups (24 October 2026):** back and forward are one history for the window, not per tab: every change of the note in front counts (a note picked, a tab switched to, the other side clicked into), and going back returns to the note's tab if it's open, or opens it in the tab in front. (Per-tab history only recorded a note opened into the same tab, so in practice it stayed empty.) The list's search field is the comfortable row height in either density.
- **Follow-ups (24 October 2026):** Settings is a split view with its sections down the left; the window has no title ("Point Settings" is gone) and a unified toolbar, so its window buttons sit in from the corner like the main window's, and the toolbar holds back and forward through the pages visited, then the page's name, larger. The note bar's back and forward capsule uses plain glass (interactive glass took the buttons' clicks). The one-column sidebar's unfold arrows measure clicks within the row's cell (the source list insets it from the row), and nested tags unfold beneath their parent tag as subfolders do (a tag remembered as `#tag`). The list's search field sits a point lower, level with a selected row in the tree beside it.
- **Mike's notes (24 October 2026):** the sidebar's search field is as tall as a selected row (32pt comfortable, 24pt compact), and tabs are 32pt in either density. ⌘W closes Settings (and any window that isn't a note window). Wikilinks to notes that don't exist yet are fainter (half the link colour); editors restyle when notes come, go or are renamed. Back and forward buttons sit together before the tabs (a glass capsule from macOS 26), acting on that side's current tab. A note's title at the top of the page is editable: Return or clicking away renames the note (and its file, updating links), Escape puts it back. ⌘Z reopens the tab just closed, with its history, but only while closing it was the last thing done (no typing or tab change since); otherwise Edit › Undo undoes as usual. In the one-column sidebar a folder with folders in it has an arrow that unfolds them beneath it (remembered); clicking the name still opens the folder. Narrowing the window past a set width (760 points unless changed; Settings › Sidebar) hides the sidebar, and widening it back shows it, if narrowing hid it. Settings has sections in a list down the left (Sidebar, Notes, Text, Typography); Typography sets the body size and line height and each heading's size, weight and italic (`Typography` in EditorKit, saved as JSON), and ⌘+ / ⌘− scale it all.
- **Mike's notes (19 October 2026, second list):** the start page's search field is a rounded box rather than a line. In the palette, a name no note has yet offers "New Note “name”" (first, so Return makes it, when nothing else matches). ⌃⌘T opens a new tab on the other side, splitting the window if needed. ⌘/ (Help › Keyboard Shortcuts, or the palette) shows every shortcut. Folders drag onto folders in both sidebar layouts (onto the one-column list's "Folders" heading for the top level); notes inside keep showing, and pins follow, but links written as paths aren't rewritten. Every section of the one-column sidebar folds (Pinned, Folders, Tags, Notes), and the two-column tree's sections fold from macOS 14. The app opens as it was left: the first window gets the last-used window's tabs, sides, current tabs and folder, saved per vault. Headings and list items fold: an arrow beside the line (on hover, and always when folded, with "⋯" after it), or ⌥⌘[ and ⌥⌘]. Folded lines are collapsed like frontmatter (the text and the file are unchanged), folds move with typing, and an edit that reaches into a fold opens it. Folds aren't kept when the note closes.
- **Mike's list (19 October 2026):** the note title is semi-bold. The properties summary lines up with the title and the text, its chevron hanging in the margin. The top bar has no background of its own: the editor's scroll view (`MarkdownScrollView`) blurs the text scrolling under the bar with a within-window `NSVisualEffectView` inside itself, with a hairline at the edge, like the system's hard scroll edge effect. The system's own effect was tried and dropped: it needs a title bar that isn't marked transparent, which then takes the top bars' drags and drops and, with no note open, blurs the tabs; and AppKit showed it only after forcing its style to hard by key. A blur from outside the scroll view (`NSVisualEffectView` or a Core Animation filter) doesn't pick up the text, and a tint isn't a blur. With the sidebar hidden, clicking a tag opens the explorer on that tag's notes. The palette lists notes open in tabs first, marked "Open". The comfortable sidebar has more room above each section's line. Pasting a list item into a list item drops its marker (and the line break a triple-click takes). ⌘X with nothing selected cuts the whole line.
- **File path hidden by default (19 October 2026):** the folders above a note's title take room, so they're off unless turned on (Settings › Text, View › Show File Path, or the palette).
- **Dragging tabs:** drag a tab along its bar to reorder it, or onto the other side's bar to put it there. Drag it onto the page: in an unsplit window, the left or right half (shaded as you drag) splits the window with that tab alone on that side (a window's only tab leaves an empty start page behind); with a split, the other side's page takes it as its current tab. A side left without tabs closes. Not across windows yet. Tabs handle the mouse, and drop targets take the drag, in AppKit: in the title bar area the window takes any drag SwiftUI doesn't claim and moves itself, and SwiftUI's drop targets never see a drag started in AppKit.
- **Top of the window:** no title bar or toolbar. The sidebar and each side of the split have their own bar along the window's top edge, sized from where macOS puts the close, minimise and zoom buttons so everything sits on one line. The sidebar's bar holds New Note and Hide Sidebar; while the sidebar is hidden, the first side's bar holds them. Empty bar space drags the window and double-click zooms it, like a title bar.
- **Each side's bar:** the note's title, or with more than one tab, the tabs as the system's segmented control (the current tab a light pill). Then New Tab (+), and Split, or with a split, Close This Side (x). Right-click a tab: Close Tab, Close Other Tabs, Move to Other Side, Merge Both Sides into Tabs. With a split, the other side's title is dimmed.
- **Height and glass (18 October 2026, revised 24 October):** the window's toolbar holds only the system's sidebar button, which gives its top row the standard height (52 points on macOS 27); the bars line up with it. (An invisible toolbar item used to do this, but it took the clicks of whatever bar sat under it.) On macOS 26 and later, tabs are Liquid Glass capsules (the current one solid glass, the others clear glass, a close button on hover) and the bar buttons are round glass buttons. Older systems keep the segmented control and plain buttons.
- **Keyboard on load:** an editor only takes the keyboard if it's on the active side (and the note wasn't picked in the list), so rebuilding the split never moves the active side.
- **Later:** a blank tab will show a small file browser. Dragging tabs between sides.

- **Sorting in two columns (24 October 2026):** the notes column has its own sort menu along its bottom (date edited, date created, title), like the folders column's. Both are as wide as their column: a box like the search field's that opens the choices (`SortBar`), since the system's pop-up menu sizes itself to its text.

**G. Palettes, editor, sidebar, properties and identity** (Mike's notes, 24 October 2026). In seven batches, smallest first. Not started.

*Batch 0: back and forward, still not right* (first). Done 24 October 2026: each tab keeps its own history (a note opened in the tab counts, switching tabs doesn't); the arrows are off unless there's an existing note to go to; going back to a note open in another tab moves it here and that tab steps back itself (or shows a start page). Checked with real clicks sent through the window (`-PointClickBack YES`), ten checks, sidebar open and hidden.
1. **Back changes the sidebar highlight, but the note stays the same.** Likely the window-wide history going to a note open in another tab and not bringing that tab forward properly. To reproduce with the click test (`-PointClickBack`) and fix.
2. **Back is active with nowhere to go back to.** The arrow must be off when this tab has no earlier note.
3. **History belongs to each tab, not the window.** Each tab keeps its own back and forward. Every change of the tab's note counts: a note opened in it, a link followed, a note picked in the list. Switching tabs doesn't count.
   - **A note already open in another tab:** a note is open in at most one tab, so two editors never write the same file. Decision needed for going back to such a note. The plan: it moves into this tab, and the other tab goes back to the note before it, or to a start page. To confirm with Mike.
   - **The window-wide history goes:** per-tab history replaces it.

*Batch 1: editor and properties polish* (small, well-defined). Done 24 October 2026: tag pills 6 points either side and 2 above and below, with matching space around them; highlights and inline code drawn by the layout manager with 3-point corners, the text's height, line by line; the properties arrow is part of the button (the button moves into the margin, not just its label); the properties divider is a one-point separator-colour line, like a rule; properties open and close per note (remembered for the session, a new note starting as they were last left); and after a note opens, the rest of it is laid out in 20,000-character steps, so its true height is known before a fast scroll reaches the end. The scrolling fix couldn't be reproduced here, so needs confirming by hand.
1. **Tags:** more room inside the colour pill around the text.
2. **Highlight and inline code:** slightly rounded corners on their colour areas.
3. **Properties arrow:** clicking the arrow (not just the summary) opens and closes the properties.
4. **Properties divider:** the same weight and colour as a horizontal rule in the note.
5. **Properties open per note:** opening or closing them in one note, say in a split, leaves the other note alone. (Now one shared setting; it becomes per note, remembered for the session.)
6. **Bug: fast scrolling stops short of the end of a note.** Likely the editor laying out only what's on screen (non-contiguous layout) and not knowing the full height until later. To reproduce first, then fix (for example, finish layout in the background once a note opens).

*Batch 2: the properties element, redesigned*. Done 24 October 2026: one row per property (a column of keys as wide as the longest, left-aligned under the summary, 4 points above and below each row), a faint rounded background on the row under the pointer, a key renamed by clicking it (Return or clicking away renames, Escape cancels; only the name before the colon changes, quoted if YAML needs it: `Frontmatter.edit(renaming:to:in:)`), dragging a key still reorders, and the Add Property window laid out as a tight grid (labels, then 240-point fields, Kind as a segmented control). Hover and renaming need trying by hand.
1. A little more height for each row.
2. Keys aligned left, not right.
3. A faint background on a row under the pointer, so it's clear it can be clicked.
4. Renaming a key (click its name). Only that key's line changes in the file.
5. **The Add Property window:** a tighter layout, without the empty space on its right.

*Batch 3: the sidebar*. Done 24 October 2026:
- **Special places:** All Notes (`SidebarPlace.everything`) and Trash (`.trash`) at the top of both sidebar layouts, with no heading.
- **Where deleted notes go (decided):** a note deleted in Point always goes to the vault's `.trash` folder, whatever Obsidian is set to, because only notes there can be listed and put back. The deletion date and original folder are kept in Point's own settings, per vault (`VaultTrash`).
- **Clearing out:** notes kept longer than the set number of days (30 unless changed, in Settings › Notes) go for good when the vault opens and whenever the Trash is shown.
- **The Trash list:** each note with how long ago it went; right-click for Put Back (to its folder, or the top level if that's gone) or Delete Now; Empty asks first.
- **One column:** the Notes label always shows, with a sort menu on it. Inside a folder with folders, "Folders" and "Notes" label the two parts. With no folder in the list to unfold, there's no arrow column, and folders line up with the notes' text.
- **Checked:** a debug trash test (`-PointTrashTest <note>`) passed delete, list, put back and back; pictures of the top level, a folder with folders and one without.
1. **A top section with special places:**
   - **All Notes:** every note in one list, across folders.
   - **Trash:** notes deleted in Point are kept for 30 days, then removed for good. The number of days is in Settings. Decision needed: Obsidian has its own trash setting (system trash, the vault's `.trash` folder, or delete). The plan is that Point's Trash is the vault's `.trash` folder, so Obsidian sees the same notes, with Point clearing out notes older than the set number of days. To confirm with Mike.
2. **One column: a sort selector** at the top of the list (date edited, date created, title).
3. **One column, inside a folder with subfolders:** "Folders" and "Notes" labels over the two parts of the list. If none of the folders has subfolders, so there are no unfold arrows, the folders line up with the notes' text.

*Batch 4: the palettes* (bigger). Done 24 October 2026:
- **Dragging in the explorer:** notes drag onto folders, and folders onto folders (or the vault's top level), in the ⌘E explorer and on a start page, with the folder under the drag shaded. The explorer lists everything again when the vault changes, keeping its place.
- **⌘F:** every Format menu command, done to the selection the note had before the palette opened (sent to that note's editor). "Apply Template “name”" for each template, besides Insert Template….
- **New commands:** Block Quote (⌘') and Inline Code (⌥⌘C), in the Format menu, the palette and the cheat sheet.
- **Checked:** a debug test ran the palette's own Bold and Block Quote on a note's selection (`-PointFormatTest <note>`); the editor tests cover block quote and inline code. Dragging in the explorer needs trying by hand. (The debug picture steps' offscreen windows no longer crash on closing.)
1. **Dragging in the explorer:** drag notes and folders between folders in the ⌘E explorer (and its start-page version), as in the sidebar, so the sidebar is needed less.
2. **⌘F as a general command runner:**
   - **Templates:** "Apply Template…" inserts a template into the note.
   - **Formatting:** everything in the Format menu for the selected text, as commands: block quote, bold, italic, highlight, code, strikethrough, headings, lists, checklist, link.
   - **More:** anything else that acts on the current note or selection.

   Commands that act on a selection keep the selection the editor had before the palette opened.

*Batch 5: the editor* (biggest). Done 24 October 2026:
- **Where the cursors live:** the text view's own selection is the main cursor, and the others are kept beside it (`MarkdownTextView+Cursors`).
- **Editing:** typing, deleting, Return, Tab and the arrow keys (with or without ⇧) are done at each cursor in turn, last first, with the editor's usual handling each time: lists continue, hidden markers are stepped over. It all undoes in one step.
- **Adding cursors:** ⌥-click (⌥-click on a link still places the cursor in it), ⌃⇧↑ / ⌃⇧↓ for the line above or below, and ⌘D (the word first, then each next match). These are in the Format menu and the cheat sheet.
- **Back to one:** Escape, a plain click, undo, or any other command.
- **Drawing:** the other cursors are text-height, and their selections are drawn like the main one.
- **Tests:** seven editor tests cover typing, deleting, lists, ⌘D, adding a cursor below, Escape and undo. To try by hand: ⌥-click, and the feel of it.
1. **Several cursors at once,** as in code editors:
   - **Adding cursors:** ⌥-click adds a cursor; ⌃⇧↑/↓ adds one on the line above or below; ⌘D adds the next match of the selection.
   - **Typing:** it goes in at every cursor; Escape goes back to one.
   - **What's hard:** the hidden Markdown markers, list continuation and undo all assume one cursor. A design note comes first.

*Batch 6: identity*. Done 24 October 2026:
- **The name:** the app is Point: its name, the project and target (`Point.xcodeproj`, `Point-Mac`), the types and files once called Imprint, and the debug switches (`-PointVault`, `-PointTrace` and so on). This plan and the README use the new name throughout, history included.
- **Kept on purpose:** the bundle identifier, `org.mikegallagher.imprint` (a new one would mean a new sandbox container, losing the settings and the vault's saved access), and the search index's folder (so it isn't built again). Neither is seen.
- **The icon:** `Resources/AppIcon.icon` (Icon Composer). Light is a pale yellow field with a small dark blue dot; dark swaps the colours. Xcode makes older systems' icon from it.
- **Left for Mike:** renaming the GitHub repository and the local folder (`Repos/imprint`), which change links, remotes and this checkout's path.
1. **Icon:** a pale yellow square field with a small dark blue dot in the middle; in dark mode the colours swap (a dark blue field, a pale yellow dot). Made as an Icon Composer (`.icon`) file with light and dark variants, plus a plain asset-catalog icon for macOS before 26.
2. **Rename to Point:**
   - **In the app:** its name, the bundle identifier (`org.mikegallagher.point`), the targets in `project.yml`, and the names in the code and docs.
   - **Migration:** settings and the saved vault access move over from the old identifier, so nothing is lost. The sandbox container changes with the identifier, so this needs care.
   - **The repository:** renaming it on GitHub, and the local folder, is for Mike to do or approve, since it changes links and remotes.

**To do (24 October 2026, separate from H):** the bottom bars line up. The links bar under a note ("1 link here", `ConnectionsBar`) is shorter than the two-column sidebar's sort bars beside it (`SortBar`: 6 points, a 26-point box, 6 points, plus its top line, about 39 in all). Make the links bar exactly the sort bar's height, its top line level with theirs and its text centred, so the three read as one strip along the bottom of the window. Best done by giving both one shared height constant rather than matching by eye, then checking in a picture with the sidebar in two columns.

**To do (24 October 2026, separate from H): moving a big folder hangs the app.** Dragging Projects › Archive (about 1,240 notes) in the ⌘E explorer beach-balls for a while before it finishes. It must not hang: good software is fast software, and where work takes time, the person should see the result at once while the rest finishes in the background.
- **Why (from the code):** `VaultStore.moveFolder` moves the folder on disk in one step (quick), then updates each note inside it one at a time with `replace(_:with:url:)`. Each update changes `notes`, which rebuilds the folder tree and the link resolver over every note in the vault, publishes a change, and posts a "note moved" notice that every window handles. Each folder-tree change also makes the open explorer list everything again. That's about 1,240 × 5,000 steps on the main thread, plus 1,240 redraws.
- **The fix:**
  - **One update, not 1,240:** build the new notes list once and assign it once (one rebuild, one change). Post one "folder moved" notice, which each window uses to remap its tabs, history and selection by path prefix.
  - **Off the main thread:** move the files with `NSFileCoordinator` and rescan in the background, so the window keeps responding.
  - **Show it at once:** the explorer and sidebar show the folder in its new place as soon as it's dropped, and correct themselves if the move fails (with a message). Notes open from the folder keep showing throughout.
  - **No redraw storm:** the explorer's reload on vault changes is coalesced (once per run-loop turn, or debounced), not run on every change.
- **Check:** time a move of Archive in a copy of a big vault (not the real one) with `-PointTrace`. The drop should return in well under a frame's worth of main-thread time, with the file work after it. Also check moving a single note still feels instant.

**To do (24 October 2026, separate from H): All Notes and Trash in the explorer.** The ⌘E explorer (and its start-page version) lists the same special places as the sidebar, at the top of its left column with no heading: All Notes (every note, in the right column) and Trash. `ExplorerState.load` adds them before Pinned, with the `tray.full` and `trash` symbols. The Trash's right column lists deleted notes with how long ago each went. Return puts the highlighted one back, since a trashed note can't be opened, and the right-click menu has Put Back and Delete Now. Neither takes drops yet (dropping on Trash to delete could come later).

**To do (24 October 2026, separate from H): applying a template to a note that has properties.** Today `VaultModel.insertTemplate` inserts the whole rendered template at the cursor, its `---` frontmatter block included, so a note with properties gets a second block in the middle of its text. Instead, the template's properties and its text are handled separately:
- **Its properties:** merged into the note's own, by key.
  - **Same keys:** if the note already has every key the template has (the same set, or more besides), nothing changes. A note's existing values are never overwritten.
  - **Keys the note lacks:** if the template has keys the note doesn't, only those are added, with the template's values (rendered, so `{{date}}` and the like are filled in), after the note's existing properties, each as its own line. Only those lines change in the file (`Frontmatter.edit(adding:)` per key).
  - **A note with no properties:** it gets the template's block at the top of the note, not at the cursor.
- **Its text** (everything after its frontmatter) goes in at the cursor, as now.
- **Undo:** one undo takes back both parts.
- **Tests (VaultKit or EditorKit):** same set, a subset of the note's, more keys in the template, no frontmatter in the note, no frontmatter in the template. Also a template key that matches a note key with a different value: the note's value stays.

**H. Capsules everywhere** (Mike, 24 October 2026). Not started. Every highlight and box becomes a fully rounded capsule, to match the Liquid Glass controls, even where Finder uses rounded rectangles (Mike finds that mix incoherent). Smallest first:

1. **Our own shapes become capsules** (a line each, `Capsule()` in place of `RoundedRectangle`):
   - **In the top bar and sidebar:** tabs (`NoteTab`, 32 tall); the sidebar search field (`SearchField`); and the sort menus at the bottom of the two-column sidebar (`SortBar`).
   - **In the palette and explorer:** the start page's search box, palette rows (`PaletteRow`, including the blue highlight), and explorer rows (`ExplorerRow`).
   - **In a note:** properties rows on hover (`PropertiesStrip`).
   - **Check:** pictures of each, light and dark; a capsule on a tall two-line row may look too round, in which case it keeps the capsule's ends but at the row's height.
2. **One-column sidebar selection** (`SidebarTable`, an AppKit source list): the system draws the selected row as a rounded rectangle. A custom `NSTableRowView` (`drawSelection(in:)` drawing a capsule, inset like the system's, in the accent colour when the list has the keyboard and grey when not) replaces it, set through `tableView(_:rowViewForRow:)`. About 30 lines. Also the drop highlight on folders while dragging.
3. **Two-column folder tree selection** (`PlaceTreeColumn`, a SwiftUI sidebar `List`): the hardest, since SwiftUI draws the selection with no shape setting. Two options, to choose when we get there:
   - **Keep the List, draw our own selection:** hide the system's and draw a capsule behind the selected row with `listRowBackground`, from the model's place. Keyboard focus and the unemphasized (window inactive) state need handling by hand.
   - **Rebuild the tree as an AppKit outline view** like the one-column list, with the same capsule row view. More work, but one way of drawing for both sidebars.

   Try the first. If it fights the system (flicker, or focus rings), do the second.
4. **Anything else rounded:** look through for remaining `RoundedRectangle`s (the tag pills are capsules already; highlights and inline code keep small rounded corners, since they're text, not controls).

### M4 — iPhone
Buy the developer account first.
- Folder access through Files, list and editor.
- Formatting bar above the keyboard.
- Capture: control, Siri and App Intents, share extension.

### M5 — Meaning
- Embeddings index.
- Semantic search, related notes and tag suggestions.
- Weekly digest, topics over time and clusters, generated on the M3.

### M6 — Extras
- Apple Watch capture.
- Rich editing for tables, embeds and footnotes.
- Liquid Glass polish on macOS 26.

## Risks

1. **The editor.** Hiding syntax while keeping cursor movement, selection, undo and IME input natural is the hardest part. That's why M1 is first and isolated.
2. **iCloud Drive without an entitlement.** Files can be evicted, show up as placeholders, or arrive as conflict versions. We need to trigger downloads and coordinate reads and writes. Test early in M2.
3. **Concurrent Obsidian edits.** Both apps may write the same file. Use file coordination and reload, and never overwrite a newer version blindly.
4. **macOS 13.** TextKit and SwiftUI are older. Mitigation: test on the 2017 Mac at every milestone, and accept a simpler experience there.
5. **On-device model quality.** Foundation Models is small, so digests may be shallow. Mitigation: keep prompts narrow, and lean on embeddings and statistics for topics and clusters.
6. **Digests depend on the M3.** They're only generated when the M3 is awake and running the app. Mitigation: generate on launch for any missed weeks.

## Exploration: radically minimal (issue #2, branch `minimalist`)

**The question.** Can Point drop the usual "explorer on the left, note on the right" layout? The needs: keep a bunch of notes open, find things quickly, show as little interface as possible. Principles 5, 7 and 9 point the same way: fast, minimal, and the command palette as the main way to do things.

**Outcome (19 October 2026): no separate mode.** The draft built a third layout, "Minimal". Once the sidebar layouts gained its tabs, top bar, splitting and palette, hiding the sidebar gave almost exactly Minimal, so Minimal was folded into the app: **hiding the sidebar is the minimal setup**, remembered for new windows and relaunches. A saved "Minimal" setting becomes One column with the sidebar hidden. Settings keeps One column / Two columns, which only shape the sidebar when it shows.

**What the exploration added to the app:**
1. **Explorer or note.** You rarely need the explorer and the note at once. With the sidebar hidden, a window is one compact note (as narrow as 420 points), to sit beside other windows.
2. **Tabs along the top,** drawn by Point (Mike didn't like the glass tabs): each tab its title's whole width plus a little padding, never cut off; when they don't fit, the row scrolls sideways, keeping the current tab in view; the selected tab light grey; no shadows; a close button on hover at each tab's leading edge, as in Safari. (The first draft put tabs in a list down the side; Mike preferred regular tabs.)
3. **One top bar:** white like the page, with a hairline under it like the one under the properties, starting clear of the window buttons (measured from the window). No New Tab button (⌘T); a Split button, or with a split, a close button for each side. The sidebar button is the system's own (at the sidebar's edge, or just past the window buttons while it's hidden; Point's own button didn't receive clicks there while the sidebar was hidden). No New Note button (⌘N or the palette; removed 19 October 2026). The bar always shows tabs, even a single one.
4. **Above every note: its path, then its title.** (Issue #4, 19 October 2026: this header, with the properties and a new note's templates, now scrolls with the note, inside the editor, rather than staying fixed above it, and its spacing is tighter. Issue #5: a hairline always separates it from the text, with or without properties.) The path ("MG notes › Projects › Archive") is in the properties' size and colour, nothing bold; the title is large, in medium weight (most notes don't start with a heading). The path used to be in the top bar, only with one tab; Mike wanted it always (19 October 2026).
5. **Every new or empty tab is a start page:** the command palette laid out as the page, with exactly the palette's list (recent notes, then New Note, Today's Note and Explorer; typing searches everything, as ⌘F does). Choosing Explorer, or ⌘E on a start page, turns the page into the explorer. (An earlier version had its own list, recent notes and "Browse Folders and Tags"; Mike preferred the palette's, 19 October 2026.) ⌘F and ⌘E on a start page switch the page itself, rather than opening a palette on top.
6. **The palette is one size whether searching or exploring:** 540 points wide with a 420-point list, a roomier typing area, a divider running to its edges, rounder corners (16 points), no outline, and one shadow for the whole panel (none on the selection). The start page is 600 wide.
7. **The explorer has two columns,** like the two-column sidebar, on the start page and in the ⌘E palette alike: pinned places, folders (nested) and tags (nested) on the left; the highlighted place's notes on the right. ↑↓ move, → or Return goes into the notes, ← goes back (on a start page, ← from the places goes back to recent notes), typing filters whichever column has the keyboard, and Return opens a note (⌘Return in a new tab). It reopens where it was left.
8. **Splitting:** the Split button or ⇧⌘S, ⌥⌘-click and Open to the Side. Each side has its own tabs, and an empty side shows a start page. A tab can also go to its own window ("Open in New Window").
9. **New note gives a choice without slowing you down.** ⌘N opens a blank note in a new tab (or fills an empty one) with the cursor in it. While it's empty, a row of templates sits above the text; typing anything removes it.
10. **Shortcuts:** ⌘F opens the palette to search; ⌘E opens it as the explorer. ⇧⌘F goes to the sidebar's search field (showing the sidebar), also "Search in List" in the palette. ⌥⌘F stays Find in Note; ⇧⌘E is free. ⌥⌘↑ / ⌥⌘↓ move the current line (or the selected lines) up or down; the Previous and Next Note shortcuts are gone.
11. **Clicking a tag** searches for it in the palette while the sidebar is hidden, or in the sidebar's search field while it shows.
12. **New folders** (19 October 2026): New Folder… (⇧⌘N, the File menu, the palette, or "New Folder Inside…" on a folder) asks for a name and makes it inside the folder being browsed (or the vault root), then browses into it, so ⌘N puts a note there. Folders now come from disk as well as from where notes are, so empty folders show (with a count of 0), here and in Obsidian's vault alike.
13. **Sidebar density** (issue #6, 19 October 2026): Comfortable (the default) or Compact, in Settings > Sidebar or the palette. Both layouts follow it: the two-column tree uses the system's medium or small sidebar rows (32 or 24 points, text kept at the normal size), and the one-column list and the note list use the same heights, so the columns line up.

**Checks:** all package tests pass (VaultKit 62, MarkdownKit 33, EditorKit 57 including line moving, IndexKit 18). Layouts were checked from pictures saved by a debug hook (`-PointSnapshots <folder>`, with `-showsNoteList NO` to start with the sidebar hidden): tabs, the top bar with and without the sidebar, the start page and its explorer, both palettes, the template row, splits. Glass buttons don't show in those pictures. Not yet tried by hand: the explorer's keys, and opening a second window.

**Later:** windows that snap together; auto-hiding the sidebar below a set window width (see Topics for investigation).

## Exploration: no visible tabs (branch `no-visible-tabs`)

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

## Properties, redesigned (25 October 2026)

**Why:** a property couldn't be deleted (the edit existed but nothing called it) or have its type changed, and tags behaved differently from note to note. YAML has two ways to write a list (`tags: [a, b]` on one line, or `tags:` followed by `- a` lines); Point read both but wrote only the second, and read `tags: work` as text, so typing "work, ideas" there saved one quoted string.

**Decided (Mike):** rows like Obsidian's; lists as tokens; types from Obsidian's own file; lists always written with `-` lines.

**Built:**
- **Types** come from `.obsidian/types.json`, as Obsidian keeps them, so a property has the same type in every note and in Obsidian (`PropertyTypes` in VaultKit). `tags` is always Tags and `aliases` Aliases; a key with no type is guessed from the note (a list, a date, a date and time, true or false, a number, else text). Changing a type writes the file (keeping everything else in it, including types Point doesn't know) and carries the note's value over: text split into items at commas, items joined into text, anything that doesn't fit left empty. Renaming a property takes its type to the new name.
- **Each row:** the type's icon (click it to change the type), the name (click to rename, drag to reorder), the value, edited to suit the type, and a ⋯ menu on hover (Rename, Change Type, Delete), also on right-click. Clicking a row's empty space selects it (tinted); ⌫ or ⌦ deletes it, Escape lets it go.
- **Values:** text and numbers in a field (a number that doesn't read as one goes back); a checkbox; the system's date, or date and time, picker (an empty one offers "Empty", which sets it to now); lists, tags and aliases as tokens, each with a remove button, and a field after them where Return or a comma adds an item (⌫ in the empty field removes the last, from macOS 14). Tags offer up to six matching tags from the vault while typing. Tags written on one line (`tags: work ideas`) show as separate tokens.
- **Writing:** every list Point writes uses `-` lines, whichever way the note had it.
- **Add Property:** every type, starting from the vault's type for the name typed (or tags, or date for date-like names); a new name's type is recorded for the vault.
- **Checked:** VaultKit tests for types (guessing, the vault's type winning, converting, saving without losing the rest of the file) and for rewriting lists; a picture of a note with one property of each type. Not tried by hand yet: every interaction (Point's windows couldn't be clicked while Mike's own copy was running).

## Plan: the sidebar widens the window (25 October 2026; step 1 built)

**The aim (Mike):** showing or hiding the sidebar changes the window's width, not the notes': the notes area stays the same width, as long as the window fits on the screen, with graceful fallbacks when it doesn't.

**Today:** the window keeps its size and the notes give up or take the sidebar's space. The two-finger swipe is a trigger: once a sideways swipe is 10% under way, the sidebar toggles and animates on its own. Narrowing the window past 760 points hides the sidebar, and widening it past that brings it back.

**Learned before (Part F):** an earlier version widened and narrowed the window by remembered amounts, and drifted whenever a resize was cut short (the minimum width, the screen's edge, full screen), sometimes leaving the window wider than the screen. So nothing here relies on a remembered amount alone: every resize is worked out from the sidebar's real width at the time.

**Decided (Mike):**
1. **The window grows rightwards:** its left edge stays, the sidebar appears there and the notes move right; the right edge moves out. Hiding pulls the right edge back in.
2. **When there isn't room:** first slide the window left so it stays on its screen, growing as much as the screen allows; only if it would be wider than the screen do the notes give up the rest, as today.
3. **The swipe follows the fingers:** the sidebar and the window's right edge move with the swipe, and settle open or closed on release, like swiping between pages.
4. **The same for ⌘S and the sidebar button,** and for **auto-hide** when narrowing or widening the window. Focus mode is unchanged (the notes take the space).

**How it would work:**
- **Measuring:** the sidebar's width is read from the split view (the window's `NSSplitView`, its first pane) when it hides, and kept per window as the width to show it at next. After showing, the real width is read again and the window corrected by any difference, so the notes end exactly as wide as before.
- **Showing:** target width = window width + sidebar width. If the right edge would pass the screen's visible frame, the window slides left (its left edge no lower than the screen's). If the target is wider than the screen's visible width, the window takes the screen's width and the notes give up the difference, which is noted (the shortfall).
- **Hiding:** target width = window width − sidebar width + any shortfall (so notes that gave up room get it back, if the screen allows). The shortfall is forgotten if the window is resized by hand in between, since the notes' width is then the person's choice. The window's minimum width (600 with the sidebar, 420 without) changes only after the resize, so it never blocks one.
- **Animating together:** the window's frame and the sidebar's collapse animate in one AppKit animation group (`NSWindow.animator().setFrame` with the split view item's `animator().isCollapsed`), driven directly rather than through SwiftUI's column visibility, which is kept in step afterwards. The two separate animations are what would make the notes jitter.
- **When not to resize:** full screen, zoomed to fill the screen, or Stage Manager's tiling: the window can't or shouldn't change size there, so the notes take the space, as today.
- **The interactive swipe:** while tracking (`trackSwipeEvent`, which gives a running amount from 0 to 1), the sidebar's minimum width is lowered to 0 for the gesture, its divider set to amount × width, and the window's width to base + amount × width, every frame. On release it finishes the rest of the way, or springs back, with the same animation as above; the minimum width returns once it settles.
- **Auto-hide:** a window can't be resized while its edge is being dragged, so this happens when the drag ends: if the sidebar hid during the drag, the window then narrows by the sidebar's width (the notes keep the width they had when it hid); if it reappeared, the window widens by it. This may feel like a jump on release; to be judged once built, with today's behaviour (no resize) to fall back to.
- **Unchanged:** dragging the sidebar's divider (the notes give and take, as in Finder), a split's two sides (they keep their proportions, as the notes' total width doesn't change), new windows (they open as the last one was left, at their saved size).

**Order:** (1) measuring and the animated resize for ⌘S, the button and the current swipe trigger, with the screen fallbacks; (2) the swipe following the fingers, the riskiest part, as it drives SwiftUI's split view from AppKit (if it can't be made smooth, the trigger stays); (3) auto-hide at the end of a drag.

**Step 1, built (25 October 2026, uncommitted):** `SidebarSizing` (one per window, on `VaultModel`). ⌘S, the swipe and the system's sidebar button widen or narrow the window by the sidebar's width; auto-hide and focus mode don't (auto-hide is step 3). As planned, plus:
- **The width** comes from the sidebar as shown, or the width a collapsed sidebar keeps, so it's right the first time; after showing, any difference is corrected.
- **Undone exactly:** how far the window slid left and how much the notes' width had to change (positive when the screen was too narrow, negative when the window couldn't go below its 420-point minimum) are both undone at the next show or hide, unless the window was moved or resized in between. The window's minimum is lowered before a resize so the old one can't stop it.
- **The system's button** collapses the sidebar itself before the app hears of it, so the sidebar's collapsed state is watched (KVO) and the window starts resizing with it; the app's own changes without resizing (at launch, focus mode, auto-hide) are ignored for a moment so they aren't taken for the button.
- **Each resize settles once,** at the end of its animation or, if that doesn't come (a window out of sight, or a locked screen, doesn't run animations), shortly after it should have, by setting the frame. A completion arriving after the sidebar has been toggled again is ignored; before this, one could toggle it back and loop.
- **Checked** with a debug hook (`-PointSidebarCycle n`, with `-PointWindowFrame "x y w h"` and `-PointSidebarButton YES`) tracing the window's frame after each toggle: twenty cycles end exactly where they began; a window near the right edge slides left and back; one too wide for the screen takes the screen's width and gets the notes' width back on hiding; one at its minimum width; the two-column sidebar; launch doesn't resize. Not seen yet: the animation itself (the screen was locked for the later runs, so they fell back to setting the frame), and the system's button with real clicks.

**To check by hand:** a window near the right edge of the screen, one wider than the screen with the sidebar, two displays, full screen, a split, the two-column sidebar (470 points wide), and that showing and hiding fifty times leaves the window where it started.

## Topics for investigation

### Daily notes as a meeting log
Today, each meeting gets its own note, because finding things inside daily notes in Obsidian is hard. The goal is one note per day holding all that day's meetings (for example seven), which only works if any one meeting's minutes are easy to find later. To investigate:

- **Search that knows about sections:** results that point to the heading a match is under, and open the note scrolled to that heading.
- **Section links:** linking to one meeting, as in `[[2026-10-18#Team sync]]`, with backlinks shown per section.
- **A meetings view:** every meeting heading across all daily notes as one list, filterable by person, tag or date. This could come straight from the search index.
- **Marking a meeting:** decide how a section counts as a meeting. Options are a heading level, a `#meeting` tag under the heading, or a template.
- **Quick entry:** a "New Meeting" command that adds a meeting section to today's note from a template, including the time.

- **Auto-hide the list in narrow windows:** shrinking a window below a set width hides the note list (filed 18 October 2026, not started).

## Open questions

1. **Templater:** do you use the Templater community plugin (`<% %>` syntax), or only Obsidian's core Templates? Templater scripts can't be run outside Obsidian. We'd preserve them, but they wouldn't expand.
2. **Focus mode icons:** which icons stay visible besides the note-list button.
(Questions 3–7, about the sidebar, were answered in October 2026; see "Sidebar navigation".)
(Questions 8 and 9, about tabs and pins in the two-column view, were answered on 18 October 2026; see Part E.)
