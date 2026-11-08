# Clip to Point on the iPhone

A Shortcut that puts **Clip to Point** in the share sheet. It hands the page's address to Point, which fetches the page, finds its article and makes a note of your clip kind (Media, if the vault has it) in that kind's folder, from its template: the same as on the Mac.

A share extension would be neater, but it needs a paid developer account. The Shortcut does the same job without one.

## Make the Shortcut

In the Shortcuts app, tap **+** for a new shortcut, name it **Clip to Point**, and add these actions:

1. **Receive** *URLs* and *Safari web pages* **input from** *Share Sheet*. (Tap the shortcut's ⓘ, turn on **Show in Share Sheet**, then tap the input types to leave only these two.) **If there's no input:** *Get Clipboard*.
2. **Get URLs from** *Shortcut Input*.
3. **URL Encode** *URLs*.
4. **Text**: `point://clip?url=` followed by the *URL Encoded Text* variable, with no space between.
5. **Open URLs** *Text*.

## Use

In Safari (or any app that shares links), tap **Share**, then **Clip to Point**. Point opens, says "Clipping “…”…", then opens the new note. The first time, iOS asks whether the Shortcut may open Point: allow it.

A page clipped before opens its note again. Point fetches the page without Safari's sign-ins, so a page behind a login or paywall may give a note with only its link.

## Without the Shortcut

Copy a link, then in Point press and hold **+** and choose **Clip copied link**. iOS asks whether Point may paste from the other app: allow it (or set **Paste from Other Apps** to *Allow* in Settings › Apps › Point).
