# Sliding tabs

Part of [the plan](../PLAN.md). An experiment on branch `sliding-tabs`, from `main` (17 November 2026), after a screen recording of Ghostty's tabs (AppKit's own window tabs on macOS 26) in a narrow window.

**Parked** (17 November 2026). Mike tried it and found some UI issues, but more to the point doesn't think the approach has a future for Point. Kept on its branch, not merged.

## What Ghostty does

- The tabs share the bar at one width, down to a minimum.
- Past that, the row slides. The tabs beyond each end fold into a stack there: a few slivers, a separator line each, like the edge of a deck of cards. The tab next to the stack peeks out, cut off.
- The current tab is always whole. Choosing another slides the row just far enough to show it, not to centre it.
- Hover shows a tab's × at its leading edge, as on `main`.

Mike's calls (17 November): tabs of **one width**; the **"›› N" menu kept** for the very narrowest bars; **no ⌘-numbers** on tabs; **scrolling over the row slides it**.

## What's built

`PaneTabs` and `SlidingTabLayout` in `Apps/Mac/TopBars.swift`:

- **One width:** as wide as the longest title needs, up to 240 points; with less room, the tabs share it down to 120 points (padding and about ten letters). While they fit, the capsule is only as wide as the tabs, so the rest of the bar still moves the window.
- **Sliding:** narrower than that, the tabs stay at 120 points and the row fills the bar and slides. Each end holds a stack of up to three 6-point slivers; tabs further out lie under them. Tabs nearer the middle lie on top, so the tab next to a stack peeks out as far as its neighbour leaves.
- **Choosing a tab** (a click, a sliver, a shortcut, a new tab) slides the row, over 0.2 seconds, just far enough to show it whole, clear of both stacks. So does a change in the window's width, at once.
- **Scrolling** over the row, sideways with two fingers or up and down with a wheel, slides it (`RowScrollArea`, a local event monitor).
- **Slivers:** each tab is drawn whole but masked to what shows; its mouse area and drop target cover only that, so a sliver takes clicks for its own tab. Only a whole tab shows its × and can be closed from it. A line marks each sliver's inner edge, but not against the current tab.
- **The narrowest bars** (under 200 points for the tabs) go back to `main`'s staged `TabLayout`, with its "›› N" menu.
- Titles are still fitted by `TabLabels` (dates shortened, shared leading words dropped), all to the one width.

**Checked:** pictures of the debug build (test vault, sidebar hidden, seven or more tabs) at 1000, 640, 480 and 380 points: sliding at each, the current tab whole, a peek and slivers either side.

**Not yet:** by hand: clicking slivers, the slide's animation, scrolling, hover, dragging tabs within the sliding row and onto slivers, and a split. The staged fallback in a bar that narrow (a split side, probably).

## Open questions

- **The deck hides some tabs.** With more tabs past an end than the stack shows, the ones between the peeking tab and the three slivers are hidden under them: clicking the peek moves on by one, but a sliver jumps further. Showing the nearest tabs as the slivers instead means the slivers shift as the row slides.
- Is 120 points the right narrowest, and 3 slivers of 6 points the right stack?
- Should a stack say how many tabs it holds (a tooltip, or a menu on right-click), as "›› N" did?
- Should the tabs fill the bar while they fit, as Ghostty's do? It would leave less of the bar to move the window by.
