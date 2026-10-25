require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { AppSnapshot, EventCard, RelationEdge, NamedItem } = require('../entry/src/main/ets/domain/Models.ets');
const { Person } = require('../entry/src/main/ets/domain/Person.ets');
const { AssistantTurn, AssistantAnswer, ToolCall, decodeConversation, encodeConversation } = require('../entry/src/main/ets/domain/Assistant.ets');
const { AIAgent, executeTool, recentConversation } = require('../entry/src/main/ets/features/AIAgent.ets');
const { AssistantController } = require('../entry/src/main/ets/features/AssistantController.ets');
const { parseMarkdown, inlineMarkdown, safeMarkdownLink } = require('../entry/src/main/ets/features/Markdown.ets');
const { AI_TOOLS_JSON } = require('../entry/src/main/ets/data/AiTools.ets');

function fixture() {
  const data = new AppSnapshot(); data.profile.defaultPersonId = 'me';
  for (const [id, name, description] of [['me', '我', '自己'], ['friend', '阿宁', '大学同学'], ['same', '阿宁', '工作认识'], ['other', '小夏', '朋友']]) {
    const p = new Person(); p.id = id; p.name = name; p.description = description; data.persons.push(p);
  }
  const emotion = new NamedItem(); emotion.id = 'happy'; emotion.name = '开心'; data.emotions.push(emotion);
  const relation = new NamedItem(); relation.id = 'friendship'; relation.name = '朋友'; data.relations.push(relation);
  const edge = new RelationEdge(); edge.id = 'r'; edge.personAId = 'friend'; edge.personBId = 'me'; edge.relationId = 'friendship'; edge.strength = 2; data.edges.push(edge);
  addEvent(data, 'together', ['me', 'friend'], '普通的一天', '去餐厅吃饭，聊起大学，非常开心', Date.UTC(2025, 5, 4));
  data.events[0].emotionIds = ['happy']; data.events[0].event.locationText = '河边书店';
  addEvent(data, 'mention', ['me'], '一个人的下午', '想起和阿宁以前的争吵', Date.UTC(2024, 4, 3));
  addEvent(data, 'target-only', ['friend'], '旅行', '不确定另一方是否参与', Date.UTC(2023, 1, 1));
  addEvent(data, 'unrelated', ['other'], '散步', '一条无关记录', Date.UTC(2026, 1, 1));
  return data;
}
function addEvent(data, id, persons, title = id, content = '', occurredAt = 1) {
  const card = new EventCard(); card.event.id = id; card.event.title = title; card.event.content = content; card.event.occurredAt = occurredAt; card.personIds = persons; data.events.push(card); return card;
}
function query(data, name, args = {}) { const call = new ToolCall(); call.name = name; call.arguments = args; return JSON.parse(executeTool(data, call)); }
function turn(text, user, status = 'complete') { const value = new AssistantTurn(); value.id = Math.random().toString(); value.text = text; value.user = user; value.status = status; value.createdAt = Date.now(); return value; }
function answer(text) { const value = new AssistantAnswer(); value.text = text; return value; }
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
async function settleUntil(predicate) { for (let i = 0; i < 30; i++) { if (predicate()) return; await Promise.resolve(); } assert.fail('expected state did not arrive'); }
function memoryStore(initial = []) {
  return { value: initial, saves: [], async load() { return decodeConversation(JSON.stringify(this.value)); },
    async save(value) { const copy = JSON.parse(encodeConversation(value)); this.saves.push(copy); this.value = copy; } };
}

