import { AppSnapshot, EventCard } from '../domain/Models';

// The original list combines selected branches with OR. Search remains independent
// of the list filter when opened from the global search page.
export function findEvents(data: AppSnapshot, query: string, branchIds: string[]): EventCard[] {
  const text = query.trim().toLocaleLowerCase();
  return data.events.filter((card: EventCard) =>
    (branchIds.length === 0 || card.branchIds.some((id: string) => branchIds.includes(id))) &&
    (card.event.title.toLocaleLowerCase().includes(text) || card.event.content.toLocaleLowerCase().includes(text)));
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) { return '未知'; }
  if (bytes < 1024) { return Math.round(bytes).toString() + ' B'; }
  if (bytes < 1048576) { return (bytes / 1024).toFixed(1) + ' KB'; }
  if (bytes < 1073741824) { return (bytes / 1048576).toFixed(1) + ' MB'; }
  return (bytes / 1073741824).toFixed(2) + ' GB';
}
