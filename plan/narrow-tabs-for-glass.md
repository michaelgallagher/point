# Narrow-window tabs, for the glass header

Part of [the plan](../PLAN.md). A brief for trying the narrow-window tab work from the flat-header exploration (branch `header-narrow-tabs`, see [Exploration: a flatter header](exploration-flat-header.md)) in `main`'s Liquid Glass header, on a branch of its own.

**The problem** (Mike, 14 November 2026). Mike works in narrow windows, 420–500 points, a lot, and three or more tabs barely fit there. The window should still feel of the Mac, glass or not.

## The budget on `main`

At a 440-point window with the sidebar hidden, `main`'s top row spends its width roughly like this (`PaneTabBar` in `Apps/Mac/TopBars.swift`):

| Item | Points |
|---|---|
| Window buttons and gap (`windowButtonsInset`) | ~78 |
| Sidebar button and gap (`TopBar.sidebarButtonWidth`) | 44 |
| Back and forward, a glass capsule, and gap | ~76 |
| "…" menu, with the gaps either side | ~48 |
| **Left for tabs** | **~190** |

Tabs are at least 84 points (`PaneTabs.narrowest`), each with 20 points either side of the title (`PaneTab.padding`), and the row scrolls once they don't fit. So two tabs show, with about six characters each, and the rest scroll out of sight. The flat header had about 230 points here; glass's bigger buttons and gaps leave less.

Two jobs: free up room, and spend what's left on the text that tells tabs apart.

## The strategies

The ones considered (14 November), and what became of each on `header-narrow-tabs`:

1. **A wider current tab.** The current tab keeps a readable width; the others share the rest. As Safari's compact tabs do: you read the current one, and only need to recognise the others. *Built,* as the third stage below.
2. **The close button only on hover, below a width.** Saves 22 points on each other tab. *Tried and dropped:* it felt odd, and the current tab's title is on its page just below anyway. Every tab keeps its ×. (`main` shows × only on hover at every width, so this is a question for the glass version too: see below.)
3. **Titles shortened by what tells them apart.** Dates shortened, shared leading words dropped, the ends kept. *Built,* after a first version that gave odd results (see "Title fitting").
4. **Roll the overflow into a menu.** Tabs that don't fit at a readable width go into "›› N" at the end of the row, like the toolbar's own overflow chevron. The current tab never hides. *Built,* replacing the scrolling row.
5. **One switcher at the very narrowest.** The row becomes a single pop-up button ("Formatting tour ▾ 4"). Calm and unbreakable, but every switch is two clicks and you can't see the other tabs. *Not built:* the last resort if 4 can't show two readable tabs.
6. **Back and forward into the "…" menu** in a narrow bar with three or more tabs (⌘[ and ⌘] still work). They're the biggest fixed cost in the bar. *Built behind a switch* (`PointNarrowHidesHistory`); a matter of taste.
7. **Two rows below a width.** *Rejected:* a second row appearing as a third tab opens makes the note jump; one always there costs 38 points of height; and Mike found tabs in their own row too heavy.
8. **Lower-ranked ideas:** tabs stacked like cards behind the current one; monograms or folder colours on collapsed tabs (notes have no favicons); a scrolling row with faded ends (hidden tabs are worse than a menu that says how many). *Not built.*

Also built, outside the tabs themselves:
- **Narrower back and forward** in a bar under 520 points: 22 points each rather than 28, as the thin chevrons looked far apart.
- **No sidebar button** while the sidebar's hidden and the notes are narrower than 520 points: it fades as the sidebar slides away, and the tabs take its 30 points (⌘S, the View menu and a swipe still show the sidebar).

## What was built: the stages

`TabLayout` in `TopBars.swift` on `header-narrow-tabs`. Each stage is tried only when the one before doesn't fit:

