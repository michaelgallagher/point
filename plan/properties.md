# Properties, redesigned (25 October 2026)

Part of [the plan](../PLAN.md).

**Why:** a property couldn't be deleted (the edit existed but nothing called it) or have its type changed, and tags behaved differently from note to note. YAML has two ways to write a list (`tags: [a, b]` on one line, or `tags:` followed by `- a` lines); Point read both but wrote only the second, and read `tags: work` as text, so typing "work, ideas" there saved one quoted string.

**Decided (Mike):** rows like Obsidian's; lists as tokens; types from Obsidian's own file; lists always written with `-` lines.

**Built:**
- **Types** come from `.obsidian/types.json`, as Obsidian keeps them, so a property has the same type in every note and in Obsidian (`PropertyTypes` in VaultKit). `tags` is always Tags and `aliases` Aliases; a key with no type is guessed from the note (a list, a date, a date and time, true or false, a number, else text). Changing a type writes the file (keeping everything else in it, including types Point doesn't know) and carries the note's value over: text split into items at commas, items joined into text, anything that doesn't fit left empty. Renaming a property takes its type to the new name.
- **Each row:** the type's icon (click it to change the type), the name (click to rename, drag to reorder), the value, edited to suit the type, and a ⋯ menu on hover (Rename, Change Type, Delete), also on right-click. Clicking a row's empty space selects it (tinted); ⌫ or ⌦ deletes it, Escape lets it go.
- **Values:** text and numbers in a field (a number that doesn't read as one goes back); a checkbox; the system's date, or date and time, picker (an empty one offers "Empty", which sets it to now); lists, tags and aliases as tokens, each with a remove button, and a field after them where Return or a comma adds an item (⌫ in the empty field removes the last, from macOS 14). Tags offer up to six matching tags from the vault while typing. Tags written on one line (`tags: work ideas`) show as separate tokens.
- **Writing:** every list Point writes uses `-` lines, whichever way the note had it.
- **Add Property:** every type, starting from the vault's type for the name typed (or tags, or date for date-like names); a new name's type is recorded for the vault.
- **Checked:** VaultKit tests for types (guessing, the vault's type winning, converting, saving without losing the rest of the file) and for rewriting lists; a picture of a note with one property of each type. Not tried by hand yet: every interaction (Point's windows couldn't be clicked while Mike's own copy was running).
