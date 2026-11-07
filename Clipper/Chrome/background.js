// Clip to Point: sends the page's address, title and any selected text to Point, which
// fetches the page and makes the note itself (see Packages/ClipKit). Nothing is read from
// the page but its selection, and nothing is sent anywhere but to Point, on this Mac.

chrome.action.onClicked.addListener((tab) => clip(tab));

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: "clip", title: "Clip to Point", contexts: ["page", "selection", "link"] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  // A link right-clicked is clipped, not the page it's on.
  if (info.linkUrl) return send(tab, { url: info.linkUrl, title: info.selectionText || "" });
  clip(tab, info.selectionText);
});

async function clip(tab, selection) {
  if (!tab || !/^https?:/.test(tab.url || "")) return;
  if (selection === undefined) selection = await selectedText(tab);
  send(tab, { url: tab.url, title: tab.title || "", selection: selection || "" });
}

// The selection, as text: paragraphs kept apart.
async function selectedText(tab) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => String(window.getSelection() || ""),
    });
    return (result && result.result) || "";
  } catch (e) {
    return ""; // A page extensions can't read, like the web store.
  }
}

function send(tab, { url, title, selection }) {
  const address = new URL("point://clip");
  address.searchParams.set("url", url);
  if (title) address.searchParams.set("title", title);
  // Long selections are cut, so the address stays one macOS will open.
  if (selection) address.searchParams.set("selection", selection.slice(0, 8000));
  // Opens Point; the page stays as it is. The browser may ask the first time.
  chrome.tabs.update(tab.id, { url: address.href });
}
