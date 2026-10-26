import { ToolArguments } from '../domain/Assistant';

export class AssistantEntryRequest {
  question: string = '';
  scope: ToolArguments = new ToolArguments();
}

export function assistantDate(timestamp: number): string {
  const date = new Date(timestamp);
  return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0');
}

export function assistantRangeStart(days: number, now: number = Date.now()): number {
  const date = new Date(now);
  date.setHours(0, 0, 0, 0); date.setDate(date.getDate() - days + 1);
  return date.getTime();
}

export function assistantRangeEnd(now: number = Date.now()): number {
  const date = new Date(now); date.setHours(23, 59, 59, 999); return date.getTime();
}

export function assistantEntryRequest(kind: string, personId: string, personName: string, clue: string,
  from?: number, to?: number): AssistantEntryRequest {
  const request = new AssistantEntryRequest();
  if (personId.length > 0) { request.scope.personId = personId; }
  request.scope.from = from; request.scope.to = to;
  const period = from === undefined || to === undefined ? '' : '，时间为' + assistantDate(from) + '至' + assistantDate(to);
  if (kind === 'together') {
    request.scope.includeMentions = false;
    request.question = '帮我回顾和' + personName + '的共同经历' + period + '，梳理共同参与的经历和互动变化，并附上相关记录。';
  } else if (kind === 'memory') {
    request.question = '帮我找与“' + clue.trim() + '”相关的记录' + (personName.length > 0 ? '，人物为' + personName : '') + period + '，先列出匹配记录并说明原因。';
  } else {
    request.question = '帮我回顾最近的生活' + period + '，整理重要经历、相关人物和生活变化，并附上相关记录。';
  }
  return request;
}
