# Lists written in a note

20 November 2026. Branch `inline-lists`.

Today a list is a note of its own, embedded elsewhere with `![[Books to read]]` (see [Beyond text](structure.md), "5. Lists"). To show a list partway through a note, the list note has to exist first. This adds the "Maybe later" from [Beyond text](structure.md): a list written right in the note, for lists that belong to that one note.

## How it reads in the file

A fenced block named `list`, holding the same choices as a list note's properties, without the `list-` prefix:

````markdown
---
type: project
---

Some notes.
More notes.

```list
from: Reading
where:
  - format is Book
  - read is not set
sort: published descending
show:
  - author
  - published
```

And still more notes.
````

- **The keys** are `from`, `tags`, `where`, `match`, `sort` and `show`, meaning what `list-from` and the rest mean in a list note. Conditions are written exactly as in `list-where`.
- **The block is YAML,** read and written as properties are, so several conditions are a YAML list, not repeated keys.
- **Why a fence, not `{{A list}}`:** `{{…}}` is already the templates' syntax (`{{title}}`, `{{date}}`), so a list in a template would be filled in as a variable. And a fence is plain Markdown: Obsidian, GitHub and any other app show it as a tidy code block, and nothing is lost.
- **The name is `list`** for now. It could clash with a vault that already uses `list` fences for something else. If that happens, it can be changed later.
- **It has no name of its own.** It's part of the note, so it isn't searched, linked or pinned as a list, and isn't in the sidebar's Lists.
- **A `links to [[X]]` condition inside the block isn't a link.** Code blocks hold no links, so the note doesn't link to X.

## How it looks

- **With Markdown hidden,** the block's lines are replaced by the list's table, drawn over the text with the same views as `![[…]]` embeds and images. No caption.
- **With Markdown showing,** the block's lines show as written, and are typed like any other text. With it hidden, the cursor skips the block, as it skips a code fence. Still to decide: whether moving the cursor into the block should show its lines, with the table coming back once they're left.
- **A block not yet closed** (its closing fence not typed yet) shows as code, its opening fence as typed (```` ```list ````), so what's typed on it can be seen. Fences are hidden only once a block is closed; this is so for every code block, not only lists (before, typing ```` ``` ```` squeezed the line to a grey sliver at once).
- **Set apart by an outline:** a rounded line around the list, its filters and its table, 12 points in at the sides and 10 at the top and bottom.
- **First 10 rows,** one line each, as embeds are. Under them, **Show all 23** unfolds the block in place to show the rest. Show fewer folds it back. Folding is remembered while the note is open, not written in the file.
- **A very long list,** unfolded, shows 50 rows, then more on request, as a list note does.
- **The room is known before it's drawn,** as with embeds: rows are one height, and the query's results are cached, so typing never waits on the index. The first time a list is asked for, before the index answers, the room is for none of its notes, so its lines don't show for a moment, and it grows when the answer comes.
- **A block that doesn't read as a list** shows as an ordinary code block, so a mistake shows as the text, not as a different list: a key that isn't one of the six, a key written twice, a line that isn't `key: value` or an item under one, or a condition or sort that doesn't read. Blank lines and `#` comments are fine.
- **An empty block is a list** of every note: the fence already says it's a list.

## How it's edited

