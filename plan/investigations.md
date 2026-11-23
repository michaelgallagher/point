# Investigations and open questions

Part of [the plan](../PLAN.md).

# Topics for investigation

## Daily notes as a meeting log
Today, each meeting gets its own note, because finding things inside daily notes in Obsidian is hard. The goal is one note per day holding all that day's meetings (for example seven), which only works if any one meeting's minutes are easy to find later. To investigate:

- **Search that knows about sections:** results that point to the heading a match is under, and open the note scrolled to that heading.
- **Section links:** linking to one meeting, as in `[[2026-10-18#Team sync]]`, with backlinks shown per section.
- **A meetings view:** every meeting heading across all daily notes as one list, filterable by person, tag or date. This could come straight from the search index.
- **Marking a meeting:** decide how a section counts as a meeting. Options are a heading level, a `#meeting` tag under the heading, or a template.
- **Quick entry:** a "New Meeting" command that adds a meeting section to today's note from a template, including the time.

- **Auto-hide the list in narrow windows:** shrinking a window below a set width hides the note list (filed 18 October 2026, not started).

## Bug: the Mac app doesn't work in full screen (filed 7 November 2026)
Found by Mike while writing a blog post. Blog writing usually happens in full screen, so this matters. Not started.

- The top bar is moved to the bottom of the screen.
- The note can't be scrolled.
- The sidebar doesn't work at all.

Full screen has never been tested: the 25 October app review couldn't enter it from a debug hook, and the sidebar plan lists it under "not yet tried". Check it alongside focus mode, the split view and a second display.

## Bug: thin lines below the text when a lot is selected (filed 23 November 2026)
Seen by Mike in a long note in a split, probably selected by dragging down to the end: faint 1px lines of the selection colour, one line height apart, from the end of the text down the empty space, exactly as wide as the selection. Mike says it was there before the room past the end of the note. Not fixed, because it hasn't been reproduced.

- **What the lines are:** partly covered pixel rows, like the antialiased edge of a selection fill. They're not drawn whole. The last line's highlight in Mike's picture also steps by a pixel partway along, so parts of the selection were drawn at different times with slightly different heights. That suggests pixels left over from an earlier drawing, not something drawn now.
- **Clean everywhere tried:** offscreen drawing, whole and in fractional strips, with endings of blank lines, spaces, tabs, non-breaking spaces and `--`. In a test copy in the background: Select All, then jumping to the end, wheel steps, trackpad-style steps, or scrolling in fractional, line-sized steps into the room past the end. The same for a drag selection driven as AppKit's tracking does (growing with "still selecting", autoscrolling) down past the end, and fractional-strip redraws of the empty space. Each time the layer's own pixels were checked, stale ones included (`CALayer.render`, not a fresh drawing). Logging the layout manager's selection fills showed one correct rect, clipped to the area being drawn.
- **Not tried properly:** an active window with the blue selection, with real mouse or trackpad input. Posted mouse events don't work, because AppKit's drag loop checks the real button, and the window couldn't be captured during the runs in front.
- **Leads:** the editor draws into one `ContentLayer` the size of the visible area, which AppKit shifts as it scrolls; with line heights in fractions of a point, a shift might leave partial rows. Writing Tools' badge shows beside large selections and lays out views per line. Next: does the line pattern survive scrolling it away and back, or resizing the window? If it does, it's being drawn and the note's content matters; if not, it's stale pixels. Try it on the note itself.

# Open questions

1. **Templater:** do you use the Templater community plugin (`<% %>` syntax), or only Obsidian's core Templates? Templater scripts can't be run outside Obsidian. We'd preserve them, but they wouldn't expand.
2. **Focus mode icons:** which icons stay visible besides the note-list button.
(Questions 3–7, about the sidebar, were answered in October 2026; see "Sidebar navigation".)
(Questions 8 and 9, about tabs and pins in the two-column view, were answered on 18 October 2026; see Part E.)
