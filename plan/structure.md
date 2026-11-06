# Beyond text: structure, names and Obsidian

*6 November 2026. Decisions made with Mike on how Point's bigger features fit together. Decided, not yet built.*

Part of [the plan](../PLAN.md). Follows on from [Images: where to store them](images.md).

## Why together

Several big features were on the table at once: images, comparing drafts, lists made from properties, and people, tags and property types as things in their own right. Choosing a storage format for one of them (TextBundle, for images) would have constrained all the others. Most of them rest on the same foundations, so they were decided together, along with the question under all of them: how closely Point stays tied to Obsidian.

## The principle: plain files, readable anywhere

Point no longer aims to be compatible with Obsidian. It aims for this:

> **Plain files, readable anywhere.** Notes are Markdown files that any tool can read. Point can add things of its own, but each one must still read sensibly, and lose nothing, in a text editor, Obsidian or Claude.

What that keeps, and what it lets go:

| | Decision |
|---|---|
| Plain `.md` files in real folders | **Kept.** They're what make the notes Mike's own: they sync safely through iCloud, and git, editors and Claude's skills can read them. |
| `[[links]]`, `![[embeds]]`, YAML properties, `#tags` | **Kept** as the base. Point adds to them. |
| Reading Obsidian's settings in `.obsidian/` | **Kept for now.** Replaced by Point's own settings in `.point/` as features need them. |
| Editing side by side with Obsidian, on the same files at the same time | **Kept until Point's iPhone app is in daily use.** Until then Obsidian may still be the app on the phone. New features are designed as Point's own from now on, but must not break Obsidian's editing meanwhile. |
| Obsidian's feature formats (`.base`, Dataview, canvas) | **Not followed.** Existing files are converted or left alone. |

**Ruled out, whatever Point's ties to Obsidian:**
- **Notes as bundles or folders** (TextBundle, or a folder for each note). Every note's text would be a file called `text.md`, Obsidian couldn't read the vault, and every tool and skill would have to learn the format.
- **Properties outside the note** (in TextBundle's `info.json`, say). A note in two files can be half-synced by iCloud, with its text from one device and its properties from another. And in Point it would look no different, since Point already hides the YAML.
- **A database of Point's inside the vault.** SQLite in iCloud can corrupt, and no other tool can read it.
- **Facts that live only outside the notes.** Indexes and caches stay outside the vault, and hold only what can be rebuilt from the notes.

## Where things live

- **Meaning goes in the notes:** text, properties as YAML at the top of the same `.md` file, links and embeds.
- **Point's settings go in `.point/`** as small JSON files, synced with the vault, or in `.obsidian/` where an Obsidian setting already covers it and side-by-side editing still matters.
- **Indexes and caches stay outside the vault,** on each device, and can always be rebuilt.

## The shared foundations

**1. A typed index of the vault.** `IndexKit`'s SQLite index already has tables for tags, links, property names and property values, but every value is text and every link is just a name. It grows into a typed graph of the vault:
- **Properties with types:** dates as dates and numbers as numbers, so "edited this week" or "rating above 3" is a fast query at 10,000 notes.
- **Links with a kind:** a link in the text, an embed, a link in a property (`people:`), or a draft's link to its post.
- **Tags, people and images as things,** each with the notes that use them.

**2. One way of describing a query.** Search, lists, sidebar places, the palette, people's pages and the planned properties view all ask the index through it.

**3. Changes across the vault, with undo.** Renaming a note, a tag, a property, a person or an image changes every note that uses it, writes well-formed Markdown and can be undone. Point already does this for a note's links. It becomes general.

**4. Views laid over the text,** as tables already are. Images, embedded lists, people shown as chips, and changes in a comparison all use one mechanism.

## Titles and file names

- **The name you see comes from a `title:` property.** It can be anything: colons, question marks, slashes, capitals. Two notes can share a title.
- **The file is named from the creation date and the title:** `2026-11-06-questions-about-my-vault.md`. The date is added once, when the note is created.
- **When the title changes, the file name follows,** with the date kept. Point rewrites the links to it.
- **A link is written with the file name and the title:** `[[2026-11-06-questions-about-my-vault|Questions: about my vault?]]`. It reads well in other tools. Point shows only the title, and keeps the part after `|` up to date when the title changes.
- **Existing notes keep their names.** A note without `title:` takes its title from its file name, as now. Only new notes get the new names.

**Still to decide:**
- **Accents, other scripts, emoji and long titles** in file names, such as é becoming e, and a cap on length.
- **Two notes made the same day with the same title:** the second gets `-2`.
- **Untitled notes:** today they get a timestamp name and are renamed to their first line when you leave them. The new names need an equivalent.
- **Renaming an existing note:** does it switch to the new style, or keep its old one with a new title?
- **Daily notes** already fit: `2026-11-06.md`.
- **Notes from other tools** have no `created` date, so it would come from the file's creation date.

## People, tags and property types

- **The index works out every tag, person and property value** from the notes, with where each is used. Merging and renaming them are changes across the vault.
- **A person gets a note of their own** (`People/Sam Lee.md`) when there's something to say about them: their role, their organisation. A tag can have one too, optionally. Backlinks give each person their meetings and mentions for free. Properties such as `people:` hold `[[links]]` to these notes.
- **Point's own property types live in `.point/types.json`.** Besides Obsidian's text, list, number, checkbox, date and date & time, it adds:
  - a **person**
  - a **choice from fixed values** (status: draft, review, published)
  - a **link to a kind of note** (a `post:` property that only offers posts)
  - a **rating**

  The values are still ordinary YAML, which other tools read as text.
- **`@` is a typing shortcut.** Typing `@Sa` suggests people, and picking one writes `[[Sam Lee]]`, a link to their note. Point shows it as a person. There's no new syntax, so it's a link everywhere.
- **No separate database** of people or tags.

## Lists from properties

- **A list is a note.** Its properties describe the query: what to include, how to sort and group it, and how to show it (a list, a table, cards, a calendar or a board). The results show live under the properties. Lists are searched, linked, pinned and opened on the iPhone like any note. Obsidian shows only the properties, and nothing is lost.
- **A list can be embedded** in any note with `![[List name]]`, using the views over the text. It's defined once and can be embedded in many notes.
- **Lists are built with menus,** not typed as a query language, and saved as the list note's properties.
- **Results are worked out in the background and cached,** so an embedded list never slows typing.
- **First, lists you read and click through.** Changing values right in a list's table (which writes each note's YAML) comes after, building on the table grid.
- **Existing `.base` files** are converted once, or left alone.
- **The planned properties view** across the vault becomes the first list.
- **Maybe later:** a list block written inside a note, for one-off lists.

