# Point code review — 27 October 2026

## Scope and assessment

Reviewed the current Mac app, VaultKit, IndexKit, MarkdownKit and EditorKit source,
their relevant tests, build configuration, and the earlier vault-safety audit. This
is a source review, not a live-vault, iCloud conflict, fault-injection, or measured
performance test. Line numbers below refer to this checkout. The previous
`app-review-2026-10-25.md` concerns UI changes; this review concentrates on
architecture, security, stability, note safety, and performance.

**Overall:** The package boundaries are sensible. Plain Markdown is the source
of truth, the SQLite search index is disposable and outside the vault, reads
reject non-UTF-8 files, writes normally compare against the last-read contents,
and release builds are sandboxed. There are also unusually useful round-trip
and copy-of-vault audits. The biggest remaining concern is not the normal edit
path but failure handling: operations sometimes discard their only in-memory
copy of an edit, release an editor before knowing a move succeeded, or
permanently remove conflict/trash copies without confirming they are safe.
Treat the app as a preview, with independent vault snapshots, until the
high-priority paths below have fault-injection coverage.

## Findings, in priority order

### High — note safety and correctness

1. **A failed save can lose edits without a visible warning.**
   `EditorSession.save` cancels its pending save, logs a write error only to
   `NSLog`, and returns without preserving the unsaved text
   (`Apps/Mac/EditorSession.swift:189-207`). `NoteEditor` calls this on
   disappearance (`Apps/Mac/NoteEditor.swift:48-52`); closing a tab or window
   can then destroy the editor. `releaseFile` also sets `isReleased = true`
   even when that save failed (`EditorSession.swift:210-215`), preventing later
   writes from the still-visible editor. **Fix:** make save success/failure an
   explicit result, display a persistent error, retain a recoverable draft, and
   block destructive navigation/release until the text has been safely stored.

2. **Rename/move failures leave an editor permanently unable to save.**
   `VaultStore.rename`, `move`, and `moveToTrash` notify sessions to release
   *before* attempting the filesystem operation
   (`Apps/Mac/VaultStore.swift:233-247,267-278,357-365`). Even an ordinary
   "name already taken" rename fails after `isReleased` has been set; continued
   edits in the open note will not save. `finishUntitledNote` likewise releases
   before a rename that can fail (`VaultStore.swift:214-225`). **Fix:** separate
   a verified flush from committing release, and restore the active session on
   failure; cover destination collisions and I/O errors in app-level tests.

3. **The compare-and-write guard is bypassed if reading the original fails.**
   `NoteWriter.write` does the expected-content comparison only inside
   `if let onDisk = try? Data(contentsOf: url)` and writes to `url` anyway on
   a read error or a missing file
   (`Packages/VaultKit/Sources/VaultKit/NoteWriter.swift:25-41`). Thus an
   externally deleted note can be silently recreated, and the writer cannot
   distinguish "safe to save" from "could not verify." It also writes in
   place without an atomic replacement: a write interruption can leave a
   truncated file. **Fix:** fail closed on read errors/missing originals;
   coordinate a checked replacement that preserves required metadata, and
   test deletion, permissions, and interrupted writes. An atomic replacement
   needs deliberate creation-date and iCloud coordination handling.

4. **Conflict copies can overwrite one another.** Their name has only
   second-level precision, and both the normal conflict path and the iCloud
   "Keep Both" path use ordinary `Data.write`, not exclusive creation
   (`NoteWriter.swift:35-36,48-55`;
   `Apps/Mac/EditorSession.swift:381-386`). Two saves of the same note in
   one second can replace the earlier recovery copy. **Fix:** allocate a
   unique filename and create it without overwriting; test same-second
   conflicts from more than one window.

5. **Choosing an iCloud conflict version can discard unsaved typing or
   unselected versions.** `useOtherVersion` replaces the file, resolves every
   unresolved version, then asynchronously reloads the editor without saving
   its current text (`EditorSession.swift:365-375,392-398`). `keepBothVersions`
   copies only the first version, but `resolveICloudConflicts` marks *all*
   versions resolved and removes them, ignoring the removal error
   (`EditorSession.swift:381-398`). **Fix:** freeze/flush an edited draft
   before any resolution, enumerate all versions, only mark versions resolved
   after their retention is verified, and surface errors. This path was not
   exercised against a real iCloud conflict in this review.

6. **Finishing an untitled note treats a read failure as an empty note.**
   After a save request, `finishUntitledNote` substitutes `""` when
   `NoteReader.read` throws, then attempts to delete the file and removes it
   from the visible list (`VaultStore.swift:208-219`). This can lose a newly
   typed note if saving failed or the file temporarily became unavailable;
   even a failed deletion is suppressed. **Fix:** require a successful flush
   and read before testing emptiness; on failure leave the note and its editor
   intact and report the error.

7. **Trash operations have destructive side effects before success is known.**
   `VaultModel.moveToTrash` blanks the tab and history even if
   `VaultStore.moveToTrash` failed (`Apps/Mac/VaultModel.swift:91-101`).
   Separately, simply opening/refreshing trash permanently deletes notes
   after 30 days by default, including notes first discovered there from
   Obsidian; deletion errors are ignored and records dropped
   (`VaultStore.swift:284-327`). `emptyTrash` also suppresses each deletion
   failure (`VaultStore.swift:352-355`). **Fix:** return success before
   clearing a tab; distinguish Point-owned from externally placed trash;
   make automatic permanent deletion an explicit, clearly disclosed policy
   or opt-in, and keep failed items and errors visible.

### Medium — architecture and stability

