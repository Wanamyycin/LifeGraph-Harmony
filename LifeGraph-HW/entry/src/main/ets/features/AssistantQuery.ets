import { AppSnapshot, EventCard, RelationEdge } from '../domain/Models';
import { Person } from '../domain/Person';
import { AssistantReference, ToolArguments, ToolCall, referenceUrl } from '../domain/Assistant';
import { appHelp } from './AssistantHelp';

export class PersonSummary {
  personId: string = '';
  name: string = '';
  description: string = '';
  hidden: boolean = false;
  citation: string = '';
}
export class EventSummary {
  eventId: string = '';
  title: string = '';
  occurredAt: number = 0;
  participants: PersonSummary[] = [];
  excerpt: string = '';
  contentTruncated: boolean = false;
  matchReasons: string[] = [];
  citation: string = '';
}
class EventDetail extends EventSummary {
  content: string = '';
  locationText: string = '';
  branches: string[] = [];
  emotions: string[] = [];
}
class ResolvedRelation {
  relatedPersonId: string = '';
  relatedPersonName: string = '';
  relationId: string = '';
  relationName: string = '';
  relationStrength: number | null = null;
}
class PersonDetail extends PersonSummary {
  createdAt: number = 0;
  updatedAt: number = 0;
  eventIds: string[] = [];
  eventCount: number = 0;
  eventIdsTruncated: boolean = false;
  relations: ResolvedRelation[] = [];
}
class ToolPage<T> {
  total: number = 0;
  offset: number = 0;
  nextOffset: number | null = null;
  truncated: boolean = false;
  items: T[] = [];
}
class ScoredEvent {
  card: EventCard;
  score: number = 0;
  reasons: string[] = [];
  constructor(card: EventCard) { this.card = card; }
}
class YearCount {
  year: number = 0;
  count: number = 0;
}
class RelationshipContext {
  person: PersonSummary = new PersonSummary();
  withPerson: PersonSummary = new PersonSummary();
  manualRelations: ResolvedRelation[] = [];
  directSharedCount: number = 0;
  relatedCount: number = 0;
  mentionOnlyCount: number = 0;
  targetOnlyCount: number = 0;
  firstOccurredAt: number | null = null;
  lastOccurredAt: number | null = null;
  sharedByYear: YearCount[] = [];
  events: ToolPage<EventSummary> = new ToolPage<EventSummary>();
  caveats: string[] = ['手动强度是用户判断，仅供对照；互动次数不等于亲密程度；记录只代表记录者视角。', '仅正文提及或只有目标人物参与的记录，不证明双方共同经历。'];
}

const SYNONYMS: string[][] = [
  ['吃饭', '聚餐', '晚饭', '午饭', '饭局', '餐厅'], ['出游', '旅游', '旅行', '出去玩'],
  ['争吵', '吵架', '冲突', '不愉快', '不太愉快', '不开心', '不高兴', '不快乐', '矛盾'], ['帮助', '帮忙', '支持', '照顾'],
  ['开心', '高兴', '快乐', '愉快'], ['平静', '安稳', '放松'], ['激动', '兴奋'],
  ['愤怒', '生气', '恼火'], ['难过', '伤心', '悲伤'], ['疲惫', '疲劳', '累']
];

