# The clipper (7 November 2026, branch `clipper`)

Part of [the plan](../PLAN.md).

**Why:** articles worth keeping are read in the browser, and copying one into a note by hand (its text, title, author, address) is work enough that it doesn't happen. A clip should be one click, and give a note as well formed as one written by hand, of the right kind.

**Decided:** Point does the clipping, not the browser. The extension only sends the page's address, its title and any selected text, as `point://clip?url=…&title=…&selection=…`. Point fetches the page itself and finds its article in a web view no one sees, where the page is only parsed: its own scripts never run and nothing it refers to is loaded. That keeps the extension tiny (and the same for any browser, or the iPhone's share sheet later), and the clipping tested in Swift. The cost: Point fetches without the browser's sign-ins, so a page behind a login or a paywall may give a note with only its link.

**Built:**
- **ClipKit** (a new package): `ClipExtractor` fetches the page and runs Mozilla's Readability (finds the article) and Turndown with its GFM plugin (writes it as Markdown) in a hidden `WKWebView`, both bundled with their licences (`THIRD-PARTY-LICENSES.txt`). `clip.js` adds what pages say about themselves: authors and the publication date from structured data and meta tags, the site's name. Swift then tidies it: the site's name off the end of the title, tracking parameters (`utm_…`, `fbclid`) off the address, bylines into names, and the Markdown as Point writes it (`- ` and `1. ` lists, no soft hyphens, stray indents, trailing spaces or runs of empty lines).
- **The note** (`ClipNote`): the clip kind's first template, filled in: `title`, `author` (as links to people), `published` (if known), `format` (Article, or Video for YouTube and Vimeo), `source` and `saved`, with `type` set to the kind unless the template sets one. Selected text comes first, as a quote, then the template's own text, then the article.
- **The Mac:** opens `point://clip` links (without opening a window). The clip kind is the one named Media (or Clipping, Clip, Web clip, Article); its folder and template are used, else a `Clippings` folder. The new note opens in a new tab, as a dated note with its title. A page clipped before (the same `source`) opens its note instead. A notice says what's happening: "Clipping “…”…", then "Clipped to Clippings", "Clipped before", or "Couldn't read the page, so the note has its link". The app can now reach the network (`com.apple.security.network.client`), to fetch pages.
- **The extension** (`Clipper/Chrome`, for Dia, Chrome and other Chromium browsers; loaded unpacked, see its README): its button or ⌥⇧P clips the page; selected text is kept as a quote; right-clicking a link clips the page it goes to.

**Tried:** `ClipTests` (filling the Media template, no template, a template that sets its own type, clip addresses, bylines, dates and addresses, tidying Markdown, extracting an article with nested and numbered lists). A live clip of a real blog post (`POINT_CLIP_URL=… swift test --filter LiveClipTests` in `Packages/ClipKit`).

**Not tried:** the Mac app end to end, from the browser (it builds; running a second copy beside Mike's would share its settings). Dia itself: whether it asks before opening Point, and whether the shortcut is free.

**Next:**
- **The iPhone's share sheet.** A share extension can't write to the vault itself (that needs an App Group, so a paid developer account); instead it can hand the address to Point by opening `point://clip`, or Point can offer Clip from the clipboard. To decide with Mike.
- Maybe: a choice of kind or folder when clipping, and the page's description as a property.
