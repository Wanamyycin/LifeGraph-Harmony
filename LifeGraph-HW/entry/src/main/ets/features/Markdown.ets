export class MarkdownPart {
  text: string = '';
  bold: boolean = false;
  code: boolean = false;
}
export class MarkdownBlock {
  text: string = '';
  heading: number = 0;
  code: boolean = false;
  parts: MarkdownPart[] = [];
}

// Native text only. HTML and unsupported Markdown remain readable literal text.
export function parseMarkdown(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = []; let code = false; let buffer: string[] = [];
  const flush = (): void => {
    if (buffer.length === 0) { return; }
    const block = new MarkdownBlock(); block.text = buffer.join('\n'); block.code = true;
    blocks.push(block); buffer = [];
  };
  for (const line of source.replace(/\r\n/g, '\n').split('\n')) {
    if (/^\s*```/.test(line)) { if (code) { flush(); } code = !code; continue; }
    if (code) { buffer.push(line); continue; }
    const block = new MarkdownBlock(); const heading = line.match(/^(#{1,6})\s+(.*)$/);
    block.heading = heading === null ? 0 : heading[1].length;
    block.text = heading === null ? line.replace(/^\s*[-*+]\s+/, '• ').replace(/^>\s?/, '│ ') : heading[2];
    const tokens = block.text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g);
    block.parts = tokens.filter((token: string) => token.length > 0).map((token: string): MarkdownPart => {
      const part = new MarkdownPart(); part.bold = token.startsWith('**') && token.endsWith('**');
      part.code = token.startsWith('`') && token.endsWith('`');
      part.text = part.bold ? token.slice(2, -2) : (part.code ? token.slice(1, -1) : token); return part;
    });
    blocks.push(block);
  }
  flush(); return blocks;
}
