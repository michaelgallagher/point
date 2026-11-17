# Code review — 17 November 2026

## Scope and assessment

This review covers `main` (at `2a76149`) and the `header-one-row` experiment (at `93ed627`). It looks most closely at two things:

- the custom interface pieces Point builds itself instead of using AppKit's or SwiftUI's own;
- data security: what can reach the vault from outside, what leaves the device, and what's kept where.

It's a source review, with one exception: the tab dragging on `header-one-row` was tested with real pointer drags in a separate copy of the app. Line numbers refer to `header-one-row`; where a file isn't changed on the branch, they're the same on `main`.

The 27 October review was not re-checked item by item. Four of its findings were seen fixed while reading:

- **#1:** a failed save now keeps a draft and says so.
- **#3:** an unreadable original now stops the write.
- **#4:** conflict copies are numbered, and never written over.
- **#12:** links other than web and email now ask first.

**Overall:** the core of note safety is sound. Writes compare against what was last read, under file coordination. Conflicts become copies, never overwrites. Release builds are sandboxed, and debug-only code and launch flags are compiled out of them. The clipper's page parsing is inert, and web images load without cookies.

The weak points are at the edges:

- **The `point://clip` address.** Any page or app can use it to write a note, and it can be made to use a great deal of memory.
- **The sidebar's drop target.** It treats any dropped text as a note or folder to move.
- **The window-level tricks the custom bars need.** These rely on AppKit details that aren't promised.

## Findings, in priority order

### High

1. **A `point://clip` address can exhaust memory.**
   - **Where:** the `page=` value is unpacked with no limit on its size (`Packages/ClipKit/Sources/ClipKit/Clip.swift:245-251`).
   - **The problem:** deflate can shrink highly repetitive text by about 1,000 to 1. A link of a megabyte or two can therefore expand to gigabytes as Point decodes it, then again as a string, and again in the web view. Opening such a link (from a page, a message or a shortcut) is enough to make Point stop responding or be killed. On the iPhone this happens sooner.
   - **Fix:** decompress with a stream (`compression_stream`, or `NSData` in chunks) and stop past a cap, say 10 MB. Also refuse a `page` value that's too long before decoding it.

