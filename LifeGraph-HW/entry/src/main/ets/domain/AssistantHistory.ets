import { AssistantTurn, ToolArguments } from './Assistant';

export class AssistantChat {
  id: string = '';
  title: string = '';
  preview: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  draft: string = '';
  draftScope?: ToolArguments;
}

export class AssistantHistory {
  version: number = 1;
  activeId: string = '';
  chats: AssistantChat[] = [];
  draft: string = '';
  draftScope?: ToolArguments;
}

export class AssistantChatSave {
  id: string = '';
  history: AssistantHistory = new AssistantHistory();
}

export function decodeAssistantHistory(value: string): AssistantHistory {
  const history = JSON.parse(value) as AssistantHistory;
  if (history === null || history.version !== 1 || typeof history.activeId !== 'string' ||
    !Array.isArray(history.chats) || typeof history.draft !== 'string' || history.draft.length > 6000) {
    throw new Error('历史聊天目录格式不正确');
  }
  const ids = new Set<string>();
  for (const chat of history.chats) {
    if (chat === null || typeof chat.id !== 'string' || chat.id.length === 0 || ids.has(chat.id) ||
      typeof chat.title !== 'string' || typeof chat.preview !== 'string' || typeof chat.draft !== 'string' ||
      chat.draft.length > 6000 || !Number.isFinite(chat.createdAt) || !Number.isFinite(chat.updatedAt)) {
      throw new Error('历史聊天目录格式不正确');
    }
    ids.add(chat.id);
  }
  if (history.activeId.length > 0 && !ids.has(history.activeId)) { throw new Error('当前聊天不在历史目录中'); }
  history.chats.sort((a: AssistantChat, b: AssistantChat) => b.updatedAt - a.updatedAt || a.id.localeCompare(b.id));
  return history;
}

export function assistantChatTitle(turns: AssistantTurn[]): string {
  const first = turns.find((turn: AssistantTurn) => turn.user);
  if (first === undefined) { return '生活记录回顾'; }
  const together = first.text.match(/^帮我回顾和(.+?)的共同经历/);
  if (together !== null) { return '与' + together[1] + '的共同经历'; }
  const memory = first.text.match(/^帮我找与“([^”]+)”相关的记录/);
  if (memory !== null) { return '查找：' + Array.from(memory[1]).slice(0, 20).join(''); }
  if (first.text.startsWith('帮我回顾最近的生活')) {
    const from = first.scope?.from; const to = first.scope?.to;
    return from !== undefined && to !== undefined ? '近' + Math.round((to - from + 1) / 86400000).toString() + '天的生活回顾' : '近期生活回顾';
  }
  return Array.from(first.text.trim().split('\n')[0]).slice(0, 24).join('');
}

export function assistantChatPreview(turns: AssistantTurn[]): string {
  const last = turns[turns.length - 1];
  return last === undefined ? '' : Array.from(last.text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[#*`>|]/g, '').replace(/\s+/g, ' ').trim()).slice(0, 70).join('');
}

export function assistantChatGroup(timestamp: number, now: number = Date.now()): string {
  const today = new Date(now); today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today.getTime()); yesterday.setDate(yesterday.getDate() - 1);
  return timestamp >= today.getTime() ? '今天' : timestamp >= yesterday.getTime() ? '昨天' : '更早';
}
