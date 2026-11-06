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
- **Not yet:** people aren't yet shown as chips in the text. (The iPhone's properties sheet edits Point's kinds since 6 November, branch `iphone-catchup`.)

**3. Titles (built 6 November 2026, branch `titles`):**
- **Names** (`NoteNames`, VaultKit): a new note is named for its day and its title, `2026-11-06-questions-about-my-vault.md`. Accents and other scripts become plain letters, emoji and punctuation go, and long titles stay long. A name that's taken gets `-2`, `-3` and so on.
- **The title shown** is the note's `title:` property, but only for a note named this way. Every other note shows its file name, as before, even if it has a `title:` (many clipped notes do).
- **Retitling** sets `title:` (added first in the frontmatter) and renames the file to match, keeping its day. Links to it follow, and a link's label that was the old title becomes the new one; a label of its own stays.
- **Links** to these notes are written `[[2026-11-06-questions-about-my-vault|Questions: about my vault?]]`, when picked from suggestions or added to a property.
- **The `title:` property is hidden** in the Mac's properties strip and the iPhone's properties sheet. It's the title above the note.
- **New notes only:** linked notes, daily notes and templates are named as before, and existing notes keep their names.
- **Not yet:** notes made in Obsidian aren't given titles. (Tried on the phone in the Simulator on 6 November, branch `iphone-catchup`, which fixed titling an open note there: see `m4-iphone.md`.)

**4. Images (built 6 November 2026, branch `images-support`):**
- **Shown in the Mac's editor:** an image embedded alone on its line (`![[a.png]]`, `![[a.png|300]]`, `![alt](Attachments/a.png)`) is drawn above the line, at its own size (a Retina screenshot at half its pixels), narrowed to fit the text and no taller than 520 points. Its Markdown stays under it as a small grey caption with the file's name, so the cursor, typing and Delete work on it as on any line. An image in a line of text stays a link; a missing one is a faint link.
- **Quick:** sizes come from the files' headers, and pictures are decoded off the main thread at the size shown, and cached. Typing in a long note with 40 images is no slower than in the same note without them.
- **Pasting and dropping:** a screenshot or image files pasted or dropped into a note are saved in the attachment folder Obsidian is set to (`attachmentFolderPath`), named after the note (`2026-11-06-meeting-1.png`, or `Meeting 1.png` for an older note), and embedded on lines of their own. A TIFF is saved as PNG, a HEIC photo as JPEG. Text copied from a web page still pastes as text.
- **Renamed with their note:** renaming a note (or its title, or naming an untitled note) renames the images named after it, and their embeds, in it and in any other note showing them, keeping a path or a width as written.
- **Trashed with their note:** a note's images that no other note shows go to the trash with it (`.trash/images`), and come back when it's put back. They're deleted for good with it.
- **Find Unused Images…** (palette): lists the images no note embeds or links to, each with Show in Finder, and moves them to the Trash.
- **Also fixed:** a note Point named was listed in the trash by its file name, and put back under its title.
- **Not yet:** resizing an image by dragging. (Images show on the iPhone since 6 November, branch `iphone-catchup`.)

