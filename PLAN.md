# Point — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. Its notes are plain Markdown files, readable anywhere. It opens an existing Obsidian vault and, until the iPhone app is in daily use, works alongside Obsidian on the same files. From 6 November 2026 it goes its own way where that's better (see [Beyond text](plan/structure.md)).

The plan is in several documents, in [`plan/`](plan/). This page says where things stand and what's in each.

## Where things stand (3 November 2026)

On `main`, which has everything so far, including search that learns.

**Since 27 October:**
- **The real-vault trial is under way.** Point has been the main notes app on the Mac since 29 October, on the real vault (phase 4 of [Live vault safety](plan/live-vault-safety.md)).
- **Tables** are a grid view laid over their hidden Markdown, with wrapping cells, rows and columns to add and drag, Tab and arrows between cells, and always a line to type on above and below. See [Tables: where things stand](plan/tables-status-2026-11-03.md), including what's still missing.
- **Bold and italic at the cursor** work as in a word processor: nothing to see until you type, the shortcut again stops the style, and a run across several words stays one run in the Markdown.
- **A new principle:** the Markdown Point writes is well formed, as if written by hand, at every keystroke. See [Principles and decisions](plan/decisions.md).
- **Search that learns** (merged into `main`): the notes you open and pick move up among matches of similar quality, on each device, outside the vault. See [Search that learns](plan/search-learning.md).
- **The Mac:** tabs rebuilt in Liquid Glass and hidden while only one note is open, revised headers and breadcrumb, the properties UI, and a new icon. In the explorer (⌘E), commands that match better than any note's title come first, and Run Command (⇧⌘E) lists only commands.
- **The iPhone:** three rounds of Mike's notes (30 October to 1 November): the system's search field, a menu of actions for each page, moving notes and folders, templates, the properties sheet and adding a property, the bar above the keyboard, and the note being worked on reopening the same day. See [M4, the iPhone app](plan/m4-iphone.md).

**Next, as of 7 November 2026** (each on its own branch from `main`):
1. **`iphone-home`:** the simpler phone home screen. See "Home, simplified" in [M4, the iPhone app](plan/m4-iphone.md).
2. **`kinds`:** kinds of note defined in Point (template, folder, properties), with New meeting offering its templates, and `type` filled in once where the folder makes it plain. Built, and the real vault has its kinds and `type` filled in: see [Kinds of note](plan/kinds.md).
3. **`recall`:** what happened before, in meeting notes first ("4 earlier · last on 21 October"), then while writing blog posts.
4. **`clipper`:** a Chrome extension for Dia on the Mac and a share-sheet extension on the iPhone; Point extracts the article and sets its kind.
5. **`mac-full-screen`:** the full-screen bug (see [Investigations](plan/investigations.md)). Not blocking anything.

**Next, as of 3 November** (older list):
1. **The real-vault trial goes on.** Anything it turns up comes first, including how search that learns (so far checked only by tests) and tables do on real notes. The [27 October review](plan/app-review-2026-10-27.md)'s findings are fixed except 5 (iCloud conflict versions, to fix against a real one) and 13–15 (performance, to measure first).
2. **The iPhone app (M4):** finish step 3, editing through the day, then step 4, making it feel right. The bold and italic rules and search that learns are shared with the iPhone but haven't been tried on one yet.
3. **The properties view** across the vault, the last item of the [25 October batch](plan/batch-2026-10-25.md).
4. **The sidebar's remaining steps:** the swipe follows the fingers, and auto-hide resizes the window at the end of a drag. See [The sidebar widens the window](plan/sidebar-widens-window.md).
5. **When the screen is free for recordings:** the header's jitter as the sidebar slides, and full screen. See [App review](plan/app-review-2026-10-25.md).
6. **Small things, if they get in the way:** in tables, several cursors don't reach into cells and Find's highlight doesn't show over a match in a cell; a note renamed in Obsidian loses what search had learned about it.
7. **Later milestones:** meaning (M5) and extras (M6). See [Milestones](plan/milestones.md).

## The documents

**Foundations**
- [Principles and decisions](plan/decisions.md): what Point is for, and the decisions so far, by area (platforms, vault and sync, editor, sidebar, note list, focus mode, search, AI, capture, shortcuts).
- [Architecture and risks](plan/architecture.md): how the app is built, and what could go wrong.
- [Milestones](plan/milestones.md): M0 to M6.

**Work, newest first**
- [Beyond text: structure, names and Obsidian](plan/structure.md) (6 November): how images, comparing drafts, lists from properties, and people and types fit together. Decided: plain files readable anywhere, not Obsidian compatibility; titles from a `title:` property, with dated file names; a typed index under it all; lists as notes; and the order of work.
- [Images: where to store them](plan/images.md) (6 November): the options, from Obsidian's one attachment folder to a folder for each note, and a recommendation: one folder, images named after their note, and Point looking after them as notes are renamed and deleted.
- [Search that learns](plan/search-learning.md) (3 November, merged): ranking the notes you open and pick higher, kept on each device, outside the vault.
- [Tables: where things stand](plan/tables-status-2026-11-03.md) (3 November): why tables became a grid view over hidden Markdown, how it works, the rough edges fixed, and the limits left.
- [Live vault safety](plan/live-vault-safety.md) (26–27 October): testing, then fixing, what Point writes to a real vault; the results, and the trial still to come.
- [M4, the iPhone app](plan/m4-iphone.md) (27 October): what it's for, two screens and a button, what it leaves out, how it's built, and the steps.
- [Code review](plan/app-review-2026-10-27.md) (27 October): an external review of note safety, stability and performance; what's fixed, and what's still open.
- [App review](plan/app-review-2026-10-25.md) (25 October): the review's findings by severity, and the fixes since, including the close flash.
- [The 25 October batch](plan/batch-2026-10-25.md): the links panel, templates, the properties view, palette defaults, tags and the home button, sorting in two columns, splits that slide, and the small fixes after.
- [The sidebar widens the window](plan/sidebar-widens-window.md) (25 October): the design, the attempts, and the bugs fixed.
- [Properties, redesigned](plan/properties.md) (25 October).
- [Exploration: no visible tabs](plan/exploration-no-visible-tabs.md) (25 October): tabs without a tab bar.
- [Exploration: radically minimal](plan/exploration-minimal.md) (19 October).
- [M3.5, Mac refinements](plan/m3.5-mac-refinements.md) (18–24 October): parts A to H.

**Ideas**
- [Investigations and open questions](plan/investigations.md): daily notes as a meeting log, and questions still open.
- [Optional: tabs kept alive](plan/tabs-kept-alive.md) (5 November): keeping each open tab's editor so switching tabs is instant; for later, if switching feels slow again.
