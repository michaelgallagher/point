# Principles and decisions

Part of [the plan](../PLAN.md).

# Principles

1. **The file is the truth.** Notes are plain `.md` files in a folder that is also an Obsidian vault. Every unchanged byte stays unchanged, including frontmatter key order, whitespace, and syntax we don't render.
2. **Never see Markdown.** Editing feels like rich text. Markdown decides what formatting is possible. A raw-source toggle exists for emergencies.
3. **Little filing.** Search, links and tags do most of the finding. Folders exist for the few broad areas that need them (as in Obsidian), but filing is never required.
4. **Capture is instant.** One press on the iPhone gets you to a blank note with the keyboard up.
5. **Fast software is good software.** Open instantly, and stay responsive with 10,000 notes. Speed wins over features that would slow things down.
6. **Native.** Use platform conventions and the system's own controls.
7. **As minimal as possible, but no more.** Show as little interface as we can, without making common actions hard to do.
8. **Know what you need to know.** Half of the app's job is managing knowledge: surfacing what matters, connecting related notes and making it easy to find things again, not just storing text.
9. **The command palette is the main way to do things.** Every action is reachable from it. Menus, buttons and shortcuts are secondary ways to get there.

# Decisions so far

## Platforms

| Machine | OS | Role |
|---|---|---|
| M3 MacBook Pro | macOS 26 | Primary. Full experience. |
| 2017 Intel MacBook Pro | macOS 13.7.8 | Occasional use. Simpler experience is fine: no semantic search, no AI features, no Liquid Glass. |
| iPhone 13 | iOS 26 | Full experience except generated AI text: the iPhone 13 can't run Apple Intelligence. iPad is not in scope. |

- **Builds:** made on the M3. Xcode 26 doesn't run on macOS 13, so builds are copied to the old Mac to test. The first launch there needs right-click and Open.
- **Audience:** just Mike for now.
- **Developer account:** none yet. Start Mac-first, and buy the paid account when the iPhone milestone begins. Free-account iPhone builds expire after 7 days and can't use extensions.
- **Involvement:** Mike reviews at milestone boundaries.

## Vault, storage and sync

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

## Editor

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

## Sidebar navigation (decided October 2026)

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

## Note list

- **Rows:** the filename is the main thing. No preview line.
- **Sort:** most recently edited first by default. Can switch to alphabetical, or to date created.
- **Optional row details:** a date (last edited by default, or date created) and tags. Both are off unless turned on.

## Focus mode (Mac)

- A near-blank window with almost all interface chrome hidden.
- Keeps a button to show the note list. A few other icons may stay; which ones is to be decided.

## Search and connections

- **Search:** handles typos and partial words, word forms (run, running, ran), filters by tag, date and links without a query language, and meaning (semantic search).
- **Connections:** backlinks, unlinked mentions (one click to link), a related-notes panel, and tag suggestions. No graph view.

## AI (on-device only)

- **Outputs:** a weekly digest, topics over time, and clusters of related but unlinked notes.
- **Embeddings** (Natural Language framework; macOS 14+ and iOS 17+, so the M3 and the iPhone 13). These power semantic search, related notes, tag suggestions (from the tags of similar notes) and clusters.
- **Generated text** (Apple Foundation Models; needs Apple Intelligence, so **the M3 only**). This writes the weekly digest and names topics and clusters. The iPhone 13 and the 2017 Mac can't run it.
- **Storage:** the M3 writes digests and topic summaries as ordinary Markdown notes in the vault, so every device sees them. Each has a deterministic filename (for example `Digest 2026-W42.md`) so a note is never written twice.

## Quick capture (iPhone)

- **Entry points:** a Lock Screen and Control Center control (also usable on the Action button), Siri phrases and dictation, the share sheet, and Apple Watch.
- **Destination:** each capture is a new note, and a link to it is added to today's daily note.
- **Mac:** no global hotkey for now.

## Mac keyboard shortcuts

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
