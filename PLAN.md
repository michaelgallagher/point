# Point — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. Its notes are plain Markdown files, readable anywhere. It opens an existing Obsidian vault and, until the iPhone app is in daily use, works alongside Obsidian on the same files. From 6 November 2026 it goes its own way where that's better (see [Beyond text](plan/structure.md)).

The plan is in several documents, in [`plan/`](plan/). This page says where things stand and what's in each.

## Where things stand (11 November 2026)

On `main`, which has everything so far.

**The Mac is the daily notes app,** on the real vault since 29 October, and is ready to use without Obsidian. Since 3 November: kinds of note, recall, the clipper, types, links and lists, the 8 November batch, and stage 4 (list notes, the split target, and links and recall as one related notes panel sliding up from the bottom). On 10 November: Format › Numbered List (⌥⌘L), and a new note named by hand no longer renamed after its first line when it's left.

**The iPhone app** is steps 0–4 of [M4](plan/m4-iphone.md) and the catch-up with the Mac, and since 10 November uses the vault in iCloud Drive, chosen in Files ([The iPhone on the real vault](plan/iphone-real-vault.md)): the safety tests passed on a copy there, and **on the real vault since 11 November**. The same day, the Mac learned to follow a note renamed on the phone while it's open, and to write out iCloud's conflict versions of every note, not only open ones.

**Still open:** full screen on the Mac ([Investigations](plan/investigations.md), set aside for now); performance (13–15 of the review, measured only if something feels slow).

**Not merged into `main`:** design experiments `animating-the-cursor`, `simple-but-bigger`, `tighter-and-lighter`, `capsules` and `skinny-bar`.

## Next: a week on Point alone, Mac and iPhone (from 10 November 2026)

Mike travels soon with the laptop and the iPhone, and wants to use Point on both for a week without opening Obsidian. The Mac is ready; the iPhone isn't. In order:

1. **The iPhone on the real vault** (see [The iPhone on the real vault](plan/iphone-real-vault.md)): built and merged on 10 November, tried on a copy of the vault in iCloud Drive, and in use on the real vault since 11 November.
2. **Signing:** the free account's 7-day builds are fine; the laptop comes along, so Xcode can reinstall on the road.
3. **A shakedown at home:** two or three days on both apps, no Obsidian: write on the phone, edit the same note on the Mac, and `scripts/vault-snapshot.sh changes` to see exactly what Point wrote.
4. **Before leaving:** a snapshot (`scripts/vault-snapshot.sh take`; the first set for Thursday 12 November, 8:00), Obsidian Sync still off on every device, and the vault set to Keep Downloaded in Files on the iPhone, so nothing is a placeholder offline.
5. **The fallback:** Obsidian stays installed on both, unopened. The files are plain Markdown, so it can take over at any point.

**After the trip:** full screen on the Mac, and anything the week turns up, which comes first. Then [reader mode on the iPhone](plan/reader-mode.md): Media notes set for reading, your place kept, highlights, and your notes above the saved text, under the marker `==---- Text ----==` (designed 11 November, not started). (The iPhone caught up on 11 November: the related notes sheet, and Numbered list in the bar above the keyboard.)

**Later:** comparing drafts (Compare with…: two notes, or a note and an earlier version or conflict copy, shown as tracked changes; designed in [Beyond text](plan/structure.md), not started), daily notes as a meeting log ([Investigations](plan/investigations.md)), and the milestones meaning (M5) and extras (M6). See [Milestones](plan/milestones.md).

## The documents

**Foundations**
- [Principles and decisions](plan/decisions.md): what Point is for, and the decisions so far, by area (platforms, vault and sync, editor, sidebar, note list, focus mode, search, AI, capture, shortcuts).
- [Architecture and risks](plan/architecture.md): how the app is built, and what could go wrong.
- [Milestones](plan/milestones.md): M0 to M6.

**Work, newest first**
- [Reader mode on the iPhone](plan/reader-mode.md) (11 November, designed): reading clipped Media notes with type set for reading, your place kept on the phone, highlights, and a notes sheet that writes above the `==---- Text ----==` marker; in four steps.
- [The 8 November batch](plan/batch-2026-11-08.md): Mike's list of fixes and changes for the Mac and the iPhone.
- [The iPhone on the real vault](plan/iphone-real-vault.md) (8 November): what's needed to use the iPhone app on the real notes, and in what order.
- [Links and recall](plan/links-and-recall.md) (8 November): links and recall become one function, a panel sliding up from the bottom opened from the recall line; what's decided and what's left.
- [Types, links and lists](plan/types-and-links.md) (8 November): links grouped by relation and type, Person and Project kinds, types and Lists in the sidebar, properties in Settings.
- [Recall: what came before](plan/recall.md) (7 November): under a note's properties, its earlier meetings with the same people, or the notes on a post's topics.
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
