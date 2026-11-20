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

## Built: marking read and unread (19 November 2026, branch `improving-lists`)

- **Mark as Read / Mark as Unread** for a note whose kind has a `read` property: in the notes list's context menu, the File menu and the command palette, with ⇧⌘U as in Mail (changeable in Settings). One note at a time, as the list selects one.
- **What it writes:** marking read sets the property to today (`read: 2026-11-19`), filling in an empty `read:` where a template left one, or adding it at the end of the properties; a note that says it's read already is left alone. Marking unread empties it (`read:`), so the note looks as its template made it. The rest of the file is untouched (`NoteKinds.markingRead` and `markingUnread`; the clipper's own mark-read now uses the same code).
- **The note keeps its date edited,** so marking a note read doesn't move it to the top of a list in that order. An editor with the note open saves first, then takes the change at once. The row changes straight away, before the index catches up.
- **Tried:** unit tests for both edits; in the debug build, ⇧⌘U on an unread book wrote the date and cleared the dot, and again emptied `read:` and brought the dot back, white on the blue selection. The iPhone app builds.
- **Not done:** several notes at once (the list selects one); moving a read clipping into another folder, as the iPhone does.

## Built: only unread (19 November 2026, branch `improving-lists`)

- **A filter button at the foot of the notes list,** between the filter field and the sort button, as Mail has. It shows only where some notes say when they were read (their kind has `read`), in two columns. On, it's filled and coloured, the list keeps only unread notes, and the count above says "N unread". An empty result says "No unread notes".
- **Kept per place, per vault:** turned on for Media, it stays on there, across launches, and nowhere else (`onlyUnread.<vault>` in the app's settings, by place).
- **The note open from the list stays** while it's selected, so marking it read doesn't whisk it away; it goes when you move on.
- **Speed:** on the 10,000-note vault, building the Media list's 4,000 rows takes about 15.5 ms without the filter (as before) and 18 ms with it. Whether a place tracks reading is worked out once until the list changes.
- **Tried:** the test vault (on, off, kept after relaunch) and the big vault (1,999 unread of 4,000).
- **Not tried:** one column, where it doesn't apply (there's nowhere to turn it off).

## Built: the same on the iPhone (19 November 2026, branch `improving-lists`)

