# Plan: using Point safely with the live vault (26 October 2026; not started)

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

**Phase 3: fix what's found.** Each finding gets a VaultKit test (from the actual note that showed it, made anonymous) before the fix. Likely candidates, from reading the code: frontmatter shapes `Frontmatter` doesn't understand; `[a, b]` lists rewritten as lines (a choice to confirm: keep each note's own list style instead); link forms `LinkUpdater` misses; writes to linking notes that are open in an editor (should go through the editor, not around it).

**Phase 4: trial on the real vault**, after a snapshot. For a week, compare the vault with the snapshot each day (`git diff` from the outside repository) and read every change Point made. Keep using Obsidian alongside.

**Done when:** phase 1 shows every note round-trips (or the exceptions are understood and safe); every phase 2 operation diffs as it should; a week of phase 4 shows no change Point shouldn't have made.
