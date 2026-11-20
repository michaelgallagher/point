# Slash commands

20 November 2026. Planned; to be built after steps 4 and 5 of [Lists written in a note](inline-lists.md), on a branch of its own.

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

1. **List:** puts in an empty `list` block on its own lines (as Insert List does), and opens its filters on the Mac. On the iPhone, which can't edit a list yet, the list starts as every note, changed later on the Mac.
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

## Not now

- **A list made from the notes list's filter** ("Put this list in a note": the filter at the top of the notes list written into the open note as a `list` block). A good way to make a list where you'd make one anyway; perhaps later.
- **Right-clicking an empty line** to insert things: the menu and Format menu cover it.
- **Commands of your own,** or from templates.
