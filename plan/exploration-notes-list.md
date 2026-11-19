# Exploration: a more powerful notes list in two columns

Part of [the plan](../PLAN.md).

**The question** (Mike, 19 November 2026). The folder-pages trial (branch `folder-pages`) raised a broader idea: the two-column layout's notes column could do more. That might mean better filtering, smart and saved searches, or optional extra columns as list notes have. These are notes only; nothing is built.

## The short version

Point already has the engine for this; the notes column just doesn't use it. List notes have a full query language (`ListDefinition`, `NoteQuery`):
- folders and tags as the source;
- conditions (`is`, `contains`, `before`, `in last 7 days`, `between`, `is set`, `links to`, `has words`);
- any or all;
- sorting by any property;
- columns.

List notes also have a chips interface (`ListPanel`, `ListFilterSheet`). The notes column has a title-only filter, a global sort, dates and an optional tags line. So most of this is wiring up what exists. The folder-pages trial and this idea are the same idea.

## What exists

- **The notes column** (`NoteList` / `SidebarTable`, content `.notes`) is about 215 points at the default sidebar width (60% of 360). Each row shows a title, with dates as headings or beside the title, and tags on a second line if turned on. The filter is a title substring, and sorting is global, not per place.
- **List notes** are stored in `list-` properties, so Obsidian reads them, and the iPhone shows them as a home tile. Results come asynchronously from the index ("Finding notes…").
- **Lists in the sidebar** is a place listing every list note. Clicking one opens the note; its results don't show in the notes column.
- **Search** (⌘F, ⌘E) covers the whole vault, with typos, word forms and meaning. That's a different job from narrowing the list in front of you.

## The key observation

A place and a list note are both definitions that yield notes.

| | Where notes come from | How they're narrowed | How they're shown |
|---|---|---|---|
| Folder | the folder | nothing | the column |
| Tag | the tag | nothing | the column |
| List note | `list-from` / `list-tags` | `list-where` | a table in the note |
| Folder page (trial) | the folder | nothing | a table in the panel |

If every place carries a list definition, the column and the folder page are two views of one thing. The column is compact: titles and a line of detail. The page is full: a table and columns. A "saved search" is then that definition saved as a list note, a format that already exists.

## Ideas, ranked by value for cost

1. **Lists as places in the notes column** (small, high value).
   - Picking a list note in the tree (under Lists, or pinned) shows its results live in the column, as a folder shows its notes. These are smart folders, stored as Markdown, and they work on the iPhone too.
   - The note itself stays one click away, through the name in the bar or a menu.
   - Trade-offs: a list note is both a note and a place, so "open the note" versus "browse its results" needs one clear rule. Results arrive asynchronously, so the column mustn't flash empty.
2. **A filter that understands more than titles, plus "Save as list…"** (medium).
   - A "+ Filter" button beside the field adds a condition through the existing sheet: tagged, edited in the last…, has a property, links to. Plain typing stays a title match.
   - "Save as list…" turns the current place and its chips into a new list note.
   - Trade-offs: chips take height in a short column. Each condition is an index query, so it needs measuring on the real vault for lag. It overlaps with ⌘E: the filter narrows this list, and search finds notes anywhere.
3. **Per-place view settings** (small to medium).
   - Sort, date style and a chosen detail line per place: for example `status` or `author` under titles in Reading, dates in Daily. This is the column's form of "extra columns".
   - Trade-off: settings kept in Mac preferences are invisible and don't sync, unless they live in a list note.
4. **Extra columns in the notes column** (not recommended as such).
   - At about 215 points, a second column leaves titles 100 points or less, and Mike's windows are often narrow. Columns belong to the full view: the folder page or a list note.
   - If they're wanted anyway, show them only once the column is wide enough, as Mail's wide layout does, and fall back to the detail line.
5. **Folder pages as the full view** (the trial already built).
   - Once places carry definitions, the page is where columns, layouts and customising go. It edits the same definition the column uses.

## Risks

- **Speed.** Today's column is synchronous, with titles from memory. Conditions go to the index. Every new filter needs measuring on the real vault, and rows mustn't jump while results arrive.
- **Notion creep.** Keep the definition in Markdown (the `list-` properties) and keep the options few. If an option can't be written as a `list-` property, question whether it should exist.
- **Three ways to narrow notes.** The column filter, list notes and ⌘E all do it, so each needs a distinct job.
- **The iPhone.** Ideas 1 and 2 come almost free there, since it shares list definitions. Per-place settings kept in Mac preferences wouldn't.

## Open questions

1. Are list notes in the vault the right home for saved searches, visible in Obsidian? Or should saved searches stay out of the vault?
2. Which filters would be used day to day: tags, dates, a property like `status`, or links?
3. Which properties belong in a detail line under titles?
4. Should two columns grow toward the folder-page model, with the column compact and the page full? Or should folder pages stay a separate trial?

**Suggested first step:** idea 1. It's small, gives smart folders at once, and settles the "a place is a definition" model the rest builds on.

## Revised after Mike's reply (19 November 2026)

