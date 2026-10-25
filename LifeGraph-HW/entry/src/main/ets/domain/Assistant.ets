export class AssistantReference {
  kind: string = 'event';
  id: string = '';
  title: string = '';
  occurredAt: number = 0;
}

export class AssistantTurn {
  id: string = '';
  text: string = '';
  user: boolean = false;
  status: string = 'complete';
  createdAt: number = 0;
  readAt: number = 0;
  references: AssistantReference[] = [];
  contextNote: string = '';
}

export class AssistantAnswer {
  text: string = '';
  references: AssistantReference[] = [];
  readAt: number = 0;
  contextNote: string = '';
}

export class ToolArguments {
  query?: string;
  keywords?: string[];
  personId?: string;
  personIds?: string[];
  withPersonId?: string;
  eventId?: string;
  from?: number;
  to?: number;
  emotionName?: string;
  branchName?: string;
  offset?: number;
  limit?: number;
  includeMentions?: boolean;
  includeHidden?: boolean;
}

export class ToolCall {
  id: string = '';
  name: string = '';
  arguments: ToolArguments = new ToolArguments();
}

export function referenceUrl(reference: AssistantReference): string {
  return 'lifegraph://' + reference.kind + '/' + encodeURIComponent(reference.id);
}

export function decodeConversation(value: string): AssistantTurn[] {
  const turns = JSON.parse(value) as AssistantTurn[];
  if (!Array.isArray(turns) || turns.length > 1000) { throw new Error('聊天记录格式不正确'); }
  const ids = new Set<string>();
  for (const turn of turns) {
    if (turn === null || typeof turn.id !== 'string' || typeof turn.text !== 'string' || turn.text.length > 100000 ||
      typeof turn.user !== 'boolean' || !Number.isFinite(turn.createdAt) || !Number.isFinite(turn.readAt) ||
      !['complete', 'pending', 'failed', 'canceled'].includes(turn.status) || !Array.isArray(turn.references) || turn.references.length > 100 ||
      typeof turn.contextNote !== 'string' || turn.id.length === 0 || ids.has(turn.id)) { throw new Error('聊天记录格式不正确'); }
    ids.add(turn.id);
    for (const ref of turn.references) {
      if (ref === null || !['event', 'person', 'help'].includes(ref.kind) || typeof ref.id !== 'string' ||
        typeof ref.title !== 'string' || !Number.isFinite(ref.occurredAt)) { throw new Error('聊天来源格式不正确'); }
    }
    if (turn.status === 'pending') { turn.status = 'canceled'; }
  }
  return turns;
}

export function encodeConversation(turns: AssistantTurn[]): string {
  const value = JSON.stringify(turns);
  if (value.length > 1000000 || utf8Length(value) > 1000000 || turns.length > 1000) { throw new Error('聊天记录已达当前容量上限，请先备份或复制需要的内容，再清空对话'); }
  // Validate an independent copy; never rewrite a live pending turn on save.
  decodeConversation(value);
  return value;
}

function utf8Length(value: string): number {
  let bytes = 0;
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code < 0x80) { bytes++; }
    else if (code < 0x800) { bytes += 2; }
    else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length && value.charCodeAt(i + 1) >= 0xDC00 && value.charCodeAt(i + 1) <= 0xDFFF) { bytes += 4; i++; }
    else { bytes += 3; }
  }
  return bytes;
}
