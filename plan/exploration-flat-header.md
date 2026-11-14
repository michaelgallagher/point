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