## Comparing drafts

- **Compare with…,** from the palette or a note's menu, compares two notes, or a note with an earlier version.
- **It opens inline,** like tracked changes in one note: removed words struck through, new ones highlighted. A switch shows the two side by side instead, in the split, aligned and scrolling together.
- **Paragraphs are matched first,** including ones moved or split, then words within each changed paragraph. It compares what you read, not the Markdown, so `**bold**` appearing isn't reported as new text.
- **Drafts are linked by a property:** `draft-of: [[Post]]`. "New draft" copies a note and sets it. A post's page lists its drafts, and Compare offers them first.
- **The same engine serves:**
  - iCloud conflict copies, which must be "surfaced, never silently dropped"
  - earlier versions of a note
  - what changed outside Point since you last looked
- **Later:** taking a paragraph from the other draft with one click.

## Images

As recommended in [Images: where to store them](images.md):
- **One attachment folder.**
- **Images named after their note.** With the new file names, that's the note's file name plus a number.
- **Point looks after them:**
  - they move to the trash with the only note using them
  - they're renamed with it
  - a command finds images no note uses
- **An image is something the index knows about,** shown with the views over the text. This view is also what embedded lists will use.

## Order of work

1. **The typed index and the query model.** The foundation for everything after, starting with the properties view.
2. **Types and people:**
   - `.point/types.json`
   - values to choose from
   - person notes and `@`
   - renaming tags, properties and people across the vault
3. **Titles and the new file names.**
4. **Images,** with the views over the text for embeds.
5. **Lists,** as notes, embedded with `![[…]]`.

**Comparing drafts can come at any point.** It depends mostly on the editor and a diff engine, not on the index. `draft-of:` only needs a property.

The iPhone app (M4) and the real-vault trial still come first. Dropping side-by-side editing with Obsidian waits until the iPhone app is in daily use.

## Progress

**1. The typed index and the query model (built 6 November 2026, branch `typed-index`):**
- **The index (schema 8)** keeps each property value with its number or date, and the name it links to if it's a link. Links have a kind (text, embed, property, with the property's name). Notes have their folder, and their dates created and edited.
- **`NoteQuery`** (IndexKit) describes which notes, sorted how: filters for tags, folders, properties (exists, missing, empty, is, contains, less, greater, within the last or next so many days), the note's own title, folder and dates, links to a note, and words. They combine with all, any and not. It's turned into one SQL statement, and saved as JSON. `property is Sam Lee` finds `people: ["[[Sam Lee]]"]`, numbers compare as numbers, and "on or before 6 November" takes in the whole of the 6th.
- **Fast:** on a real vault of a few thousand notes, a query takes 1 to 4 ms, and summarising every property takes 8 ms.
- **The properties view** (Mac): Properties in the sidebar, beside All notes and Trash, once the vault has any. It lists each property with its type's symbol and how many notes have it. A property shows its values, each with how many notes give it, and its notes. A value shows its notes. Values differing only in case are one, and a link shows as its name. The notes come from the index in the background, in the list's own order, and are never waited for on the main thread.
- **Not yet:** renaming a property and fixing its type across the vault from there. That comes with the changes across the vault, in the next step.

**2. Types and people (built 6 November 2026, branch `types-and-people`):**
- **Changes across the vault** (`VaultChanges`, VaultKit): rename a property, change a value, or rename a tag (and the tags nested under it, in properties and in the text) in every note that has it. Each note is read, changed as it writes things (its quotes, a list in brackets kept in brackets), and written only if unchanged since. A note that already has a property with the new name is left alone and named. Undo puts back each note not changed since.
- **In the Mac app:** Rename Tag…, Rename Property… and Change Value… on the sidebar's tags, properties and values, and in the palette while browsing one. A notice says what changed, in how many notes, with Undo for a few seconds; the palette has Undo too until the next change.
- **Point's own kinds of property** (`.point/types.json`): choice (a menu of its choices, edited with Edit Choices…, starting as the values the vault gives it), person (links to people's notes, suggested), rating (stars), and link to note (suggested from a folder). Each is also kept in Obsidian's types file as what it's written as (text, list, number), so Obsidian goes on reading it the same way.
- **People** are the notes in the people folder (`.point/types.json`, else a top-level folder called People) and whoever's linked in a person property, most linked first.
- **`@` in a note:** typing `@` and a name suggests people; picking one writes `[[Name]]`. Not in an email address, code or a link.
- **Not yet:** the iPhone's properties sheet edits Point's kinds as what they're written as (a choice as text, say). People aren't yet shown as chips in the text.
