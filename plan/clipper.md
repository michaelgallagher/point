# The clipper (7 November 2026, branch `clipper`, merged; the iPhone side 8 November)

Part of [the plan](../PLAN.md).

**Why:** articles worth keeping are read in the browser, and copying one into a note by hand (its text, title, author, address) is work enough that it doesn't happen. A clip should be one click, and give a note as well formed as one written by hand, of the right kind.

**Decided:** Point does the clipping, not the browser. The extension only sends the page's address, its title and any selected text, as `point://clip?url=…&title=…&selection=…`. Point fetches the page itself and finds its article in a web view no one sees, where the page is only parsed: its own scripts never run and nothing it refers to is loaded. That keeps the extension tiny (and the same for any browser, or the iPhone's share sheet later), and the clipping tested in Swift. The cost: Point fetches without the browser's sign-ins, so a page behind a login or a paywall may give a note with only its link.

**Built:**
- **ClipKit** (a new package): `ClipExtractor` fetches the page and runs Mozilla's Readability (finds the article) and Turndown with its GFM plugin (writes it as Markdown) in a hidden `WKWebView`, both bundled with their licences (`THIRD-PARTY-LICENSES.txt`). `clip.js` adds what pages say about themselves: authors and the publication date from structured data and meta tags, the site's name. Swift then tidies it: the site's name off the end of the title, tracking parameters (`utm_…`, `fbclid`) off the address, bylines into names, and the Markdown as Point writes it (`- ` and `1. ` lists, no soft hyphens, stray indents, trailing spaces or runs of empty lines).
- **The note** (`ClipNote`): the clip kind's first template, filled in: `title`, `author` (as links to people), `published` (if known), `format` (Article, or Video for YouTube and Vimeo), `source` and `saved`, with `type` set to the kind unless the template sets one. Selected text comes first, as a quote, then the template's own text, then the article.
- **The Mac:** opens `point://clip` links (without opening a window). The clip kind is the one named Media (or Clipping, Clip, Web clip, Article); its folder and template are used, else a `Clippings` folder. The new note opens in a new tab, as a dated note with its title. A page clipped before (the same `source`) opens its note instead. A notice says what's happening: "Clipping “…”…", then "Clipped to Clippings", "Clipped before", or "Couldn't read the page, so the note has its link". The app can now reach the network (`com.apple.security.network.client`), to fetch pages.
- **Shared by both apps** (`Clipping`, in ClipKit): which kind clips are, reading the page or settling for its link, how a page clipped before is recognised, and the note's title and text. Each app makes the note and shows how it went in its own way. ClipKit's scripts are in `Scripts`, not `Resources`: an iOS bundle can't have a top-level folder of that name (signing fails).
- **The iPhone:** opens `point://clip` links the same way, with a capsule above the search bar saying how it's going, then opens the new note. A share-sheet Shortcut sends them (`Clipper/iPhone`, which has the steps). Pressing and holding **+** offers **Clip copied link** too, for a link copied anywhere.
- **The extension** (`Clipper/Chrome`, for Dia, Chrome and other Chromium browsers; loaded unpacked, see its README): its button or ⌥⇧P clips the page; selected text is kept as a quote; right-clicking a link clips the page it goes to.

**Tried:** `ClipTests` (filling the Media template, no template, a template that sets its own type, clip addresses, bylines, dates and addresses, tidying Markdown, extracting an article with nested and numbered lists). A live clip of a real blog post (`POINT_CLIP_URL=… swift test --filter LiveClipTests` in `Packages/ClipKit`).

On the iPhone, in the Simulator: a `point://clip` link, with Point open and with it closed, made a Media-less vault's note in `Clippings` with its title, author, published, format, source and saved; the same page again, with `utm_` parameters added, opened that note ("Clipped before").

**Not tried:** the Mac app end to end, from the browser (it builds; running a second copy beside Mike's would share its settings). Dia itself: whether it asks before opening Point, and whether the shortcut is free. The Shortcut itself (the Simulator has no Shortcuts app) and a real iPhone. **Clip copied link** with a link on the clipboard: the Simulator can't show iOS's "Allow paste" prompt and refuses the paste, so it only says "No link copied"; on an iPhone the prompt should appear.

**Next:**
- **Mike to try:** the Shortcut and Clip copied link on his iPhone.
- **A share extension**, once there's a paid developer account: Clip to Point in the share sheet without making a Shortcut, and clipping without leaving Safari.
- If Allow paste is refused, say so rather than "No link copied".
- Maybe: a choice of kind or folder when clipping, and the page's description as a property.
