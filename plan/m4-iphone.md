# M4: the iPhone app (sketched 27 October 2026)

Part of [the plan](../PLAN.md). Replaces the outline under M4 in [Milestones](milestones.md).

Simple, fast and obvious. It doesn't do everything the Mac app does: it does three things well.

1. **Writing a new note**, fast: one tap to a blank page with the keyboard up.
2. **Looking something up**, most likely a note from the last few days, or one of a handful looked at again and again.
3. **Editing one note through the day**, at a workshop or event: always one tap away, never losing a word.

Syncing waits: the first versions work on a vault folder on the phone, to get the mechanics right. (Picking the iCloud vault comes after; see "Later".)

## What it is

Two screens and a button.

**Home** is the app. It opens here (or back in the note being worked on; see "Coming back").

```
┌─────────────────────────────┐
│ 🔍 Search                    │  Search field, always at the top.
│                             │
│ Workshop notes          ›   │  The note being worked on, if one was
│ Edited 4 minutes ago        │  edited today.
│                             │
│ BOOKMARKS                   │  The handful looked at regularly.
│ Reading list                │
│ People                      │
│ Current projects            │
│                             │
│ RECENT                      │  Everything else, newest first:
│ Team sync           14:02   │  edited (or opened) most recently.
│ Idea for the talk   Mon     │
│ Ann Smith           Sun     │
│ …                           │
│                        ╭──╮ │
│                        │✎ │ │  New note, always in reach of the thumb.
│                        ╰──╯ │
└─────────────────────────────┘
```

