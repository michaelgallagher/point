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
    turndown.remove(["script", "style", "noscript", "iframe", "form", "button"]);
    markdown = turndown.turndown(article.content);
  }

  return {
    title: title.trim(),
    authors: ldAuthors.length ? ldAuthors : [article && article.byline, metaAuthor].filter(Boolean).slice(0, 1),
    published: (article && article.publishedTime) || published,
    siteName: (article && article.siteName) || meta('meta[property="og:site_name"]'),
    excerpt: (article && article.excerpt) || meta('meta[name="description"]') || meta('meta[property="og:description"]'),
    markdown: markdown,
  };
}
