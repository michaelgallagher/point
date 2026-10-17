# Imprint — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. It works directly on an Obsidian vault.

"Imprint" is a working name.

## Principles

1. **The file is the truth.** Notes are plain `.md` files in a folder that is also an Obsidian vault. Every unchanged byte stays unchanged, including frontmatter key order, whitespace, and syntax we don't render.
2. **Never see Markdown.** Editing feels like rich text. Markdown decides what formatting is possible. A raw-source toggle exists for emergencies.
3. **No filing.** Notes appear as one flat list, organised by links and tags. Search does the finding.
4. **Capture is instant.** One press on the iPhone gets you to a blank note with the keyboard up.
5. **Native and fast.** Use platform conventions, open instantly, and stay responsive with 10,000 notes.

## Decisions so far

### Platforms

| Machine | OS | Role |
|---|---|---|
| M3 MacBook Pro | macOS 26 | Primary. Full experience. |
| 2017 Intel MacBook Pro | macOS 13.7.8 | Occasional use. Simpler experience is fine: no semantic search, no AI features, no Liquid Glass. |
| iPhone | iOS 26 | Full experience. iPad is not in scope. |

- **Builds:** made on the M3. Xcode 26 doesn't run on macOS 13, so builds are copied to the old Mac to test. The first launch there needs right-click and Open.
- **Audience:** just Mike for now.
- **Developer account:** none yet. Start Mac-first, and buy the paid account when the iPhone milestone begins. Free-account iPhone builds expire after 7 days and can't use extensions.
- **Involvement:** Mike reviews at milestone boundaries.

### Vault, storage and sync

- **Location:** the existing Obsidian vault moves into iCloud Drive. Turn off Obsidian Sync for it, because two sync engines on one folder cause conflicts.
- **Access:** the user picks the vault folder once, and the app keeps a security-scoped bookmark to it. On iPhone the folder is picked through the Files app. This needs no iCloud entitlement.
- **Folders:** existing folders are read recursively and shown as one flat list. Files stay where they are on disk. New notes go to the vault root.
- **Dot-folders:** `.obsidian/` and other dot-folders are ignored, except for the Obsidian settings we read (below).
- **Attachments:** follow Obsidian's configured attachment folder (`.obsidian/app.json`).
- **Daily notes:** compatible with Obsidian. Read the folder, date format and template from `.obsidian/daily-notes.json`.
- **Note names:** the title is the filename. An untitled note gets a timestamp name until it has a first line, and is renamed to that first line when you leave the note. Never rename while typing.
- **Renames:** update all `[[links]]` to the note across the vault, honouring Obsidian's link-format settings.
- **Side by side with Obsidian:** Obsidian edits the same files concurrently. The app watches the vault and reloads externally changed notes without losing your cursor. iCloud conflict versions are surfaced, never silently dropped.

### Editor

- **Display:** a custom native text view. The underlying string is always the exact Markdown. Rendering hides syntax characters and applies styles. We never convert to rich text and serialise back, which is what makes byte-for-byte preservation possible.
- **Commands:** formatting commands edit the Markdown directly. For example, ⌘B wraps the selection in `**`.
- **Syntax visibility:** never shown. A menu command toggles raw source.
- **Rich editing in v1:** headings, bold, italic, highlight, links, wiki links, tags, lists, checklists, quotes, images, code blocks, callouts.
- **Rendered but read-only in v1:** tables, `![[embeds]]` and footnotes. You change these through the raw toggle. Their contents are always preserved.
- **Frontmatter:** a collapsed strip under the title, such as `3 properties · #work #ideas`, that expands into a key/value editor. Unknown keys and their formatting are preserved.
- **Tags:** read from both inline `#tags` and the frontmatter `tags:` property, and treated as one set. New tags go inline.
- **Pasting links:** pasting a URL over selected text makes that text a link.

### Search and connections

- **Search:** handles typos and partial words, word forms (run, running, ran), filters by tag, date and links without a query language, and meaning (semantic search).
- **Connections:** backlinks, unlinked mentions (one click to link), a related-notes panel, and tag suggestions. No graph view.

### AI (on-device only)

- **Outputs:** a weekly digest, topics over time, and clusters of related but unlinked notes.
- **Engine:** Apple Foundation Models and Natural Language embeddings, on macOS 26 and iOS 26 only.
- **Storage:** results are written as ordinary Markdown notes in the vault, so they sync everywhere, the old Mac included. Each has a deterministic filename (for example `Digest 2026-W42.md`) so two devices never both write one.

### Quick capture (iPhone)

- **Entry points:** a Lock Screen and Control Center control (also usable on the Action button), Siri phrases and dictation, the share sheet, and Apple Watch.
- **Destination:** each capture is a new note, and a link to it is added to today's daily note.
- **Mac:** no global hotkey for now.

### Mac keyboard shortcuts

| Keys | Action |
|---|---|
| ⌘E | Command palette (search, all tags, commands) |
| ⌘F | Search (see open question 3) |
| ⌘B / ⌘I / ⌘U | Bold / italic / highlight |
| ⌘1 … ⌘6 | Heading level |
| ⌘K | Link selected text |
| ⌘L | List |
| ⌘→ / ⌘← | Indent / outdent (replaces line start and end; Ctrl-A and Ctrl-E still work) |
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
- **Text engine:** TextKit 1 vs TextKit 2 is decided in milestone 1. TextKit 1 is the default candidate because it is mature on macOS 13.
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
- Wiki links with autocomplete, tags, the frontmatter strip and daily notes.
- External change handling (Obsidian, iCloud) and conflict surfacing.
- Raw toggle, focus mode (hide all chrome), back and forward, link pasting.

### M3 — Search and palette
- Index, fuzzy and word-form search, filters.
- ⌘E palette with tags and commands.
- Backlinks and unlinked mentions.

### M4 — iPhone
Buy the developer account first.
- Folder access through Files, list and editor.
- Formatting bar above the keyboard.
- Capture: control, Siri and App Intents, share extension.

### M5 — Meaning
- Embeddings index.
- Semantic search, related notes and tag suggestions.
- Weekly digest, topics over time and clusters.

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

## Open questions

1. **Name:** is "Imprint" the name?
2. **iPhone model:** Foundation Models needs an Apple Intelligence-capable iPhone (15 Pro or newer). Which iPhone do you use?
3. **⌘F:** should it search the whole vault (your spec) or find within the note (the Mac convention)? Suggestion: ⌘F searches the vault and ⌥⌘F finds within the note.
4. **Obsidian link format:** do you use `[[wikilinks]]` everywhere, or some `[markdown](links)`? Do you use Obsidian templates?
5. **Hiding chrome:** what should focus mode look like? Just the text, or text plus a faint title?
6. **Note list:** sort order, pinned notes, and whether rows show a preview line.
