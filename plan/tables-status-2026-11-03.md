# Tables: where things stand (3 November 2026)

Part of [the plan](../PLAN.md). Written after the second round of table work went wrong: columns jump while typing, and notes have started jumping when a list item is added.

# Update: the table is now a view

Mike chose option 2. It's built, uncommitted, on top of the Markdown work:

- **The Markdown is hidden, and room is made for the grid.** `MarkdownStyler.layOutTable` marks the table's text as a `.table` block, which the layout manager hides. Its first line is as tall as the grid, and the rest are slivers. Each cell is measured at its column's width by `TableCellMeasurer`, which uses the same layout manager as the cell views. The geometry goes in `TableDecoration`: column edges and widths, row heights, and alignments.
- **The grid view** (`TableGridView.swift`) sits over that room. It draws the border, the lines and the header shading, and holds a `TableCellView` text view for each cell. `MarkdownTextView+TableGrid` keeps the grids in step after every edit and layout change.
- **The note stays the only copy.** What's typed in a cell is typed into the note at the same place, through the editor's `insertText`, which escapes pipes. The cell then takes its text and formatting from the note. Undo is the note's.
- **The note's selection follows the cell's cursor,** so Tab, Return, the menu commands and tidying work as they did. A selection arriving in a table's hidden text (an arrow key, undo, Find) goes on into the cell it lands in. Up and Down enter a table at its first or last row, in the column under the cursor. Arrows at a cell's edge go to the next cell, or out of the table.
- **Columns hold their widths while a table is typed in** (`heldTableWidths`). They fit the text again once the keyboard is back in the note.
- **Column widths can't be set any more.** Set widths were kept in the delimiter row's dashes, and whether dashes were widths had to be guessed, which ordinary typing broke (a trailing space, a cell growing to the dash count), so columns jumped. Mike chose to drop the feature. Columns always fit their text, held still while a table is typed in; long dashes in a file are ignored, and written out neatly when the table is next tidied.
- **The + strips, grips and dragging** use the grid's geometry. The dragged row or column is now a view above the grid.
- **Removed:** `TableTypesetter`, `TableTextContainer`, and the layout manager's table line placement, hit testing and drawing. The text container is a plain one again, so the list jump can't come back from it.

**Checked:**
- EditorKit's 163 tests and MarkdownKit's 54 tests pass.
- The Mac and iOS apps build.
- In a test copy of the app, on the scratch vault:
  - the grid draws and wraps
  - typing in a cell reaches the file, and Undo takes it back
  - Tab from the last cell adds a row
  - dragging a row's grip moves the row
  - all of these were saved to the file

**Rough edges, worked on after `30a287d`:**
- **There's always somewhere to type below a table.** Down from the last row, a click below a table that ends the note, and typing just after a table's last pipe all go to the line after the table, adding it if the table ends the note. Up from the first row does the same above a table that starts the note.
- **The cursor in a cell steps over hidden markers** such as `**`, rather than stopping inside them, and arrows at a cell's edge look past them.
- **Find doesn't take the keyboard.** A match found in a cell is shown in the cell, but the keyboard stays with the Find bar.
- **Text being composed with an input method** (marked text) isn't replaced while the cell is refreshed.
- **The grid is placed again when the header or insets change,** which had left it drawn too high.
- Checked in the test copy: Down out of a table at the end of a note, then typing; typing in a cell and one Undo taking the whole run back; the grid's placement.

**Limits that remain:**
- Spaces typed at the start of a cell are dropped. GFM trims them, so they couldn't be kept in the Markdown.
- Several cursors don't reach into cells.
- Find's yellow indicator isn't drawn over a match in a cell, since the note's text there is hidden.
- IME input is protected but hasn't been tried with a real input method.
- A real mouse click below a table is covered by a test, not tried in the app (the test tool sets the selection rather than clicking).

# In short (written before the rebuild)

Wrapped cells have been built against the grain of the text system. Each fix has passed its tests, and the real app keeps finding new ways to break. The Markdown side is solid; the layout side isn't. I recommend going back to the committed single-line tables now. For wrapping, resizing and dragging, build the table as its own view laid over the hidden Markdown, rather than patching more.

# What's committed and what isn't

- **Committed (`cc7c46d`, "improve support for tables"):** single-line rows (long cells clipped), Tab, Return and the menu commands, Insert Table, tidying when the cursor leaves a table, round-trip-safe Markdown.
- **Uncommitted, on top of that:**
  - **Markdown (MarkdownKit):** wide tables written without padding; column widths kept in the delimiter row's dashes; moving rows and columns. All tested.
  - **Editor fixes:** undo takes back the tidying along with the edit before it; a space typed at the end of a cell stays there; the header shading fills its row.
  - **Wrapping:**
    - `TableTypesetter` breaks lines at the pipes between cells.
    - `TableTextContainer` narrows lines to their column.
    - `PointLayoutManager` moves each cell's lines back up to the top of the row, makes the row as tall as its tallest cell, and has its own hit testing and drawing ranges.
  - **Hover controls:** the + strips, the row and column grips, and dragging column edges.

# What's going wrong, and why

## Columns jump while typing

Two causes, both confirmed:

