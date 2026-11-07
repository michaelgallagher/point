# Kinds of note (7 November 2026, branch `kinds`)

Part of [the plan](../PLAN.md).

**Why:** most notes fall into a few predictable kinds (meetings, books, articles, weekly notes), and labelling each by hand is work. A note's kind is what its `type` property says. Point now knows the vault's kinds, so it can start a note as one, and later recall what came before (earlier meetings with someone) and clip into one.

**Decided (Mike, 7 November):** `type` is the one answer to "what is this note?" (books are `type: Book`, with `genre` apart; a source's format went into `type`). Playbacks, communities of practice, 1:1s, office hours and workshops are all meetings; a 1:1 is a meeting with one other person, and its conversation guide is a template, not a kind. Kinds aren't inferred from folders behind the scenes: where a folder makes a note's kind plain, `type` is written into the note once, so the file says what Point knows.

**Built:**
- **`.point/kinds.json`** (`NoteKinds`, in VaultKit), next to Point's property types: the kinds in the order they're offered, each with its name (its `type` value), a symbol, the folder new ones go to (the vault root if none) and its templates (the first is the usual one). Several kinds can share a template (articles, videos and podcasts start from the same one). A kind with no template isn't offered for new notes. With no file, nothing changes anywhere. The Mac reads it again on coming back to Point, as it's edited by hand.
- **A new note of a kind** starts from its template, filled in, goes in its folder, and has `type` set to the kind unless the template sets it already.
  - **Mac:** File › New Note of Kind, with a submenu of templates for a kind with several; and in the palette, "New Meeting", "New Meeting: 1-1" and so on.
  - **iPhone:** a long press on home's blue New note offers the kinds, with a kind's templates in a submenu. A tap still makes a plain note. (A menu in the bottom bar is drawn plain whatever its style, so this one draws its own blue glass circle.)
- **`type` is a choice of the kinds** in the properties, on both: implied by the kinds, not saved in `.point/types.json` (`PointTypes.implied`), so the types file keeps only what was chosen there. A value that isn't a kind still shows, and stays.

**Tried:** `NoteKindsTests` (loading, finding a note's kind, templates and their labels, setting `type`, the implied choice). On the iPhone Simulator (iOS 27), with a test vault: the long press, Meeting's templates, a 1:1 made from its template with `type: Meeting`, and `type` as a menu in the properties sheet.

**In the real vault (7 November):** a kinds file, and `type` written into about a thousand notes where it was plain: dated notes with people became meetings, notes under the blog and topic and recipe folders became posts, topics and recipes. Index, scratch and site notes were left alone, and so were notes that already had a type. Each kept its modified date, one second on. A few that might not be meetings (day lists, prep and written notes) were held back for Mike.

**Not tried:** the Mac's menu and palette by hand (both build; running a second copy of Point beside Mike's would share its settings and search history). The iPhone itself.

**Next, maybe:** a kind's symbol in note lists; a kind's own page (all its notes), which lists can already do with a `type` filter.