2. **Any page or app can put a note in the vault, saying it came from anywhere.**
   - **Where:** `ClipRequest(_:)` (`Clip.swift:217-225`), which the Mac (`Apps/Mac/Clipping.swift:33`, `45`) and the iPhone (`Apps/iOS/PointPhoneApp.swift:60`) act on with no confirmation.
   - **The problem:** the request carries its own HTML, title and selection, and Point writes the note from those, with `source:` set to whatever `url=` says.
     - A page that sends Point a link can file an article that claims to be from a site it isn't from. The article can carry links that look like they belong to that site.
     - Without `page=`, Point fetches the address itself. That can be any `http` address, including ones only reachable on the local network (a router's admin page, say), and their text goes into the vault, which syncs.
     - Browsers usually ask before opening `point:`, but Chrome's "always allow" is remembered for each site. Once it's ticked for a site, that site can do this silently.
   - **Fix:** clip only after a short confirmation that names the page ("Clip ‘…’ from example.com?"), unless the request is known to come from the extension. Requests could carry a secret the extension and app share, kept in the shared preferences. Separately, refuse private and link-local addresses when Point fetches a page itself.

### Medium

3. **Any text dropped on a sidebar folder is taken as a note or folder to move.**
   - **Where:** the sidebar accepts plain strings from anywhere (`Apps/Mac/SidebarTable.swift:285`, `720-729`) and passes them to `VaultModel.drop` (`Apps/Mac/VaultModel.swift:109-115`).
   - **The problem:** text beginning `point-folder:` goes to `VaultStore.moveFolder` (`Apps/Mac/VaultStore.swift:734-741`). That joins the path onto the vault root without checking that the result is still inside it. `NoteFiles.moveFolder` (`Packages/VaultKit/Sources/VaultKit/NoteFiles.swift:126-129`) checks only that a folder isn't moved into itself.
     - Dragging the text `point-folder:../../Documents` (from a web page or a note) onto a folder would try to move a folder from outside the vault into it.
     - In the sandboxed release build that fails for lack of access.
     - The debug build has no sandbox (`Apps/Mac/Point-Debug.entitlements` is empty), so there it would succeed. This matters if a debug build is ever the one used on the real vault, because it shares the release build's bundle ID.
     - Plain text that happens to match a note's path moves that note.
   - **Fix:** drag sidebar rows as a private pasteboard type, as tabs already are (`TabDrag.pasteboardType`), and accept only drags whose source is Point. In `moveFolder`, check that the folder and its destination both resolve to places inside the vault and that the folder is a known one.

4. **Escape doesn't cancel a tab drag.** *(Read from the code, not tried.)*
   - **Where:** `TabMouseView.draggingSession(_:endedAt:operation:)` (`Apps/Mac/TopBars.swift:1416-1425`) drops the tab wherever the drag ended and ignores `operation`.
   - **The problem:** no view is registered as a drop destination, so AppKit reports every drag as missed, cancelled or not. A drag abandoned with Escape over another tab or a page still reorders tabs or opens a split.
   - **Fix:** look at `NSApp.currentEvent` when the drag ends. If it's Escape (key code 53), drop nothing.

5. **A tab dropped over something drawn on top of the page lands on the page beneath.**
   - **Where:** `TabDropArea.DropView.area(at:)` (`TopBars.swift:1504-1515`) picks the smallest drop area whose rectangle contains the pointer. It doesn't check whether anything in the same window covers that area.
   - **The problem:** dropping a tab over the related-notes panel sliding up from the bottom, the command palette, or a popover drawn in the window still splits or moves into the page underneath.
   - **Fix:** confirm the area is what's actually under the pointer: hit-test the window's frame view at that point and check that the hit view is the area or sits inside the area's own branch. If not, refuse the drop.

6. **The sidebar button is added to the window's private frame view.**
   - **Where:** `placeSidebarButton` (`Apps/Mac/SidebarSplit.swift:218-248`) adds an `NSHostingView` straight into `contentView.superview`, the window's frame view, whenever the sidebar is collapsed.
   - **The problem:** that view belongs to AppKit. Adding views to it is unsupported, has drawn console warnings in past macOS versions, and is the kind of thing a macOS update breaks without notice. Point depends on it on both branches.
   - **Fix:** use a title bar accessory (`NSTitlebarAccessoryViewController`, placed `.leading`) for the resting position. Keep the in-sidebar copy for when it rides the sidebar's edge. Or keep the button in the content view, which already runs under the title bar (full-size content).

7. **On `header-one-row`, the window can only be moved where Point's own bars say.**
   - **Where:** the window is made unmovable (`SidebarSplit.swift:351`), and `WindowDragArea` (`TopBars.swift:1613-1632`) turns moving back on just for its own `performDrag`.
   - **The problem:** this is the fix for tabs dragging the window, and it works: a real-pointer test reordered and split tabs with the window held still. But it has costs:
     - Any part of the title bar strip without a `WindowDragArea` behind it no longer moves the window. That includes the 2-point gaps between tabs, the edges of the tab row, and the strip by the traffic lights.
     - Anything that relies on `isMovable` (window tiling by drag, other apps' window tools) sees an immovable window.
     - The fix depends on `performDrag` still working while `isMovable` is switched on and off around it. That's true today, but not promised.
   - **Fix:** keep it for this experiment. Before it goes to `main`, check:
     - dragging from every part of the bar;
     - window tiling (dragging to a screen edge);
     - Stage Manager.

   The comment on `PaneTabs` (`TopBars.swift:458-460`) still says the scroll view was the cause of the window moving. It wasn't: the window decides at mouse-down, in the window server. Correct the comment, and see the next item.

### Low

8. **The tab row's own scrolling can now go back to a scroll view.**
   - **Where:** the custom row (`TopBars.swift:447-604`): an offset `HStack`, a scroll-wheel monitor and `TabRowScroll`.
   - **The problem:** it was built to get away from `ScrollView`, on the belief that the scroll view was what let the window take tab drags. With the window unmovable (item 7), that reason has gone.
     - The custom row has no elastic edges and no scroll bar, and VoiceOver doesn't see it as scrolling.
     - Its sign was wrong once already. With a monitor per row and a scroll vector worked out by hand, it's easy to get wrong again.
   - **Fix:** try `ScrollView(.horizontal)` with `ScrollViewReader` again, now that the window holds still. Keep the custom row only if a scroll view brings back a problem.

9. **Tab labels are measured afresh on every redraw.**
   - **Where:** `PaneTabs.body` builds a `TabLayout` each time (`TopBars.swift:449-450`).
   - **The problem:** each layout measures every title with AppKit. `TabLabels.fit` (`TopBars.swift:641-669`) compares each tab with every other, with a binary search of text measurements for each, so the work grows with the square of the tab count. `PaneTabs` watches the whole `VaultModel`, so any change the model publishes redoes this for every side. It isn't noticeable with a handful of tabs, but it goes against "no noticeable lag" with many.
   - **Fix:** cache the layout by its titles (a small dictionary in `TabRowScroll` keyed on the titles array), or measure in a `@StateObject` that updates only when the titles change.

10. **Hover in `ClickArea` still uses `visibleRect`.**
    - **Where:** `ClickView.syncHover` (`TopBars.swift:1018`).
    - **The problem:** it checks `bounds.contains && visibleRect.contains`. For views SwiftUI hosts, `visibleRect` has been found to be unreliable (see `TabDropArea.DropView.shownRect`). It's harmless when it comes back too large, but if it came back too small or empty, a button would never shade.
    - **Fix:** drop the `visibleRect` test, as the tabs did.

    `ClickArea` also shows no pressed state: a button gives no feedback between mouse-down and mouse-up.

11. **Some event monitors and observers outlive their window.**
    - **Where:** `SidebarSplitController` adds a mouse-up monitor (`SidebarSplit.swift:165`) and block-based notification observers (`SidebarSplit.swift:355-370`), and never removes them.
    - **The problem:** each window closed leaves a monitor that runs on every mouse-up for the rest of the session, plus observers that stay registered. This is a small leak, but it grows with every window opened and closed.
    - **Fix:** remove both in `viewWillDisappear`, or when the view leaves its window.

12. **An image embed can point outside the vault.**
    - **Where:** `VaultImages.resolve` (`Packages/VaultKit/Sources/VaultKit/VaultImages.swift:206-219`) joins a path from the note onto the vault root, or onto the note's folder, and uses it if a file exists there. It doesn't check that the result is inside the vault.
    - **The problem:** `![](../../../Pictures/x.png)` shows a file from outside the vault, and Open in Preview (`Apps/Mac/PaneView.swift:266`) opens it. The release build's sandbox limits this to files Point has access to anyway. The debug build (no sandbox) reads anything.
    - **Fix:** standardise the path, resolve symbolic links, and require the result to be inside the vault root.

13. **Web images are loaded by default, and in full before their size is checked.**
    - **Default on:** showing a note with web images asks each site for them (`showsWebImages` defaults to on, `Apps/Mac/VaultStore.swift:1293`). That tells the site your IP address and when the note was first opened. Cookies and referrer are already left out, and later views come from the cache, so this is a choice to make knowingly rather than a flaw. Consider defaulting it off for notes that weren't clipped, or asking the first time.
    - **Size check comes too late:** `WebImageCache.load` (`Packages/VaultKit/Sources/VaultKit/WebImageCache.swift:43-53`) and `WebImages.download` (`Packages/VaultKit/Sources/VaultKit/WebImages.swift:259-270`) download the whole response before comparing it with their 30 MB or 50 MB limit, so a server can send far more. Check `expectedContentLength` first, and stream with a running count.

14. **The iPhone keeps earlier versions of notes that have been deleted.**
    - **Where:** `NoteVersions` keeps up to 20 versions of each note in Application Support (`Apps/iOS/PhoneStore.swift:79`, `Apps/iOS/PointPhoneApp.swift:183-186`). Versions follow renames, but nothing removes them when a note is deleted.
    - **The problem:** a note deleted because it was sensitive lives on in the app's storage, and in the phone's iCloud backup, which includes Application Support. There's no way to see or clear them once the note is gone.
    - **Fix:** remove a note's versions when it's deleted for good (or after the trash is emptied). Add a "Clear earlier versions" setting.

15. **Note names go into the system log.**
    - **Where:** `NSLog` calls name the note: `Apps/Mac/EditorSession.swift:277` and many in `VaultStore.swift`, such as `445`, `478` and `542`. `WebImageSaving.swift:56` logs image addresses.
    - **The problem:** `NSLog` text is public in the unified log, so it can be read in Console and is included in diagnostic reports sent to Apple. Note names can be private.
    - **Fix:** use `Logger` with `privacy: .private` for names and addresses.

16. **Notes are rewritten in place, not atomically.**
    - **Where:** `NoteWriter.write` (`Packages/VaultKit/Sources/VaultKit/NoteWriter.swift:71`) writes over the file, so it keeps its creation date, as Obsidian does. This is deliberate and documented.
    - **The problem:** a crash or power loss part-way leaves a short or empty note. iCloud may then sync it before Point opens again.
    - **Fix:** the iPhone's versions and the Mac's drafts make this recoverable on the device that wrote it, and the risk is small. If it's ever seen, writing a temporary file and swapping it in with `FileManager.replaceItemAt` keeps the creation date and is atomic.

17. **On `header-one-row`, a note's "Bookmarked" line is gone.**
    - **Where:** the branch deletes `BookmarkReadout` (`Apps/Mac/RelatedPanel.swift`) and its use under the title (`Apps/Mac/NoteEditor.swift`).
    - **The problem:** bookmarking still works from the menus and the palette, but a bookmarked note no longer says so on the page. The readout came in with the 13 November batch. If this was meant only for the one-row experiment, fine. If not, put it back before merging.

## What's done well

- **Writing notes** (`NoteWriter`): compares with the last read under `NSFileCoordinator`. It never recreates a note that has gone, and never writes over a conflict copy.
- **Links:** web and email links open directly; any other kind asks first, naming the app (`LinkTarget.opensWithoutAsking`, `VaultModel.confirmOpening`). File links resolve only to notes.
- **The clipper:** it parses pages with `DOMParser` in a non-persistent web view, so a page's scripts never run and nothing it refers to loads. Its tests check that `javascript:` addresses are refused.
- **Web images:** an ephemeral session with no cookies and no shared cache, files named by hash, and only real images kept.
- **Sandboxing:** release builds are sandboxed, with access to the vault through a security-scoped bookmark. Debug-only code (`DebugSnapshots`, `Trace`, `-PointVault`) is compiled out of them.
- **Drafts and versions:** a failed save on the Mac keeps a draft outside the vault, and the iPhone keeps earlier versions. Both turn many failures into something recoverable.

## Suggested order

1. Items 1 and 2 together: a size cap and a confirmation for `point://clip`.
2. Item 3: a private drag type for the sidebar, and checks that folder moves stay inside the vault.
3. Before `header-one-row` goes to `main`:
   - items 4 and 5 (tab drop correctness);
   - item 7's checks;
   - item 8 (try a scroll view again);
   - item 17.
4. Items 12, 14 and 15 (privacy) as a small batch.
5. The rest when that code is next touched.
