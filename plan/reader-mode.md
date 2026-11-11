# Reader mode on the iPhone (11 November 2026; steps 1 to 3 built)

Part of [the plan](../PLAN.md). Builds on [the clipper](clipper.md).

**Why:** clipped articles are the notes Mike reads rather than writes, and the iPhone is where he reads them. The editor is the wrong place for that: the type is set for writing, a stray tap edits the article, and the place reached is lost when the note closes. Read-later apps (Instapaper, Matter, Readability) do this well: type set for reading, the place kept, highlights. Point should do the same, and add something they don't: notes written into the note itself, above the saved text, in plain Markdown.

## Decided

- **Media notes only, for now:** reader mode is for notes of the clip kind, the one `Clipping.kind(in:)` finds (Media in Mike's vault). Whether a note opens in reader mode is decided in one place, so it can later take a `source` property, or a setting, instead.
- **Reader mode is the default** for those notes. **Edit** switches to the editor, and **Done** switches back.
- **The marker** between your notes and the saved text is a line of its own:

  ```markdown
  ==---- Text ----==
  ```

  Mike already uses it in notes from Obsidian's Web Clipper. It's unique, it shows itself as a highlight in Point, Obsidian and most editors, and it can't be confused with a heading the article starts with. Everything between the properties and the marker is your notes. Everything after it is the saved text. Point recognises the first line that's exactly the marker (spaces around it ignored).
- **New clips write the marker.** The text selected when clipping, as a quote, and the template's own text go above it as the start of your notes. The article goes under it. A clip that got only its link has the link under the marker.
- **Old clips get the marker when it's needed.** That's the first time you add a note, a highlight or a quote, and only if the note doesn't already have the marker (notes from Obsidian's Web Clipper may already have it). It goes straight under the properties, so everything already in the note counts as saved text. That's slightly wrong for a note whose template added text of its own, but it's simple, and nothing is lost or moved.
- **Your place stays on the phone,** outside the vault, as search learning does. It isn't synced between devices.
- **The read date is a property set by hand** (`read: 2026-11-12`) for now. A button, or setting it on reaching the end, can come later.
- **The Mac shows the marker as it is,** a line with a highlight, for now.

## How it works

### Reading