export function executeTool(data: AppSnapshot, call: ToolCall): string {
  const args = call.arguments;
  const query = typeof args.query === 'string' ? args.query.trim().toLocaleLowerCase() : '';
  validateWindow(args);
  if (call.name === 'getAppHelp') { return JSON.stringify(appHelp(query)); }
  if (call.name === 'searchPersons') {
    const people = data.persons.filter((person: Person) => (person.deletedAt === null || args.includeHidden === true) &&
      (person.name.toLocaleLowerCase().includes(query) || (person.description ?? '').toLocaleLowerCase().includes(query)));
    return JSON.stringify(page(people.map(personSummary), args));
  }
  if (call.name === 'getPersonDetail') {
    const id = requiredText(args.personId); const person = data.persons.find((item: Person) => item.id === id);
    if (person === undefined) { return 'null'; }
    const summary = personSummary(person); const detail = new PersonDetail();
    detail.personId = summary.personId; detail.name = summary.name; detail.description = summary.description;
    detail.hidden = summary.hidden; detail.citation = summary.citation;
    detail.createdAt = person.createdAt; detail.updatedAt = person.updatedAt;
    const ids = data.events.filter((card: EventCard) => card.personIds.includes(person.id)).map((card: EventCard) => card.event.id);
    detail.eventIds = ids.slice(0, 100); detail.eventCount = ids.length; detail.eventIdsTruncated = ids.length > 100;
    detail.relations = resolvedRelations(data, person.id); return JSON.stringify(detail);
  }
  if (call.name === 'getPersonRelations') { return JSON.stringify(page(resolvedRelations(data, requiredText(args.personId)), args)); }
  if (call.name === 'getEventDetail') {
    const id = requiredText(args.eventId); const card = data.events.find((item: EventCard) => item.event.id === id);
    if (card === undefined) { return 'null'; }
    const summary = eventSummary(data, card); const detail = new EventDetail();
    detail.eventId = summary.eventId; detail.title = summary.title; detail.occurredAt = summary.occurredAt;
    detail.participants = summary.participants; detail.excerpt = summary.excerpt; detail.citation = summary.citation;
    detail.content = card.event.content.slice(0, 12000); detail.contentTruncated = card.event.content.length > 12000;
    detail.locationText = card.event.locationText;
    detail.branches = data.branches.filter((item) => card.branchIds.includes(item.id)).map((item) => item.name);
    detail.emotions = data.emotions.filter((item) => card.emotionIds.includes(item.id)).map((item) => item.name);
    return JSON.stringify(detail);
  }
  if (call.name === 'getRelationshipContext') { return relationshipContext(data, args); }
  if (['searchEvents', 'getEventsByPerson', 'getEventsByDateRange', 'getEventsByEmotion', 'countEvents'].includes(call.name)) {
    if (call.name === 'getEventsByDateRange' && (args.from === undefined || args.to === undefined)) { throw new Error('日期范围不正确'); }
    if (call.name === 'getEventsByPerson') { requiredText(args.personId); }
    if (call.name === 'getEventsByEmotion') { requiredText(args.emotionName); }
    const found = searchEvents(data, args);
    if (call.name === 'countEvents') { return '{"count":' + found.length.toString() + '}'; }
    const summaries = found.map((item: ScoredEvent): EventSummary => {
      const summary = eventSummary(data, item.card); summary.matchReasons = item.reasons.slice(0, 5); return summary;
    });
    return JSON.stringify(page(summaries, args));
  }
  if (call.name === 'countPersons') { return '{"count":' + data.persons.filter((person: Person) => person.deletedAt === null && person.id !== data.profile.defaultPersonId).length.toString() + '}'; }
  if (call.name === 'getDaysUsed') {
    const self = data.persons.find((person: Person) => person.id === data.profile.defaultPersonId);
    return '{"days":' + (self === undefined ? 0 : Math.max(1, Math.floor((Date.now() - self.createdAt) / 86400000) + 1)).toString() + '}';
  }
  throw new Error('不支持的本地查询工具');
}

function searchEvents(data: AppSnapshot, args: ToolArguments): ScoredEvent[] {
  const terms = expandedTerms(args);
  const found: ScoredEvent[] = [];
  for (const card of data.events) {
    if (!within(card, args)) { continue; }
    const result = new ScoredEvent(card);
    if (args.personIds !== undefined && !args.personIds.every((id: string) => card.personIds.includes(id))) { continue; }
    if (args.personId !== undefined) {
      const person = data.persons.find((item: Person) => item.id === args.personId);
      const direct = card.personIds.includes(args.personId);
      const mentioned = person !== undefined && person.name.length > 0 && (card.event.title + '\n' + card.event.content).includes(person.name);
      if (!direct && (args.includeMentions === false || !mentioned)) { continue; }
      result.reasons.push(direct ? '该人物是参与者' : '正文／标题提及该姓名（同名需核对）');
    }
    if (args.emotionName !== undefined) {
      const ids = data.emotions.filter((item) => matchesEmotion(item.name, args.emotionName ?? '')).map((item) => item.id);
      if (!card.emotionIds.some((id: string) => ids.includes(id))) { continue; }
      result.reasons.push('情绪标签匹配');
    }
    if (args.branchName !== undefined && !data.branches.some((item) => card.branchIds.includes(item.id) && item.name.includes(args.branchName ?? ''))) { continue; }
    if (terms.length > 0) {
      const title = card.event.title.toLocaleLowerCase(); const content = card.event.content.toLocaleLowerCase();
      const labels = [card.event.locationText, ...data.persons.filter((p: Person) => card.personIds.includes(p.id)).map((p: Person) => p.name),
        ...data.branches.filter((item) => card.branchIds.includes(item.id)).map((item) => item.name),
        ...data.emotions.filter((item) => card.emotionIds.includes(item.id)).map((item) => item.name)].join(' ').toLocaleLowerCase();
      for (const term of terms) {
        if (title.includes(term)) { result.score += 5; result.reasons.push('标题含“' + term + '”'); }
        else if (content.includes(term)) { result.score += 2; result.reasons.push('正文含“' + term + '”'); }
        else if (labels.includes(term)) { result.score++; result.reasons.push('地点／人物／标签含“' + term + '”'); }
      }
      if (result.score === 0) { continue; }
    }
    found.push(result);
  }
  return found.sort((a: ScoredEvent, b: ScoredEvent) => b.score - a.score || b.card.event.occurredAt - a.card.event.occurredAt || a.card.event.id.localeCompare(b.card.event.id));
}

