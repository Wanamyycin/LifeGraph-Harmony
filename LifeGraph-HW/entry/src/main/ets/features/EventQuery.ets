import { AppSnapshot, EventCard } from '../domain/Models';

export type TimelineGrain = 'year' | 'month' | 'week';

export class TimelineEventGroup {
  key: string = '';
  label: string = '';
  events: EventCard[] = [];
}

export interface EventTimelineOptions {
  query: string;
  branchIds: string[];
  personId: string;
  grain: TimelineGrain;
  ascending: boolean;
}

// The original list combines selected branches with OR. Search remains independent
// of the list filter when opened from the global search page.
export function findEvents(data: AppSnapshot, query: string, branchIds: string[]): EventCard[] {
  const text = query.trim().toLocaleLowerCase();
  return data.events.filter((card: EventCard) =>
    (branchIds.length === 0 || card.branchIds.some((id: string) => branchIds.includes(id))) &&
    (card.event.title.toLocaleLowerCase().includes(text) || card.event.content.toLocaleLowerCase().includes(text)));
}

export function timelineEvents(data: AppSnapshot, options: EventTimelineOptions): EventCard[] {
  return findEvents(data, options.query, options.branchIds)
    .filter((card: EventCard) => options.personId.length === 0 || card.personIds.includes(options.personId))
    .sort((first: EventCard, second: EventCard) => options.ascending ?
      first.event.occurredAt - second.event.occurredAt : second.event.occurredAt - first.event.occurredAt);
}

export function groupTimelineEvents(events: EventCard[], grain: TimelineGrain): TimelineEventGroup[] {
  const groups: TimelineEventGroup[] = [];
  const byKey = new Map<string, TimelineEventGroup>();
  for (const card of events) {
    const key = timelineGroupKey(card.event.occurredAt, grain);
    let group = byKey.get(key);
    if (group === undefined) {
      group = new TimelineEventGroup(); group.key = key; group.label = timelineGroupLabel(card.event.occurredAt, grain);
      byKey.set(key, group); groups.push(group);
    }
    group.events.push(card);
  }
  return groups;
}

export function timelineGroupKey(timestamp: number, grain: TimelineGrain): string {
  const date = new Date(timestamp);
  if (grain === 'year') { return date.getFullYear().toString(); }
  if (grain === 'month') { return date.getFullYear() + '-' + twoDigits(date.getMonth() + 1); }
  const start = startOfWeek(date);
  return start.getFullYear() + '-' + twoDigits(start.getMonth() + 1) + '-' + twoDigits(start.getDate());
}

export function timelineGroupLabel(timestamp: number, grain: TimelineGrain): string {
  const date = new Date(timestamp);
  if (grain === 'year') { return date.getFullYear() + ' 年'; }
  if (grain === 'month') { return date.getFullYear() + ' 年 ' + (date.getMonth() + 1) + ' 月'; }
  const start = startOfWeek(date);
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6);
  return formatMonthDay(start) + '—' + formatMonthDay(end);
}

export function eventDayLabel(timestamp: number): string {
  const date = new Date(timestamp);
  return twoDigits(date.getDate());
}

export function eventWeekdayLabel(timestamp: number): string {
  return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][new Date(timestamp).getDay()];
}

function startOfWeek(date: Date): Date {
  const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const distance = (copy.getDay() + 6) % 7;
  copy.setDate(copy.getDate() - distance);
  return copy;
}

function formatMonthDay(date: Date): string { return (date.getMonth() + 1) + ' 月 ' + date.getDate() + ' 日'; }
function twoDigits(value: number): string { return value.toString().padStart(2, '0'); }

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) { return '未知'; }
  if (bytes < 1024) { return Math.round(bytes).toString() + ' B'; }
  if (bytes < 1048576) { return (bytes / 1024).toFixed(1) + ' KB'; }
  if (bytes < 1073741824) { return (bytes / 1048576).toFixed(1) + ' MB'; }
  return (bytes / 1073741824).toFixed(2) + ' GB';
}
