# Architecture and risks

Part of [the plan](../PLAN.md).

# Architecture

```
Point.xcodeproj
├─ Point (macOS app, deployment target 13.0)
├─ Point (iOS app, 26.0)            + share extension, controls/intents, watchOS app
└─ Packages/
   ├─ VaultKit     folder access, file watching/coordination, Obsidian settings,
   │               note model, wiki-link resolution, rename-with-link-update
   ├─ MarkdownKit  fast, lossless, incremental parser (CommonMark + GFM + Obsidian
   │               extensions: wiki links, embeds, tags, callouts, highlights,
   │               frontmatter, block ids) producing ranges for styling
   ├─ IndexKit     SQLite (GRDB): FTS5 with porter (word forms) and trigram (partial words)
   │               tables, fuzzy title matching, tags, links, backlinks; per-device,
   │               stored outside the vault; incremental by modification time + hash
   ├─ EditorKit    the text view: AppKit on Mac, UIKit on iOS, sharing styling logic
   └─ InsightKit   embeddings, related notes, tag suggestions, digests
                   (only active on macOS 26 / iOS 26)
```

- **UI:** SwiftUI shell (split view on Mac, navigation stack on iPhone) with the editor wrapped from AppKit or UIKit.
- **macOS 13 support:** SwiftUI is limited to macOS 13 APIs, using `ObservableObject` instead of `@Observable`. Newer features are gated with `#available`.
- **Text engine:** TextKit 1 (decided in M1). It is mature on macOS 13, and its glyph-generation hook hides Markdown markers cleanly while the text stays exactly as on disk. Still to confirm on the 2017 Mac.
- **Parser:** our own. Off-the-shelf parsers don't round-trip losslessly or know Obsidian syntax, and the editor needs exact ranges for every token.


# Risks

1. **The editor.** Hiding syntax while keeping cursor movement, selection, undo and IME input natural is the hardest part. That's why M1 is first and isolated.
2. **iCloud Drive without an entitlement.** Files can be evicted, show up as placeholders, or arrive as conflict versions. We need to trigger downloads and coordinate reads and writes. Test early in M2.
3. **Concurrent Obsidian edits.** Both apps may write the same file. Use file coordination and reload, and never overwrite a newer version blindly.
4. **macOS 13.** TextKit and SwiftUI are older. Mitigation: test on the 2017 Mac at every milestone, and accept a simpler experience there.
5. **On-device model quality.** Foundation Models is small, so digests may be shallow. Mitigation: keep prompts narrow, and lean on embeddings and statistics for topics and clusters.
6. **Digests depend on the M3.** They're only generated when the M3 is awake and running the app. Mitigation: generate on launch for any missed weeks.