function relationshipContext(data: AppSnapshot, args: ToolArguments): string {
  const target = data.persons.find((person: Person) => person.id === requiredText(args.personId));
  const otherId = args.withPersonId ?? data.profile.defaultPersonId;
  const other = data.persons.find((person: Person) => person.id === otherId);
  if (target === undefined || other === undefined) { throw new Error('人物已不存在，请先搜索人物核对'); }
  if (target.id === other.id) { throw new Error('请选择两个不同的人物'); }
  const result = new RelationshipContext(); result.person = personSummary(target); result.withPerson = personSummary(other);
  result.manualRelations = resolvedRelations(data, target.id).filter((relation: ResolvedRelation) => relation.relatedPersonId === other.id);
  if (data.persons.filter((person: Person) => person.name === target.name).length > 1) { result.caveats.push('目标人物有同名记录，正文姓名提及不能直接认定为此人。'); }
  const records: EventSummary[] = []; const shared: EventCard[] = [];
  for (const card of data.events.filter((event: EventCard) => within(event, args)).sort((a: EventCard, b: EventCard) => b.event.occurredAt - a.event.occurredAt || a.event.id.localeCompare(b.event.id))) {
    const direct = card.personIds.includes(target.id) && card.personIds.includes(other.id);
    const targetOnly = card.personIds.includes(target.id) && !card.personIds.includes(other.id);
    const mention = target.name.length > 0 && (card.event.title + '\n' + card.event.content).includes(target.name);
    if (!direct && (args.includeMentions === false || (!targetOnly && !mention))) { continue; }
    const summary = eventSummary(data, card);
    summary.matchReasons = [direct ? '双方共同参与' : targetOnly ? '目标人物参与，未记录另一方参与' : '正文／标题提及姓名（需核对）'];
    records.push(summary);
    if (direct) { result.directSharedCount++; shared.push(card); }
    else if (targetOnly) { result.targetOnlyCount++; }
    else { result.mentionOnlyCount++; }
  }
  result.relatedCount = records.length; result.events = page(records, args);
  if (shared.length === 0) { result.caveats.push('当前范围没有双方共同参与记录，无法据此判断关系强弱；未记录不等于没有经历或关系疏远。'); }
  if (shared.length > 0) {
    result.firstOccurredAt = shared[shared.length - 1].event.occurredAt;
    result.lastOccurredAt = shared[0].event.occurredAt;
    const years = new Map<number, number>();
    for (const card of shared) { const year = new Date(card.event.occurredAt).getFullYear(); years.set(year, (years.get(year) ?? 0) + 1); }
    result.sharedByYear = Array.from(years.keys()).sort().map((year: number): YearCount => { const row = new YearCount(); row.year = year; row.count = years.get(year) ?? 0; return row; });
  }
  return JSON.stringify(result);
}

