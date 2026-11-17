# Clip to Point

A browser extension for Dia, Chrome and other Chromium browsers. It clips the page you're reading into Point: Point fetches the page, finds its article and makes a note of your clip kind (Media, if the vault has it) in that kind's folder, from its template.

## Install

1. In the browser, open `chrome://extensions` (in Dia, `dia://extensions`).
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this folder (`Clipper/Chrome`).

Point needs to be installed (it opens `point://clip` links). The first time, the browser asks whether to open Point: allow it, and tick the box to always allow it.

Then give the clipper its key: in Point, open Settings › Notes and click **Copy** beside **Clipper key**; in the browser, right-click the extension's button, choose **Options**, and paste it. Any page or app can open a `point://clip` link, so Point asks before a clip that comes without the key, and reads that page itself rather than taking what was sent. **New key** in Point's settings stops the old one working: paste the new one in again.

## Use

- Click the extension's button, or press **⌥⇧P** (change it at `chrome://extensions/shortcuts`).
- Select text first to keep it as a quote at the top of the note.
- Right-click a link and choose **Clip to Point** to clip the page it goes to.

A page clipped before opens its note again. The extension sends the page as you see it, so a page you're signed in to (or past a paywall you've paid for) is clipped whole. A link right-clicked is fetched by Point, without the browser's sign-ins, so a page behind a login may give only what's public, or a note with only its link.

After updating the extension's files, click its reload button on the extensions page.