**Idea 1 is weaker than it looked.** Lists as places means every list note becomes a row in the tree. That's fine for three lists and unwieldy for thirty. It would need a rule like "only pinned lists are places", which makes smart folders a special case of pinning. It's moved down, behind the ideas below.

**Types already go beyond Obsidian.** In two columns, a kind (Media, Meeting, Topic…) lists every note whose `type` says so, wherever it lives. Obsidian has no such thing without Dataview or Bases. So Point already has smart lists; what's missing is that they all look the same.

**The stronger idea: rows that suit what they show.** The notes column's second line is a global "Show tags" toggle (`showsTagsInList`; `SidebarTable` already sizes rows that have one). Make that line, and a marker beside the title, depend on context:
- **By kind, set in `.point/kinds.json`.** Media shows whether it's been read (a dot, as Mail shows unread) and its format. Topics, people and meetings each show a property of their own under the title. Because the rule belongs to the note's kind, a Media note looks the same in its folder, under a tag or in search, and the setting lives in the vault, so the iPhone gets it too.
- **By place, for folders that hold reading.** Such folders usually hold one kind already (every note has `type: Media`), so the kind's rule covers them without folder settings. A per-place setting is only needed for the exceptions: sort and grouping, such as Media grouped by status (Unread, Reading, Read).
- **"Read" needs one decision:** which property and which values mean done (a `status` value, or a `read` date). That belongs in the kind's entry, not hard-coded.
- **Topics under the name** come from the note's `topics` links, shown as names, as tags are now.

## What Obsidian's plugins suggest