- **Search:** typing narrows the list in place: titles first, then text, as on the Mac (IndexKit), with `#tags` as filters. Nothing to choose, no scopes.
- **Bookmarks:** the regulars, from Obsidian's bookmarks (see "Decided"). Long-press a note to bookmark it, drag to reorder.
- **Recent:** by date edited, and opened on this phone. No folders, no tags, no sorting choices. (Folders and tags can come later, if search plus recent isn't enough.)
- **New note:** the round button. One tap, a blank note with the keyboard up.

**The note** fills the screen. Back (or a swipe from the left edge) goes home.

```
┌─────────────────────────────┐
│ ‹                       ⋯   │  Back; a menu with Bookmark, Share, Delete.
│                             │
│ Workshop notes              │  The title is the file name.
│                             │
│ - Opening: why services fail│  The note, styled as on the Mac, Markdown
│ - Ann: "start with the..."  │  hidden.
│ - [ ] follow up with Bo     │
│ █                           │
│─────────────────────────────│
│ • ☐ ⇥ ⇤  # [[  ⌄           │  Above the keyboard: list, checkbox,
│ q w e r t y u i o p         │  indent, outdent, tag, link, hide keyboard.
└─────────────────────────────┘
```

- **Saving** is automatic and constant (a second after typing stops, and whenever the app leaves the screen), with the Mac's safety: never over a change made elsewhere, and edits that can't be saved kept as a draft.
- **A new note's title** comes from its first line, as on the Mac. An empty note is removed when left.
- **Properties** show as a single line under the title ("3 properties · #work"), not editable at first.
- **Links** open their note; `[[` suggests notes as you type; `#` suggests tags.

**Coming back:** opened the same day as last editing a note (and without going home or opening another note since), the app goes straight back into it, where the cursor was. Otherwise it opens home. This is what makes a day at a workshop work: unlock, tap, keep typing.

**Getting to a new note even faster:** pressing and holding the app icon offers New Note (a home screen quick action, which needs no extension). With the paid developer account: a Lock Screen and Control Center control (also the Action button), and Siri, as [decided](decisions.md#quick-capture-iphone).

## What it leaves out (at first)

Folders and the tag tree, the properties editor, templates and daily notes, the links panel and unlinked mentions, renaming (other than by the first line), moving, the trash list, tabs and splits, the command palette, Settings. Each is worth adding only if its absence is felt.

## How it's built

- **Shared, as is:** MarkdownKit and IndexKit build for iOS already. VaultKit builds except for its file watcher, which uses FSEvents (Mac only). On iOS, file coordination with `NSFilePresenter` replaces it; that's needed for iCloud later anyway.
- **The editor is the work.** EditorKit is about 3,000 lines of AppKit. Most of it (the styler, the hidden markers, the drawing of lists and checkboxes, the cursor rules) is logic that UIKit can share: TextKit 1 is on iOS too (`UITextView(usingTextLayoutManager: false)`), with the same `NSLayoutManager` hooks. The plan: split EditorKit into a shared core (styling and layout, with colours and fonts behind small platform aliases) and two thin views, `NSTextView` on the Mac and `UITextView` on iOS. Selection and the cursor differ most: touch, the magnifier, and the keyboard's own cursor movement.
- **The app:** SwiftUI, a navigation stack with two screens; the editor wrapped from UIKit. iOS 26, on the iPhone 13.
- **The vault on the phone, for now:** a folder in the app's own Documents, visible in the Files app. Copy notes in through Finder or Files (a copy of the real vault, or part of it), so the phone app can be judged on real notes without touching them.
- **The search index:** built on the phone, outside the vault, as on the Mac.

## Steps

Each ends with a build on the iPhone to try. Free-account builds work for steps 0 to 4; they expire after 7 days and can't have extensions.

0. **The spike (the risk first):** an iOS target; VaultKit's watcher made Mac only; the editor showing a note in a `UITextView` with the Markdown hidden. Measure on the iPhone 13: opening the longest note, and typing in it. If TextKit 1 on iOS fights back, this is where we find out.
1. **Looking up:** home with search, bookmarks and recent, opening notes to read. The vault in the app's Documents folder.
2. **Writing:** the new-note button, the first line as the title, saving as on the Mac (with drafts), the empty note removed, the quick action.
3. **Editing through the day:** the bar above the keyboard, link and tag suggestions, coming back to the note being worked on, the cursor kept, undo.
4. **Making it feel right:** Dynamic Type, dark mode, haptics, large notes, the keyboard never covering the cursor, VoiceOver.
5. **Then:** the real vault through the Files app (iCloud), and with the paid account, the control, Siri and the share sheet.

## Step 0, the spike (27 October 2026)

**Built:**
- **The shared packages run on iOS:** VaultKit's file watcher is Mac only, and one expression in IndexKit was split up so the iOS compiler could type-check it.
- **EditorKit is split:** the styler, decorations and layout manager are shared, with `Platform.swift` mapping colours, fonts, paths and symbol images between AppKit and UIKit. The Mac's text view is unchanged.
- **The iPhone view:** `PhoneTextView`, a `UITextView` on TextKit 1 with the shared layout manager and styler. It restyles as you type, but doesn't yet have the Mac's folding, cursor rules or formatting commands.
- **A spike app (`Point-iOS`, `Apps/iOS`):**
  - It lists the notes in a vault folder in the app's Documents (shown in Files).
  - It opens a note in the editor and saves as the Mac does.
  - Its timings show above the note.
- **A typing test, `-SpikeTypeTest YES`:** it opens a generated long note and types 200 characters into it. `-SpikeSections 900` makes the note as long as the vault's longest. Results are appended to `spike-timings.txt` beside the vault.

**What it shows:** the editor works on iOS. Notes look as on the Mac, with the frontmatter and markers hidden, and headings, links, tags, lists, checkboxes, quotes and highlights drawn. (A tag's pill sticks out past the left margin: a small fix.)

**Timings, on the iPhone 13** (Release build, iOS 27; the Simulator on the M3 gives nearly the same):

| Note | Opening | Each keystroke: median (parsing) | 95th percentile | Slowest |
|---|---|---|---|---|
| 45,000 characters | 33 ms | 3.4 ms (2.5) | 9.3 ms | 14.5 ms |
| 272,000 characters (as the vault's largest) | 99 ms | 6.6 ms (5.5) | 9.4 ms | 21.9 ms |

- **Typing is fast enough,** even in the vault's largest notes. A keystroke costs well under a frame at 60 Hz, and the slowest of 200 is about one frame.
- **Opening the largest note takes about a tenth of a second.** The median note is 1.2 KB, and 99% are under 31 KB, so most open far faster.
- **Reading a note takes 2–15 ms.** The first read after launch is slower while file coordination starts up, once.
- **Debug builds mislead:** unoptimised, the same 272,000-character note took 64 ms a keystroke (58 ms of it parsing). Measure in Release.
- **What this means for finding 13 of the [27 October review](app-review-2026-10-27.md),** that each edit re-parses the whole note: in Release it costs about 6 ms in the largest note. Incremental parsing isn't needed for now, on either the iPhone or the Mac.
- **Still to do before step 3:**
  - Tag pills stick out past the left margin. (Done, 31 October.)
  - Type on the phone by hand: the keyboard, autocorrect and the magnifier, around the hidden markers.

**On the iPhone:** the target is signed with Mike's personal team (a free account, so builds last 7 days). With the iPhone connected and unlocked (and, the first time, the developer profile trusted in Settings › General › VPN & Device Management), choose the `Point-iOS` scheme and the iPhone in Xcode, and run. For the typing test, add `-SpikeTypeTest YES` (and `-SpikeSections 900`) to the scheme's arguments. The timings show above the note, and in `spike-timings.txt` (Files › On My iPhone › Point).

## Step 1, looking up (27 October 2026)

**Built:**
- **Home (`HomeScreen`):**
  - Search sits at the top, with results in place: titles first, and matches in bold in each note's text (IndexKit, with an index built on the phone).
  - Below it, the note being worked on (the one last edited here, if that was today).
  - Then your bookmarks, Obsidian's (`ObsidianBookmarks` in VaultKit, with tests). Long-press to bookmark a note or remove a bookmark; drag to reorder.
  - Then every note, newest first, by when it was edited anywhere or opened here.
- **A note (`NoteScreen`):** the shared editor, with Bookmark in its menu. Opening a note counts towards recent.
- **The vault on the phone** is still the app's Documents folder.

**Tried on a copy of the vault in the Simulator** (3,407 notes; the six bookmarks showed, one under its own title):
- **Scanning:** 166 ms.
- **The first index build:** 13.6 s in a Debug build. Only once; after that, only changed notes. Searches wait for it.
- **Search found the right notes,** but ranked "Designing fonts with low-vision readers" above "NHS design vision" for "design vision". Fixed in IndexKit, so the Mac's search ranks the same way: a whole word in a title now counts for more than a title starting with part of one.

**On the iPhone 13** (Release, the same vault copy and bookmarks copied into Point's folder): scanning 3,408 notes takes 562 ms; the first index build, 8.4 s.

**Not yet:** the new-note button (step 2), and the real vault (step 5). Notes reach the phone by copying them into Point's folder in Files.

## Step 2, writing (27 October 2026)

**Built:**
- **New Note:**
  - A button in home's bottom toolbar (first a round floating button; see below).
  - It makes an empty note at the vault's top level and opens it with the keyboard up.
  - It's also a quick action: press and hold the app icon (`Apps/iOS/Info.plist`; a scene delegate passes it to home, whether Point was running or not).
- **Naming:** leaving a new note names it from its first line, under a free name ("… 2" if taken), as on the Mac. An empty one is removed, but only if it saved and read back empty. A note left untitled when the app stopped is named or removed at the next launch.
- **Saving (`NoteSession`):** a second after typing stops, on leaving, and when the app goes to the background. It never writes over a change made elsewhere (a conflict copy instead). If a save fails, the banner says so, with Try Again, and the edits are kept as a draft (`NoteDrafts`), offered back with Restore or Discard when the note next opens.

**Found and fixed: typed words went missing.** The iPhone editor restyled inside the text system's own edit step, as the Mac's does. On iOS that threw off the keyboard's autocorrection and suggestions: "Workshop on service design / - Start with the problem…" was saved as "Workshop service / - start with, …". It now restyles just after each edit, and waits while the keyboard is composing. Typing in the Simulator now arrives exactly, styled as it's typed (bullets, checkboxes, bold).

**To watch for:** the first note opened after a launch takes a moment to appear (in a Debug build, at least): what looked like New Note failing was that. The quick action can only be tried on the phone itself.

**Changed after Mike tried it (27 October):**
- **Titles are visible.** Naming a note silently from its first line wasn't obvious. Every note now shows its title (its file name, as on the Mac) at the top, scrolling with the text, in a field that renames the note (`PhoneTextView.header`).
  - A new note opens with the cursor in an empty "Title", and Return goes on to the text.
  - A rename updates links to the note across the vault (`LinkUpdater`, as on the Mac), and its bookmarks (`ObsidianBookmarks.rename`, tested).
  - A name that's taken is refused with a message, and the title goes back.
  - A new note left without a title still takes its first line; an empty one is still removed.
  - Navigation follows the rename (`PhoneStore.currentID`): renamed while open, the note's screen had gone blank, as it looked the note up by its old name.
- **The system's bottom toolbar:** New Note on the left, search on the right (minimised to a button until tapped), in place of the floating button and the search field at the top.

## Home, reshaped (27 October 2026)

After Mike tried it, home became like the Notes app's list of folders:
- **The top:** a large "Notes" title, with Settings at the top right.
- **The note being worked on** was shown here, then removed (it read as a stray note): coming back to it is step 3's job, reopening it when the app opens the same day.
- **Bookmarks, Recent and Tags:** rows leading to pages of their own, with counts. On the Tags page, nested tags sit under their parents, and a tag leads to its notes.
- **Folders:** the vault's top-level folders. Each leads to a page of the folders inside it, then its notes.
- **Notes:** the notes at the vault's top level, the most recently edited or opened first.
- **The bottom toolbar:** Add (`plus`) on every page, a menu with New Note and New Folder (a folder goes where you are: the top level from home, or inside the folder whose page you're on). Search is on home, where it searches the whole vault.
- **Settings:** a sheet saying where the notes are and how many there are (nothing to set yet).
- **The note screen:** the text runs under the top bar, so the bar blurs what scrolls beneath it, as the system's bars do.

## Mike's notes, worked through (30 October 2026)

After Mike tried it. These change "What it leaves out": the app now has sorting, a search page with commands, and a properties editor. It's no longer two screens and a button. The real vault waits; Mike said not yet.

**The order:** lists and titles, then editing, then search, then properties, then the real vault.

**Built:**
- **Lists:** no "Folders" and "Notes" subheadings. Titles run to as many lines as they need. Notes sit under date headings (`NoteDateGroup`, brought across from `main` unchanged, with its tests).
- **Sorting:** Date Edited, Date Created or Title, one choice for every list, as on the Mac. Sorted by title there are no headings, and each note's date goes below its title. Recent keeps its own order, and it's the only list that opening a note changes; elsewhere the dates are the note's own.
- **The note's title:** as many lines as it needs (`TitleView`), at 24 pt, with the phone's H1 down to 22 pt to stay below it.
- **Formatting commands:** `MarkdownEditing`, the Mac's commands as plain text edits. `MarkdownEditingTests` runs each one through the Mac's editor and this code, from the same text and selection, and they must agree.
- **The bar above the keyboard (`FormatBar`):** links, tags, lists, indenting, headings and styles, scrolling sideways, with Hide Keyboard fixed at the right. While a `[[link` or `#tag` is being typed, suggestions take the tools' place.
- **The editor (`PhoneTextView`):** Return continues lists and quotes. The frontmatter can't be selected, typed in or deleted. A checkbox ticks on a tap. A link opens on a tap while reading; with the keyboard up, the tap places the cursor, so a link's text can be edited. A link to a note that doesn't exist makes it, as on the Mac. A link that isn't to a web page or email (`zoommtg:`, `shortcuts:`) asks first, as on the Mac, showing the address: the Mac names the app, but the phone can't without declaring every scheme it might meet. If no app takes it, an alert says so.
- **Around hidden Markdown (`HiddenMarkers`):** the Mac's rules, which `HiddenMarkersTests` holds to the Mac's results. The cursor never rests inside hidden markers, and skips code fences. Delete at the start of a heading, list item or quote removes the formatting, otherwise it takes visible text, and it won't join a line to a code fence. Deleting or typing over all of a formatted span's text takes its markers too.
- **Coming back:** the app reopens the note being worked on the same day, with the cursor where it was and the keyboard up, until going home or opening another note.
- **Search (`SearchScreen`):** a page of its own, from the bottom toolbar of every page, the note included. It opens with the field not focused, so its lists can be seen and picked from: Recent (opened on this phone, five at most, without the current note), Bookmarks, Linked (notes the current note links to, then notes linking to it, five at most, leaving out any already listed), Commands. Typing shows results in their place. From a note, the first result is "Find in …" with a count, as Safari's "On This Page": it goes back to the note and opens the system's find bar, also in the note's ⋯ menu. A note picked from search takes the search page's place, so Back goes to where search was opened from. This, not tabs, is how to switch notes.
- **Properties (`NoteHeader`, `PropertiesSheet`):** a line under the title sums them up ("5 properties · #work #plans") and opens the sheet, also in the ⋯ menu, for notes with none yet. Each value edits to suit its type, as on the Mac: fields, a switch, the system's date picker, tokens for lists and tags. Tap the icon to change the type, the name to rename, swipe to delete. Types are kept in `.obsidian/types.json`. A value nested under its key is left for the Mac.

**Found and fixed: `---` saved as a dash.** Adding the first property to a note wrote `-—` in place of the frontmatter's fences. `replace(_:withText:)` punctuates what's inserted unless the view is the one focused, whatever its own smart-punctuation settings, so anything set from the sheet could change (quotes and `--` too). `applyAboveBody` now changes the text directly and does its own undo. Checkbox taps still use `replace`, and only ever insert a space or an `x`.

**Found and fixed: undo selected hidden markers.** Undoing a removed list marker left the `- ` selected, unseen, so the next key would have replaced it. A selection of only hidden text now collapses to a cursor after it.

**Decided (Mike):**
- Search opens without focus.
- Properties: a line under the title, opening a sheet to edit. In-place editing would put date pickers and tag fields inside the text view's header.

**Keeping `main` merging cleanly:** `main` is ahead on the Mac, with changes in `MarkdownTextView+Formatting.swift`, `MarkdownTextView.swift` and `PointLayoutManager.swift`. So the Mac's editor files aren't touched here: the iPhone's code is in new files, which repeats some of the Mac's logic for now. After merging, the Mac can move onto `MarkdownEditing`. `MarkdownEditing` and `LinkTarget` (iOS only, for now) are the pieces to fold together.

**Tried:** in the Simulator, on sample notes: every item above but the items marked below. `MarkdownEditingTests` passes.

**Not tried:** the iPhone itself; the keyboard's autocorrection and suggestions around Return; the Heading menu, indent buttons by tap, and the bar scrolling (their commands were run, not tapped); `#` suggestions on screen (tested as logic); dragging the cursor (the magnifier, or the space bar as a trackpad) past hidden markers, where nothing tells the editor a drag is under way, as the Mac's `stillSelecting` does. In the properties sheet: the date-and-time picker, a nested value, the repeated-key warning, tag suggestions.

**Still to do:**
- The Mac shades a link while the cursor is inside its end, so it's clear that typing goes on with the link. The phone has the stop but not the shading, and doesn't yet take a tap to the right of a link as after it.
- Tag pills: a tag starting a line now starts its pill at the margin, its line moved in to make room. A tag wrapped to the start of a line can't be moved, so its pill is cut off at the margin and sits tight against the `#`. On an empty last line after a line starting with a tag, the cursor sits 6 points in.

## Decided (27 October 2026)

1. **Bookmarks are Obsidian's** (`.obsidian/bookmarks.json`): the phone shows the notes in it, in its order, and bookmarking or reordering on the phone writes it back, keeping everything else in the file (folders, searches and headings Obsidian bookmarks too, which the phone doesn't show). The Mac can move to the same file later.
2. **New notes go to the vault's top level,** as on the Mac. They aren't linked from a daily note for now (the daily notes plugin is off).
3. **The app opens to home,** or back into the note being worked on (below). New Note is the round button, and the icon's quick action.
4. **Coming back into a note lasts the rest of the day:** until midnight, or until going home or opening another note.