test('tool schemas remain compatible with the existing backend and expose only read-only names', () => {
  const defs = JSON.parse(AI_TOOLS_JSON); assert.equal(defs.length, 13); assert.equal(new Set(defs.map(x => x.name)).size, 13);
  assert.ok(defs.some(x => x.name === 'getRelationshipContext')); assert.ok(defs.some(x => x.name === 'getAppHelp'));
  assert.ok(defs.every(x => !/save|write|delete|update/i.test(x.name) && x.parameters.type === 'object'));
});
test('person search returns same-name candidates and supports descriptions for disambiguation', () => {
  const data = fixture(); assert.equal(query(data, 'searchPersons', { query: '阿宁' }).total, 2);
  assert.equal(query(data, 'searchPersons', { query: '大学' }).items[0].personId, 'friend');
});
test('fuzzy event retrieval searches body, location and emotion synonyms with reasons', () => {
  const data = fixture();
  const result = query(data, 'searchEvents', { query: '聚餐' }); assert.equal(result.items[0].eventId, 'together');
  assert.ok(result.items[0].matchReasons.some(x => x.includes('正文')));
  assert.equal(query(data, 'searchEvents', { query: '书店' }).items[0].eventId, 'together');
  assert.equal(query(data, 'getEventsByEmotion', { emotionName: '快乐' }).items[0].eventId, 'together');
  assert.equal(query(data, 'searchEvents', { query: '完全不存在的词' }).total, 0);
});
test('person AND and time filters distinguish participants from body mentions', () => {
  const data = fixture();
  assert.deepEqual(query(data, 'searchEvents', { personIds: ['me', 'friend'] }).items.map(x => x.eventId), ['together']);
  assert.equal(query(data, 'getEventsByPerson', { personId: 'friend' }).total, 3);
  assert.equal(query(data, 'getEventsByPerson', { personId: 'friend', includeMentions: false }).total, 2);
  assert.equal(query(data, 'countEvents', { from: Date.UTC(2025, 0), to: Date.UTC(2025, 11, 31), personIds: ['me', 'friend'] }).count, 1);
  assert.throws(() => query(data, 'getEventsByDateRange', { from: 3, to: 1 }), /日期/);
});
test('pagination beyond 100 records has stable cursors without omissions and exact full counts', () => {
  const data = fixture(); data.events = [];
  for (let i = 0; i < 237; i++) addEvent(data, 'event-' + i, ['me', 'friend'], '聚餐', '', 1);
  let offset = 0; const ids = [];
  do { const page = query(data, 'searchEvents', { query: '聚餐', offset, limit: 40 }); assert.equal(page.total, 237); ids.push(...page.items.map(x => x.eventId)); offset = page.nextOffset; } while (offset !== null);
  assert.equal(ids.length, 237); assert.equal(new Set(ids).size, 237);
  assert.equal(query(data, 'countEvents', { personIds: ['me', 'friend'] }).count, 237);
  assert.throws(() => query(data, 'searchEvents', { limit: 101 }), /分页/);
});
test('relationship context separates shared events, target-only and mentions, and marks ambiguous names', () => {
  const data = fixture(); const result = query(data, 'getRelationshipContext', { personId: 'friend', limit: 1 });
  assert.equal(result.directSharedCount, 1); assert.equal(result.targetOnlyCount, 1); assert.equal(result.mentionOnlyCount, 1);
  assert.equal(result.relatedCount, 3); assert.equal(result.events.nextOffset, 1); assert.equal(result.manualRelations[0].relationStrength, 2);
  assert.deepEqual(result.sharedByYear, [{ year: 2025, count: 1 }]); assert.ok(result.caveats.some(x => x.includes('同名')));
  assert.equal(query(data, 'getRelationshipContext', { personId: 'friend', includeMentions: false }).relatedCount, 1);
  assert.throws(() => query(data, 'getRelationshipContext', { personId: 'me' }), /不同/);
});
test('read-only tools do not mutate a snapshot and omit storage paths or media binaries', () => {
  const data = fixture(); data.mediaAssets = [{ id: 'audio', storagePath: 'private-recording.wav', mediaKind: 'audio' }];
  const before = JSON.stringify(data); const result = query(data, 'getEventDetail', { eventId: 'together' });
  assert.equal(result.participants.length, 2); assert.ok(!JSON.stringify(result).includes('private-recording'));
  query(data, 'getRelationshipContext', { personId: 'friend' }); assert.equal(JSON.stringify(data), before);
  assert.throws(() => query(data, 'deletePerson', { personId: 'friend' }), /不支持/);
});
test('overlong event details clearly mark excerpt limits', () => {
  const data = fixture(); data.events[0].event.content = '长'.repeat(15000);
  const result = query(data, 'getEventDetail', { eventId: 'together' }); assert.equal(result.content.length, 12000); assert.equal(result.contentTruncated, true);
});
test('software help does not read personal data, and requires no database snapshot', async () => {
  let snapshots = 0, calls = 0;
  const agent = new AIAgent({ async snapshot() { snapshots++; return fixture(); } }, { async chat(messages) {
    calls++; if (calls === 1) return { kind: 'tool_calls', tool_calls: [{ id: 'help', name: 'getAppHelp', arguments: { query: 'events' } }] };
    assert.ok(messages.find(x => x.role === 'tool').content.includes('参与者'));
    return { kind: 'text', content: '从首页＋记录进入事件表单。' };
  } });
  const result = await agent.askDetailed('怎么新建事件？'); assert.equal(snapshots, 0); assert.equal(result.readAt, 0); assert.equal(result.references[0].kind, 'help');
});
test('agent uses one fresh snapshot per turn and only verifies queried source links', async () => {
  let snapshots = 0, calls = 0; const data = fixture();
  const agent = new AIAgent({ async snapshot() { snapshots++; return data; } }, { async chat() {
    calls++; if (calls === 1) return { kind: 'tool_calls', tool_calls: [{ id: 's', name: 'getEventDetail', arguments: { eventId: 'together' } }] };
    if (calls === 2) return { kind: 'tool_calls', tool_calls: [{ id: 'p', name: 'getPersonDetail', arguments: { personId: 'friend' } }] };
    return { kind: 'text', content: '见[聚餐](lifegraph://event/together)，[错误](lifegraph://event/unrelated)。' };
  } });
  const result = await agent.askDetailed('我们经历了什么？'); assert.equal(snapshots, 1);
  assert.ok(result.text.includes('[聚餐](lifegraph://event/together)')); assert.ok(!result.text.includes('](lifegraph://event/unrelated)'));
  assert.ok(result.references.some(x => x.id === 'together')); assert.ok(!result.references.some(x => x.id === 'unrelated'));
});
test('an ungrounded model answer is not accepted as a database fact', async () => {
  let calls = 0; const agent = new AIAgent({ async snapshot() { assert.fail('no tool requested'); } }, { async chat() { calls++; return { kind: 'text', content: '你们有99次共同经历。' }; } });
  await assert.rejects(agent.ask('我和阿宁有多少共同经历？'), /具体/); assert.equal(calls, 8);
});
test('canceled transports stop before reading records or accepting a late answer', async () => {
  const transport = { canceled: false, isCanceled() { return this.canceled; }, async chat() { this.canceled = true; return { kind: 'tool_calls', tool_calls: [{ id: '1', name: 'countEvents', arguments: {} }] }; } };
  await assert.rejects(new AIAgent({ async snapshot() { assert.fail('must stop first'); } }, transport).ask('统计'), /停止/);
});
test('multi-turn context includes successful recent pairs and excludes canceled or failed questions', () => {
  const history = [];
  history.push(turn('失败的问题', true, 'failed'));
  for (let i = 0; i < 10; i++) history.push(turn('问题' + i, true), turn('回复' + i, false));
  const result = recentConversation(history); assert.equal(result.messages.length, 12); assert.equal(result.messages[0].content, '问题4');
  assert.ok(result.note.includes('最近6轮')); assert.ok(!JSON.stringify(result).includes('失败的问题'));
});
test('markdown supports emphasis, fenced code, quotes and pipe tables without HTML execution', () => {
  const blocks = parseMarkdown('# 回顾\n> 一段引用\n\n| 项目 | 说明 |\n| --- | --- |\n| a\\|b | `c|d` |\n\n~~~js\n<script>bad()</script>\n~~~');
  assert.equal(blocks[0].heading, 1); assert.equal(blocks[1].quote, true);
  const table = blocks.find(x => x.rows.length); assert.equal(table.rows[1].cells.length, 2); assert.equal(table.rows[1].cells[0].map(x => x.text).join(''), 'a|b');
  const code = blocks.find(x => x.code); assert.equal(code.text, '<script>bad()</script>'); assert.equal(code.parts.length, 0);
  const parts = inlineMarkdown('**重要** *推断* `代码` [来源](lifegraph://event/together)');
  assert.ok(parts.some(x => x.bold)); assert.ok(parts.some(x => x.italic)); assert.ok(parts.some(x => x.code)); assert.ok(parts.some(x => x.href === 'lifegraph://event/together'));
});
test('markdown rejects executable or malformed links and never links code contents', () => {
  for (const url of ['javascript:alert(1)', 'file:///private/db', 'data:text/html,x', 'lifegraph://event/%broken', 'https://host/a b']) assert.equal(safeMarkdownLink(url), '');
  assert.equal(safeMarkdownLink('https://example.com/help'), 'https://example.com/help');
  assert.equal(inlineMarkdown('`https://example.com`')[0].href, '');
  assert.ok(inlineMarkdown('[x](javascript:alert(1))').every(x => !x.href));
});
test('history codec preserves pending state on write and marks interrupted requests canceled on reopen', () => {
  const user = turn('一个问题', true, 'pending'); const value = encodeConversation([user]);
  assert.equal(JSON.parse(value)[0].status, 'pending'); assert.equal(user.status, 'pending'); assert.equal(decodeConversation(value)[0].status, 'canceled');
  assert.throws(() => decodeConversation('[{}]'), /格式/); assert.throws(() => encodeConversation([turn('长'.repeat(100001), true)]), /格式/);
});
test('controller persists a complete pair and sends prior successful context on follow-up', async () => {
  const store = memoryStore(); const requests = [];
  const controller = new AssistantController(store, () => ({ async ask(q, history) { requests.push({ q, history }); return answer('答复'); }, cancel() {} }), () => {});
  await controller.load(); await controller.send('我和阿宁如何？'); await controller.send('那去年呢？');
  assert.equal(requests[1].history.length, 2); assert.equal(store.value.length, 4); assert.equal(store.value.every(x => x.status === 'complete'), true);
  const reopened = new AssistantController(store, () => {}, () => {}); await reopened.load(); assert.equal(reopened.snapshot().turns.length, 4);
});
test('cancel during initial persistence prevents any outbound request', async () => {
  const store = memoryStore(), gate = deferred(); let saves = 0, runners = 0;
  const save = store.save.bind(store); store.save = async value => { if (++saves === 1) await gate.promise; await save(value); };
  const controller = new AssistantController(store, () => { runners++; return {}; }, () => {}); await controller.load();
  const pending = controller.send('问题'); await settleUntil(() => saves === 1); const cancel = controller.cancel(); gate.resolve(); await Promise.all([pending, cancel]);
  assert.equal(runners, 0); assert.equal(store.value[0].status, 'canceled'); assert.equal(controller.snapshot().busy, false);
});
test('late replies after cancel cannot overwrite a newer request or saved history', async () => {
  const store = memoryStore(), old = deferred(); let calls = 0, canceled = 0;
  const controller = new AssistantController(store, () => ({ async ask() { return ++calls === 1 ? old.promise : answer('新答复'); }, cancel() { canceled++; } }), () => {});
  await controller.load(); const pending = controller.send('旧问题'); await settleUntil(() => calls === 1); await controller.cancel();
  await controller.send('新问题'); old.resolve(answer('不应出现的旧答复')); await pending;
  assert.equal(canceled, 1); assert.equal(store.value.at(-1).text, '新答复'); assert.ok(!JSON.stringify(store.value).includes('不应出现'));
});
test('clear invalidates an in-flight query and cannot be undone by its late result', async () => {
  const store = memoryStore(), gate = deferred(); let running = false;
  const controller = new AssistantController(store, () => ({ async ask() { running = true; return gate.promise; }, cancel() {} }), () => {});
  await controller.load(); const pending = controller.send('问题'); await settleUntil(() => running); await controller.clear(); gate.resolve(answer('迟到')); await pending;
  assert.equal(controller.snapshot().turns.length, 0); assert.equal(store.value.length, 0);
});
test('failed final persistence retains the generated answer and warns instead of retrying the model', async () => {
  const store = memoryStore(); let saves = 0, calls = 0; const save = store.save.bind(store);
  store.save = async value => { if (++saves === 2) throw new Error('disk full'); await save(value); };
  const controller = new AssistantController(store, () => ({ async ask() { calls++; return answer('可复制的回复'); }, cancel() {} }), () => {});
  await controller.load(); await controller.send('问题'); assert.equal(calls, 1);
  assert.equal(controller.snapshot().turns.at(-1).text, '可复制的回复'); assert.ok(controller.snapshot().error.includes('保存未完成'));
});
test('corrupted history is isolated from records and can be cleared; local help uses no runner', async () => {
  const store = memoryStore(); store.load = async () => { throw new Error('bad history'); };
  let runners = 0; const controller = new AssistantController(store, () => { runners++; return {}; }, () => {});
  await controller.load(); assert.equal(controller.snapshot().ready, false); assert.ok(controller.snapshot().error.includes('人物和事件不受影响'));
  await controller.clear(); await controller.showHelp(); assert.equal(runners, 0); assert.ok(controller.snapshot().turns.at(-1).text.includes('参与者'));
});

