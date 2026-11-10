# Links and recall: to work on (8 November 2026; decided the same day)

Part of [the plan](../PLAN.md). Follows [Types, links and lists](types-and-links.md) and [Recall](recall.md).

**Mike's note:** the links panels' layout and UI need work, and so does how they relate to recall, which is confused at the moment.

**Where things are:** two features, built a day apart on separate branches, answer much the same question ("what's related to this note?") in two places and two styles.
- **Recall** is a line under a note's properties ("9 earlier meetings · last on 9 September"). Clicking it lists notes found by what they share: for a meeting, earlier notes of its type with any of its people; for a post, notes with any of its topics. Its rows show who or which topics are shared, the day, and the first line.
- **Links** are a button at the note's bottom right (opening a panel beside the pane) or a strip at the bottom left (sliding up over the note), chosen in Settings. They list the notes that link here, grouped by relation (By, About, a property's name, With, Mentioned, Not linked) and narrowed by type. Their rows show the title, type and date.

**What's confusing:**
- For a person, a topic or a project, the two overlap: notes about a topic are both recall (they share the topic) and links (they link to it in `topics`). For a meeting, they differ: its earlier meetings don't link to it.
- Two entry points (a line at the top, a button at the bottom), two list designs, and two ways to open a note from them.
- The links have two layouts to keep right; recall has a third.

**Layout and UI to work on (both placements):** the header and its close button, the type chips, the group headings and folding, the rows (what each shows, and how wide titles, types and dates share the room), the panel's width or height, and the empty state. Mike's answers are under Decided, below.

**Ways it could go:**
1. **One "Related" place:** recall becomes the first section of the links panel ("Before": earlier meetings with these people; or "On the same topics"), above the notes linking here. The line under the properties stays as a summary that opens the panel at that section.
2. **Keep them apart, make them alike:** recall keeps its line and list but uses the links panel's rows, chips and opening, so they read as one family.
3. **Recall replaces part of links:** for notes with people or topics, the panel's groups come from what's shared as well as what links, and the separate recall list goes.

**How 1 and 3 differ** (Mike asked): both make one panel. In 1, recall is a section of its own at the top ("On the same topics", "Before"), and the groups below it list only notes that link here, as now; a note can appear in both. In 3 there's no recall section: what a note shares is folded into the groups themselves (a note on the same topics joins "About" though it never links here), so each note appears once, but you can no longer tell a note that links here from one that only shares something with it.

## Decided (Mike, 8 November)

**One function, not two: way 3.** Links and recall become one panel, and recall stops being a thing of its own: what a note shares with this one (topics, people) is folded into the panel's groups alongside what links here. Way 1 would still have left two functions doing nearly the same job.

**Ranked by how much is shared.** A note sharing all of this note's topics comes first, then those sharing all but one, and so on down to those sharing one. So for a note with three topics: all three, then two of the three, then one. (The same for people on a meeting, presumably: all the same people first.) Within each tier, newest first.

**How it looks: the slide-up from the bottom**, as the main way. None of today's layouts is liked.
- The side panel is good for focused writing but no use in a narrow window, which is how Mike takes notes at work. It may stay as an option.
- Recall's current pop-out is too small to filter in comfortably.
- **The note above stays scrollable** while the panel is up; otherwise it may as well take the whole window, which Mike doesn't want.
- **Width:** the panel's content can be wider than the note's column, up to a limit. Simplest: the same maximum width as the note's content.
- **Section headings** (Mentioned, Media, By and so on) easier to see: bold, in the text colour (not grey), and the same size as the panel's heading.
- **A divider** under the panel's heading once its content scrolls: a plain line, as wide as the content.
- **The type chips move up**, beside the panel's title.

**One button or readout, not two.** Start with today's recall line under the properties ("9 earlier meetings · last on 9 September"): it's discreet, and clicking it opens the panel. Where it finally goes isn't settled.

**What's shared comes first in the panel**, above the notes that only link here. With way 3 there's no separate recall section, so this means the notes found by what they share (most shared first) lead, and the relation groups (By, About, Mentioned…) follow.

**Expect to try a few versions** of both the readout's place and the panel's order before settling. Build them so they're easy to change, and show Mike each.

**Still open:** whether a note that both links here and shares topics shows among the shared notes or in its relation group (it appears once either way), Then the iPhone follows.

**The readout with nothing shared** (Mike, 8 November): it counts the links and says what kinds they are, for example "12 links (articles by this author, mentions, and with)", built from the groups the note actually has. The wording to try out with the rest.

## Built (9 November)

A first version of all of the above, made easy to change.

- **One panel, "Related notes".** First the notes sharing this note's topics or people, in tiers: "On all 3 topics", "On 2 of 3 topics", "On 1 of 3 topics" (for a meeting, "Earlier meetings with all 3"…), newest first in each, with which topics or people each shares when it isn't all of them. Then the notes linking here, under headings saying what they are ("Articles by this person", "Meetings with this person", "Mentions", or the property's name), then "Unlinked mentions". Each heading folds. At most 300 shared notes are ranked; past that it says how many more.
- **Slide-up from the bottom**, now the default (Settings › Notes › Related notes). Its content is as wide as the note's text at most, lined up with it; the title has the type chips beside it; a hairline appears under the header once the list scrolls. The note above scrolls as usual, and gets room at its end to scroll clear of the panel. The top edge drags to resize; the close button or Escape closes it. It stays open from note to note; a note with nothing related doesn't show it. The side panel is still there as the other choice, with the same list.
- **One readout, under the properties** (under the title for a note with none): recall's line when something's shared ("4 earlier meetings · last on 21 October"), otherwise "4 links (articles by this person, meetings with this person, and unlinked mentions)". Clicking it opens or closes the panel. The links button and the strip's button are gone.
- **The open question, as a setting:** Settings › Notes › Related notes › "Links with multiple connections" (Mike's wording, 10 November): "As part of topics" (the default) or "As part of backlinks". Try both. Location there is Bottom, Side or Do not show (which turns the feature off).
- Where to change things: `RelatedNotes` (IndexKit) ranks and words it; `RelatedPanel.swift` (Mac) draws it.
- Not done yet: the iPhone; trying other places for the readout.
