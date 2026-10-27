import { AppSnapshot, EventCard, RelationEdge } from '../domain/Models';

export class DesktopCardConfig {
  personIds: string[] = [];
  nameMode: string = 'hidden';
  showEventTitles: boolean = false;
}

export class DesktopCardNode {
  id: string = '';
  label: string = '';
  shortLabel: string = '';
  x: number = 50;
  y: number = 50;
  color: string = '#7BA88A';
  count: number = 0;
  recent: string = '还没有共同记录';
}

export class DesktopCardLink {
  key: string = '';
  x1: number = 50;
  y1: number = 50;
  x2: number = 50;
  y2: number = 50;
  width: number = 1;
  color: string = '#7BA88A';
}

export class DesktopCardData {
  nodes: DesktopCardNode[] = [];
  links: DesktopCardLink[] = [];
  appearance: string = 'system';
  empty: string = '在设置中选几位重要的人';
}

export function normalizeCardConfig(config: DesktopCardConfig): DesktopCardConfig {
  const result = new DesktopCardConfig();
  if (config === null || typeof config !== 'object') { return result; }
  if (Array.isArray(config.personIds)) {
    result.personIds = Array.from(new Set<string>(config.personIds.filter((id: string) => typeof id === 'string' && id.length > 0))).slice(0, 6);
  }
  result.nameMode = ['hidden', 'initial', 'name'].includes(config.nameMode) ? config.nameMode : 'hidden';
  result.showEventTitles = config.showEventTitles === true;
  return result;
}

const XS: number[] = [20, 50, 80, 80, 50, 20];
const YS: number[] = [28, 15, 28, 72, 85, 72];
const COLORS: string[] = ['#C97B6B', '#7BA88A', '#6A8A8F', '#C49A6C', '#A88CB2'];

// Publish only the minimum desktop presentation. Never send bodies, media,
// descriptions, credentials or hidden names to the widget rendering process.
export function projectDesktopCard(data: AppSnapshot, rawConfig: DesktopCardConfig): DesktopCardData {
  const config = normalizeCardConfig(rawConfig);
  const result = new DesktopCardData(); result.appearance = data.profile.appearance;
  const me = data.profile.defaultPersonId;
  const self = new DesktopCardNode(); self.id = me; self.label = '我'; self.shortLabel = '我'; self.color = '#C97B6B';
  result.nodes.push(self);
  config.personIds.forEach((id: string, slot: number): void => {
    const person = data.persons.find((p) => p.id === id && p.id !== me && p.deletedAt === null);
    if (person === undefined) { return; }
    const node = new DesktopCardNode(); node.id = id; node.x = XS[slot]; node.y = YS[slot];
    node.label = config.nameMode === 'name' ? person.name.slice(0, 8) :
      (config.nameMode === 'initial' ? Array.from(person.name)[0] + '·' : '人物 ' + (slot + 1).toString());
    node.shortLabel = config.nameMode === 'hidden' ? (slot + 1).toString() :
      Array.from(person.name).slice(0, config.nameMode === 'initial' ? 1 : 2).join('');
    let recent: EventCard | undefined = undefined;
    for (const card of data.events) {
      if (!card.personIds.includes(me) || !card.personIds.includes(id)) { continue; }
      node.count++;
      if (recent === undefined || card.event.occurredAt > recent.event.occurredAt ||
        (card.event.occurredAt === recent.event.occurredAt && (card.event.createdAt > recent.event.createdAt ||
          (card.event.createdAt === recent.event.createdAt && card.event.id.localeCompare(recent.event.id) < 0)))) { recent = card; }
    }
    if (recent !== undefined) {
      node.recent = config.showEventTitles ? recent.event.title.slice(0, 48) : '最近共同记录已隐藏，进入应用查看';
    }
    const edge = data.edges.find((e: RelationEdge) => (e.personAId === me && e.personBId === id) || (e.personBId === me && e.personAId === id));
    if (edge !== undefined) { node.color = COLORS[Math.max(0, data.relations.findIndex((r) => r.id === edge.relationId)) % COLORS.length]; }
    result.nodes.push(node);
  });
  for (const edge of data.edges) {
    const a = result.nodes.find((n: DesktopCardNode) => n.id === edge.personAId);
    const b = result.nodes.find((n: DesktopCardNode) => n.id === edge.personBId);
    if (a === undefined || b === undefined || a === b) { continue; }
    const pair = [a.id, b.id].sort().join(':');
    const width = 1 + Math.max(0, Math.min(5, edge.strength ?? 0)) * 0.45;
    const existing = result.links.find((link: DesktopCardLink) => link.key === pair);
    if (existing !== undefined) { existing.width = Math.max(existing.width, width); continue; }
    const link = new DesktopCardLink(); link.key = pair;
    link.x1 = a.x; link.y1 = a.y; link.x2 = b.x; link.y2 = b.y; link.width = width;
    link.color = COLORS[Math.max(0, data.relations.findIndex((r) => r.id === edge.relationId)) % COLORS.length];
    result.links.push(link);
  }
  return result;
}

export class CardRoute {
  action: string = '';
  personId: string = '';
}

export function cardLaunchBlocked(pages: string[], recording: boolean, changing: boolean): boolean {
  return recording || changing || pages.some((page: string) =>
    ['personEditor', 'eventEditor', 'profileEditor', 'aiSettings', 'desktopCard', 'tags', 'appearance'].includes(page));
}

// A single pending launch survives cold start; take only after app initialization.
export class CardLaunch {
  private static pending: CardRoute | null = null;
  static onRequest: (() => void) | null = null;
  static request(action: string, personId: string = ''): void {
    if (!['settings', 'person', 'record'].includes(action)) { return; }
    if (action === 'person' && (personId.length === 0 || personId.length > 128)) { return; }
    const route = new CardRoute(); route.action = action; route.personId = personId;
    CardLaunch.pending = route; CardLaunch.onRequest?.();
  }
  static take(): CardRoute | null { const route = CardLaunch.pending; CardLaunch.pending = null; return route; }
  static clear(): void { CardLaunch.pending = null; CardLaunch.onRequest = null; }
}
