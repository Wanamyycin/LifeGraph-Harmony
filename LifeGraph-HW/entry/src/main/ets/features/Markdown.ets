export class MarkdownPart {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  code: boolean = false;
  href: string = '';
}
export class MarkdownRow {
  cells: MarkdownPart[][] = [];
}
export class MarkdownBlock {
  text: string = '';
  heading: number = 0;
  code: boolean = false;
  quote: boolean = false;
  rule: boolean = false;
  indent: number = 0;
  parts: MarkdownPart[] = [];
  rows: MarkdownRow[] = [];
}

// Native presentation only: no HTML execution, remote images or embedded Web.
export function parseMarkdown(source: string): MarkdownBlock[] {
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  const blocks: MarkdownBlock[] = []; let fence = ''; let buffer: string[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]; const mark = line.match(/^\s*(`{3,}|~{3,})(.*)$/);
    if (fence.length > 0) {
      if (mark !== null && mark[1][0] === fence[0] && mark[1].length >= fence.length && mark[2].trim().length === 0) {
        const block = new MarkdownBlock(); block.code = true; block.text = buffer.join('\n'); blocks.push(block); buffer = []; fence = '';
      } else { buffer.push(line); }
      continue;
    }
    if (mark !== null) { fence = mark[1]; continue; }
    if (index + 1 < lines.length && line.includes('|') && tableSeparator(lines[index + 1])) {
      const block = new MarkdownBlock(); block.rows.push(tableRow(line)); index++;
      while (index + 1 < lines.length && lines[index + 1].includes('|') && lines[index + 1].trim().length > 0) { index++; block.rows.push(tableRow(lines[index])); }
      blocks.push(block); continue;
    }
    const block = new MarkdownBlock(); const heading = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*$/);
    block.heading = heading?.[1].length ?? 0;
    block.rule = /^\s*(?:---+|\*\*\*+|___+)\s*$/.test(line);
    block.quote = /^\s*>/.test(line);
    block.indent = Math.min(3, Math.floor((line.match(/^\s*/)?.[0].length ?? 0) / 2));
    block.text = heading === null ? line.replace(/^\s*[-*+]\s+/, '• ').replace(/^\s*>\s?/, '') : heading[2];
    block.parts = inlineMarkdown(block.text); blocks.push(block);
  }
  if (fence.length > 0) { const block = new MarkdownBlock(); block.code = true; block.text = buffer.join('\n'); blocks.push(block); }
  return blocks;
}

export function safeMarkdownLink(url: string): string {
  if (url.length > 2048 || /[\s<>"'\\]/.test(url)) { return ''; }
  if (/^https?:\/\/[^/?#]+(?:[/?#].*)?$/i.test(url)) { return url; }
  if (/^lifegraph:\/\/(event|person|help)\/[^/?#]+$/.test(url)) {
    try { decodeURIComponent(url); return url; } catch (_) { return ''; }
  }
  return '';
}

export function inlineMarkdown(source: string, bold: boolean = false, italic: boolean = false, href: string = '', depth: number = 0): MarkdownPart[] {
  if (depth > 4) { return [part(source, bold, italic, false, href)]; }
  const result: MarkdownPart[] = [];
  const pattern = /\\([\\`*_[\]{}()#+.!|>-])|`([^`]+)`|\[([^\]]+)\]\(([^\s)]+)\)|\*\*(.+?)\*\*|__(.+?)__|\*([^*\n]+)\*|_([^_\n]+)_|<(https?:\/\/[^>]+)>|(https?:\/\/[^\s<>]+[^\s<>.,，。！？!?:;；])/g;
  let cursor = 0; let match: RegExpExecArray | null = pattern.exec(source);
  while (match !== null) {
    if (match.index > cursor) { result.push(part(source.slice(cursor, match.index), bold, italic, false, href)); }
    if (match[1] !== undefined) { result.push(part(match[1], bold, italic, false, href)); }
    else if (match[2] !== undefined) { result.push(part(match[2], bold, italic, true, '')); }
    else if (match[3] !== undefined) { result.push(...inlineMarkdown(match[3], bold, italic, safeMarkdownLink(match[4]), depth + 1)); }
    else if (match[5] !== undefined || match[6] !== undefined) { result.push(...inlineMarkdown(match[5] ?? match[6], true, italic, href, depth + 1)); }
    else if (match[7] !== undefined || match[8] !== undefined) { result.push(...inlineMarkdown(match[7] ?? match[8], bold, true, href, depth + 1)); }
    else { const url = match[9] ?? match[10]; result.push(part(url, bold, italic, false, safeMarkdownLink(url))); }
    cursor = match.index + match[0].length; match = pattern.exec(source);
  }
  if (cursor < source.length) { result.push(part(source.slice(cursor), bold, italic, false, href)); }
  return result;
}
function part(text: string, bold: boolean, italic: boolean, code: boolean, href: string): MarkdownPart {
  const value = new MarkdownPart(); value.text = text; value.bold = bold; value.italic = italic; value.code = code; value.href = href; return value;
}
function cells(line: string): string[] {
  const result: string[] = []; let cell = ''; let code = false;
  const text = line.trim().replace(/^\|/, '').replace(/(?<!\\)\|$/, '');
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '\\' && i + 1 < text.length) { cell += char + text[++i]; continue; }
    if (char === '`') { code = !code; }
    if (char === '|' && !code) { result.push(cell.trim()); cell = ''; } else { cell += char; }
  }
  result.push(cell.trim()); return result;
}
function tableSeparator(line: string): boolean {
  const values = cells(line); return values.length >= 2 && values.every((value: string) => /^:?-{3,}:?$/.test(value));
}
function tableRow(line: string): MarkdownRow {
  const row = new MarkdownRow(); row.cells = cells(line).map((value: string) => inlineMarkdown(value)); return row;
}
