# Reader mode on the iPhone (11 November 2026; designed, not started)

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
