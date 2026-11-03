# Search that learns (plan, 3 November 2026)

Part of [the plan](../PLAN.md). Follows the principle "Know what you need to know".

# The goal

Point should learn which notes you go to, and put them first, without search ever feeling unpredictable. Today every search is ranked the same way for everyone: how well a title matches, then full-text relevance. Opening a note every day doesn't make it any easier to find.

# What it learns

1. **What you open, and how recently.** Each time you open a note on purpose, Point notes the time. A note's score adds up its recent opens, each counting for less as it gets older (half as much after two weeks). This is "frecency", as in Spotlight, Raycast and Firefox's address bar. A note opened ten times last month beats one opened once yesterday, and both beat one not opened for a year.
   - **Counts:** opening from the palette, search, the sidebar, the note list, a link, or a new note.
   - **Doesn't count:** windows and tabs restored at launch, or Back and Forward, which revisit rather than choose.
2. **What you pick for what you type.** When you choose a result, Point remembers what you'd typed and which note you chose. Next time you type the same thing, or the start of it, that note goes first. So once you've typed "mtg" and picked "Meetings", "mtg" and "mt" both bring it to the top. A newer pick for the same text replaces an older one.

# How it changes ranking

The rule: **learning reorders results of similar quality, and never puts a weak match above a clearly better one.** It never adds a note that doesn't match.

- **A remembered pick** for what's typed goes first, as long as it still matches.
- **Title matches** are already grouped by quality: exact, starts with, contains, and near misses. Within a group, the more often opened note comes first. Today the shorter title wins.
- **Matches in the text** keep their relevance order, except that a much-opened note can move up a few places past notes of about the same relevance.
- **The empty palette's "Suggested" notes** are the highest by frecency instead of the most recently edited. Recent editing still counts: an edit counts as an open.
- **The iPhone search screen's recent notes** use the same scores.

With nothing learned yet, results are exactly what they are today. That's the safety net, and it gets a test.

# Where it's kept

- **On each device, outside the vault.** It goes in a small file in Point's Application Support folder, one per vault, next to the search index. It's not in the index itself, because the index is rebuilt from scratch whenever its format changes.
- **Nothing goes in the vault,** and nothing goes to Obsidian or iCloud. What you search for is private to the device.
- **It stays small:** the last 20 opens per note, for at most 2,000 notes, and the last 500 picks. The oldest are forgotten first.
- **It follows notes:** a renamed or moved note keeps its history, and a deleted note's history is dropped.
- **A "Forget What Search Has Learned" command** in the palette clears it.

# How it's built

- **IndexKit:** a new `SearchHistory` type, with no UI, so it can be tested on its own:
  - `opened(_ id:at:)`, `picked(_ id:for query:)`, `renamed(from:to:)` and `forget()`
  - `score(of:)` for frecency
  - `rank(_ results:for query:)`, which reorders search results by the rule above
  - its load and save
- **Both apps** record opens where a note is opened, and record a pick when a search or palette result is chosen. Each runs results through `rank` before showing them. The Mac does this in `VaultModel` (opening notes and sidebar search) and `CommandPalette`; the iPhone in `PhoneStore` and `SearchScreen`.
- The full-text query itself doesn't change. Reranking happens after it, on at most 50 results, so it costs nothing you'd notice.

# Steps

1. `SearchHistory`, its file and its tests, including that with no history the order is unchanged.
2. On the Mac, record opens and picks.
3. On the Mac, rerank the palette and sidebar search, and base "Suggested" on frecency.
4. The iPhone: the same, and its recent notes. Its own opened list (`PhoneStore.opened`) moves into `SearchHistory`.
5. The Forget command.
6. Try it in a test copy of the app with the scratch vault, then use it day to day.

# Questions for you

1. **Each device on its own, or shared?** I recommend each on its own for now. Sharing between the Mac and iPhone would need iCloud sync of private data, outside the vault. It could come later.
2. **Recent searches:** should the empty palette also show your last few searches, so you can run one again? I'd leave it out to start with, since searches you pick from are already remembered.
3. **How strong:** I've suggested a gentle setting (a two-week half-life, and moving up only past matches of similar quality). Too gentle and you won't notice it; too strong and results start to feel random.
