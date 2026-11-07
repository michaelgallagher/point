# Recall: what came before (7 November 2026, branch `recall`)

Part of [the plan](../PLAN.md).

**Why:** before a meeting, the useful question is "what happened last time with these people?". The notes say it already: a meeting has `type: Meeting`, `people` and a `date`. Point now asks.

**Built (meetings first):**
- **What counts as before:** notes of the same type, with any of the same people, dated earlier (by `date:`, else the day the file name starts with), newest first. People are in the properties of Point's person kind (`.point/types.json`), else `people`; `[[Sam Lee]]` and `Sam Lee` are the same person. A later meeting, one the same day and one of another type aren't counted. It isn't only for meetings: any note with a type, people and a day has it. (`Recall`, in IndexKit, with `RecallTests`.)
- **Mac:** a line under the properties, collapsed or open: "4 earlier meetings · last on 21 October" (the year when it isn't this one). Clicking it lists them, with whoever of this note's people were in each, its day and its first line; clicking one opens it, ⌘-click in a new tab.
- **iPhone:** "4 earlier" beside the properties and links buttons; it opens the same list as a sheet.

**Tried:** the tests (types, people, days, the summary, and the query against an index). On the iPhone Simulator with test meetings: the count, the sheet, opening one, and the earlier one's own count. **Not tried:** the Mac by hand (it builds; running a second copy would share Mike's settings).

**Blog posts, by topics (built the same day):** a note with topics and no people (a post, a source) recalls by its topics instead: every other note with any of the same topics, of whatever type, newest first, in groups by type with the note's own type first ("23 notes on Org design and Service design"; on the iPhone, "23 on its topics"). Each row says which of the topics it shares. A meeting has people, so it still recalls by people. In the vault, 78 of 134 posts have topics, and 2,567 notes use `topics` (80 on Org design). Tried in the tests and on the iPhone Simulator with a post, an older post, a book and a meeting.

**Maybe next:**
- Posts that link to the same notes, not only those with the same topics.
- The last one's text, not just its first line.
- A meeting with many people (165 with one person) might want those sharing the most people first.