The phone already had reading for clips alone: a check at the right of a read clip and an empty circle on one not yet read, a Read swipe (filing in Sources from the clippings folder), and All / Unread on the clip kind's list. That's kept, the phone's own way, and now follows the kinds file:
- **The read mark** shows on any note whose kind has `read` (and on clips, as before).
- **The line under the title** starts with the kind's `detail` when it has one ("Systems thinking, Service design · List looks"), then the folder, as before. Kinds without `detail` show what they did.
- **Marking:** a swipe gives Read, or Unread on a note that's read; a long press has Mark as read or Mark as unread, above Bookmark. Both write the kind's property as the Mac does, keeping the note's date edited, so the list doesn't reorder. "Read, to Sources" stays for clips waiting in the clippings folder.
- **All / Unread** is on every kind's list that tracks reading, remembered for each kind (the clip kind keeps the setting it had).
- **Tried** in the Simulator with the kinds keys added to its vault: detail lines, marks, Unread by swipe and Read by swipe (each written to the file, the list keeping its order), and the Unread switch.
- **Not done:** folders and tags on the phone have no Unread switch (only a kind's list has one); the reader's own Mark read, at the end of a clip, is still for clips only.


## Built: terms in the filter field (19 November 2026, branch `improving-lists`)

The filter field at the foot of the notes list still matches titles with plain words. It now also takes short terms, mixed freely with words, all of which a note must meet:
- `#tag` (with tags nested under it); `property:value`, a property containing the value (`topics:design`, `people:ana`, `topics:"service design"`); `property>value` and `property<value` for numbers and dates (`published>2020`);
- `has:property` (given a value), `in:folder`, `title:`, `folder:`, `tag:`;
- `is:unread` and `is:read`, by each kind's `read` property, as the dots show it (typed, it wins over the unread button);
- `@today`, `@yesterday`, `@thisweek`, `@thismonth`, `@thisyear`, `@7d`: edited then;
- `-` before any of them leaves those out (`-#draft`, `-has:read`, `-in:Archive`).

**What stays text:** `name:value` is a term only when the vault has a property by that name, so `Re: plans` or `10:30` still match titles. A half-typed term (`#`, `topics:`, `is:un`) is left out, so the list doesn't empty while it's typed. With any term, only notes show (not folders, tags or images, which have no properties). Hovering over the field lists the terms.

**How:** `FilterText` (IndexKit) reads the field into words and `NoteQuery` filters, using the conditions lists already have (`ListCondition`). The terms are asked of the index in the background, as list notes are; while a new answer is on its way the last one stands. `is:unread` uses the rows' looks, as the dots do.

**Tried:**
- Unit tests for reading terms, text that stays text, half-typed terms, and the terms against an index.
- The debug build on the test vault, a dozen terms traced (`-PointFilters`), each finding what it should.
- The 10,000-note vault's Media folder (4,000 notes): rows with a term take 13 to 16 ms to build, against 15.5 to 17.5 ms with plain words; the first after each change takes a little longer, building the set of matches.

**Not done:**
- The count above the list still counts the place's notes, not what the filter leaves (as with plain words before).
- No suggestions while typing a term (property names, values); terms aren't on the iPhone.
- Saving a filter as a list note, or pinning it: the next step, and these terms are what it would save.

## Built: tokens, suggestions and a filter menu (19 November 2026, branch `improving-lists`)

Typing terms was error-prone and hidden, so the field now builds them for you, as Mail's search does. The terms above are still what's underneath; the field and button stay where they were for now (they may move later).
- **Suggestions as you type.** Above the field, a short list of what the word could mean among the notes here: values (`Topics: Service design`, with how many notes have it), tags, `Unread`, `Has topics`, and times (`Edited this week`). Down and up arrows move through them, Return or a click picks one, Escape hides them (and, with none showing, clears the field). Nothing is chosen until you press an arrow, so Return still opens the top note. A lone `#` lists the tags here, `@` the times. The list is in Liquid Glass, as menus are, and sits in the field's own stack, growing up over the notes: glass in an overlay reaching outside its view wasn't drawn at all.
- **Tokens.** A picked suggestion becomes a token in the field, before the typed words. A term typed in full (`#work`, `has:read`) becomes one at a space or Return. A click on a token offers Leave Out (or Include) and Remove; Backspace in an empty field takes the last one away. Tokens keep their whole names while they fit and shorten, widest first, when they don't.
- **The filter menu** (the button beside the field, now in every list in two columns, not only those that track reading): Only Unread (kept for the place, as before), Edited ▸, Tags ▸, and each property here ▸ its values (most used first, with counts), Has Any Value and Has No Value. A choice adds a token, ticked in the menu while it's there; choosing it again removes it. Clear Filter at the foot. The button fills and colours while anything filters.
- **Only what's here:** suggestions and the menu come from the notes in the place, so neither offers what would leave nothing. They're counted by the index in the background (`SearchIndex.facets(of:)`): 4,000 notes in about 70 ms, again when the index or the place's notes change.
- **Tried:** unit tests for tokens (typed terms becoming tokens, labels, turning round) and facets; in the debug build on the test vault, typing, arrows, Return, a typed term, Backspace and Escape, each checked in a screenshot; the menu traced on the 10,000-note vault (`-PointFilterMenu`). Suggestions take 0.1 to 0.2 ms to work out there.
- **Not done:** the menu itself hasn't been opened by a click in testing (only traced), nor a token's menu; values given by every note here (Media's `type: Media`) are still offered; one column has the field's tokens and suggestions but no button; the iPhone has none of this.

## Exploring: the filter at the top, with chips (19 November 2026, uncommitted)

**The question** (Mike): would the filter field, filter button and sort button work better at the top of the notes column, with what's filtering shown as chips you can remove, rather than tokens inside the field? At the foot, three tokens in a 340-point column were already "Form…", "Topic…", "With…".

### Scroll with the list, or pin to the top?

| | Pinned under the column's title (built) | Scrolls with the list |
|---|---|---|
| Always visible | Yes: the field, buttons and chips are always there | No: they go once you scroll, along with any sign the list is filtered |
| ⇧⌘F | Unchanged: focus goes to the field, which is on screen | Would have to scroll to the top first, losing your place |
| The field keeps focus as you type | Yes: it's a SwiftUI view over the list, as at the foot | At risk: it would be a row in the AppKit table, which rebuilds its rows on every keystroke |
| Suggestions | Open downward in glass over the chips and list, in the same stack as the field (glass outside its view isn't drawn) | Also downward, but they'd scroll with the row, and would be cut off by the table's clipping |
| Blur | None new: the list's scroll view already blurs whatever is under its top inset (`BarEdgeScrollView`). Making the inset the bar plus the controls gives one blurred surface with the hairline below the chips | None needed |
| Room for notes | Fixed: 42 points for the field's row, plus 30 for each line of chips while filtering. The foot took 52, so with no filter the list has 10 points more | Gives everything back once scrolled |
| Cost | Small: a top inset on `SidebarTable`, the controls moved, a chips row | Medium to large: a SwiftUI field inside a table row, with its focus and state kept across reloads |

Two other options considered:
- **Pinned, but folding away when idle:** only a magnifier in the title row until you filter, as Mail's toolbar search does. It saves 42 points but hides the filter, the opposite of the aim. It could come later, as a setting.
- **Stay at the foot, with chips above the field:** this keeps the layout, but the chips would sit between the list and the field, with suggestions growing up over them. The column's name, the count and its filter would be at opposite ends.

**Recommendation: pin it.** Scrolling with the list goes against what the move is for, which is seeing what filters the list. Pinning is also the cheaper option, because the blur already exists.

### What pinning needed, and how the prototype does it

- **Under the column's top bar:** the controls sit `model.topBarHeight` down, so a taller bar (being tried in another session) moves them with it. The list's top inset is the bar plus the controls and chips, as measured, not counting the suggestions. So suggestions float over the list without moving it, and adding a chip pushes the list down only while it's at the top.
- **Chips** (`FilterChips`): one per term, with its whole name (`Format: Book`, `Topics: Planning`, `Without read`, `Format: not Podcast`, `Edited this month`). They wrap onto more lines rather than shortening. Only Unread shows as an "Unread" chip whose × turns it off, still kept per place. Clicking a chip's name offers Leave Out or Include, and Remove. Its × removes it. "Clear" follows when there are two or more.
- **The field** holds only the typed text at the top. Its ⓧ clears the text; at the foot it still clears everything.
- **Keys, unchanged:** arrows move through suggestions, Return picks one or turns a typed term into a chip and opens the top note, Backspace in an empty field removes the last chip, and Escape hides suggestions, then clears.
- **Menus** (filter, sort, a chip's) open downward at the top.
- **The count** ("4,000 notes") is still the list's first row, so it scrolls away, and it still counts the place, not what the filter leaves (as before). With chips at the top, "357 of 4,000" belongs in the chips row or beside the title. Not done.
- **Date labels** don't stick (no floating group rows), so nothing clashes with the pinned bar. If they ever stick, they'd need to stick below the inset.
- **One column** keeps the field at the foot; the top is for two columns only. `-filterAtTop NO` puts the two-column controls back at the foot, to compare.

### Tried

- The debug build on the 10,000-note vault's Media folder (4,000 notes). Pictures (before and after with three terms, suggestions open, scrolled with four chips) are in the side-session notes folder, `filter-at-top/`, outside the repo.
- A new debug hook, `-PointFilterKeys "focus|text:topics:pla|down|return|backspace|escape|scroll|unread"`, steps through the field inside the app and traces the tokens, the text, the suggestions and how long each step held the main thread. The same steps, top and foot, give the same tokens and text after every step.
- Not tried by hand: clicking a chip's name or its ×, the menus opened downward, the field's ⓧ, and dark mode.

### Timings (10,000-note vault, Media's 4,000 notes)

These were measured with `-PointFilterKeys`, from each change to the run loop coming round twice. That covers the change, SwiftUI's update and the table's reload. The build was optimized (`-O`, whole module) with the debug hooks in. Each figure is the median of three runs, in ms:

| Step | Top | Foot |
|---|---|---|
| Typing `i`, `it`, `ite` (title words) | 97, 48, 47 | 96, 48, 46 |
| `topics:pla` (suggestions show) | 37 | 42 |
| ↓ (highlight a suggestion) | 9 | 14 |
| Return (pick: a chip) | 88 | 102 |
| `format:Book`, then Return (a typed term as a chip) | 73, 125 | 76, 116 |
| `@thismonth ` (a chip at the space) | 126 | 131 |
| Backspace (remove the last chip) | 72 to 89 | 83 to 95 |
| Escape (clear) | 121 | 117 |

**Moving the controls adds nothing measurable:** top and foot are within a few ms of each other at every step. The unoptimized debug build is about 1.6 times slower, and again the same for both.

**But both are slow:** 40 to 130 ms for each change to the filter on 4,000 notes is perceptible. That was so before this change; earlier measurements (13 to 17 ms) timed building the rows alone, not the redraw. Worth its own look: what takes the time between the rows and the screen (SwiftUI's update of `NoteList`, the table's reload and row heights, the index's answer arriving as a second update).


### Mike's answer, and what changed (19 November 2026)

Pinned, but not always showing. A filter button (`line.3.horizontal.decrease`) beside the sidebar button opens the tools, sliding down, and closes them, sliding up. Closed, the filters stay, described by chips that scroll with the list.

**Built:**
- **The button** is in the column's top bar, just left of the sidebar button, in every place but the trash. It's shaded while the tools show, and blue while anything filters the list, so it shows even with the tools away and the summary scrolled off.
- **The menu beside the field** now has its own symbol, `list.bullet.badge.ellipsis` (in two columns), as the funnel lines are the bar's.
- **Opening** slides the field, menu and sort down from under the bar, clipped at its foot so they don't pass over the name. The field takes the keyboard. The list moves down with them on the same curve and time (0.25 s, ease in and out): its top inset is stepped each frame by a display link, as neither AppKit nor SwiftUI animates an inset.
- **Closing** slides them back up. The filters stay. While anything filters, a row of chips sits under the count at the top of the list and scrolls with it (`SidebarRow.filters`): Unread, each term, and any words typed (in quotes). They're a description only. Clicking the row opens the tools, where chips have their ×.
- **⇧⌘F** opens the tools, if they're away, and puts the cursor in the field. **Escape** hides the suggestions, then clears the filter, then, with nothing left to clear, closes the tools.
- **Clear:** "Clear" has gone from the end of the chips, where it often took a line of its own. The field's ⓧ clears everything, Only Unread included, as the foot's did.
- **Where it's kept:** the tools' state is its own small object (`VaultModel.filterTools`), watched by the notes column and its bar alone, so opening them doesn't redraw the rest of the window. They start closed in each window.

**Making it quick.** The first version took 50 to 240 ms to open or close on the 10,000-note vault, with the slide stalling for up to 250 ms. A sample showed the time going on working out the list, not on the tools:
- `VaultStore.notes(in:)` went through all 10,000 notes, about 15 ms, three times for each redraw of the column (the rows, the count, whether it's empty). It's now kept per place until the notes or their tags change (`listVersion`), for the top level, folders and tags.
- In `sidebarRows` and `unreadCount`, `selection` and `listLooks` were read once per note. Each read of a published property costs, so they're now read once per call.
- The "No matches" message built the rows again just to see if any were left; the table now says so when that changes (`onHasItems`).
- Adding or removing the chips row reloaded all 4,000 rows; now it's that one row (`filtersRowChange`).

**Timings after** (optimized build, Media's 4,000 notes, median of three runs, in ms):

| Step | Before these fixes | After |
|---|---|---|
| Open or close the tools | 50 to 240 | 16 to 56 |
| Longest gap between frames in a slide | up to 250 | 9 to 17 closing, 30 to 50 opening |
| Typing `i`, then `it` | 96, 48 | 48, 27 |
| A typed term becoming a chip (Return) | 116 | 84 |
| Escape clearing | 117 | 79 |

The fixes help everywhere, not just the tools. But 25 to 85 ms per change is still perceptible. What's left: the table reloading its visible rows on every update, SwiftUI redrawing the window whenever a published property of the model changes (the filter text is one), and the index's answer arriving as a second update. Opening still drops two or three frames as the field appears and takes focus.

**Tried:** the debug-hook walk-through (`-PointFilterKeys` with `tools`, `focus`, keys, `scroll`, `unread`): open, chips, Backspace, close with the summary, scroll, reopen, ⇧⌘F, Escape twice, and "No matches" open and closed. Pictures are in `filter-at-top/` (5 to 9).

**Not tried by hand:** clicking the bar button, the summary row and a chip's ×; the slide as seen (only frame times); dark mode; one column, which keeps its field at the foot and has no button.

### Quicker still (20 November 2026, uncommitted, on top of the above)

A second pass at the per-change times, aiming at one frame (16 ms). What changed:
- **The filter is no longer published by the model.** The typed text and the tokens live in `FilterToolsState` with the tools' visibility; `noteFilter` and `filterTokens` on the model just pass through. Only the notes column, its bar, the field, the chips and the filter menu watch it. Before, every keystroke redrew everything watching the model, including the folder tree, whose rows each counted their notes.
- **Rows find their note by ID.** Each note row looked itself up by going through all 10,000 notes (`model.notes.first`), every time it drew. `bookmarkedNotes` built a 10,000-entry dictionary each call (the tree asks it for the Bookmarks count); it uses `notesByID` now.
- **No reload when nothing a row is handed has changed.** With the same rows, the table only remakes them if folding changed, or the two rows coming on and off the highlight. Each row watches the model, so it redraws itself for anything else.
- **Heights worked out once.** Every row's height was worked out twice per reload (once for the table, once to keep), each time building the row's second line just to see if there was one, and reading half a dozen published settings per row. Now they're measured once, before the table asks, from settings read once, and kept per note until something they come from changes.
- **An index answer no longer counts as the notes changing.** It bumped `listVersion`, which threw away every folder's notes and every height. It bumps a new `queryVersion` instead, which what's kept from answers (the filter's matches, whether a place tracks reading) watches.

**Timings** (optimized build, Media's 4,000 notes, `-PointFilterKeys "tools|text:i|text:it|text:topics:pla|down|return|text:format:Book|return|backspace|escape|tools"`, screen on, both builds run the same way, median of three runs, in ms):

| Step | Before | After |
|---|---|---|
| Open the tools | 48 | 15 |
| Type `i`, then `it` | 58, 27 | 13, 8 |
| Type `topics:pla` | 25 | 16 |
| ↓ to the suggestion | 4 | 4 |
| Return (a chip) | 49 | 17 |
| Type `format:Book` | 46 | 15 |
| Return (a second chip) | 68 | 23 |
| Backspace (removes it) | 47 | 11 |
| Escape (clears, closes) | 89 | 61 |
| Close the tools | 57 | 20 |

The slides themselves barely changed. The first opening still stalls for 210 to 340 ms in one gap (it did before too, 225 to 417), as the tools' views are made for the first time. Later slides have their longest gap at 9 to 34 ms (before, 9 to 57).

Typing and most steps now take a frame or so. Escape, the second chip and closing don't yet, and the first opening stalls. What's left is the cost of changing which notes show. AppKit makes the visible rows again, about 18 SwiftUI hosting views at roughly half a millisecond each (about 10 ms). The rows are worked out again (2 to 5 ms). Escape also measures 4,000 heights again (about 10 ms) when the tags arrived after they were last measured. Getting these under a frame would mean drawing note rows in AppKit rather than SwiftUI, or reusing the row views for notes still showing. That's a bigger change.

**Same behaviour:** the walk-through above, and a longer one (Only Unread on and off, the tools closed with chips, arrows up and down, Backspace twice, Escape three times) give the same tokens, text, suggestions, Only Unread and selection at every step as before. `-PointFilters` with eight filters (words, a term, a term and words, `is:unread`, a left-out term, `@thisweek`, `has:`, no match) lists the same notes.

**Not tried by hand:** looking at it on screen (only timed), sort, one column.

### Questions for Mike

1. Should the tools stay open per window, or for each place, as Only Unread is kept?
2. Should the chips in the scrolling summary each have their × too? That would need a click on a part of a table row, which takes some care.
3. Where should the count go now: as "357 of 4,000" in the summary, beside the title, or stay as the first row? It still counts the place, not what's left.
4. Should one column move to the top too, or keep its field at the foot?
