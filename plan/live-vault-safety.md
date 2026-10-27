# Plan: using Point safely with the live vault (26 October 2026; phases 1–3 done, phase 4 next)

Part of [the plan](../PLAN.md).

A focused piece of work, to do before relying on Point for the real vault. Goal: know exactly what Point writes, prove each write does only what it should, and fix whatever doesn't, before any of it touches the real files.

**What Point writes, besides the text typed into a note** (the things to test):
- **Saving a note:** `NoteWriter` writes only if the file on disk is still what Point last read; if it changed elsewhere, a conflict banner offers Keep Mine or Use Theirs (`EditorSession`), and leaving the note with a conflict pending saves a conflict copy. A note changed elsewhere with no unsaved edits here is reloaded.
- **Properties:** edits rewrite only the changed property's lines; anything `Frontmatter` doesn't understand is meant to be kept as it is. Lists are written as `- item` lines (a note that used `[a, b]` changes format on its first edit). Types go into `.obsidian/types.json`, keeping the rest of the file.
- **Renames and moves:** update `[[links]]` to the note across the vault (`LinkUpdater`), writing every note that links to it.
- **Untitled notes:** renamed from their first line when left.
- **Trash:** moved into the vault's `.trash` folder (as Obsidian's own trash does), with Point's own record of where each came from; Empty Trash deletes for good.
- **Daily notes and templates:** created from Obsidian's settings (`.obsidian/daily-notes.json`, `templates.json`).

**Ground rules**
- Nothing is tried on the real vault until phase 4. Phases 1–3 read the real vault, or work on a copy of it.
- Every write test runs on a copy kept in git (outside the vault), so each operation's effect is one `git diff`, and anything beyond what it should do shows.
- The real vault gets a snapshot (Time Machine, or a git repository outside the vault, never a `.git` inside it, which Obsidian and iCloud would sync) before phase 4.

**Phase 1: read-only audit of the real vault** (a small command-line tool on VaultKit, or a test target, that only reads)
1. **Frontmatter round trip:** for every note, parse the frontmatter and check that a no-op edit (setting a property to the value it has) gives back the identical text. List every note where it doesn't.
2. **Frontmatter shapes:** count and list the forms that need care: nested maps, multi-line strings (`|`, `>`), comments, quoted keys and values, anchors, flow lists (`[a, b]`), empty values, duplicate keys, frontmatter not at the very top, a BOM, CRLF line endings.
3. **Text round trip:** load each note into the editor's text model and back, unedited; check the bytes are the same (line endings, trailing newline, tabs, Unicode normalisation).
4. **Names and links:** notes with the same name in different folders, names differing only in case, characters Obsidian or iCloud treat specially; link forms in use (`[[note]]`, `[[folder/note]]`, `[[note|alias]]`, `[[note#heading]]`, `[[note#^block]]`, embeds `![[...]]`, Markdown links, links inside frontmatter); and the vault's link settings (`.obsidian/app.json`: new-link format, wikilinks or Markdown).
5. **Settings read:** daily notes, templates, attachments folder, types: what Point reads, and whether it matches what Obsidian does.

The output is a report: the shapes found, how many notes each, and which notes fail a round trip. It decides what phase 2 must cover.

