"use strict";

function safeLink(raw, baseURL, image) {
  if (!raw.trim()) return null;
  try {
    const url = new URL(raw, baseURL || undefined);
    if (url.username || url.password) return null;
    if (url.protocol === "https:" || url.protocol === "http:" || (!image && url.protocol === "mailto:")) {
      return url.href;
    }
  } catch {
    return null;
  }
  return null;
}

window.bakerWebImport = function (html, baseURL, extractArticle) {
  // Keep source markup in an inert template and run only bundled scripts.
  const template = document.createElement("template");
  template.innerHTML = html;
  const source = template.content;
  const elements = source.querySelectorAll("*");
  if (elements.length > 50000) throw new Error("This page contains too many elements.");
  const depths = new WeakMap();
  for (const element of elements) {
    const depth = (depths.get(element.parentElement) || 0) + 1;
    if (depth > 128) throw new Error("This page is nested too deeply.");
    depths.set(element, depth);
  }

  const title = source.querySelector("title")?.textContent.trim()
    || source.querySelector("h1")?.textContent.trim() || "";
  source.querySelectorAll("script,style,link,meta,title,base,iframe,frame,object,embed,form,button,template,noscript,svg").forEach(node => node.remove());

  const math = [];
  const token = "BAKER" + Math.random().toString(36).slice(2).toUpperCase() + "MATH";
  for (const node of source.querySelectorAll("math")) {
    const annotation = node.querySelector('annotation[encoding="application/x-tex"]');
    const tex = (annotation?.textContent || node.getAttribute("alttext") || "").trim();
    if (!tex) continue;
    const block = node.getAttribute("display") === "block";
    const replacement = document.createElement(block ? "div" : "span");
    replacement.textContent = token + math.length + "END";
    math.push(block ? "\n\n$$\n" + tex + "\n$$\n\n" : "$" + tex + "$");
    node.replaceWith(replacement);
  }

  const attributes = new Set(["alt", "class", "id", "start", "colspan", "rowspan"]);
  for (const element of source.querySelectorAll("*")) {
    for (const attr of Array.from(element.attributes)) {
      if (attr.name === "href" || attr.name === "src") {
        const link = safeLink(attr.value, baseURL, attr.name === "src");
        if (link) element.setAttribute(attr.name, link);
        else element.removeAttribute(attr.name);
      } else if (!attributes.has(attr.name)) {
        element.removeAttribute(attr.name);
      }
    }
  }

  const doc = document.implementation.createHTMLDocument(title);
  doc.body.append(source);
  let body = doc.body;
  let articleTitle = title;
  if (extractArticle) {
    const fallback = doc.querySelector("main") || doc.querySelector("article") || doc.body;
    const article = new Readability(doc.cloneNode(true), { maxElemsToParse: 50000, charThreshold: 160 }).parse();
    const extracted = doc.createElement("template");
    extracted.innerHTML = article?.content || "";
    const preservesCode = !fallback.querySelector("pre") || extracted.content.querySelector("pre");
    const preservesMath = !fallback.textContent.includes(token) || extracted.content.textContent.includes(token);
    body = article?.content && preservesCode && preservesMath ? extracted.content : fallback;
    articleTitle = article?.title || title;
    if (articleTitle && !body.querySelector("h1") && (body.textContent.trim() || body.querySelector("img"))) {
      const heading = doc.createElement("h1");
      heading.textContent = articleTitle;
      body.prepend(heading);
    }
  }

  const converter = new TurndownService({
    headingStyle: "atx", codeBlockStyle: "fenced", bulletListMarker: "-"
  });
  converter.use(turndownPluginGfm.gfm);
  converter.addRule("printLabels", {
    filter: ["a", "em", "strong", "del"],
    replacement: content => content
  });
  converter.addRule("printImageLabels", {
    filter: "img",
    replacement: (_, node) => node.getAttribute("alt") || ""
  });
  const printText = converter.turndown(body)
    .replace(new RegExp(token + "(\\d+)END", "g"), (_, index) => math[Number(index)] || "")
    .trim();
  return { title: articleTitle.slice(0, 200), printText };
};