- **Type:** set for reading: New York (the system serif) or the system sans, a comfortable size, about 65 characters to a line, more space between lines, hyphenation, and paragraphs spaced rather than indented.
- **A header:** the title, then the author, the site (from `source`), the date published and the reading time. The properties are hidden. Edit shows them.
- **Your notes, if any,** come first, set apart from the article (a tinted block, or smaller type), then the article. The marker isn't shown: the gap between the two does its job.
- **An Aa menu:** text size, serif or sans, and page colour (paper, sepia, night, or following the system). Kept on the phone, for every article.
- **Progress:** a thin line at the top, and how much of the article is left.
- **Built on the editor, read-only, with a reader look,** not a web view. The editor knows where every character is in the file (MarkdownKit's exact positions), so a highlight or a quote is written to the right place. A web view would make that mapping guesswork. Images, tables, quotes and code all draw as they already do in the editor.

### Your place

- Kept as the start of the paragraph at the top of the screen (its first 60 or so characters) and its position in the note. Not a scroll offset, which a change of text size, or an edit on the Mac, would break.
- On opening, Point looks for that paragraph near the position it had, and then anywhere in the note. If the text is no longer there, it uses the position alone.
- Kept for each note by its ID, and follows a note renamed or moved, as search history does. Notes not opened for a long time can be forgotten.

### Highlights

- **In the file as `==…==`,** Markdown's highlight, which Point, Obsidian and most editors already show.
- **Select text, then Highlight** in the menu. Point writes well-formed Markdown:
  - **Across paragraphs:** one highlight for each paragraph, list item or quote line.
  - **Next to or overlapping another highlight:** they become one.
  - **Partly over bold, italic or a link:** the highlight goes outside the marks, so the markers stay balanced (`==**word** and more==`, never `**wo==rd**==`).
  - **Inside code:** not offered, since Markdown can't highlight there.
- **Remove highlight** when the selection is inside one.
- Highlights are allowed only in the saved text and your notes, never in the properties or the marker.

### Your notes

- **A notes button** in reader mode opens a sheet. The sheet shows and edits only your notes: what's between the properties and the marker. It opens at half height, so the article stays readable and scrolls behind it, and it can be pulled up to full height. The keyboard comes up at the end of your notes.
- **Add to notes** in the selection menu, next to Highlight, quotes the selected text into your notes (`> …`, a new paragraph at the end) and opens the sheet with the cursor under the quote, ready for a comment. The quoted text is highlighted in the article too, so you can see what you've quoted.
- **Highlights in the sheet:** under your notes, a list of the article's highlights. Tapping one closes the sheet and scrolls to it.
- **Saving the notes splices them into the file as it is on disk at that moment:** the properties and the saved text are whatever the file holds then, not what Point read when the note opened. So a change synced from the Mac while you read is kept. It uses `NoteWriter`'s safe write and the same checks as the editor: a file changed since it was read, a file gone, and iCloud's conflict versions. If the file has changed in your notes too, your typing goes into a conflict copy, as it does in the editor.
- **Highlights and quotes are saved the same way:** each is a small edit to the file on disk, made where the text still matches. If the text has changed so that it doesn't, nothing is written and a notice says so.

## Step 1, built (11 November, branch `reader-view`)

- **Which notes:** `Reading.opensForReading` (ClipKit): the note's kind is the clip kind. A new note, or one opened while the Markdown shows, opens for writing as before.
- **The view:** the editor, not editable, set by `ReaderSettings`: New York (or the system sans) at 19 pt to start, lines at 1.5, margins of 24, headings a little smaller against the text. The title is set in the same face, with a byline under it in place of the properties and related notes buttons (`Reading.byline`: authors, the site from `source`, the date published, minutes to read).
- **The bar:** how far through, and the minutes left, in the middle; **Aa** (size, serif or sans, Automatic, Paper, Sepia or Night) and **Edit** at the right. Edit gives the usual editor, with the cursor at the top of what was showing; **Done** saves and goes back to reading there. Changing the size or face keeps the same line at the top.
- **Your place:** `Reading.Place` (the paragraph at the top of the screen, its first 60 characters and where it was), kept once scrolling stops, on leaving and on going to the background, in `Reading/places.json` in the app's own storage (`ReadingPlaces`, at most 500 notes, following renames and moves, dropped with deleted notes).
- **Tried:** `ReadingTests` (9: which notes, minutes, bylines, places found again after an edit above, gone, repeated, or only mid-line). In the Simulator, on a 3,500-word Media note: it opens for reading with its byline; scrolling, leaving and coming back returns to the same paragraph; size, Sepia and Night; size changes keep the top line; Edit and Done; a meeting note still opens for writing; the file unchanged throughout.
- **Not tried:** a real iPhone, the real vault's clips (images, tables, very long ones), VoiceOver, and the Simulator's first tap in the Aa menu sometimes went to closing it.

## Step 2, built (11 November, branch `reader-notes`)

- **The marker and your notes** (`ReaderNotes`, ClipKit): the marker's line (the first line that's exactly the marker, after the properties), your notes (between the two, without the blank lines around them), and `settingNotes`, which puts new notes in and leaves the rest of the file exactly as it was: a blank line between your notes and the marker, none above an empty set of notes, and for a note without the marker, the marker straight under the properties.
- **New clips write the marker** (`ClipNote`, both apps): the selected text as a quote, the template's own text, the marker, then the article (or its link). A template that has the marker itself keeps it, and the article follows.
- **Reading:** the marker is drawn as a plain rule across the page (`EditorTheme.dividerLine`), your notes above it. Editing, it's the highlighted line, as on the Mac.
- **Your notes:** a notes button beside Aa opens a sheet with only your notes, in the usual editor with the format bar, the cursor at the end. It opens at half height over the article, which still scrolls; with the keyboard up it takes the screen. Saved a second after typing stops and when the sheet closes: read from disk, your notes spliced in, written with `NoteWriter`, then the reader shows the file as it is now, the same paragraph at the top. Nothing typed, nothing written, so opening the sheet on an old clip adds no marker.
- **Changed elsewhere:** a change outside your notes, made while the sheet is open, is kept, and yours spliced in around it. A change to your notes themselves sends yours to a conflict copy, with the usual notice, and reading carries on in the copy. A change synced while reading (no sheet) is shown in place, the same paragraph at the top.
- **Tried:** `ReaderNotesTests` (9) and the clip tests changed for the marker (4, one new). In the Simulator, on an old clip without the marker: typing a note added it under the properties, the properties and article byte for byte unchanged; the article changed from outside while typing, both kept, no copy; the notes changed from outside, a conflict copy with mine and the original with the other. Notes then rule then article in reader mode.
- **Not tried:** a real iPhone, a clip made on the phone or the Mac since (only the tests), the Mac with the marker in a real clip.
- **Decided on the way:** your notes are set off by the rule alone for now, not tinted; easy to change once tried.

