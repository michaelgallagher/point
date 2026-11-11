// Clip to Point: sends the page's address, title, any selected text and the page itself, as
// the browser shows it, to Point, which finds its article and makes the note (see
// Packages/ClipKit). Sending the page means a clip has what you can see when signed in, or
// past a paywall you've paid for; Point only fetches the page itself when it isn't sent (a
// link right-clicked, or a page too big to send). Nothing is sent anywhere but to Point, on
// this Mac.

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
  const page = await read(tab);
  if (selection === undefined) selection = page.selection;
  send(tab, { url: tab.url, title: tab.title || "", selection: selection || "", page: await pack(page.html) });
}

// The selection, as text (paragraphs kept apart), and the page's HTML as it is now: what's
// shown when signed in, and anything the page's scripts put there. Left out: what isn't shown
// (other layouts' copies, closed menus), what's only for screen readers ("Image", "Credit"),
// what floats over the page (banners, docks, pop-ups), and scripts (but structured data),
// styles and pictures drawn in code. None of it is the article.
async function read(tab) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const live = Array.from(document.documentElement.querySelectorAll("*"));
        const page = document.documentElement.cloneNode(true);
        const copy = Array.from(page.querySelectorAll("*")); // In the same order as `live`.
        const pageText = (document.body && document.body.innerText.length) || 1;
        const skipped = new Set();
        live.forEach((element, i) => {
          if (skipped.has(element.parentElement) || element.closest("head")) {
            if (skipped.has(element.parentElement)) skipped.add(element);
            return;
          }
          const style = getComputedStyle(element);
          let skip = style.display === "none";
          if (!skip && style.position === "fixed") skip = (element.innerText || "").length < pageText * 0.3;
          if (!skip && style.position === "absolute" && !element.querySelector("img")) {
            const box = element.getBoundingClientRect();
            skip = box.width <= 1 && box.height <= 1 && element.textContent.trim() !== "";
          }
          if (skip) {
            skipped.add(element);
            copy[i].remove();
          }
        });
        const unwanted = 'script:not([type="application/ld+json"]), style, link:not([rel="canonical"]), svg, canvas, noscript, template, iframe';
        for (const node of page.querySelectorAll(unwanted)) node.remove();
        return { selection: String(window.getSelection() || ""), html: "<!doctype html>\n" + page.outerHTML };
      },
    });
    return (result && result.result) || {};
  } catch (e) {
    return {}; // A page extensions can't read, like the web store.
  }
}

// The page, compressed (raw deflate) and in base64url, to fit in the address: a few tens of
// kilobytes for most articles. One too big for the browser to open (2 MB) isn't sent, and
// Point fetches it instead.
async function pack(html) {
  if (!html) return "";
  try {
    const stream = new Blob([html]).stream().pipeThrough(new CompressionStream("deflate-raw"));
    const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    const packed = btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    return packed.length < 1500000 ? packed : "";
  } catch (e) {
    return "";
  }
}

function send(tab, { url, title, selection, page }) {
  const address = new URL("point://clip");
  address.searchParams.set("url", url);
  if (title) address.searchParams.set("title", title);
  // Long selections are cut: they're a quote, not the article.
  if (selection) address.searchParams.set("selection", selection.slice(0, 8000));
  if (page) address.searchParams.set("page", page);
  // Opens Point; the page stays as it is. The browser may ask the first time.
  chrome.tabs.update(tab.id, { url: address.href });
}
