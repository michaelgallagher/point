# Point

A notes app for Mac and iPhone. It's as simple as I could make it without it feeling useless. The Mac app is meant to be used mostly from the command palette. The whole project happened because I *really* hate Obsidian's mobile app. 

Notes are plain Markdown files in folders. The app hides the Markdown formatting garbage, so editing feels like rich text.

It started out compatible with Obsidian and still opens an Obsidian vault. Since November it goes its own way where that's better, but loses nothing critical in Obsidian. It doesn't do everything Obsidian does, so some things won't work (Dataview, for example).

Sync is via iCloud Drive.

What it does:

- **Writing:** an editor with the Markdown hidden (lists, tables, images, links, properties), and a raw-source view for emergencies.
- **Finding:** search that learns which notes you open, links, tags, folders, and a command palette for everything.
- **Kinds of note:** meetings, people, projects and so on, each with its own folder, template and properties.
- **Related notes:** under each note's title, the notes that share its people or topics, and the notes that link to it, grouped by how.
- **Clipping:** a browser extension and an iPhone Shortcut that turn a web page into a note.
- **Reading:** on the iPhone, clips open in a reader mode. You can highlight passages, quote them into your notes on the article, and keep the notes above it.

Where it's going is in [PLAN.md](PLAN.md), and the documents in [`plan/`](plan/) explain how each part came to be the way it is.

## Building

You need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is made from `project.yml` and isn't checked in:

```bash
xcodegen && open Point.xcodeproj
```

**The Mac:** run the `Point-Mac` scheme. It runs on macOS 13 or later. Debug builds aren't sandboxed, so they can open a vault by its path instead of the folder picker: add `-PointVault ~/path/to/vault` to the scheme's launch arguments.

**The iPhone:** run the `Point-iOS` scheme on an iPhone with iOS 26. First, set `DEVELOPMENT_TEAM` in `project.yml` to your own team ID and run `xcodegen` again. On a free Apple account, a build stops opening after 7 days and has to be installed again. On first launch, Point uses a folder of its own. To use your vault in iCloud Drive instead, choose its folder in Files.

### A build for another Mac

```bash
./scripts/build-mac.sh
```

This writes `build/Point.app`, a universal app (Apple Silicon and Intel) for macOS 13 or later, and `build/Point.zip` for copying. It's signed ad hoc, so on the other Mac, right-click it and choose Open the first time.

### Tests

Each package has its own tests. Run them from the package's folder:

```bash
cd Packages/VaultKit && swift test
```

Do the same for `MarkdownKit`, `EditorKit`, `IndexKit` and `ClipKit`.

There are also a few checks you turn on by hand:

- **Round trip** (EditorKit) opens every note in a vault in the editor and confirms nothing changes. It only reads files, never writes:

  ```bash
  cd Packages/EditorKit && IMPRINT_ROUNDTRIP_VAULT=~/path/to/vault swift test -c release --filter VaultRoundTripTests
  ```

- **Snapshots** (EditorKit): `IMPRINT_SNAPSHOT_DIR` and `IMPRINT_SNAPSHOT_NOTE` render a note to light and dark PNGs (`SnapshotTests`).
- **A live clip** (ClipKit): `POINT_CLIP_URL=… swift test --filter LiveClipTests` clips a real page.
- **Reader mode on a copy of a vault** (ClipKit, then EditorKit) tries reader mode's writes on every clip, in memory. It never writes to the notes, but run it on a copy anyway. `POINT_AUDIT_REPORT` names where each report goes. The first check saves the notes, quotes and cleared notes and confirms nothing else changes. It also writes the list of clips that the second check needs:

  ```bash
  cd Packages/ClipKit && POINT_AUDIT_COPY=~/path/to/copy POINT_AUDIT_CLIPS=/tmp/clips.txt swift test --filter ReaderNotesAudit
  ```

  The second highlights random selections in each clip, and confirms that only highlight markers change and that taking them off again leaves the text as it was:

  ```bash
  cd Packages/EditorKit && POINT_AUDIT_COPY=~/path/to/copy POINT_AUDIT_CLIPS=/tmp/clips.txt swift test --filter HighlightingAudit
  ```

### Keeping an eye on a real vault

`scripts/vault-snapshot.sh` keeps a copy of a vault outside it, and shows exactly what has changed since. That's useful when trying a new build on notes you care about:

```bash
POINT_VAULT=~/path/to/vault scripts/vault-snapshot.sh take
```

```bash
POINT_VAULT=~/path/to/vault scripts/vault-snapshot.sh changes
```

### The clipper

- **Browsers:** an extension for Chrome, Dia and other Chromium browsers. Its README has the steps to load it: [`Clipper/Chrome`](Clipper/Chrome/README.md).
- **iPhone:** a share-sheet Shortcut. Its README has the steps to make it: [`Clipper/iPhone`](Clipper/iPhone/README.md).

Both send the page to Point as a `point://clip` link, and Point does the clipping.

### App icons

The app's own icon is `Resources/AppIcon.icon`, made in Icon Composer. The other icons offered in Settings › App Icon are in `Resources/AppIcons`. To add one:

1. Make it in Icon Composer, or copy an existing `.icon` and change it. Save it in `Resources/AppIcons` as, say, `Dusk.icon`.
2. In `project.yml`, list it with the others in the app's sources, and add its name to `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
3. Add it to `AppIconOptions.all` (`Apps/Shared/AppIconOptions.swift`), with the name Settings shows.
4. Run `xcodegen` and build.

The chosen icon shows in the Dock while Point runs. It also shows while Point isn't running, through the Dock tile plug-in (`Apps/DockTile`), if Point is kept in the Dock. Finder and Launchpad always show `AppIcon`, because changing the app's own icon would mean changing its files, which breaks its signature.

## Layout

- `Apps/Mac`: the Mac app (SwiftUI and AppKit)
- `Apps/iOS`: the iPhone app (SwiftUI and UIKit)
- `Apps/Shared`: code both apps use
- `Apps/DockTile`: the Dock tile plug-in, which shows the chosen icon while Point isn't running
- `Packages/VaultKit`: the vault: finding, reading and safely writing notes, drafts, conflicts, and notes renamed or moved elsewhere
- `Packages/MarkdownKit`: the Markdown parser (CommonMark, GFM and Obsidian syntax), with exact positions for every part of a note
- `Packages/EditorKit`: the editor, a TextKit 1 text view that hides the Markdown and draws lists, quotes, tables and code
- `Packages/IndexKit`: the search index, and what's needed for related notes, links and kinds
- `Packages/ClipKit`: turns a web page into a note
- `Clipper`: the browser extension and the iPhone Shortcut
- `plan`: how each part was designed and built, and what's next
- `scripts`: the Mac build, and vault snapshots