8. **Overlapping scans can publish results for the wrong vault or in the wrong
   order.** Every watcher event starts a new untracked `reload` task. It
   captures a root, awaits a detached scan, then updates the shared store
   without checking that the root or scan generation is still current
   (`VaultStore.swift:87-100,125-150`). Opening vault B while A's scan is
   running can publish A's notes in B's window and schedule those notes
   against B's index. Even within one vault, an older scan can finish last.
   **Fix:** generation-token the vault and scan, coalesce changes, and
   discard stale results before publishing or indexing.

9. **Transient read errors can permanently remove notes from search until
   their modification date changes.** `SearchIndex.update` uses only mtime
   to decide whether to re-read a note, turns a read failure into `nil`,
   inserts an empty body with the same mtime, and considers the note
   up-to-date thereafter
   (`Packages/IndexKit/Sources/IndexKit/SearchIndex.swift:101-125,145-161`).
   Tags read for the sidebar have the same empty-on-failure/mark-as-read
   pattern (`VaultStore.swift:638-655`). **Fix:** retain the previous index
   entry on read failure and retry later; use a content fingerprint or other
   validation where mtime alone is insufficient. Report index errors rather
   than converting them to a successful zero-change update
   (`VaultStore.swift:697-709`).

10. **Settings writes can erase an unreadable or malformed Obsidian settings
    file.** `ObsidianSettings.set` substitutes an empty dictionary for either
    a missing file or any parse/read error, then atomically writes it over the
    existing file (`Packages/VaultKit/Sources/VaultKit/ObsidianSettings.swift:123-130`).
    `PropertyTypes.save` follows the same pattern for `types.json`
    (`Packages/VaultKit/Sources/VaultKit/PropertyTypes.swift:145-153`).
    **Fix:** distinguish missing from invalid/inaccessible, refuse to overwrite
    the latter, and compare with the version read before writing when
    cooperating with Obsidian.

11. **File watching has silent blind spots.** `VaultWatcher` discards every
    event whose *absolute path* contains a dot-prefixed component, so a valid
    vault nested under a hidden directory never receives note change
    notifications (`Packages/VaultKit/Sources/VaultKit/VaultWatcher.swift:25-29`).
    It does not check whether `FSEventStreamStart` succeeds or act on dropped/
    must-rescan event flags (`VaultWatcher.swift:25-40`). **Fix:** filter
    components relative to the vault root, verify stream startup, and
    trigger a full rescan on dropped events or wake/reconnection.

### Security and performance

12. **External links accept arbitrary non-file URL schemes.**
    `MarkdownTextView.link` categorizes any scheme except `file` as a web
    target; clicking passes it to `NSWorkspace.shared.open`
    (`Packages/EditorKit/Sources/EditorKit/MarkdownTextView+Links.swift:20-30`;
    `Apps/Mac/VaultModel.swift:889-890`). This is user-initiated, not
    automatic code execution, but a note obtained from another source can
    invoke a registered custom-protocol handler on click. **Fix:** allow
    expected schemes (for example HTTPS, HTTP, and mailto), and require
    confirmation for other schemes. Release is sandboxed by
    `Apps/Mac/Point.entitlements`; the intentionally unsandboxed Debug
    configuration (`project.yml:51-55`) should not be distributed as a
    production build.

13. **Each edit reparses the entire note, and the sidebar refreshes all
    rows.** `MarkdownTextView.textStorage` calls
    `MarkdownParser.parse(textStorage.string)` on every character edit
    (`Packages/EditorKit/Sources/EditorKit/MarkdownTextView.swift:427-453`).
    Even when the sidebar's row identities are unchanged, its coordinator
    measures and reloads every row (`Apps/Mac/SidebarTable.swift:206-229`).
    This is linear in note length and visible-list size per update, with
    possible extra restyling; responsiveness of very long notes and large
    lists is not established by the current round-trip audits. **Fix:**
    profile large notes and vaults, then incrementally parse the edited
    region and reload only affected rows if measurements warrant it.

14. **Backlink work is repeated on unrelated file changes.** Every open
    `Connections` listens to all file events and, after a fixed delay,
    performs backlink and mention queries
    (`Apps/Mac/LinksButton.swift:14-37`). Those queries re-read and parse
    candidate note files (`SearchIndex.swift:310-348`), so more visible editor
    panes/windows multiply background I/O after each edit. **Fix:** refresh on completion
    of the index update, filter by affected note/link relationships where
    possible, and cache candidate parsing. Measure before optimizing.

15. **Search has additional vault-size work on each query.**
    `SearchIndex.search` scores and sorts every in-memory title before
    returning at most 50 results and typo correction scans all vocabulary
    terms sharing a first letter when needed
    (`SearchIndex.swift:203-207,237-255`). This is acceptable for smaller
    vaults but may make interactive search latency grow with title and
    vocabulary counts. The existing opt-in `VaultIndexBenchmark` is a good
    starting point; record p50/p95 latencies on representative vault sizes
    before choosing a title-prefix or vocabulary-candidate index.

## Suggested order

1. Make saves observable and recoverable, then repair release/rename/trash
   ordering (findings 1, 2, 6, 7).
2. Make checked writes and conflict-copy creation fail closed; exercise
   iCloud resolution with multiple versions (3, 4, 5).
3. Add generation/cancellation to scans and preserve the last good index
   result on transient failures (8, 9, 11).
4. Harden settings and external-link handling (10, 12).
5. Run long-note and many-pane/vault benchmarks before performance refactors
   (13-15).

The existing tests cover successful read/write, no-op byte round-trips,
renames, links, and a watcher happy path. Missing coverage is concentrated
in failed writes, failed moves, deleted originals, conflict-name collisions,
multiple unresolved iCloud versions, overlapping scans, and read failures
while indexing. No live notes were modified for this review.