- **On the Mac,** the list's filters show above its table, as tokens, as in a list note. Add filter, or a click on a filter, opens the same filters window. Heading clicks sort, and dragging a heading reorders the columns.
- **Every change rewrites only the block's lines,** as one undoable edit in the note's own undo, the same way a list note writes only the properties that changed.
- **Column widths** are remembered on this Mac for the note and the block's place in it, as they are for each list note.
- **Insert List** (palette, and the Format menu, under Insert Table; no shortcut until one's set): puts an empty `list` block on lines of its own after the cursor's line, with a blank line before and after, the cursor after it, and opens its filters window. The list starts as all notes, as New List does with nothing being browsed. (Planned as "New list in this note"; named to sit beside Insert Table.)
- **On the iPhone,** the block shows its list, read only, as embeds are. Show all unfolds it in place there too. Typing in the block's lines, with Markdown showing, still works.

## Not now

- **Moving a block into a list note of its own** (and leaving `![[…]]` in its place). Perhaps later.
- **Making a missing `![[…]]` into a list note.** Decided against: lists written in the note cover "a list here, not made yet".
- **Grouping,** and other ways to show a list (cards, a board), as for list notes.

## How it fits the code

- **IndexKit:** `ListDefinition` gets a second way in, from a block's text: parse it as properties (as `Frontmatter` does), map the plain keys to the `list-` ones, and reuse what's there. And a way out, writing a `ListDefinition` back as the block's YAML, as `properties` and `Frontmatter.yaml` do for list notes.
- **MarkdownKit:** already reads fences (`codeBlock(language:)`), so a `list` fence is a code block with language `list`.
- **EditorKit:** `layOutBlockEmbed` makes room above a `![[…]]` line. A `list` fence needs the same hook, keyed by the block's text rather than a target name: room where the block's lines are, the lines hidden while Markdown is hidden, and `makeBlockEmbedView` given the block's text and range. The hook could become one "block the app draws" with two cases, an embed and a fence.
- **The app (Mac):** `ListEmbed` and `ListResults` take a `ListDefinition` and a key for widths, rather than a list note's ID, and a `write` that replaces the block's lines in the editor. "Show all" unfolds rather than opening a note. `listEmbedHeight` gains a version for a definition, plus the unfolded state.
- **The filters window and tokens** write through a small "where this list lives" choice: a list note's properties, or a block in a note.
- **iPhone:** `PhoneListView` and `PhoneEmbeds` as the Mac, read only.

## Steps

1. **Reading** (built 20 November): `ListDefinition` from a block's text, with tests (keys, conditions, YAML lists, bad blocks). Writing it back, with round-trip tests that leave hand-written blocks as written where nothing changed. `ListDefinition(block:)`, `blockBody(over:)` and `block`, in IndexKit's `ListBlock.swift`; tests in `ListBlockTests`.
2. **Showing on the Mac** (built 20 November): the fence's room, the table over it, Markdown showing or hidden, first 10 then Show all unfolding in place. EditorKit's hook is now `BlockEmbed`, `.note(name)` or `.list(body:index:)`; the styler hides a closed `list` block's lines, a point high each, and makes the room above its opening fence. On the Mac, `ListBlockEmbed` (in `ListPanel.swift`) draws it, and the note's `EditorSession` keeps how far each block is unfolded. The iPhone leaves `list` blocks as code until step 4. **Tried:** EditorKit tests for the room, hidden lines, unclosed blocks, other code blocks and Markdown showing; the debug build on a test vault, folded and unfolded (`-PointUnfoldListBlock`), with a block that doesn't read and a Swift block beside it, both shown as code.
3. **Editing on the Mac** (built 20 November): the block's filters show above its table as tokens, wrapping as in a list note; the room is made for one line of them, and grows once they're drawn if they take more (the session keeps how tall). Tokens, the filters window, heading sorts and column moves all write through `EditorSession.writeListBlock`, which rewrites only the block's lines with `blockBody(over:)`, as one undoable edit ("Change List"). Rows stay a line each. Column widths are kept by note and block (`ListBlockEmbed.listID`). Insert List, in EditorKit's `MarkdownTextView+ListBlocks.swift`, with the app opening the new block's filters. **Fixed on the way:** when a drawn block's view no longer matched (a block's lines changed), the editor reused the next block's view for it, so the first list showed the second's; now a view is only reused for its own block (`blockEmbedView`, Mac and iPhone). **Tried:** EditorKit tests for finding, rewriting and undoing a block, inserting in each kind of place, and view reuse; the debug build on a test vault (`-PointEditListBlock edit|undo|insert`): the file after an edit (only the changed keys, an emptied `where` removed), after undo (as it was), and after Insert List (the filters window opens). Not yet clicked by hand.
4. **The iPhone** (built 20 November): shown read only, as embeds are (`PhoneListView`, a row a note, its columns on a line under the title), in an outline like the Mac's (`PhoneListBlockView`, in `PhoneEmbeds.swift`). Show all unfolds it in place, 50 rows at a time, and Show fewer folds it; how far is kept by the open note (`ListBlockRows`), so only the block's own view redraws. `PhoneEmbeds.listBlockHeight` makes the room, for no rows until the index answers, and a list's room is made again only when the rows it shows, or whether there are more, change (as on the Mac). Its filters are changed on the Mac. **Tried** in the Simulator (iPhone 17 Pro), on the test notes copied into its vault: folded, Show all, Show fewer; a block that doesn't read and a Swift block beside them, shown as code; the note's file unchanged.
5. **Checked:** on a copy of the vault, the file after each kind of edit (well-formed, hand-written-looking Markdown); a note with several blocks; a block in a template; typing near a long list on the real vault, for lag.