test('negative moods in fuzzy queries are not expanded into positive emotion matches', () => {
  const result = query(fixture(), 'searchEvents', { query: '不太愉快' });
  assert.ok(result.items.some(x => x.eventId === 'mention'));
  assert.ok(!result.items.some(x => x.eventId === 'together'));
  assert.equal(query(fixture(), 'getEventsByEmotion', { emotionName: '不开心' }).total, 0);
});

test('historical people can be explicitly searched without changing active counts', () => {
  const data = fixture(); data.persons.find(p => p.id === 'friend').deletedAt = 1;
  assert.equal(query(data, 'searchPersons', { query: '大学' }).total, 0);
  assert.equal(query(data, 'searchPersons', { query: '大学', includeHidden: true }).items[0].hidden, true);
  assert.equal(query(data, 'countPersons').count, 2);
  assert.throws(() => query(data, 'searchEvents', { query: 1 }), /格式/);
  assert.throws(() => query(data, 'searchEvents', { includeMentions: 'false' }), /格式/);
  assert.throws(() => query(new AppSnapshot(), 'getEventDetail'), /参数缺失/);
  assert.throws(() => query(new AppSnapshot(), 'getPersonDetail'), /参数缺失/);
});
test('long earlier answers keep the most recent question in context with an explicit excerpt notice', () => {
  const history = [turn('我和阿宁如何？', true), turn('长'.repeat(40000), false)];
  const result = recentConversation(history); assert.equal(result.messages[0].content, '我和阿宁如何？');
  assert.ok(result.messages[1].content.length < 10000); assert.ok(result.note.includes('全文仍保存在本机'));
});
test('history byte budget accounts for Chinese text and duplicate row identities', () => {
  const history = Array.from({ length: 4 }, () => turn('中'.repeat(90000), false));
  assert.throws(() => encodeConversation(history), /容量/);
  const item = turn('hello', true); assert.throws(() => encodeConversation([item, item]), /格式/);
});
test('leaving a completed response waits for its queued persistence before restoring another database', async () => {
  const store = memoryStore(), gate = deferred(); let saves = 0, reachedFinalSave = false, drained = false; const save = store.save.bind(store);
  store.save = async value => { if (++saves === 2) { reachedFinalSave = true; await gate.promise; } await save(value); };
  const controller = new AssistantController(store, () => ({ async ask() { return answer('已生成'); }, cancel() {} }), () => {});
  await controller.load(); const pending = controller.send('问题'); await settleUntil(() => reachedFinalSave);
  const barrier = controller.cancel().then(() => { drained = true; }); await Promise.resolve(); assert.equal(drained, false);
  gate.resolve(); await Promise.all([pending, barrier]); assert.equal(drained, true); assert.equal(store.value.length, 2);
});
test('disposed controllers ignore progress and late results', async () => {
  const store = memoryStore(), gate = deferred(); let progress, running = false, changes = 0, statuses = 0;
  const controller = new AssistantController(store, () => ({ async ask(q, h, cb) { progress = cb; running = true; cb('活跃进度'); return gate.promise; }, cancel() {} }), () => { changes++; }, () => { statuses++; });
  await controller.load(); const pending = controller.send('问题'); await settleUntil(() => running);
  assert.equal(statuses, 1); controller.dispose(); const before = changes; progress('迟到进度'); gate.resolve(answer('迟到回复')); await pending;
  assert.equal(statuses, 1);
  assert.equal(changes, before); assert.equal(store.value.length, 1); assert.equal(store.value[0].status, 'pending');
  assert.equal(decodeConversation(JSON.stringify(store.value))[0].status, 'canceled');
});