**4b. Web images and browsing images (built 6 November 2026, branch `image-browsing`):**
- **Web images** (`![](https://…)`, most of a clipped vault's) load from their sites once and are kept in Point's caches, outside the vault (`WebImageCache`), then shown from there, offline too. They're loaded without cookies and with a User-Agent that says what Point is; a site can still tell when its image is loaded. Notes restyle once they arrive. Settings › Notes › Images turns them off.
- **Side by side and in quotes:** a line of only images (`![[a.png]]![[b.png]]`) shows them side by side at one height, fitted across the text; a quote or list item of only an image shows it inside.
- **Images in the list:** a folder's images are listed after its notes, under Images, each with a small picture, and filtered with them. All notes stays notes only.
- **The image viewer:** an image opens in a tab, as a note does (back, forward and tabs work for it): its name, size and folder, the picture as big as fits, and the notes that show it, each opening with a click. Show in Finder, Open in Preview, Rename… (which renames its embeds in every note, keeping a path or a width) and Move to Trash (the Finder's, saying how many notes show it first).
- **Not yet:** dragging an image from the list into a note (it would be copied, not embedded); images sorted by date.
- **Fixes (6 November 2026, branch `image-fixes`):**
  - Right-clicking an image in a note offers Open Image, Replace Image… (keeping its width; the old image stays, for Find Unused Images), Copy Image, Show in Finder (or Copy Image Address for a web image) and Remove Image. Double-clicking opens it.
  - Clicking an image's caption, or any link to an image, opens the image's viewer; it never makes a note. A missing image just beeps.
  - An image could stay blurred: a small picture decoded before the note was laid out could arrive after the sharp one and replace it.
  - Captions have no spelling marks.
  - A wrapped title in the list could take more lines than its row had room for: titles now wrap at the width their row's height was measured for.

**5. Lists (built 6 November 2026, branch `lists`):**
- **A list is a note** whose properties say what it lists (`ListDefinition`, IndexKit), so it reads the same in Obsidian, as properties:
  - `list-from`: folders, with the folders inside them
  - `list-tags`: tags, with the tags nested under them
  - `list-where`: conditions, one short line each, such as `format is Book`, `read is not set`, `rating > 3`, `published before 2020`, `date edited in last 7 days`, `links to [[Service design]]` or `has words org design`
  - `list-match: any`: to list notes meeting any condition, not all of them
  - `list-sort`: such as `published descending`
  - `list-show`: the columns after the title
- **Opened on the Mac:** under its other properties (the `list-` ones are hidden from the strip), the list's choices show as a line of tokens. Add filter adds a folder, a tag or a condition, made in a small editor. "and" or "or" between conditions switches them. The sort and columns menus choose from the vault's properties. Under the tokens is a table of the notes it finds, 50 at first, then more on request. A heading click sorts, and a row click opens its note (⌘-click in a new tab, ⌥-click on the other side). Each change is one undoable edit to the note's properties, writing only what changed.
- **New List** (palette): a list of the folder or tag being browsed, or of every note.
- **Embedded:** `![[Books to read]]` alone on a line in another note shows the list's first 10 notes, with Show all to open it, and its name under it as a caption. The room is made from what the list finds, and notes restyle when that changes. EditorKit has a general hook for this (`blockEmbedHeight` and `makeBlockEmbedView`).
- **Also fixed:** notes didn't restyle when web images arrived while they were open (SwiftUI didn't update the editor). Editors now restyle on a notice.
- **Not yet:** editing a list on the iPhone (it shows lists, read only, since 6 November, branch `iphone-catchup`); grouping; a list's results in the sidebar.
- **The filters window (6 November 2026, branch `list-filters`):**
  - Add filter, or a click on a filter, opens a window that edits all of a list's filters the way macOS edits rules (a Finder smart folder, a Mail rule). It reads "Show notes that match all (or any) of these conditions". Each condition is a row: what it's about (the note's folder, tag, title, dates, links and words, then the vault's properties A to Z, each with its type's symbol), how it compares, and its value. It is laid out in rounded groups, as System Settings is, but with standard Mac pop-up menus, always outlined: what it's about and how it compares are set widths, so they line up down the rows, and each value is one width too. An ✕ removes a row; a row is dragged by its handle, the others sliding aside as it passes; and "Add condition" below adds one.
  - The comparisons and the value's control suit the property's type, from Point's kinds, the vault's types, or how its values read. A date can be on, before or after a day, between two days, this week, month or year, or in the last or next so many days, weeks, months or years. A choice gets its menu, a rating stars, a checkbox ticked or not. Text, lists, tags and links get a combo box that completes from what the vault uses.
  - New in the list's format:
    - `read between 2024-03-01 and 2025-06-30`
    - `read is this year`
    - `read in last 3 months`
    - `folder is not Archive`
    - `tag is not draft`
  - "Has a value" and "has no value" mean what they say: a blank `read:` is no value.
  - With "any", a note in one of the folders, or with one of the tags, is listed too, as with any other condition.
- **The table (6 November 2026, branch `list-filters`):**
  - A list's notes are shown in a Mac table (`NSTableView`) with headings in sentence case. Click a heading to sort by it, and again to reverse. Drag a heading to reorder the columns: the title stays first, and the order is written to `list-show`. Drag a heading's edge to resize; widths are remembered for each list, on this Mac.
  - Long text wraps onto more lines in a list note; in an embed, rows stay one line, so the room made for it is right.
  - Titles turn link blue under the pointer, and the pointer is a pointing hand over rows, filters and buttons. The editor's I-beam no longer overrides the pointers of views in the note.
  - Date properties show as the Mac writes dates (1 Jan 2024).
  - A column's heading could show another column's name: the grid's heading row didn't always line up with its rows.
