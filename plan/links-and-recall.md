# Links and recall: to work on (8 November 2026)

Part of [the plan](../PLAN.md). Follows [Types, links and lists](types-and-links.md) and [Recall](recall.md).

**Mike's note:** the links panels' layout and UI need work, and so does how they relate to recall, which is confused at the moment.

**Where things are:** two features, built a day apart on separate branches, answer much the same question ("what's related to this note?") in two places and two styles.
- **Recall** is a line under a note's properties ("9 earlier meetings · last on 9 September"). Clicking it lists notes found by what they share: for a meeting, earlier notes of its type with any of its people; for a post, notes with any of its topics. Its rows show who or which topics are shared, the day, and the first line.
- **Links** are a button at the note's bottom right (opening a panel beside the pane) or a strip at the bottom left (sliding up over the note), chosen in Settings. They list the notes that link here, grouped by relation (By, About, a property's name, With, Mentioned, Not linked) and narrowed by type. Their rows show the title, type and date.

**What's confusing:**
- For a person, a topic or a project, the two overlap: notes about a topic are both recall (they share the topic) and links (they link to it in `topics`). For a meeting, they differ: its earlier meetings don't link to it.
- Two entry points (a line at the top, a button at the bottom), two list designs, and two ways to open a note from them.
- The links have two layouts to keep right; recall has a third.

**Layout and UI to work on (both placements):** the header and its close button, the type chips, the group headings and folding, the rows (what each shows, and how wide titles, types and dates share the room), the panel's width or height, and the empty state. Mike to say what isn't working.

**Ways it could go (to decide with Mike):**
1. **One "Related" place:** recall becomes the first section of the links panel ("Before": earlier meetings with these people; or "On the same topics"), above the notes linking here. The line under the properties stays as a summary that opens the panel at that section.
2. **Keep them apart, make them alike:** recall keeps its line and list but uses the links panel's rows, chips and opening, so they read as one family.
3. **Recall replaces part of links:** for notes with people or topics, the panel's groups come from what's shared as well as what links, and the separate recall list goes.

**Also:** the iPhone has recall (as a sheet) but its links are still one list; whatever's decided should land on both.
