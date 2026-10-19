# Imprint — plan

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
- **Pins:** folders and tags can be pinned (right-click), such as the NHS, Sources and Personal folders. Pins are stored in Imprint's settings, per vault, never in the vault.
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
| ⇧⌘T | Today's note |
| ⌘-click | Open a note or link in a new tab |
| ⌘, | Settings |

All shortcuts will be remappable.

## Architecture

```
Imprint.xcodeproj
├─ Imprint (macOS app, deployment target 13.0)
├─ Imprint (iOS app, 26.0)            + share extension, controls/intents, watchOS app
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
   - Finding: a debug trace (`-ImprintTrace <file>`) shows the rows, with their tags and dates, are built 0.2 s after the click, so the data isn't late. The delay is in how SwiftUI's `List` lays out and draws rows. It can't be seen from Claude's tools.
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
     - **Tabs:** native tabs at first; replaced on 18 October 2026 by Imprint's own tabs inside each side of a split (see Part F, "Panes and tabs"). ⌘T is New Tab, and Today's Note moved to ⇧⌘T.
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
- **New Note button** in the toolbar, beside the button that hides the sidebar.

**Panes and tabs (decided 18 October 2026, built and checked in the app):**
- **Decisions:** the split sits at the top of the note area, and each side has its own tabs (like Xcode or VS Code editor groups). These replace macOS window tabs, which are turned off. The window never resizes itself: hiding the list or splitting gives the space to the notes, whose text column (with its maximum width) recentres. The old approach widened and narrowed the window by remembered amounts, which drifted whenever a resize was cut short (minimum width, screen edge, full screen) and could leave the window wider than the screen.
- **Model:** a window has one or two panes; a pane has tabs; a tab has a note (or none) and its own back/forward history. The active pane is the one last typed or clicked in; the list, palette, Go menu and note commands act on it. A note is open in at most one tab per window, so opening it again goes to that tab.
- **Keys and menus:** ⇧⌘S splits, with an empty side that gets the next note picked; pressed again, it merges both sides back into one side's tabs. ⌘T new tab, ⌘W close tab (a side's last tab closes the side; the window's last closes the window), ⇧⌘[ / ⇧⌘] previous and next tab, ⌥⌘N new window. View > Move Tab to Other Side (or to a new split). ⌥⌘-click and Open to the Side open a note on the other side.
- **Top of the window:** no title bar or toolbar. The sidebar and each side of the split have their own bar along the window's top edge, sized from where macOS puts the close, minimise and zoom buttons so everything sits on one line. The sidebar's bar holds New Note and Hide Sidebar; while the sidebar is hidden, the first side's bar holds them. Empty bar space drags the window and double-click zooms it, like a title bar.
- **Each side's bar:** the note's title, or with more than one tab, the tabs as the system's segmented control (the current tab a light pill). Then New Tab (+), and Split, or with a split, Close This Side (x). Right-click a tab: Close Tab, Close Other Tabs, Move to Other Side, Merge Both Sides into Tabs. With a split, the other side's title is dimmed.
- **Height and glass (18 October 2026):** the window keeps an empty toolbar (its one invisible item has no glass backing), so its top row has the system's standard height (52 points on macOS 27) and the bars line up with it; clicks still reach the bars. On macOS 26 and later, tabs are Liquid Glass capsules (the current one solid glass, the others clear glass, a close button on hover) and the bar buttons are round glass buttons. Older systems keep the segmented control and plain buttons.
- **Keyboard on load:** an editor only takes the keyboard if it's on the active side (and the note wasn't picked in the list), so rebuilding the split never moves the active side.
- **Later:** a blank tab will show a small file browser. Dragging tabs between sides.

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

**The question.** Can Imprint drop the usual "explorer on the left, note on the right" layout? The needs: keep a bunch of notes open, find things quickly, show as little interface as possible. Principles 5, 7 and 9 point the same way: fast, minimal, and the command palette as the main way to do things.

**Decisions:**
1. **A third layout, "Minimal",** beside One column and Two columns (Settings > Sidebar > Layout, or the palette's "Use Minimal Layout"). It's a layout rather than a replacement, so the two can be compared day to day.
2. **Explorer or note, never both.** You don't need the explorer and the note at the same time. The window is one compact note (it can be as narrow as 420 points), to sit beside other windows.
3. **Tabs along the top,** drawn by Imprint (Mike didn't like the glass tabs), revised 19 October 2026: the top row is always light grey; each tab is its natural width plus a little padding, and only shares the width equally (titles truncated) once they don't fit; the selected tab is a slightly darker grey; no shadows; a close button on hover at each tab's leading edge, as in Safari. The row starts clear of the window buttons, measured from the window. + opens a new tab. The same tabs are used in the other layouts on this branch. (The first draft put tabs in a list down the side; Mike preferred regular tabs.)
   - **With one tab,** the top row shows the note's path: its folders, then its name in bold.
   - **The note's title always shows above its properties** (the path is too small to be the main title, and most notes don't start with a heading).
4. **Every new or empty tab is a start page:** a large search field (searching everything, as ⌘F does) over recent notes and "Browse Folders and Tags". Browsing, or ⌘E on a start page, turns the page into the explorer.
5. **The palette is one size whether searching or exploring:** 540 points wide with a 420-point list (the explorer's height), a roomier typing area, a divider running to its edges, rounder corners (16 points) and one shadow for the whole panel (none on the selection). The start page is 600 wide. **⌘F and ⌘E on a start page switch the page itself** between searching and exploring, rather than opening a palette on top. **The explorer has two columns,** like the two-column sidebar, on the start page and in the ⌘E palette alike: pinned places, folders (nested) and tags (nested) on the left; the highlighted place's notes on the right. ↑↓ move, → or Return goes into the notes, ← goes back (on a start page, ← from the places goes back to recent notes), typing filters whichever column has the keyboard, and Return opens a note (⌘Return in a new tab). It reopens where it was left.
6. **No splitting.** Two notes side by side means two windows: ⌥⌘-click, Open to the Side and a tab's "Open in New Window" open a new window; ⇧⌘S is unavailable.
7. **New note gives a choice without slowing you down.** ⌘N opens a blank note in a new tab with the cursor in it. While it's empty, a row of templates sits above the text; typing anything removes it.
8. **Shortcuts (in every layout, decided 19 October 2026):** ⌘F opens the palette to search; ⌘E opens it as the explorer (on a start page, both switch the page itself). In the sidebar layouts, ⇧⌘F goes to the list's search field (also "Search in List" in the palette); Minimal has no list. ⌥⌘F stays Find in Note. ⇧⌘E is free. One scheme for all layouts, so switching layouts never changes what the keys do.
   **Line moving:** ⌥⌘↑ / ⌥⌘↓ move the current line (or the selected lines) up or down (Format menu). The Previous and Next Note shortcuts are gone: the list isn't on screen in Minimal.
9. **Search goes through the palette.** ⌘F and clicking a tag open the palette (with the tag typed in).

**Draft status (19 October 2026):** built on branch `minimalist`. Checked from pictures of the window saved by a debug hook (`-ImprintSnapshots <folder>` with `-browsingStyle minimal`): top tabs, the start page, its explorer, the ⌘E explorer over a note, the template row and the single-tab window all render as intended. The + button's glass doesn't show in those pictures. Line moving is covered by EditorKit tests. Not yet tried by hand: the explorer's keys, and opening a second window.

**Not in the draft:** windows that snap together; a pinned first "explorer" tab (decided against: ⌘T reaches the start page from anywhere, which is simpler); a slimmer default size for new Minimal windows.

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
