# Optional: tabs kept alive

*5 November 2026. Not scheduled: an option for later, if switching tabs feels slow again.*

## Why

Point should never have any noticeable lag. On 5 November, switching tabs took a noticeable 200–300ms on the real vault. Most of it was the sidebar: it found each row's note by going through the whole list and measured every title again at each update, and a switch of tab updates it. That's fixed. With 3,200 notes, a switch went from 2 seconds to about 130ms, and now feels much better.

What's left doesn't depend on the vault: 65–370ms per switch even in a vault of ten notes. Notes with tables are the slowest. It's the cost of building the note's editor from scratch each time its tab is shown:

- a new `MarkdownTextView`, its text loaded, styled and laid out
- a table cell view (each its own text view) for every cell of every table
- a new SwiftUI header: the path, the title and the properties strip, with its text fields, date pickers and menus as AppKit views
- the header measured before the text shows, since the text is hidden until the header's height is known

Small fixes can't take this away. Not building it again can.

## The idea

Each tab's editor is built once and kept while the tab is open. Showing a tab only shows its editor and hides the others. Switching back to a tab is then a matter of a frame, not of building a page.

In `PaneView`, all of the pane's tabs would be laid out on top of each other instead of only the current tab's `NoteEditor`. The current one shows; the rest are hidden, and take no clicks, no keys and no accessibility focus. An editor goes when its tab closes.

## What it would mean dealing with

- **Notifications to the window.** Some commands reach the editor through a notification for the whole window. For example, Add property is posted with the window's model as its object, so every properties strip that hears it would act on it. Each would need to act only when its editor is the one showing, or be sent to that editor alone.
- **Which editor commands act on.** The model and the menus assume one editor per pane: the last one attached. The current tab's editor would need to be the one they reach, and to become it again on being shown.
- **Focus.** Building an editor is what puts the cursor in it now. Shown again, it would need to take focus and get back its selection and scroll position, and a hidden one must never keep focus.
- **Saving.** A note is saved for good when it's closed, and today switching tabs counts as closing it. A hidden editor would keep its edits until its timer saves them, so closing the tab, closing the window and quitting must still save them.
- **Changes from outside.** A hidden note changed in Obsidian (or synced) must be up to date when shown, without a flash.
- **Memory.** One editor for each open tab. That's fine for a handful of tabs, but many long notes with tables would add up. If needed, only the most recent few could be kept.

## How we'd know it worked

The debug hook `-PointTabTiming "a.md,b.md,c.md,d.md"` (in `Apps/Mac/DebugSnapshots.swift`) opens notes in tabs, goes from tab to tab, and traces how long each switch keeps the app busy and how long until the note shows. It should be run on an optimised build, with a large vault and notes with tables. The aim is well under a frame's worth of work for a tab already open.
