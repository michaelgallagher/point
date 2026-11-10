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

**Status (10 November 2026):** 1–3 built, on branch `iphone-real-vault`, for a week on Point alone while travelling (see [the plan](../PLAN.md)).
- **Choosing the vault:** Settings › Vault › Choose vault… opens the Files folder picker; the folder is kept as a bookmark and reopened at launch (if it can't be, Point says so and shows its own folder). Use Point's own folder goes back. Each vault has its own index, search history, drafts, and its own note being worked on, untitled notes, favourites and trash records, so nothing from one acts on another's notes. The spike notes and `spike-timings.txt` only ever go in Point's own folder.
- **Notes not yet downloaded:** each scan asks iCloud for any placeholder notes and looks again every 5 seconds until none are left; Settings shows how many are still downloading. A note opened while downloading says so and can't be typed into, then opens once it arrives.
- **Changes from elsewhere:** a file presenter on the vault's folder reads it again (a second after the last change), as does coming back to the app. Reads run one at a time. An open note with no edits takes in a change to its file; one with edits keeps them, and saving puts them in a conflict copy, as before.
- **Tried in the Simulator** on a folder chosen in the Files picker: choosing it, the bookmark kept across launches, notes written from outside appearing without a refresh, an open note taking in an outside edit, typing saved into the chosen folder, and the vault's state kept apart. **Not yet tried:** iCloud itself (placeholders downloading, edits arriving from the Mac), which needs Mike's iPhone and the vault in iCloud Drive; then 4, the safety tests on the phone.

**Order:** 1 and 2, tried on a copy of the vault in iCloud Drive; then 3; then 4 on the real vault with a backup; then Mike uses it day to day.

**Size:** a few days' work. After the iPhone clipper.
