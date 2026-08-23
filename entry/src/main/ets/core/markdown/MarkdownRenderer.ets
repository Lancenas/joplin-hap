// Markdown -> HTML rendering tailored to Joplin's flavour. We support the
// features that are most common in personal notes (headings, emphasis, lists,
// code blocks, links, images, blockquotes, task lists) without pulling in an
// external parser.
//
// ArkTS constraint: `String.prototype.replace` only accepts a *string*
// replacement — the `(match, ...groups) => string` callback overload is not
// available. Every inline construct is therefore resolved by a hand-written
// scanner instead of a regex with a replacer function.

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Escapes a URL for use inside a double-quoted HTML attribute.
function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/`/g, '&#96;');
}

const RESOURCE_PREFIX = ':/';

interface Delimited {
  found: boolean;
  content: string;
  next: number;
}

const NOT_FOUND: Delimited = { found: false, content: '', next: 0 };

// Reads `src` starting at `start` (which must point at the opening delimiter)
// and returns the text up to the matching closing delimiter.
function readDelimited(src: string, start: number, open: string, close: string): Delimited {
  if (!src.startsWith(open, start)) {
    return NOT_FOUND;
  }
  const contentStart: number = start + open.length;
  const closeAt: number = src.indexOf(close, contentStart);
  if (closeAt < 0) {
    return NOT_FOUND;
  }
  const result: Delimited = {
    found: true,
    content: src.substring(contentStart, closeAt),
    next: closeAt + close.length,
  };
  return result;
}

interface LinkParts {
  found: boolean;
  label: string;
  target: string;
  next: number;
}

const NO_LINK: LinkParts = { found: false, label: '', target: '', next: 0 };

// Parses `[label](target)` beginning at `start`, where `start` points at `[`.
function readLink(src: string, start: number): LinkParts {
  const label: Delimited = readDelimited(src, start, '[', ']');
  if (!label.found) {
    return NO_LINK;
  }
  const target: Delimited = readDelimited(src, label.next, '(', ')');
  if (!target.found) {
    return NO_LINK;
  }
  // Strip an optional `"title"` suffix: [x](http://a "t")
  let raw: string = target.content.trim();
  const quoteAt: number = raw.indexOf(' "');
  if (quoteAt > 0 && raw.endsWith('"')) {
    raw = raw.substring(0, quoteAt).trim();
  }
  const parts: LinkParts = { found: true, label: label.content, target: raw, next: target.next };
  return parts;
}

function isWordBoundary(src: string, index: number): boolean {
  if (index <= 0) {
    return true;
  }
  const ch: string = src.charAt(index - 1);
  return ch === ' ' || ch === '\t' || ch === '(' || ch === '\n';
}

function renderInline(src: string): string {
  const out: string[] = [];
  let i: number = 0;
  const n: number = src.length;

  while (i < n) {
    const ch: string = src.charAt(i);

    // Escaped character: \*  \_  \[ ...
    if (ch === '\\' && i + 1 < n) {
      out.push(escapeHtml(src.charAt(i + 1)));
      i += 2;
      continue;
    }

    // Image or Joplin resource: ![alt](src) / ![:hash](:/resourceId)
    if (ch === '!' && i + 1 < n && src.charAt(i + 1) === '[') {
      const link: LinkParts = readLink(src, i + 1);
      if (link.found) {
        if (link.target.startsWith(RESOURCE_PREFIX)) {
          const resourceId: string = link.target.substring(RESOURCE_PREFIX.length);
          out.push(`<img data-resource-id="${escapeAttr(resourceId)}" alt="${escapeAttr(link.label)}"/>`);
        } else {
          out.push(`<img src="${escapeAttr(link.target)}" alt="${escapeAttr(link.label)}"/>`);
        }
        i = link.next;
        continue;
      }
    }

    if (ch === '[') {
      // Task-list checkbox: `[ ]`, `[x]`, `[X]`
      const three: string = src.substring(i, i + 3);
      if (three === '[ ]' && isWordBoundary(src, i)) {
        out.push('<input type="checkbox" disabled/>');
        i += 3;
        continue;
      }
      if ((three === '[x]' || three === '[X]') && isWordBoundary(src, i)) {
        out.push('<input type="checkbox" disabled checked/>');
        i += 3;
        continue;
      }
      const link: LinkParts = readLink(src, i);
      if (link.found) {
        if (link.target.startsWith(RESOURCE_PREFIX)) {
          const noteId: string = link.target.substring(RESOURCE_PREFIX.length);
          out.push(`<a href="#" data-note-id="${escapeAttr(noteId)}">${renderInline(link.label)}</a>`);
        } else {
          out.push(`<a href="${escapeAttr(link.target)}">${renderInline(link.label)}</a>`);
        }
        i = link.next;
        continue;
      }
    }

    // Inline code — content is never re-parsed.
    if (ch === '`') {
      const code: Delimited = readDelimited(src, i, '`', '`');
      if (code.found) {
        out.push(`<code>${escapeHtml(code.content)}</code>`);
        i = code.next;
        continue;
      }
    }

    // Strikethrough
    if (src.startsWith('~~', i)) {
      const del: Delimited = readDelimited(src, i, '~~', '~~');
      if (del.found) {
        out.push(`<del>${renderInline(del.content)}</del>`);
        i = del.next;
        continue;
      }
    }

    // Bold before italic so `**x**` is not consumed as two emphases.
    if (src.startsWith('**', i)) {
      const strong: Delimited = readDelimited(src, i, '**', '**');
      if (strong.found && strong.content.length > 0) {
        out.push(`<strong>${renderInline(strong.content)}</strong>`);
        i = strong.next;
        continue;
      }
    }

    if (ch === '*' || (ch === '_' && isWordBoundary(src, i))) {
      const em: Delimited = readDelimited(src, i, ch, ch);
      if (em.found && em.content.length > 0 && em.content.indexOf('\n') < 0) {
        out.push(`<em>${renderInline(em.content)}</em>`);
        i = em.next;
        continue;
      }
    }

    out.push(escapeHtml(ch));
    i += 1;
  }

  return out.join('');
}