function within(card: EventCard, args: ToolArguments): boolean {
  return (args.from === undefined || card.event.occurredAt >= args.from) && (args.to === undefined || card.event.occurredAt <= args.to);
}
function validateWindow(args: ToolArguments): void {
  if ([args.query, args.personId, args.withPersonId, args.eventId, args.emotionName, args.branchName].some((value: string | undefined) =>
    value !== undefined && typeof value !== 'string') || (args.includeMentions !== undefined && typeof args.includeMentions !== 'boolean') ||
    (args.includeHidden !== undefined && typeof args.includeHidden !== 'boolean')) {
    throw new Error('查询参数格式不正确');
  }
  if ((args.from !== undefined && (typeof args.from !== 'number' || !Number.isFinite(args.from))) ||
    (args.to !== undefined && (typeof args.to !== 'number' || !Number.isFinite(args.to))) ||
    (args.from !== undefined && args.to !== undefined && args.from > args.to)) { throw new Error('日期范围不正确'); }
  if (args.personIds !== undefined && (!Array.isArray(args.personIds) || args.personIds.length > 20 || args.personIds.some((id: string) => typeof id !== 'string'))) { throw new Error('人物查询参数不正确'); }
  if (args.keywords !== undefined && (!Array.isArray(args.keywords) || args.keywords.length > 20 || args.keywords.some((word: string) => typeof word !== 'string'))) { throw new Error('关键词参数不正确'); }
}
function expandedTerms(args: ToolArguments): string[] {
  const words = [...(args.query ?? '').toLocaleLowerCase().slice(0, 300).split(/[\s,，。！？、;；]+/), ...(args.keywords ?? []).map((word: string) => word.toLocaleLowerCase().slice(0, 80))].filter((word: string) => word.length > 0);
  const result = new Set<string>(words);
  const negative = words.some((word: string) => /不(?:太|怎么|很)?(?:开心|高兴|快乐|愉快)/.test(word));
  for (const group of SYNONYMS) {
    if (negative && group[0] === '开心') { continue; }
    if (words.some((word: string) => group.some((alias: string) => word.includes(alias)))) { for (const alias of group) { result.add(alias); } }
  }
  return Array.from(result).slice(0, 80);
}
function matchesEmotion(name: string, query: string): boolean {
  if (name === '开心' && /不(?:太|怎么|很)?(?:开心|高兴|快乐|愉快)/.test(query)) { return false; }
  const group = SYNONYMS.find((words: string[]) => words.includes(name)) ?? [name];
  return query.trim().length > 0 && group.some((word: string) => query.includes(word) || word.includes(query));
}
function page<T>(items: T[], args: ToolArguments): ToolPage<T> {
  const offset = args.offset ?? 0; const limit = args.limit ?? 50;
  if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 100) { throw new Error('分页参数不正确，limit 应为 1～100'); }
  const result = new ToolPage<T>(); result.total = items.length; result.offset = offset; result.items = items.slice(offset, offset + limit);
  result.truncated = offset + result.items.length < items.length;
  result.nextOffset = result.truncated ? offset + result.items.length : null; return result;
}
function personSummary(person: Person): PersonSummary {
  const result = new PersonSummary(); result.personId = person.id; result.name = person.name;
  result.description = (person.description ?? '').slice(0, 1000); result.hidden = person.deletedAt !== null;
  const ref = new AssistantReference(); ref.kind = 'person'; ref.id = person.id; result.citation = referenceUrl(ref); return result;
}
function eventSummary(data: AppSnapshot, card: EventCard): EventSummary {
  const result = new EventSummary(); result.eventId = card.event.id; result.title = card.event.title; result.occurredAt = card.event.occurredAt;
  result.participants = data.persons.filter((person: Person) => card.personIds.includes(person.id)).map(personSummary);
  // Event rows don't need unrelated biographies; keep only identity here.
  for (const person of result.participants) { person.description = ''; }
  result.excerpt = card.event.content.slice(0, 600); result.contentTruncated = card.event.content.length > 600;
  const ref = new AssistantReference(); ref.id = card.event.id; result.citation = referenceUrl(ref); return result;
}
function resolvedRelations(data: AppSnapshot, id: string): ResolvedRelation[] {
  return data.edges.filter((edge: RelationEdge) => edge.personAId === id || edge.personBId === id).map((edge: RelationEdge): ResolvedRelation => {
    const result = new ResolvedRelation(); result.relatedPersonId = edge.personAId === id ? edge.personBId : edge.personAId;
    result.relatedPersonName = data.persons.find((person: Person) => person.id === result.relatedPersonId)?.name ?? '已删除的人物';
    result.relationId = edge.relationId; result.relationName = data.relations.find((item) => item.id === edge.relationId)?.name ?? '关系';
    result.relationStrength = edge.strength; return result;
  });
}
function requiredText(value: string | undefined): string {
  if (typeof value !== 'string' || value.trim().length === 0) { throw new Error('查询参数缺失'); } return value;
}
