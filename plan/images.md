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

## Keeping web images in the vault (built 11 November 2026, not yet committed)

**Why:** a clipped page's pictures stay on its site (`![](https://…)`), shown from Point's cache. Mike wants to keep a note's pictures in the vault when he chooses, without that being the default.

**Built:** **File › Save Web Images to Vault** on the Mac (and in Run Command…; a shortcut can be set in Settings), and **Save web images** in the note's menu on the iPhone. Both only appear when the note has pictures from the web. Clipping doesn't use it, and nothing runs it unasked.
- Finds every picture embedded from the web: `![alt](https://…)` (with a title or `<…>` too), the picture of a link (`[![alt](…)](page)`), and `<img src="https://…">`. Pictures in code and in the properties are left alone.
- Gets them several at a time, off the main thread: the copy in Point's cache if the note has shown it already (instant, and offline), else downloaded as the cache does (no cookies), asking for PNG or JPEG first. Each is kept as what it is (JPEG, PNG, GIF, WebP, AVIF and SVG as they are; anything else as a pasted image is), not as what the server or the address says it is.
- Saves each in the attachment folder (`attachmentFolderPath`), named after the note as a pasted image is (`Storm hits the coast 1.jpg`, `2026-11-06-meeting-1.png`), numbered in the order the note shows them, past any name already in the folder or the vault (embeds find images by name). Never writes over a file. The same picture twice is saved once.
- Rewrites each link as the vault writes links: `![[Name 1.jpg|alt text]]` (the alt text kept, without Markdown escapes or anything that would end the link; a width stays as `|300`), or `![alt](Name%201.jpg)` in a vault set to Markdown links, with the path as its "New link format" says. The picture of a link stays a Markdown image, since Obsidian doesn't show an embed inside a link. A picture that couldn't be downloaded stays as it was.
- One step to undo, made in the open editor around anything typed meanwhile (typing isn't blocked). If the note has been closed by then, its file is changed instead, if nothing else changed it. An alert (a notice on the iPhone) says how it went: "Saved 12 of 13 images in the vault: 1 couldn’t be downloaded, so it’s still shown from the web."
- `WebImages` in VaultKit (shared by both apps), `WebImageSaving.swift` on the Mac, `NoteSession.saveWebImages` on the iPhone.

**Also fixed:** an image's name in its new embed came back from the disk with its accents decomposed (`a` plus an accent, as the system writes names), unlike the rest of the note. Pasted and dropped images had the same fault; both now write the name as Point chose it.

**Tried:** `WebImagesTests` (finding, writing both link styles, alt text, widths, linked pictures, what's left alone, naming in order without overwriting, accents; a network test with `POINT_NETWORK_TESTS=1`). In a test copy of the Mac app (its own bundle ID) on a scratch vault, with `-PointWebImages "<note>|type|undo"`: a clipped article with 13 pictures from Wikimedia (photos, PNGs, SVGs, one twice, a linked one, an `<img>`, one in a code block, one gone) saved 12 and reported the missing one; only the picture lines changed, in clean Markdown; the file already called `… 1.jpg` was kept; typing during the downloads was kept; one Undo put the note back byte for byte; a note with no web images isn't offered the command. The saved pictures show in the editor.

On the iPhone, in the Simulator, the same note in Point's own folder: **Save web images** shows in the note's menu; tapped, it saved 12 of 13 (really downloaded, the addresses new to the cache) and said so in a notice; the note shows the copies, and its file changed only in the picture lines, in clean Markdown.

**Not tried:** a real iPhone, a vault in iCloud Drive, and the menu clicked by hand on the Mac (the debug hook calls what the menu calls). Undo takes back the links but leaves the saved files, which Find Unused Images finds. Pasted images are still always written as `![[…]]`, even in a vault set to Markdown links.
