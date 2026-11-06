# Images: where to store them

*6 November 2026. A report on the options, with a recommendation. Not yet decided or built.*

Part of [the plan](../PLAN.md).

## The question

Point needs to support images. Where should their files go? Obsidian puts them in one attachment folder for the vault, which works well enough. The alternative is to tie each image more tightly to its note, for instance by making each note a little folder that holds its text and its images.

## What a real vault shows

A look at a long-used vault, from the real-vault trial (the details are kept privately):

- **Local images are few** compared with notes, and almost all are in the one attachment folder set in Obsidian.
- **Almost every image belongs to one note.** Very few are shared, and very few are unused.
- **Local images are embedded as `![[image.png]]`**, by file name only: no paths, no sizes. Obsidian finds them by name, wherever the file is.
- **Most images are on the web:** `![](https://…)` in clipped pages.
- **Some local embeds point at missing files,** left over from notes converted from PDFs.
- **Most are screenshots,** plus a few large photos of several megabytes.

So the single folder already works; the mess is small, and it's missing files rather than lost images.

## The options

**1. One attachment folder for the vault.** Obsidian's default, and Point's decision so far ("follow Obsidian's configured attachment folder", in [Principles and decisions](decisions.md)).
- *For:* fully compatible with Obsidian, notes stay single files, folders stay uncluttered, and moving a note never breaks an image.
- *Against:* nothing links an image to its note except the note's text. Deleting a note leaves its images behind, and the folder becomes an anonymous heap of screenshots.

**2. Next to the note, in the same folder** (Obsidian's `./`).
- *For:* easy to see what belongs where.
- *Against:* images clutter every folder, so the sidebar has to hide them. Moving a note in Point means moving its images, and moving it in Obsidian doesn't. It runs against "little filing".

**3. A subfolder in each folder** (Obsidian's `./assets`). Tidier than option 2, but there's an assets folder wherever there are images: many attachment folders instead of one, and the same problem when a note moves.

**4. Each note as a folder** (`Meeting/Meeting.md` with its images), or the TextBundle format of Bear and iA Writer (`Meeting.textbundle/text.md` with `assets/`).
- *For:* the tightest link. The note and its images move, copy and delete as one.
- *Against: it breaks too much.*
  - **TextBundle:** Obsidian can't read it at all, since every note would be called "text".
  - **Folder per note:** Obsidian shows each note as a folder with a note inside, doubling the nesting everywhere, and Point's sidebar would have to fake that away.
  - **Migration:** moving every existing note touches daily notes, templates and link updates, and puts thousands more folders in iCloud.
  - **Every note pays:** it complicates every note for the few that have images.

**5. One folder, with a subfolder per note** (`Assets/Meeting/screenshot.png`).
- *For:* Obsidian still finds `![[screenshot.png]]` by name, so it stays compatible, notes stay single files, and images are grouped by note.
- *Against:* the subfolder has to be renamed with the note. Point can do that; Obsidian won't, but nothing breaks if it doesn't. Images pasted in Obsidian still go loose into the main folder.

**6. One folder, with images named after their note** (`Meeting 2026-11-06 09.14.png`).
- *For:* the same link as option 5, with nothing to rename except the image itself. The folder sorts by note, and search finds images by note title.

**7. Images kept outside the vault,** in Point's own storage. This breaks "the file is the truth", and Obsidian wouldn't see them. Ruled out.

## Recommendation

1. **Where:** wherever `.obsidian/app.json` says (`attachmentFolderPath`, which Point already reads). That's one folder for most vaults, and it covers Obsidian's other choices (`./`, `./assets`) for vaults that use them.
2. **Naming:** images pasted or dropped in Point are named after their note (option 6), not "Pasted image 2026…". Point writes `![[Meeting 2026-11-06 09.14.png]]`, as Obsidian does.
3. **The link to the note comes from what Point does:**
   - **Delete:** deleting a note moves the images only it uses to the trash with it, and undo brings them back.
   - **Rename:** renaming a note renames the images named after it, along with their embeds.
   - **Clean up:** a command finds images no note uses.

This gives most of what a folder per note would, without its costs. If the folder ever gets too big, option 5 can come later, and Obsidian won't notice.

## Other decisions images will need

- **Web images,** most of a typical vault's. Showing them means loading them over the network. Point needs a cache, so they show offline and don't load on every visit, and a decision on whether loading them is acceptable for privacy.
- **Missing images** need a clear, quiet placeholder, not a blank gap or an error.
- **Photos from the iPhone.** The camera makes HEIC files, which Obsidian on other platforms may not show. Converting to JPEG when saving is the safe choice. Shrinking large photos to a sensible size is a decision to make too.
- **iCloud.** On the iPhone, an image can be evicted to a placeholder. Images should download when a note needs them, not all up front.
- **Size and editing.** Read Obsidian's `![[image.png|300]]` widths. The decisions say embeds are "rendered but read-only in v1". Images in a notes app probably need at least paste, drop, delete and resize from the start.
