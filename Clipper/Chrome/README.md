# Clip to Point

A browser extension for Dia, Chrome and other Chromium browsers. It clips the page you're reading into Point: Point fetches the page, finds its article and makes a note of your clip kind (Media, if the vault has it) in that kind's folder, from its template.

## Install

1. In the browser, open `chrome://extensions` (in Dia, `dia://extensions`).
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this folder (`Clipper/Chrome`).

Point needs to be installed (it opens `point://clip` links). The first time, the browser asks whether to open Point: allow it, and tick the box to always allow it.

## Use

- Click the extension's button, or press **⌥⇧P** (change it at `chrome://extensions/shortcuts`).
- Select text first to keep it as a quote at the top of the note.
- Right-click a link and choose **Clip to Point** to clip the page it goes to.

A page clipped before opens its note again. Point fetches the page without the browser's sign-ins, so a page behind a login or paywall may give a note with only its link.
