# Imprint

A simple, fast, native Markdown notes app for Mac and iPhone that works on an Obsidian vault. See [PLAN.md](PLAN.md).

## Building

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and is not checked in.

```bash
xcodegen && open Imprint.xcodeproj
```

Run the `Imprint-Mac` scheme. Tests for the shared code:

```bash
cd Packages/VaultKit && swift test
```

### A build for another Mac

```bash
./scripts/build-mac.sh
```

This writes a universal (Apple Silicon and Intel) app that runs on macOS 13 or later to `build/Imprint.app`, plus `build/Imprint.zip` for copying. The app is signed ad hoc, so on the other Mac right-click it and choose Open the first time.

## Layout

- `Apps/Mac` — the Mac app (SwiftUI, deployment target macOS 13)
- `Packages/VaultKit` — vault access: finding notes, reading them, remembering the vault folder
- `scripts` — build helpers
