# The iPhone on the real vault (planned 8 November 2026)

Part of [the plan](../PLAN.md). Step 5 of [M4, the iPhone app](m4-iphone.md).

**Why:** Mike wants to try the iPhone app for real, on his own notes. Today it only reads a vault folder in its own Documents, filled by copying notes in through Files: fine for judging it, but edits there never reach the Mac.

**Meanwhile (no code needed):** copy the whole vault into Point's folder (Finder › the iPhone › Files › Point) to try speed, search and reading on every note without touching the real ones. The first index build of a full copy took 8.4 s on the iPhone 13.

**What's needed:**
1. **Choosing the vault.** First run (and Settings) offers the Files picker; Mike picks the Obsidian vault in iCloud Drive. Point keeps a bookmark to it across launches (`VaultLocation` already does this on iOS) and asks again if the bookmark goes stale. Point's own copy in Documents stays available, for trying things safely.
2. **Notes not yet on the phone.** iCloud keeps some files only as placeholders until asked for. The scan has to see them, ask for them (`startDownloadingUbiquitousItem`), index each as it arrives, and show a note that's still downloading as such rather than as empty.
3. **Changes from elsewhere.** The Mac's file watcher (FSEvents) doesn't exist on iOS. The phone uses iCloud's own notices (`NSMetadataQuery` over the vault, with `NSFilePresenter` on the open note), so an edit on the Mac shows up, and an open note reloads or flags a conflict as on the Mac.
4. **Safety, on the phone.** The tests from [Live vault safety](live-vault-safety.md) again on the iPhone: coordinated reads and writes (already used), saving while iCloud is syncing, a note changed on both devices, and iCloud's conflict versions, which the [27 October review](app-review-2026-10-27.md) left open (finding 5).
5. **What stays on the device.** The index, search that learns and drafts stay outside the vault, in the app's own storage, as now.
6. **Signing.** With the free account, a build lasts 7 days and is reinstalled from Xcode. Workable for the trial; the paid account ($99 a year) ends that, and allows a share extension (see [The clipper](clipper.md)).

**Before the first run:** a backup of the vault, and Obsidian's own sync left as it is (iCloud), so nothing else writes the files.

**Status (10 November 2026):** 1–4 built and merged into `main`, for a week on Point alone while travelling (see [the plan](../PLAN.md)).
- **Choosing the vault:** Settings › Vault › Choose vault… opens the Files folder picker; the folder is kept as a bookmark and reopened at launch (if it can't be, Point says so and shows its own folder). Use Point's own folder goes back. Each vault has its own index, search history, drafts, and its own note being worked on, untitled notes, favourites and trash records, so nothing from one acts on another's notes. The spike notes and `spike-timings.txt` only ever go in Point's own folder.
- **Notes not yet downloaded:** each scan asks iCloud for any placeholder notes and looks again every 5 seconds until none are left; Settings shows how many are still downloading. A note opened while downloading says so and can't be typed into, then opens once it arrives.
- **Changes from elsewhere:** a file presenter on the vault's folder reads it again (a second after the last change), as does coming back to the app. Reads run one at a time. An open note with no edits takes in a change to its file; one with edits keeps them, and saving puts them in a conflict copy, as before.
- **Tried on the iPhone, on a copy of the vault in iCloud Drive (10 November):** iOS doesn't use `.icloud` placeholders; a note not yet downloaded keeps its own name, and reading it waits for the download. The first build read them as downloaded, so the index stalled at 200 notes (types and tags looked empty). The scanner and reader now ask iCloud for each file's download status on iOS, so those notes are indexed by title and asked for, and filled in as they arrive.
- **Bookmarks:** the Mac kept its own in its preferences while the iPhone used Obsidian's `.obsidian/bookmarks.json`. The Mac now uses the vault's file too (and re-reads it on coming back to the app and after each scan); the bookmarks it had are added to the file once.
- **Types on home:** Settings › Home › Types: all types as one tile, and any chosen to show as tiles of their own (each vault its own choice).
- **Tried in the Simulator** on a folder chosen in the Files picker: choosing it, the bookmark kept across launches, notes written from outside appearing without a refresh, an open note taking in an outside edit, typing saved into the chosen folder, and the vault's state kept apart. iCloud itself was then tried on Mike's iPhone, below.

- **The safety tests on the phone (10 November, on the copy in iCloud Drive), and what they changed:**
  - **A note changed on both devices:** the phone keeps its edits and saves them as one conflict copy beside the note, as the Mac does. iCloud's own conflict versions (finding 5 of the [27 October review](app-review-2026-10-27.md)) are written out as conflict copies, byte for byte, then resolved: when the phone hears of one, and in a sweep once each launch. "Changed on two devices" says so.
  - **A note renamed, moved or deleted elsewhere while open:** the phone follows a rename or move (by name in another folder, or by created date in the same one); a deleted note offers "Save it again". A move no longer shows the note's file name, in lower case, in Recent.
  - **Restoring from the trash:** where each note Point deleted came from is kept in the vault (`.point/trash/<name>.json`, one small file per note, so the two devices never write the same file), so a note deleted on one device goes back to its folder from the other. Notes Obsidian put in the trash are still tracked by each app.
  - **Offline:** editing and making notes in airplane mode work, and reach the Mac when the phone is back online (about a minute after typing stopped). Making a note offline used to go blank part way through its title, a race between reading the vault and the rename; fixed.
  - **New notes:** untitled notes are named by the time they're made (`2026-11-10-untitled-142305.md`), so two devices never make the same name, and each device only tidies away empty untitled notes it made itself, within two minutes of making them. Before, the Mac and the phone could both make, and fight over, "Untitled 3". The phone's New note quick action makes one note each time.
- **Reading the vault quickly:** asking `FileManager` for each file's details went through iCloud: 12 s for 3,500 notes. The phone now reads folders directly (`readdir` and `lstat`; a note not yet downloaded is marked dataless), in 0.66 s, and after a change reads only the files that changed (about 60 ms). Ready at launch in 1.5 s, down from 13–15 s.
- **Changes from the Mac:** reach the phone in 8–14 s. A note the phone already had is fetched as soon as it changes, rather than waiting on iCloud's background download (which once took 43 s), and a renamed note shows its new title, from its new file name, until its text arrives. The phone logs how long each change took to `spike-timings.txt`, in Point's own folder.
- **Known gaps:** the Mac doesn't follow a rename made on the phone while the note is open on the Mac; the Mac only writes out iCloud's conflict versions for notes open there; and when iCloud reports a change to a whole folder, the phone reads the whole vault again (half a second).

**Order:** 1 and 2, tried on a copy of the vault in iCloud Drive; then 3; then 4 on the real vault with a backup; then Mike uses it day to day.

**Size:** a few days' work. After the iPhone clipper.
