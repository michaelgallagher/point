# Slash commands

20 November 2026. Planned, then built on the `slash-commands` branch the same day: steps 1 to 5, tried on the Mac and in the iPhone Simulator, not yet on a phone. See [Built](#built) for how it came out.

Typing `/` in a note opens a small menu at the cursor, of things to put in or do there, so markup that's awkward to type (a list, a table, a callout) never has to be typed. It came from lists written in a note: typing ```` ```list ```` by hand is fiddly, and on the iPhone the backtick is hard to reach. The Mac's Format menu and palette already do most of these; the menu brings them to where you're writing, and to the iPhone, which has no Format menu.

## How it works

- **Where `/` opens it:** at the start of a line, or after a space. Never in the middle of a word (`and/or`, `1/2`), in a link or web address, in code (inline or a block), in the properties, or in a table's cells.
- **Typing narrows it:** `/li` shows List; `/h2` shows Heading 2. Matched as the palette matches, by the start of each word and by other names (`/date` finds Today's date; `/rule` finds Divider).
- **Choosing:** Return or a click puts it in, replacing the `/` and what was typed after it. Up and down move through it.
- **Leaving it:** Escape, a space while nothing matches, or moving the cursor away closes it and leaves what was typed as text. Backspace over the `/` closes it too.
- **One undo** takes back what a command put in, back to the `/` as typed.
- **The Mac:** a small list under the cursor, like link completion's, each row with an icon and its shortcut, if it has one.
- **The iPhone:** the same list, above the keyboard, in the bar where the Undo and Redo buttons are.
- **Both at once:** the commands are the same on the Mac and the iPhone.

## What's in it

In this order, with nothing typed after the `/`:

1. **List:** puts in an empty `list` block on its own lines (as Insert List does), and opens its filters on the Mac. On the iPhone its filters open too, once [Editing lists on the iPhone](iphone-list-editing.md) is built.
2. **Table, callout** (then its type: note, tip, warning…), **code block** (then its language, or none), **divider.**
3. **Link to a note, embed a note** (the note chosen as `[[` chooses it), **image** (from Files or Photos on the iPhone, a file on the Mac).
4. **Today's date, the time; today's note, tomorrow's note** (links to the daily notes).
5. **Template** (Apply Template's list), **property, tag.**
6. **Heading 1 to 3, bulleted list, numbered list, checklist, quote:** these already have shortcuts on the Mac, so they're last there, but they matter on the iPhone.

## Fences close themselves

Return at the end of an opening fence (```` ``` ````, ```` ```swift ````, ```` ```list ````) with no closing fence below it puts the closing fence in, with the cursor on the empty line between. A ```` ```list ```` fence becomes a list at once, and on the Mac its filters open. Not when the fence is closed already further down (typing Return in a fence that's being edited), so a block is never closed twice.

## How it fits the code

- **EditorKit:** the trigger (`/` where it can open, and what's typed after it, as `wikiLinkPartialRange` finds a `[[` being typed), on the Mac and the iPhone. The commands are given by the app, as names, other names, icons and what each does; the editor shows them, narrows them and calls the one chosen with the range to replace.
- **The Mac:** the list drawn under the cursor; the commands, mostly the Format menu's selectors and the palette's actions.
- **The iPhone:** the list in the keyboard's bar.
- **Fences:** in `MarkdownEditing`'s Return handling, with tests, for both.

## Steps

1. **Fences close themselves,** with tests. Small, and useful on its own.
2. **The menu on the Mac:** trigger, narrowing, choosing, leaving; the commands that are already Format menu items or palette actions, then List.
3. **The menu on the iPhone,** the same commands.
4. **The rest:** dates, daily notes, embeds, images, templates, properties, tags.
5. **Checked:** typing `/` where it mustn't open (words, links, code, properties, tables); undo after each command; the file after each (well-formed Markdown); typing in a long note, for lag.

## Built

20 November 2026, on `slash-commands`.

- **Fences close themselves** (`MarkdownEditing.closingFence`, tested against both editors). A closed block with an empty line under its fence takes the cursor there instead, so Return after a code block's language, as the menu writes it, goes in without a second closing fence.
- **The commands** are `SlashCommand.all`, in EditorKit, shared; the trigger and the narrowing are `SlashMenu.query` and `SlashMenu.matching`. What a command writes is `MarkdownEditing.slashEdit`, tested: a block on lines of its own, with a blank line from the text around it.
- **The Mac:** the list under the `/` (above it, near the window's bottom), with icons and the shortcuts set for each. Return, Tab or a click puts one in; Escape leaves what was typed. Image asks for files; template opens Apply Template's list; property adds one in the properties; List opens its filters.
- **The iPhone:** the commands as buttons in the bar above the keyboard, in place of the tools, the first tinted, which Return puts in. Template asks which in a dialog; property opens the properties; List, from the menu or a ```` ```list ```` fence and Return, opens its filters. Image asks whether from the photo library or Files, saves what's chosen in the attachment folder as the Mac does (a photo as JPEG), and embeds it where the `/` was (21 November). With a hardware keyboard, up and down move the highlight through the bar, which scrolls to keep it in view; Return or Tab puts it in; Escape closes the menu, as on the Mac (21 November; Escape and Tab not tried, as the Simulator's tools can't press them).
- **Checked:** `/` doesn't open in words, links, web addresses, code, the properties or tables (tests); one Undo goes back to the `/` as typed, on both (a test on the Mac, by hand on the iPhone, where Undo selects what came back, as it does everywhere on iOS); the file after each command by hand; the trigger and narrowing take 0.04 ms a key in a 45 KB note.

Simpler than planned:

- **Choices are a second step:** choosing Callout or Code block writes `/callout ` or `/code block `, and the menu offers the types or languages; typing narrows them too (`/callout w`).
- **Matching** is by the start of each word and by other names, written for the menu, not the palette's fuzzy matching, which is in IndexKit, which EditorKit doesn't use.
- **Image is two steps to undo,** on both: the picker answers after the menu's own step, so one Undo takes the image out and the next brings back the `/` as typed. The saved file stays in the attachment folder.
- **Tag** writes `#`, and tag completion takes over; **date and time** are `2026-11-20` and `14:05`. `/today` offers Today's date before Today's note, in the menu's order.

## Not now

- **A list made from the notes list's filter** ("Put this list in a note": the filter at the top of the notes list written into the open note as a `list` block). A good way to make a list where you'd make one anyway; perhaps later.
- **Right-clicking an empty line** to insert things: the menu and Format menu cover it.
- **Commands of your own,** or from templates.