const BULLET_RE: RegExp = /^\s*[-*+]\s+/;
const ORDERED_RE: RegExp = /^\s*\d+\.\s+/;
const HEADING_RE: RegExp = /^(#{1,6})\s+(.*)$/;
const RULE_RE: RegExp = /^(-{3,}|\*{3,}|_{3,})$/;

function isBlockStart(line: string): boolean {
  return line.startsWith('#')
    || line.startsWith('>')
    || line.startsWith('```')
    || BULLET_RE.test(line)
    || ORDERED_RE.test(line);
}

export function markdownToHtml(input: string): string {
  if (!input) {
    return '';
  }
  const lines: string[] = input.replace(/\r\n?/g, '\n').split('\n');
  const out: string[] = [];
  let i: number = 0;

  while (i < lines.length) {
    const line: string = lines[i];

    // Fenced code block
    if (line.startsWith('```')) {
      const lang: string = line.substring(3).trim();
      const body: string[] = [];
      i += 1;
      while (i < lines.length && !lines[i].startsWith('```')) {
        body.push(lines[i]);
        i += 1;
      }
      i += 1;
      const cls: string = lang ? ` class="lang-${escapeAttr(lang)}"` : '';
      out.push(`<pre><code${cls}>${escapeHtml(body.join('\n'))}</code></pre>`);
      continue;
    }

    // ATX headings
    const heading: RegExpExecArray | null = HEADING_RE.exec(line);
    if (heading !== null) {
      const level: number = heading[1].length;
      out.push(`<h${level}>${renderInline(heading[2])}</h${level}>`);
      i += 1;
      continue;
    }

    // Blockquote — consume contiguous lines, then render recursively
    if (line.startsWith('>')) {
      const body: string[] = [];
      while (i < lines.length && lines[i].startsWith('>')) {
        body.push(lines[i].substring(1).replace(/^\s/, ''));
        i += 1;
      }
      out.push(`<blockquote>${markdownToHtml(body.join('\n'))}</blockquote>`);
      continue;
    }

    // Unordered list (including task lists)
    if (BULLET_RE.test(line)) {
      const items: string[] = [];
      while (i < lines.length && BULLET_RE.test(lines[i])) {
        items.push(lines[i].replace(BULLET_RE, ''));
        i += 1;
      }
      const rendered: string[] = [];
      for (const item of items) {
        rendered.push(`<li>${renderInline(item)}</li>`);
      }
      out.push(`<ul>${rendered.join('')}</ul>`);
      continue;
    }

    // Ordered list
    if (ORDERED_RE.test(line)) {
      const items: string[] = [];
      while (i < lines.length && ORDERED_RE.test(lines[i])) {
        items.push(lines[i].replace(ORDERED_RE, ''));
        i += 1;
      }
      const rendered: string[] = [];
      for (const item of items) {
        rendered.push(`<li>${renderInline(item)}</li>`);
      }
      out.push(`<ol>${rendered.join('')}</ol>`);
      continue;
    }

    // Horizontal rule
    if (RULE_RE.test(line.trim())) {
      out.push('<hr/>');
      i += 1;
      continue;
    }

    // Blank line — paragraph break
    if (line.trim() === '') {
      i += 1;
      continue;
    }

    // Paragraph: collect until a blank line or the start of another block
    const buf: string[] = [];
    while (i < lines.length && lines[i].trim() !== '' && !isBlockStart(lines[i])) {
      buf.push(lines[i]);
      i += 1;
    }
    if (buf.length > 0) {
      out.push(`<p>${renderInline(buf.join('\n'))}</p>`);
    }
  }

  return out.join('\n');
}

// Plain-text projection used by the in-app preview, which renders with ArkUI
// Text components rather than a WebView.
export function markdownToPlainText(input: string): string {
  if (!input) {
    return '';
  }
  return input
    .replace(/\r\n?/g, '\n')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/```[\s\S]*?```/g, '[代码块]')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '[图片]')
    .replace(/\*\*/g, '')
    .replace(/^>\s?/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '• ');
}

