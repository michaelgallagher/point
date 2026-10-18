# Imprint — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. It works directly on an Obsidian vault.

## Principles

1. **The file is the truth.** Notes are plain `.md` files in a folder that is also an Obsidian vault. Every unchanged byte stays unchanged, including frontmatter key order, whitespace, and syntax we don't render.
2. **Never see Markdown.** Editing feels like rich text. Markdown decides what formatting is possible. A raw-source toggle exists for emergencies.
3. **Little filing.** Search, links and tags do most of the finding. Folders exist for the few broad areas that need them (as in Obsidian), but filing is never required.
4. **Capture is instant.** One press on the iPhone gets you to a blank note with the keyboard up.
5. **Native and fast.** Use platform conventions, open instantly, and stay responsive with 10,000 notes.

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
- **Folders:** real folders on disk, shared with Obsidian. Revised in October 2026: one flat list won't scale, so the sidebar will browse folders (see "Sidebar navigation"). Until then, every note shows in one flat list and new notes go to the vault root.
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

### Sidebar navigation (proposed, October 2026)

A single flat list of notes won't scale. Proposal, to be confirmed (see open questions):

- **One list at a time:** the sidebar stays one column. Folders are listed at the top, above the notes in the current folder. Clicking a folder moves into it, and a back arrow and the folder's name at the top move back up.
- **Tags as a list:** all tags can be shown as a list, with nested tags (`work/imprint`) indented under their parent so the hierarchy is clear. Choosing a tag lists its notes.
- **Pinned areas:** some folders or tags matter more than others, like Mike's top-level NHS, Sources and Personal folders in Obsidian. These can be pinned to the top of the sidebar as the first way into the vault.

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
| ⌘E | Command palette (search, all tags, commands) |
| ⌘F | Search the vault |
| ⌥⌘F | Find within the note |
| ⌘B / ⌘I / ⌘U | Bold / italic / highlight |
| ⌘1 … ⌘6 | Heading level |
| ⌘K | Link selected text |
| ⌘L | List |
| ⌥⌘→ / ⌥⌘← | Indent / outdent. (⌘→ / ⌘← are back to the system default: end and start of line.) |
| Tab / ⇧Tab | Indent / outdent in lists |
| ⌘[ / ⌘] | Back / forward through visited notes |

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

**B. Sidebar navigation** (the big one, which needs decisions first)
- Folders, tags as a hierarchy, and pinned areas, as described under "Sidebar navigation".

**C. Investigation: daily notes as the home for meetings**
- See "Topics for investigation".

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

## Topics for investigation

### Daily notes as a meeting log
Today, each meeting gets its own note, because finding things inside daily notes in Obsidian is hard. The goal is one note per day holding all that day's meetings (for example seven), which only works if any one meeting's minutes are easy to find later. To investigate:

- **Search that knows about sections:** results that point to the heading a match is under, and open the note scrolled to that heading.
- **Section links:** linking to one meeting, as in `[[2026-10-18#Team sync]]`, with backlinks shown per section.
- **A meetings view:** every meeting heading across all daily notes as one list, filterable by person, tag or date. This could come straight from the search index.
- **Marking a meeting:** decide how a section counts as a meeting. Options are a heading level, a `#meeting` tag under the heading, or a template.
- **Quick entry:** a "New Meeting" command that adds a meeting section to today's note from a template, including the time.

## Open questions

1. **Templater:** do you use the Templater community plugin (`<% %>` syntax), or only Obsidian's core Templates? Templater scripts can't be run outside Obsidian. We'd preserve them, but they wouldn't expand.
2. **Focus mode icons:** which icons stay visible besides the note-list button.
3. **Sidebar: a flat "All Notes" view.** Should "All Notes" (every note, newest first) remain as the starting view, with folders browsable alongside? Suggestion: yes.
4. **Sidebar: new notes.** When you're inside a folder, should ⌘N create the note in that folder? Suggestion: yes. The root otherwise.
5. **Sidebar: pinning.** Pin both folders and tags? Pins would be stored in Imprint's own settings, not in the vault.
6. **Sidebar: moving notes.** Should notes be movable between folders by dragging?
7. **Sidebar: where tags live.** Should tags be a section of the sidebar, or a separate view you switch to?
