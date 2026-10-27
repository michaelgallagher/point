# Point — plan

A simple, fast, native Markdown notes app for Mac and iPhone that feels like Apple Notes and Things. It's backward compatible with Obsidian: it opens an existing vault and works alongside Obsidian on the same files, without being a copy of it.

The plan is in several documents, in [`plan/`](plan/). This page says where things stand and what's in each.

## Where things stand (27 October 2026)

Branch `no-visible-tabs`. Recently built: tabless headers, the redesigned properties, the sidebar that widens the window, links as a glass button and panel, and templates (applying merges properties, new note from a template, a Settings page).

**Next:**
1. **Using Point with the live vault:** phases 1–3 are done (audits, write tests on a copy, the comparisons with Obsidian, the conflict banner, and the fixes they called for). Sync is iCloud only. Next: phase 4, a week's trial on the real vault, once Obsidian Sync is off and the vault is snapshotted (`scripts/vault-snapshot.sh`). See [Live vault safety](plan/live-vault-safety.md). The [27 October review](plan/app-review-2026-10-27.md)'s findings are fixed except 5 (iCloud conflict versions, to fix against a real one during the trial) and 13–15 (performance, to measure first).
2. **The properties view,** the last item of the [25 October batch](plan/batch-2026-10-25.md).
3. **The sidebar's remaining steps:** the swipe follows the fingers, and auto-hide resizes the window at the end of a drag. See [The sidebar widens the window](plan/sidebar-widens-window.md).
4. **When the screen is free for recordings:** the header's jitter as the sidebar slides, and full screen. See [App review](plan/app-review-2026-10-25.md).
5. **The iPhone app (M4):** sketched and its questions answered; the first step is a spike: the editor in UIKit, measured on the iPhone 13. See [M4, the iPhone app](plan/m4-iphone.md).
6. **Later milestones:** meaning (M5) and extras (M6). See [Milestones](plan/milestones.md).

## The documents

**Foundations**
- [Principles and decisions](plan/decisions.md): what Point is for, and the decisions so far, by area (platforms, vault and sync, editor, sidebar, note list, focus mode, search, AI, capture, shortcuts).
- [Architecture and risks](plan/architecture.md): how the app is built, and what could go wrong.
- [Milestones](plan/milestones.md): M0 to M6.

**Work, newest first**
- [Live vault safety](plan/live-vault-safety.md) (26–27 October): testing, then fixing, what Point writes to a real vault; the results, and the trial still to come.
- [M4, the iPhone app](plan/m4-iphone.md) (27 October): what it's for, two screens and a button, what it leaves out, how it's built, and the steps.
- [Code review](plan/app-review-2026-10-27.md) (27 October): an external review of note safety, stability and performance; what's fixed, and what's still open.
- [App review](plan/app-review-2026-10-25.md) (25 October): the review's findings by severity, and the fixes since, including the close flash.
- [The 25 October batch](plan/batch-2026-10-25.md): the links panel, templates, the properties view, palette defaults, tags and the home button, sorting in two columns, splits that slide, and the small fixes after.
- [The sidebar widens the window](plan/sidebar-widens-window.md) (25 October): the design, the attempts, and the bugs fixed.
- [Properties, redesigned](plan/properties.md) (25 October).
- [Exploration: no visible tabs](plan/exploration-no-visible-tabs.md) (25 October): tabs without a tab bar.
- [Exploration: radically minimal](plan/exploration-minimal.md) (19 October).
- [M3.5, Mac refinements](plan/m3.5-mac-refinements.md) (18–24 October): parts A to H.

**Ideas**
- [Investigations and open questions](plan/investigations.md): daily notes as a meeting log, and questions still open.
