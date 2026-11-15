# Exploration: a flatter header (branch `header-redesign`)

Part of [the plan](../PLAN.md).

**The question** (Mike, 13 November 2026). Liquid Glass doesn't make Point look better, and tabs work badly in narrow windows. Can the header stay native (translucent, the system's window buttons and title bar) while departing from the stock macOS 26 look?

**What changed (base of the experiment, 13 November 2026):**
1. **No glass on the bar's buttons.** Sidebar, home, back and forward, and the note's "…" menu are the symbol alone (28-point square, 15-point symbol in the secondary colour), shaded with a rounded square on hover (`BarIconFace`, `BarIcon`). The see-through bar and the blur of the note scrolling under it stay.
2. **The compact title bar.** The window's empty toolbar is `.unifiedCompact` instead of `.unified`, so the bar is about 40 points rather than 52. The bar's height is still measured from the window buttons.
3. **Tabs shaped like a selected sidebar row.** The rail is the same grey as before but 32 points tall (a medium sidebar row's selection, measured from the window) with 8-point continuous corners rather than a capsule; the current tab inside it is 28 points with 6-point corners, plain white (no glass), a hairline edge and a faint shadow.
4. **The path moves into the header.** With one tab, the title bar's row holds back and forward, then the path ("Projects / Archive / Review music"), then "…" at the far right. With more than one tab, the tabs take the title bar's row across the side's whole width, and the path row sits below them (36 points), pushing the note down. The page loses its path above the title.
5. **The path** is the one from the no-visible-tabs exploration (`PanePath`): folders dimmed and clickable (they open in the sidebar or the explorer), the note's name in medium weight, clickable to rename; folders fold into "…" when there's no room, then the name is cut in its middle.

**Checked:** in pictures of the debug build (test vault): one tab and several, sidebar shown and hidden, a split, a 420-point window.

**Not checked yet:** macOS before 26 (the bar keeps its own background there); dragging tabs onto the new path row; the swipe area (it still excludes only the title bar's row).

**Open questions:**
- Is 40 points too tight? The rail leaves 4 points above and below.
- Should the path row show even with one tab, so the header never changes height when a second tab opens?

## Second try: tabs below the bar (branch `header-tabs-below`, 14 November 2026)

Mike found tabs above the other controls too jarring. Built on `header-redesign`:
1. **The title bar's row:** back and forward on the left; on the right, a split button (`rectangle.split.2x1`, or `rectangle` to close the split, which keeps both sides' notes as tabs) beside the "…" menu. Split and Close Split left the menu. No title or path in the bar.
2. **Tabs, when there's more than one,** in a 38-point row of their own below that row, from the side's leading edge (not pushed past the window buttons), with the same row-shaped rail.
3. **The path is back above the note's title,** as on `main` (`NotePath` in `NoteEditor.swift`); the bar's `PanePath` is gone.

**Checked:** in the debug build, one tab and three, with the sidebar shown. Not yet: the sidebar hidden, a split, narrow windows by hand.

## Third try: compact tabs in the top row (branch `header-compact-tabs`, 14 November 2026)

Built on `header-tabs-below`:
1. **Tabs back in the title bar's row,** between back and forward and the "…" menu, in the row-shaped rail. The path stays above the note's title.
2. **Split goes back into the "…" menu** (Split, or Close Split); no separate button.
3. **Tighter buttons:** 2 points between bar icons (was 8; the icons' own 28-point squares give the room), 6 points from a bar's ends to the sidebar's edge, the divider or the window's edge (was 8), and the sidebar button 10 points past the zoom button (was 16).
4. **Tighter tabs:** each tab's close button always shows, at its leading edge (tertiary, secondary on hover), the title follows it closely (22 points for the close button), and only 10 points after the title (was 20 either side). Tabs can narrow to 64 points (was 84) before the row scrolls.

**Checked:** in the debug build, three tabs in a 420-point note side with the sidebar shown. Not yet: the sidebar hidden, a split.

Later on this branch: the roomier standard title bar (`.unified`) is back, in place of the compact one.

## Fourth try: tabs in narrow windows (branch `header-narrow-tabs`, 14 November 2026)

Mike works in narrow windows (420–500 points) a lot, and three or more tabs barely fit there: at 440 points with the sidebar hidden, the tabs had about 230 points, so three tabs showed six or seven characters each and a fourth didn't fit. Built on `header-compact-tabs`, the tabs now give way in stages (`TabLayout` in `TopBars.swift`), each tried only when the one before doesn't fit:
1. **Whole titles,** as before.
2. **Shared room.** The tabs share the room, the widest cut first, while every tab shows about ten characters (96 points).
3. **Compact.** The current tab keeps a readable width (80–150 points, or its title's, if less); the others share the rest, down to 70 points: the close button and about five letters. Every tab keeps its close button. (Hiding the others' until hovered was tried and felt odd; showing them cost the current tab 20 points of its narrowest, as its whole title is on its page just below anyway.)
4. **Overflow.** Tabs that still don't fit go into a menu at the end of the row: a double chevron and how many ("›› 3"). The current tab is always shown, with the others in order up to as many as fit; choosing a hidden tab makes it current, so it comes into the row and the last of the others goes into the menu. The row no longer scrolls.

Then each tab's title is fitted to its width (`TabLabels.fit`): a title that fits is shown whole; one that doesn't has its dates shortened ("30 Oct" for "2026-10-30") and is cut at its end, unless what's left would look like another tab's (one's start is the other's whole), when the leading words it shares with that tab go: "Weeknote - 2026-11-09" and "Weeknote - 2026-11-02" show as "9 Nov" and "2 Nov" rather than "Week…" twice. Titles that already look different where they're cut, like "The plan" and "The list of things", are only cut at their ends. The tooltip has the whole title.

The first version shortened titles by the open tabs alone, whatever their widths, and gave odd results: any shared first word went ("The plan" as "…plan", "Meeting notes" as "…notes", "Project (post)" as "…(post)"); every tab was shortened once any was short of room, even those with room for their whole title; a shortened title that still didn't fit got "…" at both ends; the current tab kept its shared words, so a tab's text and width jumped as it was clicked; and titles ending in a number were cut from the middle ("R…47"). A leading "…" on stripped titles also went: it showed on some tabs and not others, as the rest fitted or didn't.

**Smaller fixes:** back and forward are 22 points wide each (not 28) in a bar narrower than 520 points, as the thin chevrons looked far apart; the sidebar button's symbol is 17 points (the others 15), as it read small beside the window buttons once it lost its glass circle; the "…" menu sits as far from the side's edge as from the top (12 points, was 6), so its hover square is even in the corner; and Split (or Close Split) is last in that menu, after Delete File.

**Either side of the divider:** the sidebar button's symbol and the back arrow are both 16 points from the divider (`TopBar.dividerGap`), measured from the symbols rather than their squares, as the sidebar symbol nearly fills its square and the chevron is thin in the middle of its own: the sidebar button's square is 12 points in from the sidebar's edge (was 6), and back's 6 points (9 in a narrow bar) past the divider. **The filter at the list's foot** lost its glass: a flat field shaped like the tabs' rail (32 points, 8-point corners, a faint grey fill), below the list rather than floating over it, and in two columns the sort button beside it is a plain bar icon, as in the top bars.

**An experiment behind a switch:** `-PointNarrowHidesHistory YES` (or `defaults write org.mikegallagher.point PointNarrowHidesHistory -bool YES`). In a side's bar narrower than 520 points with three or more tabs, back and forward move to the top of the "…" menu (⌘[ and ⌘] still work), giving their 58 points to the tabs. At 440 and 500 points that shows one more tab.

What shows, with the sidebar hidden and five or more tabs open:

| Window | Back and forward shown | Hidden |
|---|---|---|
| 440 | current + 1, the rest in the menu | current + 2 |
| 500 | current + 2 | current + 2, wider |
| 600 | all five | all five |

**Checked:** pictures of the debug build at 440, 500, 600 and 700 points with 3–6 tabs, with and without the switch (the table from the final tuning). Not yet: the overflow menu by hand, dragging tabs while some are hidden, a split, macOS before 26.

**Open questions:**
- Is "about five letters" enough to recognise an inactive tab, or should the row show fewer, longer tabs?
- Should the overflow menu list every tab (with the current one ticked), as a tab list, rather than only the hidden ones?
- Is hiding back and forward worth it? They're the biggest fixed cost in the bar.
