# Point

A Markdown-based notes app for Mac and iPhone. 

It is as simple as I could make it without it feeling useless. 

Notes are Markdown under the hood, but the interface hides all the formatting garbage. 

It is, currently, backward compatible with Obsidian. That might not persist. It doesn't have all of Obsidian's features though, so some stuff will definitely not work (e.g. dataview). 

The Mac app is working decently well. There will be an iOS version soon. I think. 

Sync happens via iCloud Drive. 

See [PLAN.md](PLAN.md).

## Building

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and is not checked in.

```bash
xcodegen && open Point.xcodeproj
```

Run the `Point-Mac` scheme. Debug builds aren't sandboxed, so they can open a vault by path, skipping the folder picker. Add `-PointVault ~/path/to/vault` to the scheme's launch arguments.

Tests for the shared code (run each from its package folder):

```bash
cd Packages/VaultKit && swift test
```

```bash
cd Packages/MarkdownKit && swift test
```

```bash
cd Packages/EditorKit && swift test
```

EditorKit also has two opt-in checks. The round-trip check opens every note in a vault in the editor and confirms nothing changes. It only reads files and never writes:

```bash
cd Packages/EditorKit && IMPRINT_ROUNDTRIP_VAULT=~/path/to/vault swift test -c release --filter VaultRoundTripTests
```

`IMPRINT_SNAPSHOT_DIR` and `IMPRINT_SNAPSHOT_NOTE` render a note to light and dark PNGs (`SnapshotTests`).

### A build for another Mac

```bash
./scripts/build-mac.sh
```

This writes a universal (Apple Silicon and Intel) app that runs on macOS 13 or later to `build/Point.app`, plus `build/Point.zip` for copying. The app is signed ad hoc, so on the other Mac right-click it and choose Open the first time.

### App icons

The app's own icon is `Resources/AppIcon.icon`, made in Icon Composer. The others offered in Settings › App Icon are in `Resources/AppIcons`. To add one:

1. Make it in Icon Composer (or copy an existing `.icon` and change it), and save it in `Resources/AppIcons` as, say, `Dusk.icon`.
2. In `project.yml`, list it with the others in the app's sources, and add its name to `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
3. Add it to `AppIconOptions.all` (`Apps/Shared/AppIconOptions.swift`), with the name Settings shows.
4. Run `xcodegen` and build.

The chosen icon shows in the Dock while Point runs, and, through the Dock tile plug-in (`Apps/DockTile`), while it isn't, if Point is kept in the Dock. Finder and Launchpad always show `AppIcon`: changing the app's own icon would mean changing its files, which breaks its signature. `Ink` and `Sage` are placeholders, the main icon on other backgrounds.

## Layout

- `Apps/Mac` — the Mac app (SwiftUI, deployment target macOS 13)
- `Apps/DockTile` — the Dock tile plug-in, which shows the chosen app icon while Point isn't running
- `Apps/Shared` — code used by both
- `Packages/VaultKit` — vault access: finding, reading and safely writing notes, and remembering the vault folder
- `Packages/MarkdownKit` — the Markdown parser (CommonMark, GFM and Obsidian syntax), with exact positions for every token
- `Packages/EditorKit` — the editor: a TextKit 1 text view that hides Markdown markers and draws lists, quotes and code
- `scripts` — build helpers