1. **Widths that haven't been set follow the text, keystroke by keystroke.** Each column is as wide as its widest cell, and when the table is too wide the widest columns share what's left. So every character typed can move every edge. Nothing holds a column still while its cells are being edited.
2. **Widths that have been set get lost and come back.** Point counts the dashes as widths only if the table isn't padded and the dashes aren't what padding would have made. A trailing space (as when typing between words) looks like padding, and a cell that grows to exactly the dash count looks like padding made the dashes. Either way the widths are forgotten for that keystroke, the columns snap to fit the text, and on the next keystroke they come back.

The second is a bug in a guess that can't be made reliable from the Markdown alone. The first is how the automatic widths were designed.

## The view jumps when a list item is added

**Found, and fixed for notes without a table.** Mike checked: it happens in notes with no table, and not in the build from `main`. That pointed at the uncommitted changes that touch every note.

The cause was `TableTextContainer`. A text container subclass that places lines itself doesn't count as a plain rectangle (`isSimpleRectangularTextContainer` is false), and the layout manager then turns off non-contiguous layout, for every note. The editor depends on that: it lays out only what's on screen and finishes the rest gradually (`completeLayoutGradually`). With it off, the whole note was laid out in full and gave different heights (a test note measured 12,016pt instead of 10,661pt), and the view jumped.

The fix: the container is a plain rectangle unless the note has a table (`TableTextContainer.hasTables`, set by the text view when the note is parsed, after which the layout manager is told). A test covers it (`onlyANoteWithATableIsLaidOutInFull`). The typesetter made no difference.

Not fixed: a note *with* a wrapping table still loses non-contiguous layout, so it may still jump. Option 1 below removes the container subclass altogether.

The suspects were the uncommitted changes that touch every note, not just ones with tables:

- **`TableTypesetter`** is now the typesetter for every note. It looks for table pipes in every paragraph it lays out, and otherwise does nothing, but it replaces the system's own.
- **`PointLayoutManager` overrides hit testing and the "glyphs in this rectangle" calls.** AppKit uses those to scroll to the cursor and to choose what to lay out and draw. For text that isn't in a table they should return what the system would, but they're on the path of every scroll.
- **The line-placing hook** was rewritten so table rows could be adjusted. It now runs for every line.
- **In a note with a wrapping table,** non-contiguous layout lays out only part of the note and estimates the rest. A row's cells are laid out one after another and moved back up, and the row's height is only right once its last cell is laid out. Estimates made before then are wrong, and scrolling to the cursor uses them.

Two quick checks would narrow it down:

- **Does it happen in a note with no table?** If so, it's one of the changes that touch every note. If not, it's the wrapping table.
- **Does it happen in the committed build?** If not, it's in the uncommitted work.

## The underlying problem

The text system (TextKit 1) assumes a note's lines run down the page in order, each below the last. Cells side by side, wrapping independently, break that: a row's second cell starts back at the top. Each place that relies on the order has needed its own patch:

- hit testing
- the ranges to draw
- line breaking
- row heights
- moving between lines

The patches pass their tests. But AppKit has more paths that rely on the same order, like scrolling to the cursor, layout estimates, selection drawing, spell checking and accessibility. They fail only in the running app, which is why this has felt like whack-a-mole, and it will keep doing so.

# What's possible

1. **Single-line rows (the committed version) and the Markdown work.**
   - Keep the uncommitted Markdown (compact writing, widths in the dashes, moving rows and columns), undo pairing, the space fix and the header shading.
   - Drop wrapping and the hover controls.
   - Long cells stay clipped. They could be cut off with "…", with the whole row's Markdown shown while the cursor is in it.
   - Moving rows and columns, and setting widths, stay possible through the context menu.
   - Reliable, because every row is one line, as the text system expects.
   - **Cost:** small. Mostly deleting.
2. **The table as its own view, over hidden Markdown.**
   - The table's Markdown stays in the note, exactly as now, but is hidden and given the height of the view.
   - A grid view sits over it. Each cell is a small text view styled by the same `MarkdownStyler`.
   - Wrapping, row heights, column widths, the + buttons and dragging become ordinary view work, with no fights with text layout.
   - Each change to a cell rewrites the table's Markdown as one undoable edit, so the file stays the source of truth.
   - **Cost:** the largest. Moving the cursor into and out of the table, Find, undo grouping, several cursors, and selections that run across a table all need handling.
   - It's how editors with real tables generally work, and once done it stays done.
3. **Move the editor to TextKit 2,** which lets a paragraph be drawn as any custom layout. It would solve this properly, but it means rewriting the whole editor (hidden markers, folding, cursors, decorations).
   - **Cost:** very large, and risky for an app that's now your main notes app.
4. **Keep patching the current approach.** More of the same. Not recommended.

# Recommendation

1. **Done:** the list jump in notes without a table (see above).
2. **Next:** go to option 1, keeping the Markdown work, so tables are dependable again. The widths in the dashes stay, used only to keep columns still, so typing never moves them. Columns are worked out from the text only when the table is opened or tidied.
3. **After that, if wrapping and drag-to-rearrange still matter:** prototype option 2 in its own session. Prove the hidden Markdown, the reserved height, the grid view and one cell's edit round-tripping before building on it.
