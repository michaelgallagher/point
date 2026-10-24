# Point

A simple, fast, native Markdown notes app for Mac and iPhone that works on an Obsidian vault. See [PLAN.md](PLAN.md).

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

## Layout

- `Apps/Mac` — the Mac app (SwiftUI, deployment target macOS 13)
- `Packages/VaultKit` — vault access: finding, reading and safely writing notes, and remembering the vault folder
- `Packages/MarkdownKit` — the Markdown parser (CommonMark, GFM and Obsidian syntax), with exact positions for every token
- `Packages/EditorKit` — the editor: a TextKit 1 text view that hides Markdown markers and draws lists, quotes and code
- `scripts` — build helpers
