// Point's clipper: a page's HTML in, its article out, as Markdown with what's known about it.
// Runs in a blank page after Readability.js, turndown.js and turndown-plugin-gfm.js. The page
// is only parsed (DOMParser), so its own scripts never run and nothing it refers to is loaded.
function pointClip(html, url) {
  const doc = new DOMParser().parseFromString(html, "text/html");
  // Relative links and images resolve against the page's address.
  if (!doc.querySelector("base[href]")) {
    const base = doc.createElement("base");
    base.href = url;
    (doc.head || doc.documentElement).prepend(base);
  }

  const meta = (selector) => {
    const value = doc.querySelector(selector)?.getAttribute("content");
    return value && value.trim() ? value.trim() : null;
  };

  // Structured data, where a page gives it: the article's authors and date.
  let ld = {};
  for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      const parsed = JSON.parse(script.textContent);
      const items = [].concat(parsed["@graph"] || parsed);
      const article = items.find((item) => item && /Article|BlogPosting|NewsArticle|Report/.test([].concat(item["@type"]).join(" ")));
      if (article) { ld = article; break; }
    } catch (e) {}
  }
  const ldAuthors = [].concat(ld.author || []).map((a) => (typeof a === "string" ? a : a && a.name)).filter(Boolean);

  const metaAuthor = meta('meta[name="author"]') || meta('meta[property="author"]');
  const published = ld.datePublished || meta('meta[property="article:published_time"]') ||
    meta('meta[name="date"]') || meta('meta[name="dc.date"]') || meta('meta[itemprop="datePublished"]') ||
    doc.querySelector("time[datetime]")?.getAttribute("datetime") || null;

  // Headings as the article has them. Readability drops anything whose class or id sounds
  // like the page around the article ("header", "comment", "share"…), and some sites give
  // their headings such names (Substack's are "header-anchor-post"). The link-to-this-section
  // buttons and icons put inside some aren't the heading, and a heading is bold already.
  for (const heading of doc.body ? doc.body.querySelectorAll("h1, h2, h3, h4, h5, h6") : []) {
    for (const extra of heading.querySelectorAll("button, svg, div, span")) {
      if (extra.isConnected && !extra.textContent.trim() && !extra.querySelector("img")) extra.remove();
    }
    for (const bold of heading.querySelectorAll("strong, b")) bold.replaceWith(...bold.childNodes);
    heading.removeAttribute("class");
    heading.removeAttribute("id");
  }

  pointPrune(doc);
  const canonical = doc.querySelector('link[rel="canonical"]')?.getAttribute("href") || meta('meta[property="og:url"]');

  const article = new Readability(doc.cloneNode(true), { charThreshold: 300 }).parse();
  const title = (article && article.title) || meta('meta[property="og:title"]') || doc.title || "";

  let markdown = "";
  if (article && article.content) {
    const turndown = new TurndownService({
      headingStyle: "atx",
      hr: "---",
      bulletListMarker: "-",
      codeBlockStyle: "fenced",
      emDelimiter: "*",
      strongDelimiter: "**",
      linkStyle: "inlined",
    });
    turndown.use(turndownPluginGfm.gfm);
    // List items as written by hand: "- One", "1. One", their other lines lined up under
    // the text (Turndown pads the marker to four characters).
    turndown.addRule("listItem", {
      filter: "li",
      replacement: function (content, node, options) {
        const parent = node.parentNode;
        let prefix = options.bulletListMarker + " ";
        if (parent && parent.nodeName === "OL") {
          const start = Number(parent.getAttribute("start")) || 1;
          prefix = start + Array.prototype.indexOf.call(parent.children, node) + ". ";
        }
        content = content.replace(/^\n+/, "").replace(/\n+$/, "\n").replace(/\n/gm, "\n" + " ".repeat(prefix.length));
        return prefix + content + (node.nextSibling && !/\n$/.test(content) ? "\n" : "");
      },
    });
    // A picture that's a link: the picture alone if the link is only to a bigger copy of it,
    // else the linked picture on one line (Turndown spreads it over five).
    turndown.addRule("linkedImage", {
      filter: (node) => node.nodeName === "A" && node.querySelector("img") && !node.textContent.trim(),
      replacement: function (content, node) {
        const picture = content.trim();
        if (!picture) return "";
        const href = node.getAttribute("href") || "";
        const toPicture = /\.(jpe?g|png|gif|webp|avif)(\?.*)?$/i.test(href) || /\/image\//.test(href) || !href || picture.includes("\n");
        return "\n\n" + (toPicture ? picture : "[" + picture + "](" + href + ")") + "\n\n";
      },
    });
    turndown.remove(["script", "style", "noscript", "iframe", "form", "button"]);
    // A heading starting with a number isn't a list, so needs no escape: "### 1. One".
    markdown = turndown.turndown(article.content).replace(/^(#{1,6} \d+)\\\./gm, "$1.");
  }

  return {
    title: title.trim(),
    authors: ldAuthors.length ? ldAuthors : [article && article.byline, metaAuthor].filter(Boolean).slice(0, 1),
    published: (article && article.publishedTime) || published,
    siteName: (article && article.siteName) || meta('meta[property="og:site_name"]'),
    canonical: canonical ? new URL(canonical, url).href : null,
    excerpt: (article && article.excerpt) || meta('meta[name="description"]') || meta('meta[property="og:description"]'),
    markdown: markdown,
  };
}

// What's around the article that Readability can't tell apart from it: it goes by class names
// ("sidebar", "promo"), and many sites' are made by machine ("css-1x2y3z"). So, before it
// runs: the page's own article, if it marks one; no ads, promotions, newsletter sign-ups,
// related stories or sharing buttons, by what the page calls them elsewhere (test ids, labels
// for screen readers); and no text meant only for screen readers.
function pointPrune(doc) {
  const body = doc.body;
  if (!body) return;
  const textOf = (element) => Array.from(element.querySelectorAll("p")).reduce((n, p) => n + p.textContent.trim().length, 0);
  const total = textOf(body);
  // Never what holds the headline or much of the text: that's the article, however it's named.
  const isArticle = (element) => element.matches("h1") || element.querySelector("h1") || textOf(element) > total * 0.3;

  // The article, when the page marks it (`<article>`) and it holds most of the text, with the
  // headline if any article does. A page of stories each in an `<article>` has none that does.
  if (total > 500) {
    const articles = Array.from(body.querySelectorAll('article, [role="article"]')).filter((a) => textOf(a) >= total * 0.6);
    const chosen = articles.find((a) => a.querySelector("h1")) || articles[0];
    if (chosen && chosen !== body) body.replaceChildren(chosen);
  }

  // Not shown, or only to screen readers.
  const hidden = '[hidden], [aria-hidden="true"], [class*="visually-hidden" i], [class*="visuallyhidden" i], [class*="sr-only" i], ' +
    '[class*="screen-reader" i], [class*="a11y-hidden" i], [class*="accessibilityLabel" i], [class*="accessibility-label" i]';
  for (const element of Array.from(body.querySelectorAll(hidden))) {
    if (element.isConnected && !element.querySelector("img") && !isArticle(element)) element.remove();
  }

  // Ads' labels ("Advertisement", "Skip advertisement"), with what holds only them.
  const label = /^(\s*(advertisement|skip advertisement|sponsored content|sponsored)\s*)+$/i;
  for (const element of Array.from(body.querySelectorAll("p, span, div, a, aside, section"))) {
    if (!element.isConnected || !label.test(element.textContent)) continue;
    let outer = element;
    while (outer.parentElement && outer.parentElement !== body && label.test(outer.parentElement.textContent)) outer = outer.parentElement;
    outer.remove();
  }

  // What the page calls ads, promotions and the like ("StandardAd", "related-links").
  const promotion = /(^|\s)(ads?|advert\w*|sponsor\w*|promo\w*|newsletters?|related|recirc\w*|recommend\w*|trending|popular|outbrain|taboola|paywall|subscribe\w*|subscription|sign ?up|share\w*|social|comments?|messaging|dock|gift\w*|offers?)(\s|$)/i;
  const named = "[data-testid], [aria-label], [data-component-name], [data-module], [data-component]";
  for (const element of Array.from(body.querySelectorAll(named))) {
    if (!element.isConnected || isArticle(element)) continue;
    const names = ["data-testid", "aria-label", "data-component-name", "data-module", "data-component"]
      .map((name) => element.getAttribute(name) || "").join(" ")
      .replace(/([a-z])([A-Z])/g, "$1 $2").replace(/[_\-.:]+/g, " ");
    if (promotion.test(names)) element.remove();
  }

  // Marketing, which pages mark with the campaign or audience it's for.
  for (const element of Array.from(body.querySelectorAll("[data-campaign], [data-audience]"))) {
    if (element.isConnected && !isArticle(element)) element.remove();
  }

  // Links made to look like buttons ("Leave a comment", "Subscribe"), on their own.
  for (const link of Array.from(body.querySelectorAll('a[role="button"], a.button, a[class*="button"]'))) {
    const holder = link.parentElement;
    if (!link.isConnected) continue;
    if (holder && holder !== body && holder.textContent.trim() === link.textContent.trim()) holder.remove();
    else link.remove();
  }

  // A caption and its credit, in separate parts, kept apart: "On the bridge. Ann Lee", not
  // "On the bridge.Ann Lee".
  for (const caption of body.querySelectorAll("figcaption")) {
    for (const part of Array.from(caption.children).slice(1)) {
      const before = part.previousSibling;
      if (before && before.textContent && !/\s$/.test(before.textContent) && part.textContent.trim()) part.before(" ");
    }
  }

  // A date on a line of its own: the note has it, as `published`. (One in a sentence stays.)
  for (const time of Array.from(body.querySelectorAll("time"))) {
    if (!time.isConnected || !time.textContent.trim()) continue;
    let outer = time;
    while (outer.parentElement && outer.parentElement !== body && outer.parentElement.textContent.trim() === time.textContent.trim()) outer = outer.parentElement;
    // What's around it has more to say: in a sentence, a list or a table, the date stays.
    if (!(outer.parentElement && outer.parentElement.closest("p, li, td, th"))) outer.remove();
  }

  // Pictures side by side, in a box of their own: one figure, which Readability keeps (it takes
  // a box of pictures with little text around them for clutter).
  for (const group of Array.from(body.querySelectorAll("div, section"))) {
    if (!group.isConnected || group.closest("figure")) continue;
    const figures = Array.from(group.querySelectorAll("figure"));
    if (figures.length < 2) continue;
    const inFigures = figures.reduce((n, figure) => n + figure.textContent.trim().length, 0);
    if (group.textContent.trim().length > inFigures + 20) continue;
    const figure = doc.createElement("figure");
    figure.append(...group.childNodes);
    group.replaceWith(figure);
  }
}
