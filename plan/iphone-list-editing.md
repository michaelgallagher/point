# Editing lists on the iPhone

20 November 2026. Planned; on `inline-lists`, before the checks (step 5 of [Lists written in a note](inline-lists.md)).

Today the iPhone shows lists but can't change them: a list note's filters, sort and columns are changed on the Mac (or by editing its `list-` properties by hand), and a list written in a note (a `list` block) only by its lines, with Markdown showing. This brings the Mac's editing to the iPhone, for both kinds of list, in the iPhone's own way: a sheet, not tokens and pop-up menus.

## How it looks

- **At the top of every list,** a list note's under its title and each `list` block in its outline: a line saying what it is, "In Reading · format is Book · by published", cut short if it's long, with a filter button at its end. A tap anywhere on the line opens the list's filters.
- **The filters,** a sheet, as Properties is, with Cancel and Done:
  - **Show notes that match** all or any of these (a segmented control, shown with two conditions or more).
  - **The conditions,** a row each, reading as its token does on the Mac ("format is Book", "read has no value", "In Reading", "Tagged #later"). Swipe to delete; Edit to reorder. **Add condition** at the end.
  - **Sorted by:** the key (title, date edited, date created, then the vault's properties, most used first), and ascending or descending.
  - **Columns:** those shown, in order, dragged to reorder, swiped away; **Add column** from the same list of keys.
- **A condition,** tapped or added, opens a page of its own (pushed in the sheet): what it's about (Folder, Tag, Links to, Has words, Title, the dates, then the vault's properties), the comparison, as the Mac words it for that kind ("is before", "includes", "has no value"), and the value, the way that suits its kind: a menu of choices, a date picker, a number of days, a switch, a field that suggests the vault's values, folders, tags or note titles.
- **Done** writes everything changed as one edit, which the note's Undo takes back. Cancel leaves the list as it was.
- **A list with nothing to show,** just made, opens its filters at once, as on the Mac.

## Writing it

- **A list note:** its `list-` properties, only those that changed, by their spelling in the note, as the Mac's `writeList` does; an empty `list-where` kept when nothing's left, so it stays a list.
- **A `list` block:** its lines, with `blockBody(over:)`, as on the Mac.
- **Both** as one edit in the note's text on the phone, through the editor, so Undo and Redo, the draft and saving work as for typing.

## How it fits the code

- **Shared, not copied:** `ListFilterSubject`, `ListValueKind` and `ListFilterRow` (how a condition reads, what comparisons suit a kind, turning a row back into a `ListCondition`) move from the Mac's `ListFilterSheet.swift` to IndexKit, with tests. What a property holds (`listValueKind(ofProperty:)`) is worked out there from what both apps have: the vault's property types, Point's kinds, and the index's property summaries and values. The Mac's window then uses them from there, unchanged.
- **The list note's changes,** now in `EditorSession.writeList`, become a function of `ListDefinition` (which properties to set and remove, against the note's frontmatter), shared and tested, used by both apps.
- **The block's lines on the phone:** `PhoneTextView` gets what `MarkdownTextView+ListBlocks.swift` gives the Mac, finding the `index`th block's lines and replacing them as one undoable edit.
- **The sheet:** new, in the iPhone app (`ListFiltersSheet` there), SwiftUI `Form`s in a `NavigationStack`.

## Steps

1. **Shared:** the filter model and the list note's property changes moved to IndexKit, with tests; the Mac using them, its window unchanged (checked in a snapshot). **Built 20 November:** `ListFilterSubject`, `ListValueKind` and `ListFilterRow` are in IndexKit's `ListFilters.swift`, with `ListVocabulary`, which says what a property holds from Point's kinds, the vault's property types, the index's summaries and a property's values (the Mac makes one from its store, `VaultStore.listVocabulary`), reads a condition in the filters' words (`reading`, the Mac's tokens) and a whole list in one line (`summary`, for the phone's line). `ListDefinition.propertyChanges(over:)`, in `ListBlock.swift`, is what the Mac's `writeList` did. Tests in `ListFilterTests`. Checked: the Mac's filters window and a list note's tokens, in snapshots, as before.
2. **The phone's writing:** a block's lines and a list note's properties, as one undoable edit, with tests.
3. **The sheet:** conditions (each kind's value), match all or any, sort, columns; Cancel and Done.
4. **The line at the top of each list,** opening the sheet; a new list opening it at once.
5. **Tried** in the Simulator on the test notes: every kind of condition, sort, columns, Undo; the file after each (well-formed, only what changed); then on the iPhone.

## Decided (20 November)

- **The line at the top** is the one-line summary with a filter button, not the Mac's tokens: they'd take room on a small screen and be small to tap.
- **Sorting** is only in the sheet: no sort menu on the list itself.
- **A list inserted on the phone** (`/list`, with [Slash commands](slash-commands.md)) opens its filters at once, as on the Mac.