- **[Notebook Navigator](https://github.com/johansan/notebook-navigator)** is reported to be Obsidian's most popular plugin ([dsebastien](https://www.dsebastien.net/notebook-navigator-is-now-obsidians-most-popular-plugin/)). It replaces the file explorer with an Apple Notes-style pair of panes, which is Point's two-column layout. What its rows and lists can do:
  - preview lines, feature images and dates, with property values or word counts in the row;
  - grouping by date, folder or a property;
  - per-folder and per-tag overrides of the row's look, sort and grouping;
  - shortcuts that can point to saved searches, as well as to notes, folders and tags;
  - a filter syntax typed in the filter field: `#tag`, `-word`, `.status=Read`, `@thisweek`, `folder:`. ⌘-click on a tag adds it to the filter.
  - The demand is real, and the shape is the same.
- **[Bases](https://help.obsidian.md/bases)** is Obsidian's own core answer to list notes: `.base` files holding filters, formulas and table, list or cards views. It matters for interoperability. Point's `list-` properties are Point's own format; reading or writing `.base` files would make saved searches portable both ways, and Bases' small set of views is a good guard against Notion creep.
- **[Folder Notes](https://community.obsidian.md/plugins/folder-notes)** (about 486,000 downloads) gives each folder a note of its own: the folder-pages trial's idea, done with a Markdown file.
- **Front Matter Title, [Frontmatter Alias Display](https://community.obsidian.md/plugins/frontmatter-alias-display), Workholic and Explorer Property Attributes** each show a property in the file list, or style rows by one (Explorer Property Attributes is billed as "Mark as Read"). There's clear demand for properties and read state in the list, served by many small plugins.

## Revised ranking

1. **Rows that suit their kind**: a marker and a detail line per kind, in `kinds.json`. Small to medium, and it's the variant Mike raised.
2. **Group and sort per place**, for example Media by status. Small, once 1 exists.
3. **A filter syntax in the field**: `#tag`, `status:unread`, `@thisweek`. Plain words stay a title match. Typed text costs no height in a narrow column, unlike chips.
4. **Saved searches as pinned queries**: a saved filter is pinned like any place, so only the ones chosen appear in the tree. Whether they're stored as list notes, `.base` files or Point's settings is open.
5. **Lists as places** (the old idea 1), only through pinning, as in 4.

**New questions:** which property marks Media as read today, and with what values? For each kind, what would go on its second line? Should Point read, or write, Obsidian's `.base` files?

## Mike's answers (19 November 2026)

- **Read state** is the `read` property: unread is `read is not set`, as list conditions already say.
- **The detail line** is usually topics, but not always, so it should be customisable for now. Projects would show topics; meetings, people or topics.
- **`.base` files:** unsure. They're one route; Point's own format keeps flexibility. The analysis is below.

**A shape for the detail line:** each kind in `kinds.json` names a short, ordered list of properties, and the row shows the first that has a value. A meeting would be `people, topics`: its people, or its topics when nobody's named. A folder that isn't a kind (Projects, if it's only a folder) can name its own list, which wins over the kind's. When no rule applies, the row has no line.

## Point's format or Obsidian's Bases

**What each one is.**
- **Point's list notes:** a list is an ordinary note. Its `list-` properties are short English lines (`read is not set`, `rating > 3`, `links to [[Service design]]`), and the body can hold prose. They can be read and written by hand, and they're the format used today on the Mac and the iPhone. Obsidian shows them as plain properties, not as results.
- **Bases:** a `.base` YAML file, or a `base` code block inside a note. Its filters are expressions in a JavaScript-like language (`file.hasTag("book")`, `file.inFolder("Reading")`, `read.isEmpty()`). It adds formulas, summaries and several views. Obsidian defines it, and Obsidian changes it: views like Kanban arrived in later versions.

**The asymmetry.** Writing Bases from Point's conditions is easy, because each of Point's conditions has a Bases expression. Reading Bases into Point is hard: it means parsing an expression language, and any file written in Obsidian may use formulas or functions Point can't evaluate.

**Options.**
1. **Point's format only** (today). Full flexibility and readable Markdown, at no cost. But Obsidian can't show the results.
2. **Bases as the format** (read and write). Results show in both apps, and the format is Obsidian's, not a private one. But Point takes on a language it doesn't control. It would support part of it, and a list made in Obsidian would sometimes half-work in Point. Point's own extras, like display rules, have no home in it, and the format can change under it.
3. **Point's format, plus a generated Bases block** (one way). A list note keeps its `list-` properties as the truth, and Point also writes a `base` code block into the body (marked as Point's), so Obsidian shows the same results. Only the easy direction is needed. The catch: an edit to that block in Obsidian would be overwritten, or would have to be noticed and flagged.
4. **Point's format, and read `.base` files where they fit** (one way, the other direction). A `.base` file whose filters are all expressions Point understands shows as a list. Anything else opens as a file. Useful only if `.base` files get made in Obsidian, and it carries the cost of the parser.

**Recommendation:** 1 now, and keep 3 as a cheap bridge if seeing lists in Obsidian ever matters. Avoid 2: it trades a readable format Point owns for a language it would only half-support. Option 4 isn't worth it unless `.base` files start appearing in the vault. Display rules and saved filters stay in Point's own files either way (`kinds.json`, list notes).

**Decided (Mike, 19 November 2026): option 1, Point's own format.**

## Embedded lists, and what they change

Embedding by reference is already built: `![[Books to read]]` alone on a line shows a list note's first 10 notes, on the Mac and the iPhone (`structure.md`, `m4-iphone.md`). The list is defined once, in its own note, and shown in many. That fits option 1 and changes nothing.

A list **defined inside** another note, as a block in its body rather than a note of its own, would change three things:
- **It needs a body format.** For example, a fenced `list` block holding the same lines as the `list-` properties (`from Reading`, `read is not set`, `sort published descending`). It would be the same language in a second place, so it's still option 1. In Obsidian it shows as a code block. This is the one place where Bases would have given something for free, because Obsidian draws `base` blocks inline.
- **It has no name to point to.** The column, pins and saved searches need an address. An inline list can't be pinned or shown in the notes column unless it's given one (a heading or a block ID). So the rule would be: lists that are places are list notes, and inline lists are one-off views inside a note.
- **Promoting an inline list.** "Move to its own note" would turn an inline block into a list note and leave `![[…]]` in its place, as extracting text into a new note does.

**What it suggests for rows:** an embed, a folder page and the notes column should draw rows the same way. A list with no columns (`list-show`) would use the kind's marker and detail line, so a Media note looks the same everywhere.

## Built: rows that suit their kind (19 November 2026, branch `improving-lists`)

- **In `.point/kinds.json`,** a kind can now carry two more keys, edited by hand for now:
  - `detail` is an ordered list of properties. The row shows the first that has a value, under the note's name.
  - `read` is a property; while it isn't set (or is `false` or `no`), the row is marked unread.
  - For example: `{"name": "Meeting", "detail": ["people", "topics"]}` and `{"name": "Media", "detail": ["topics"], "read": "read"}`. A kind without these looks as before.
- **In the notes list** (both layouts, since one column uses the same rows):
  - **Unread** shows as a dot in the margin before the title, as in Mail, so titles stay lined up. It turns white on the blue selection.
  - **The detail** sits on the second line, with links shown by name (`[[Topics/Service design]]` is "Service design"). Tags follow it when "Show tags" is on.
  - A note with neither stays one line.
- **Where the values come from:** the index, all at once, after each change to it and when the kinds file changes (`SearchIndex.propertyValues(named:)`, `VaultStore.listLooks`). The work is off the main thread. Only notes that look different are kept, and the list redraws only when something changed.
- **Tried:**
  - `KindListLookTests` (loading the keys, the properties asked for, the first detail with a value, links by name, unread).
  - The debug build on the test vault, with a kinds file and a "List looks" folder of samples added to it.
  - A generated vault of 10,000 notes (4,000 Media, 2,000 meetings): looks for 5,496 notes were ready 0.18 s after the index. Marking a note read on disk updated its row with the next rescan, within half a second.
- **Tried on a real vault** of a few thousand notes, with the keys added to its kinds file: dots and topics showed at once. The kinds file is read again when Point comes to the front, so a change made in another app shows on switching back.
- **Not tried:** how a selected unread row looks (the white dot); the iPhone, whose lists don't use this yet.
- **Next:**
  - a folder's own rule, which overrides its kind's;
  - the same rows in embedded lists and folder pages;
  - grouping per place, such as Media by read and unread;
  - perhaps a way to set `detail` and `read` in Settings rather than by hand.
