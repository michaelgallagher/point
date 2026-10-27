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
  - Tag pills stick out past the left margin.
  - Type on the phone by hand: the keyboard, autocorrect and the magnifier, around the hidden markers.

**On the iPhone:** the target is signed with Mike's personal team (a free account, so builds last 7 days). With the iPhone connected and unlocked (and, the first time, the developer profile trusted in Settings › General › VPN & Device Management), choose the `Point-iOS` scheme and the iPhone in Xcode, and run. For the typing test, add `-SpikeTypeTest YES` (and `-SpikeSections 900`) to the scheme's arguments. The timings show above the note, and in `spike-timings.txt` (Files › On My iPhone › Point).

## Decided (27 October 2026)

1. **Bookmarks are Obsidian's** (`.obsidian/bookmarks.json`): the phone shows the notes in it, in its order, and bookmarking or reordering on the phone writes it back, keeping everything else in the file (folders, searches and headings Obsidian bookmarks too, which the phone doesn't show). The Mac can move to the same file later.
2. **New notes go to the vault's top level,** as on the Mac. They aren't linked from a daily note for now (the daily notes plugin is off).
3. **The app opens to home,** or back into the note being worked on (below). New Note is the round button, and the icon's quick action.
4. **Coming back into a note lasts the rest of the day:** until midnight, or until going home or opening another note.