**Phase 1 results (26 October 2026, the live vault "MG notes" in iCloud: 3,401 notes, 2,649 with frontmatter).** Done with `VaultAudit` (VaultKit tests; runs only with `POINT_AUDIT_VAULT` set; read only, and skips notes iCloud hasn't downloaded). The full report has note names, so it's kept out of the repository (in the session's scratchpad).
- **Clean:** every note downloaded and valid UTF-8; no byte-order marks, CRLF or CR line endings, decomposed Unicode, nested values, multi-line (`|`, `>`) values, map values, anchors, or frontmatter lines outside a property. 1,963 notes have no line break at the end, which Point keeps.
- **Properties are rewritten in Point's own style when edited (1,958 properties would change for nothing).** Editing rewrites only the property edited, but a no-op edit isn't a no-op: an empty `key:` gains a trailing space (`key: `), values are quoted or unquoted by Point's own rule (`source: https://…` gains quotes; `title: "Carely — …"` loses them), and an empty `[]` becomes nothing. To fix (phase 3): no trailing space; a value left as it was keeps its line exactly; a changed value keeps the original's quoting where YAML allows; `[]` stays `[]`. (Only 2 notes use `[a, b]` lists, both empty.) **Fixed (26 October 2026):** setting a property to the values it has gives back its lines exactly; a changed value keeps the quotes the note used (double or single), and each list item already there keeps how it was written; an empty value is `key:` with no space; a new value is quoted only where YAML would misread it (so URLs stay plain). Tested in `FrontmatterRewriteTests`, with the shapes the audit found. The audit run again on the live vault: 1 property changes on a no-op edit, down from 1,958, and that one is the duplicate `read:` below (setting one writes the first).
- **Duplicate keys in 2 notes** (`read:` twice): Point shows and edits the first; YAML (and so Obsidian) takes the last. Low; perhaps show both, or warn.
- **The same name in different folders: 3 pairs** (one is "Onboarding", with 7 links `[[Onboarding]]` that could mean either). Renaming or moving either note must change only the links Obsidian would resolve to it (phase 2, compared with Obsidian).
- **Links:** 6,413 plain, 448 with an alias, 68 embeds, 33 with a folder path, 8 to a heading, none to a block; **7,163 inside frontmatter** (people, topics, sources as `"[[Name]]"`), which renames and moves must update too; 4,997 to notes that don't exist (mostly people and topics in frontmatter, used like tags), which renames don't touch; 14 Markdown links to files; 4,914 web links.
- **Settings:** links are wikilinks in the shortest form (Obsidian's default); attachments go in `--Meta/Assets`; trash is the vault's `.trash` (as Point's); "always update links" is on; templates are in `--Meta/Templates` with the date format `YYY-MM-DD`, which Obsidian (and Point) render as "262026-10-26" (probably a typo for `YYYY-MM-DD`); there's no daily notes setting, and the daily notes core plugin is off; 19 property types.
- **Obsidian Sync is on for this iCloud vault** (the `sync` core plugin): two sync engines on one folder, which the plan says to avoid, whatever Point does. A decision for Mike: one or the other.
- **Plugins in use:** Dataview, Notebook Navigator, Omnisearch, List Callouts, Home Tab, Hide Sidebars When Narrow, Swipe Sidebar, BRAT; core Bases and Canvas. Nothing in them changes what Point must keep, but Dataview queries show in Point as code, and `.base` and `.canvas` files aren't notes to Point.

**Phase 2: write tests on a copy** (each operation, then `git diff` checked against what it should be)
1. **Property edits** on notes of every shape from phase 1: set, add, remove, rename, reorder, change type, tags tokens. Only the intended lines may change.
2. **Renames and moves**, compared with Obsidian doing the same on a second copy (diff the two results): every link form from phase 1, notes with the same name in two folders, case-only renames, links to a note from inside its own folder, moving into and out of the vault root.
3. **Editing:** open, type, undo, save; only the typed region changes. Select All then Delete keeps the frontmatter.
4. **Untitled notes:** named from the first line; a name already taken; a first line with characters a filename can't have.
5. **Trash:** move to trash, put back, Empty Trash; compare `.trash` with what Obsidian does, and check Obsidian still sees and restores items Point trashed.
6. **Side by side with Obsidian:** the same note open in both; edit in Obsidian with no unsaved edits in Point (reloads, keeping the cursor); with unsaved edits in Point (conflict banner; both choices); leave the note with a conflict pending (conflict copy). A rename or move in Point while Obsidian has a linking note open, and the other way round.
7. **Sync:** with iCloud (and Obsidian Sync, if it's still on the vault: the plan is to turn it off, as two sync engines on one folder conflict): an edit on two devices; that iCloud conflict versions are shown, never dropped.

**Phase 2 results so far (26 October 2026, on a copy of the live vault).** Done with `VaultWriteAudit` (VaultKit tests; runs only with `POINT_AUDIT_COPY` set, and changes that copy: property edits and template merges in memory, renames, moves and the trash on the copy's files) and `VaultRoundTripAudit` (EditorKit tests; reads only). Each operation is checked automatically: links resolve as before, nothing outside a link changes, values read back as set. Without commits (Mike's rule covers every repository), so not in git: a working copy and an untouched copy, compared directly.
- **Editing:** all 3,403 notes loaded into the editor and back, byte for byte the same.
- **Property edits:** 11,635 (every property of every note set to a new value, removed, renamed): nothing else in any note changed. Found and fixed: a single-quoted value with `''` in it (YAML's escaped quote) was read with both quotes, and written back doubled; `''` now reads as one quote, and `\"` in double quotes as a quote (`QuotedValueTests`).
- **Template merges:** 51,045 (each of the vault's 15 templates applied to every note): the note's values always kept, apart from the note with a duplicate key (below).
- **Renames:** 8 notes (the "Onboarding" pair, the most linked, the most linked from frontmatter, and ones linked with an alias, a heading and a folder path). Found and fixed: **renames didn't update links in frontmatter** (661 left pointing at the old name), as the Markdown parser leaves frontmatter alone; and **a renamed note's links to itself** weren't updated (it was looked for under its old name). After the fixes (`FrontmatterLinkTests`), all 8 renames update 758 notes, with every link leading where it did, no other link changed, and nothing outside links touched. Links inside inline code are rightly left alone.
- **Moves:** 4 notes, including ones linked by folder path: links updated, nothing else changed. Path links in frontmatter are now updated too.
- **Trash:** 3 notes trashed and put back: back in place, byte for byte.
- **Still open:** the duplicate `read:` keys (2 notes): Point shows and edits the first, YAML takes the last. A decision: show the last, or warn.
- **Still to do, needing Obsidian (or Mike):** compare renames with Obsidian doing the same on a second copy, above all for the shared name "Onboarding" (Point picks the note in the linking note's folder, then the shortest path; whether Obsidian does the same is untested); the two apps open side by side on the same note (the conflict banner, reloads); untitled notes named from odd first lines; and sync (iCloud and Obsidian Sync both on).

**Checklist for Mike: the comparisons with Obsidian** (on a copy, `build/ObsidianCheck`, with Obsidian Sync turned off in it so it can't reach the real vault). Afterwards, Claude can compare the copy with an untouched one to see exactly what each app wrote.

*Set up*
1. Build Point from the current working tree (the fixes aren't in older builds).
2. Obsidian: Open folder as vault › `build/ObsidianCheck`. Check Settings › Core plugins › Sync is off.
3. Point: File › Open Vault… › the same folder.

*A. Which note a shared name means* (reading only). In Obsidian, open each note below and hover over, or click, its `[[Onboarding]]` link: which Onboarding opens? Point says `Sources/Onboarding` for all seven.
- `NHS/Archive/2024-02-08 - Farhana Yeasmin`
- `NHS/Archive/2024-02-12 - Sarah Robson`
- `NHS/Archive/2024-05-01 - Sarah Robson onboarding`
- `NHS/Management/UCD management`
- `Sources/Defra design handbook`
- `Sources/Must-haves when starting or joining a product team`
- And `2026-10-23 - 7-day review`: its `[[Draft - What I should have said - outline]]`. Point says the one at the top level, not the one in `Blog`.

*B. A rename in Point, seen in Obsidian.* In Obsidian, open `NHS/Management/UCD management` and note how many backlinks it has. In Point, rename it to `UCD management renamed`. In Obsidian: the same number of backlinks, under the new name; and in a few of the notes linking to it (`NHS/Archive/2026-10-19 - UCD work in flight`, `Sources/What I do as a head of design`), the link in their properties shows the new name and isn't shown as a missing note.

*C. Both apps on one note.* Open the same note in both.
1. Type a line in Obsidian. Within a second or two, Point shows it, without the cursor jumping.
2. Type a line in Point, then switch to Obsidian: it shows it.

*D. A new note's name from an odd first line.* In Point, ⌘N, type `Plan: Q4 / review #1?` as the first line, then click another note. What is the new note called in Point's list, and in Obsidian's file list? Does it open in Obsidian?

**Mike's results (27 October 2026):**
- **A. Shared names: Point matches Obsidian.** Obsidian opens `Sources/Onboarding` from all seven links, as Point does (so renames update the same links). Mike will point the NHS notes at a separate "NHS onboarding" himself.
- **B. Links: fixed.** Obsidian showed 290 linked mentions and 29 unlinked for "UCD management"; Point's button said 53. Of the 280 notes linking to it, 258 link only from their properties, and Point's backlinks (and its index of links) looked only in the text: 53 was 24 notes linking in their text plus 29 mentions. The unlinked mentions already matched Obsidian (29). Backlinks and the index now include links in frontmatter (the same finder as renames, `LinkUpdater.wikiLinks`; the index's version is 5, so it's rebuilt). On the copy: 280 notes link to it, and 29 mentions. Obsidian's 290 counts links rather than notes (some notes link twice). Tested in `backlinksIncludeLinksInFrontmatter`.
- **C. Both apps on one note: works.**
- **D. A new note's name: fixed.** It stayed "2026-10-27 1253" because Mike left it for a note open in another tab, and bringing another tab forward didn't name the note from its first line (only showing another note in the same tab did). Now it does (an empty one is kept, as its tab still holds it), and the tab follows the new name. Checked with a debug hook (`-PointUntitledTest`): `Plan: Q4 / review #1?` becomes `Plan Q4 review 1` (Obsidian doesn't allow `: / # ?` in names).

Tell Claude what you see for each. (Point's conflict banner, for a note changed elsewhere while it has unsaved edits, can't be reached by hand, as Point saves on switching apps; Claude will test it with a debug hook.)

**Finishing (27 October 2026):**
- **Sync: iCloud only (Mike's decision).** Obsidian Sync is to be turned off for this vault, on every device (Obsidian › Settings › Core plugins › Sync), before phase 4. Point writes in place under file coordination, as iCloud expects; iCloud's conflict versions show a banner (Keep This, Use Other, Keep Both), never dropped.
- **The conflict banner, tested** with a debug hook (`-PointConflictTest "<note>|keep|theirs|leave|rename"`, with `-PointSaveDelay 60`), on a scratch vault: with unsaved typing, another app's change to the file shows the banner, and neither saving nor switching apps overwrites it; Keep Mine writes mine, Use Theirs shows and keeps theirs, and leaving the note keeps theirs and saves mine as a conflict copy. A rename while a note linking to it has unsaved typing: the typing is saved first, then the link rewritten, and the editor shows both, with no banner. All 24 checks pass. (iCloud's own conflict versions can't be made on demand, so that banner is untested.)
- **Repeated keys: Obsidian can't read them, so Point says so.** Obsidian reads YAML strictly (its parser runs with `uniqueKeys`), so a note with `read:` twice has no readable properties there, rather than the last value winning as the earlier note here guessed. Point now shows each of the repeated properties (each with its own ID) and a warning above them: the key is there more than once, so Obsidian can't read these properties; remove one. The two notes: `Sources/Good strategy bad strategy` and `Sources/Delivery tactics - shaping your discovery`, for Mike to fix (`repeatedKeysAreFlagged`).
- **Links a rename or move couldn't update are reported.** Notes changed during the update, and notes that couldn't be read (not downloaded from iCloud, or not UTF-8), were passed over with only a log line; now an alert names them (`notesThatCantBeReadAreReported`). On this Mac every note was downloaded in phase 1, and iCloud downloads an evicted note when it's read, so this should be rare.
- **Snapshots for phase 4:** `scripts/vault-snapshot.sh take` copies the vault to `~/Point vault snapshots/<date time>` (outside the vault and iCloud); `scripts/vault-snapshot.sh changes` lists what changed since the latest copy and writes the full diff beside it. No git, as Mike's rule rules out commits.

**Phase 3: fix what's found.** Each finding gets a VaultKit test (from the actual note that showed it, made anonymous) before the fix. Likely candidates, from reading the code: frontmatter shapes `Frontmatter` doesn't understand; `[a, b]` lists rewritten as lines (a choice to confirm: keep each note's own list style instead); link forms `LinkUpdater` misses; writes to linking notes that are open in an editor (should go through the editor, not around it).

**Phase 4: trial on the real vault**, after a snapshot. First: turn off Obsidian Sync on every device, fix the two notes with repeated keys, build Point from the current tree, and run `scripts/vault-snapshot.sh take`. For a week, run `scripts/vault-snapshot.sh changes` each day and read every change (Obsidian's too: they show alongside Point's), then `take` a fresh copy. Keep using Obsidian alongside. If iCloud shows a conflict banner, don't choose yet: keep a copy of each version first, as finding 5 of the [27 October review](app-review-2026-10-27.md) asks, so that path can be fixed against a real case.

**Done when:** phase 1 shows every note round-trips (or the exceptions are understood and safe); every phase 2 operation diffs as it should; a week of phase 4 shows no change Point shouldn't have made.