export function previewTemplate(html: string): string {
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<style>
  body { font-family: -apple-system, "HarmonyOS Sans SC", sans-serif; margin: 16px; line-height: 1.6; color: #1a1a1a; }
  h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.3; margin: 1.2em 0 0.6em; }
  h1 { font-size: 1.6em; }
  h2 { font-size: 1.35em; }
  h3 { font-size: 1.15em; }
  p { margin: 0.6em 0; }
  code { background: #f3f4f6; padding: 2px 4px; border-radius: 4px; font-family: "Roboto Mono", monospace; font-size: 0.9em; }
  pre { background: #1f2937; color: #f3f4f6; padding: 12px; border-radius: 8px; overflow-x: auto; }
  pre code { background: transparent; color: inherit; padding: 0; }
  blockquote { border-left: 3px solid #1F58B8; padding: 4px 12px; color: #555; margin: 0.6em 0; background: #f5f7fa; }
  ul, ol { padding-left: 1.4em; }
  a { color: #1F58B8; }
  hr { border: 0; border-top: 1px solid #e1e4e8; margin: 1em 0; }
  img { max-width: 100%; height: auto; border-radius: 6px; }
  input[type=checkbox] { transform: scale(1.1); margin-right: 4px; }
  .attachment { display: inline-block; padding: 8px 12px; margin: 6px 0; background: #f3f4f6;
    border: 1px solid #e1e4e8; border-radius: 8px; color: #1F58B8; font-size: 0.9em; }
</style>
</head>
<body>${html}</body>
</html>`;
}