## Step 3, built (11 November, branch `reader-highlights`)

- **Highlighting** (`MarkdownEditing+Highlights`, EditorKit): the selection becomes one `==…==` to each line it covers, inside the line's own markers (`> `, `- `, `- [ ] `, `## `), spaces at its edges left out. It takes in whole any bold, italic, link or code it only partly covers, so markers stay paired, and joins any highlight it overlaps or touches (only spaces between). Code blocks, tables, the properties and the marker are left alone.
- **The edit menu while reading:** select text and the menu starts with Highlight, Remove highlight (when the selection touches one; it takes off every one it touches) and Add to notes (from the saved text only), then the system's Copy and the rest. The format bar is gone while reading.
- **Add to notes:** the selection as Markdown that stands on its own (the same widening, highlight markers left out, paragraphs a blank line apart) goes at the end of your notes as a quote, and is highlighted in the article, in one write. The sheet opens with the cursor on a new line under the quote; if it's open already, the quote appears in it.
- **The highlights list:** a highlighter button in the notes sheet lists the article's highlights in order; choosing one closes the sheet and puts its paragraph at the top.
- **Saving:** each change is made to the file read from disk just then. If that's not what's showing (changed on another device), the reader shows the file as it is now, writes nothing, and says so: a selection made in the old text might not be the same words.
- **Tried:** `HighlightingTests` (12). In the Simulator: a word highlighted; a selection half in bold made `==**everything**==` and the quote `> **everything**`; the list and going to a highlight; Remove highlight; the file changed from outside before Remove highlight, which then wrote nothing and showed the notice, and worked once tried again; a comment typed under a quote. The file stayed well-formed throughout, the rest byte for byte.
- **Not tried:** a real iPhone, a selection across paragraphs in the app (only the tests), VoiceOver.

## After step 3 (11 November, branch `reader-polish`)

- **The bars get out of the way:** reading, a little scroll on by hand hides the top and bottom bars and the status bar; a little scroll back, a tap on the text (not a link), or reaching the top or the end brings them back. Measured by the finger, not the scroll offset, which jumps as the bars go.
- **Your notes moved to the bottom,** sharing the action menu's glass, so the top has only progress, Aa and Edit.
- **Lines closer:** 1.4 rather than 1.5 by default.
- **Line spacing and margins in Aa:** line spacing 1.2 to 1.8 in tenths, margins 12 to 48 points in sixes (24 by default). Settings kept before these came in still read, with these as standard.

## The steps

1. **The reader view:** the type, the header, the Aa menu, progress, your place, and Edit and Done. It never writes to the file, so it can be used on the real vault straight away.
2. **The marker and your notes:** new clips write the marker (both apps, in `ClipNote`). The notes sheet, saving by splicing, and the marker added to old clips.
3. **Highlights and Add to notes,** and the list of highlights in the sheet.
4. **The Mac,** later and only if wanted: reader mode there too. Until then it shows the marker as highlighted text.

Each step has tests in the packages: finding the marker, splicing your notes into a changed file, highlights across paragraphs and marks, quoting, and finding your place again after an edit. Steps 2 and 3 write to the vault, so they also go through the safety checks in [The iPhone on the real vault](iphone-real-vault.md) on a copy before the real vault.

## Open

- **Your notes in reader mode:** a tinted block or smaller type? Decide on the phone.
- **Old Web Clipper notes** may have notes of yours above the marker already. They'll show as your notes, which is right.
- **Search and related notes** treat the whole note alike. Your notes could later count for more than the article.
- **Later:** a read date set by a button or on reaching the end, a list of what's unread, and reader mode for notes beyond Media.