1. **Whole titles.**
2. **Shared room.** The tabs share the room, the widest cut first, while every tab shows about ten characters (96 points).
3. **Compact.** The current tab keeps 80–150 points (or its title's width, if less); the others share the rest, down to 70 points: the × and about five letters.
4. **Overflow.** What still doesn't fit goes into the "›› N" menu (38 points). The current tab always shows, with the others in order as far as they fit. Choosing a hidden tab makes it current, so it comes into the row and the last of the others goes into the menu.

What showed, flat header, sidebar hidden, five tabs or more:

| Window | Back and forward shown | Hidden (the switch) |
|---|---|---|
| 440 | current + 1, the rest in the menu | current + 2 |
| 500 | current + 2 | current + 2, wider |
| 600 | all five | all five |

## Title fitting

`TabLabels.fit`, after the widths are settled:
- A title that fits its tab is shown whole.
- One that doesn't has its dates shortened ("30 Oct" for "2026-10-30") and is cut at its end.
- Unless what's left would look like another tab's (one's start is the other's whole): then the leading words it shares with that tab go. "Weeknote - 2026-11-09" and "Weeknote - 2026-11-02" show as "9 Nov" and "2 Nov", not "Week…" twice.
- Titles that already differ where they're cut ("The plan", "The list of things") are only cut at their ends. The tooltip has the whole title.

Lessons from the first version, which shortened by the set of open tabs alone, whatever their widths:
- Any shared first word went ("The plan" as "…plan"), even where there was no clash.
- Every tab was shortened once any was short of room, even those with room for their whole title.
- The current tab kept its shared words, so its text and width jumped as it was clicked.
- Cutting from the middle to keep a trailing number ("R…47") read badly.
- A leading "…" on stripped titles showed on some tabs and not others; it went.

## Bringing it to the glass header

Most of it is layout and text, and doesn't care about glass. Start a branch from `main` (say `glass-narrow-tabs`) and port in this order, trying each in a 440–500-point window:

1. **`TabLayout` and `TabLabels`** as they are, replacing `PaneTabs.widths(of:in:)`. Retune the numbers for glass's capsule tabs: 20 points either side of the title, not 22 for the × and 10 after, and a 2-point gap inside the capsule. The thresholds (96, 80–150, 70, 38) were set by eye for the flat header.
2. **The overflow menu** in place of the `ScrollView`. On `main` it should probably be a glass capsule like back and forward's, rather than flat `TabOverflowButton`. Tab dragging relies on the row (`TabDropTarget`, `TabMouseArea`); check dragging with tabs hidden.
3. **The close button.** `main` shows it only on hover, which saves the room strategy 2 was after but felt odd in the flat header in narrow windows. Try both: hover-only everywhere (as now), and always shown below 520 points.
4. **Narrower back and forward** below 520 points: the glass capsule around two 32-point icons could tighten to two 26-point ones.
5. **No sidebar button in narrow notes** (`fadesSidebarButton` in `SidebarSplit.swift`, `hidesSidebarButtonForWidth` in `VaultModel.swift`). On `main` it's 44 points with its gap, more than on the flat header.
6. **The history switch** (`PointNarrowHidesHistory`), last, as a comparison.

Things in `header-narrow-tabs` not to bring along: the flat button faces (`BarIconFace`), the row-shaped rail and its corner radii, and the spacing constants (`TopBar.buttonSpacing` 2, `edgeInset` 6, `dividerGap`), which are the flat header's own. The sidebar's popping open, unanimated, after its first show (fixed on `header-narrow-tabs` in `SidebarSplitController.resize`) is in `main`'s code too, and is worth fixing there on its own.

## Open questions

- Does the overflow chevron sit well beside glass capsules, or should it be inside the tabs' capsule, at its end?
- With glass's bigger fixed costs, is strategy 5 (one switcher) needed at 420 points, where the overflow stage may only show the current tab?
- Should the overflow menu list every tab (the current one ticked) rather than only the hidden ones?
