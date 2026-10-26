require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { writeZip, readZip, copyZipEntry, ZipSource } = require('../entry/src/main/ets/data/StoredZip.ets');
const { buildGraph } = require('../entry/src/main/ets/features/GraphData.ets');
const { AIAgent, ChatReply, ToolCall, executeTool } = require('../entry/src/main/ets/features/AIAgent.ets');
const { AppSnapshot, NamedItem, RelationEdge, EventCard, Palette, ProfileConfig, paletteFor, graphThemeFor } = require('../entry/src/main/ets/domain/Models.ets');
const { Person } = require('../entry/src/main/ets/domain/Person.ets');
const { findEvents, formatBytes, timelineEvents, groupTimelineEvents, timelineGroupLabel, eventWeekdayLabel } = require('../entry/src/main/ets/features/EventQuery.ets');
const { ColorModeController } = require('../entry/src/main/ets/runtime/ColorModeController.ets');

test('graph and native palette agree for explicit light/dark and follow-system in every theme', () => {
  for (const theme of ['forest', 'ocean', 'sunset', 'minimal']) for (const appearance of ['light', 'dark', 'system']) for (const systemDark of [false, true]) {
    const profile = new ProfileConfig(); profile.themeKey = theme; profile.appearance = appearance;
    const dark = appearance === 'dark' || (appearance === 'system' && systemDark);
    assert.equal(graphThemeFor(profile, systemDark), theme + (dark ? '-dark' : '-light'));
    const html = fs.readFileSync(path.join(__dirname, '../entry/src/main/resources/rawfile/graph', graphThemeFor(profile, systemDark) + '.html'), 'utf8');
    assert.ok(html.includes('background: ' + paletteFor(profile, systemDark).paper));
  }
});

test('native mode overrides return to follow-system without configuration callback loops and retry failures', () => {
  const modes = []; const controller = new ColorModeController(mode => modes.push(mode));
  for (const mode of ['system', 'system', 'dark', 'dark', 'system', 'light', 'light', 'system']) controller.setAppearance(mode);
  assert.deepEqual(modes, ['system', 'dark', 'system', 'light', 'system']);
  let calls = 0; const retry = new ColorModeController(() => { if (++calls === 1) throw new Error('platform failure'); });
  assert.throws(() => retry.setAppearance('dark'), /platform failure/); retry.setAppearance('dark'); retry.setAppearance('dark'); assert.equal(calls, 2);
});

test('primary control text has readable contrast in every dark theme', () => {
  function luminance(hex) { const channels = hex.slice(1).match(/../g).map(x => parseInt(x, 16) / 255).map(x => x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4); return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722; }
  for (const theme of ['forest', 'ocean', 'sunset', 'minimal']) {
    const profile = new ProfileConfig(); profile.themeKey = theme; profile.appearance = 'dark'; const colors = paletteFor(profile, false);
    const pair = [luminance(colors.primary), luminance(colors.onPrimary)].sort((a, b) => b - a);
    assert.ok((pair[0] + 0.05) / (pair[1] + 0.05) >= 4.5, theme);
  }
});

class BufferFile {
  constructor(bytes = new Uint8Array()) { this.bytes = bytes; this.largestRead = 0; }
  async size() { return this.bytes.length; }
  async read(offset, length) { this.largestRead = Math.max(length, this.largestRead); return this.bytes.slice(offset, offset + length); }
  async write(offset, bytes) {
    if (offset + bytes.length > this.bytes.length) { const next = new Uint8Array(offset + bytes.length); next.set(this.bytes); this.bytes = next; }
    this.bytes.set(bytes, offset);
  }
  async close() {}
}
async function archive() {
  const output = new BufferFile();
  const manifest = new TextEncoder().encode('{"format":"lifegraph-harmony","文字":"生活记录"}');
  const image = new Uint8Array(180000).map((_, index) => index % 251);
  const source = new BufferFile(image);
  await writeZip(output, [new ZipSource('manifest.json', new BufferFile(manifest)), new ZipSource('media/fixture.jpg', source)]);
  return { output, image, manifest, source };
}

test('streaming ZIP roundtrips UTF-8 manifests and binary media in bounded chunks', async () => {
  const { output, image, manifest, source } = await archive();
  const entries = await readZip(output);
  assert.equal(entries.length, 2);
  assert.ok(source.largestRead <= 65536);
  for (const entry of entries) {
    const extracted = new BufferFile(); await copyZipEntry(output, entry, extracted);
    assert.deepEqual(extracted.bytes, entry.name === 'manifest.json' ? manifest : image);
  }
  const directory = path.resolve(__dirname, '../.test'); fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, 'interop.zip'), output.bytes);
});

test('CRC detects modified attachments before a database replacement', async () => {
  const { output } = await archive(); const entries = await readZip(output);
  output.bytes[entries[1].dataOffset + 10] ^= 1;
  await assert.rejects(copyZipEntry(output, entries[1], new BufferFile()), /校验失败/);
});

test('ZIP rejects traversal, duplicate paths, truncated archives and incompatible compression', async () => {
  await assert.rejects(writeZip(new BufferFile(), [new ZipSource('media/../../database.db', new BufferFile())]), /路径/);
  await assert.rejects(writeZip(new BufferFile(), [new ZipSource('manifest.json', new BufferFile()), new ZipSource('manifest.json', new BufferFile())]), /重复/);
  const { output } = await archive();
  await assert.rejects(readZip(new BufferFile(output.bytes.slice(0, -8))), /ZIP|结构/);
  const view = new DataView(output.bytes.buffer); const end = output.bytes.length - 22;
  const central = view.getUint32(end + 16, true); view.setUint16(central + 10, 8, true);
  await assert.rejects(readZip(output), /鸿蒙版/);
});

function graphFixture() {
  const data = new AppSnapshot(); data.profile.defaultPersonId = 'me';
  for (const id of ['me', 'friend', 'other', 'unconnected']) { const p = new Person(); p.id = id; p.name = id; data.persons.push(p); }
  const relation = new NamedItem(); relation.id = 'friend-type'; relation.name = '朋友'; data.relations = [relation];
  const edge = new RelationEdge(); edge.id = 'edge'; edge.personAId = 'friend'; edge.personBId = 'me'; edge.relationId = relation.id; edge.strength = 4; data.edges = [edge];
  const branch = new NamedItem(); branch.id = 'daily'; branch.name = '日常'; data.branches = [branch];
  const card = new EventCard(); card.event.id = 'walk'; card.event.title = '散步'; card.personIds = ['friend', 'other']; card.branchIds = ['daily']; data.events = [card];
  return data;
}

test('home graph preserves relation strength and excludes disconnected people and events', () => {
  const graph = buildGraph(graphFixture(), 'home', 'me', [], [], new Palette());
  assert.deepEqual(graph.personNodes.map(p => p.id).sort(), ['friend', 'me']);
  assert.equal(graph.eventNodes.length, 0);
  assert.equal(graph.edges[0].strength, 4);
  const filtered = buildGraph(graphFixture(), 'home', 'me', ['other-type'], [], new Palette());
  assert.deepEqual(filtered.personNodes.map(p => p.id), ['me']);
});

test('person graph shows only the center events plus co-participants and valid edges', () => {
  const graph = buildGraph(graphFixture(), 'person', 'friend', [], [], new Palette());
  assert.equal(graph.eventNodes[0].id, 'walk');
  assert.deepEqual(graph.personNodes.map(p => p.id).sort(), ['friend', 'me', 'other']);
  const ids = new Set([...graph.personNodes, ...graph.eventNodes].map(node => node.id));
  assert.ok(graph.edges.every(edge => ids.has(edge.source) && ids.has(edge.target)));
  assert.equal(buildGraph(graphFixture(), 'person', 'friend', [], ['missing'], new Palette()).eventNodes.length, 0);
});

test('branch graph uses original branch node kind and links into event nodes', () => {
  const data = graphFixture(); data.events[0].personIds.push('me');
  const graph = buildGraph(data, 'branch', '', [], [], new Palette());
  assert.equal(graph.personNodes[0].nodeType, 'branch');
  assert.ok(graph.edges.some(edge => edge.source === 'branch:daily' && edge.target === 'walk'));
});

test('personal branch graph retains self, participants and unassigned events while excluding others-only events', () => {
  const data = graphFixture();
  const mine = new EventCard(); mine.event.id = 'mine'; mine.personIds = ['me', 'friend']; mine.branchIds = ['daily'];
  const unassigned = new EventCard(); unassigned.event.id = 'unassigned'; unassigned.personIds = ['me'];
  data.events.push(mine, unassigned);
  const graph = buildGraph(data, 'branch', '', [], [], new Palette());
  assert.deepEqual(graph.eventNodes.map(node => node.id).sort(), ['mine', 'unassigned']);
  assert.ok(graph.personNodes.some(node => node.id === 'me' && node.isCenter));
  assert.ok(graph.personNodes.some(node => node.id === 'friend'));
  assert.ok(graph.edges.some(edge => edge.source === 'me' && edge.target === 'branch:daily'));
  assert.ok(graph.edges.some(edge => edge.source === 'me' && edge.target === 'unassigned'));
  const ids = new Set([...graph.personNodes, ...graph.eventNodes].map(node => node.id));
  assert.ok(graph.edges.every(edge => ids.has(edge.source) && ids.has(edge.target)));
  assert.equal(buildGraph(data, 'branch', '', [], ['missing'], new Palette()).eventNodes.length, 0);
});

test('event search combines multiple branches with OR and supports an independent unfiltered global search', () => {
  const data = graphFixture();
  const second = new EventCard(); second.event.id = 'work'; second.event.title = '工作'; second.event.content = '书店讨论'; second.branchIds = ['work']; data.events.push(second);
  assert.deepEqual(findEvents(data, '', ['daily', 'work']).map(card => card.event.id), ['walk', 'work']);
  assert.deepEqual(findEvents(data, '  书店  ', ['daily', 'work']).map(card => card.event.id), ['work']);
  assert.equal(findEvents(data, '工作', ['daily']).length, 0);
  assert.equal(findEvents(data, '工作', []).length, 1);
  assert.equal(findEvents(data, '', ['missing']).length, 0);
});

test('timeline filters shared experiences, orders newest first, and groups by selected grain', () => {
  const data = graphFixture();
  data.events[0].event.occurredAt = new Date(2026, 9, 21).getTime();
  const second = new EventCard(); second.event.id = 'older'; second.event.title = '更早的记录';
  second.event.occurredAt = new Date(2025, 8, 1).getTime(); second.personIds = ['friend']; data.events.push(second);
  const newest = timelineEvents(data, { query: '', branchIds: [], personId: 'friend', grain: 'month', ascending: false });
  assert.deepEqual(newest.map(card => card.event.id), ['walk', 'older']);
  const oldest = timelineEvents(data, { query: '', branchIds: [], personId: 'friend', grain: 'month', ascending: true });
  assert.deepEqual(oldest.map(card => card.event.id), ['older', 'walk']);
  assert.equal(timelineEvents(data, { query: '', branchIds: [], personId: 'unconnected', grain: 'month', ascending: false }).length, 0);
  const groups = groupTimelineEvents(newest, 'month');
  assert.deepEqual(groups.map(group => group.key), ['2026-10', '2025-09']);
  assert.equal(timelineGroupLabel(new Date(2026, 9, 21).getTime(), 'year'), '2026 年');
  assert.equal(eventWeekdayLabel(new Date(2026, 9, 21).getTime()), '周三');
});

test('space labels distinguish byte units and unavailable measurements', () => {
  assert.equal(formatBytes(0), '0 B'); assert.equal(formatBytes(1024), '1.0 KB');
  assert.equal(formatBytes(1048576), '1.0 MB'); assert.equal(formatBytes(1073741824), '1.00 GB');
  assert.equal(formatBytes(-1), '未知'); assert.equal(formatBytes(NaN), '未知');
});

test('AI tool roundtrip sends real local tool results and one grouped assistant message', async () => {
  const data = graphFixture(); const calls = [];
  const transport = { async chat(messages) {
    calls.push(structuredClone(messages));
    const reply = new ChatReply();
    if (calls.length === 1) {
      reply.kind = 'tool_calls'; reply.tool_calls = ['countPersons', 'countEvents'].map((name, i) => { const call = new ToolCall(); call.id = `tool-${i}`; call.name = name; return call; });
    } else { reply.kind = 'text'; reply.content = '已根据记录查询。'; }
    return reply;
  } };
  assert.equal(await new AIAgent({ snapshot: async () => data }, transport).ask('有多少人物和事件？'), '已根据记录查询。');
  assert.equal(calls[1].filter(m => m.role === 'assistant').length, 1);
  assert.deepEqual(calls[1].filter(m => m.role === 'tool').map(m => JSON.parse(m.content)), [{ count: 3 }, { count: 1 }]);
});

test('AI enforces a round limit and rejects unknown tools or bad time ranges', async () => {
  const data = graphFixture(); let rounds = 0;
  const transport = { async chat() { rounds++; const reply = new ChatReply(); reply.kind = 'tool_calls'; const call = new ToolCall(); call.name = 'countEvents'; call.id = `tool-${rounds}`; reply.tool_calls = [call]; return reply; } };
  await assert.rejects(new AIAgent({ snapshot: async () => data }, transport).ask('重复查询'), /具体的问题/);
  assert.equal(rounds, 8);
  const bad = new ToolCall(); bad.name = 'deleteEverything';
  assert.throws(() => executeTool(data, bad), /不支持/);
  bad.name = 'getEventsByDateRange'; bad.arguments.from = 10; bad.arguments.to = 1;
  assert.throws(() => executeTool(data, bad), /日期范围/);
});

test('AI resolves local names, event links, emotion synonyms and reports truncated results', () => {
  const data = graphFixture();
  const emotion = new NamedItem(); emotion.id = 'happy'; emotion.name = '开心'; data.emotions = [emotion]; data.events[0].emotionIds = ['happy'];
  function query(name, args) { const call = new ToolCall(); call.name = name; call.arguments = args; return JSON.parse(executeTool(data, call)); }
  const person = query('getPersonDetail', { personId: 'friend' });
  assert.deepEqual(person.eventIds, ['walk']);
  assert.equal(person.relations[0].relatedPersonName, 'me');
  assert.equal(person.relations[0].relationName, '朋友');
  const event = query('getEventDetail', { eventId: 'walk' });
  assert.ok(event.participants.some(item => item.name === 'friend'));
  assert.deepEqual(event.emotions, ['开心']);
  assert.equal(query('getEventsByEmotion', { emotionName: '快乐' }).items[0].eventId, 'walk');
  assert.equal(query('searchPersons', { query: '' }).items[0].avatarAssetId, undefined);
  for (let i = 0; i < 110; i++) { const p = new Person(); p.id = 'extra-' + i; p.name = '人' + i; data.persons.push(p); }
  const result = query('searchPersons', { query: '' });
  assert.equal(result.items.length, 50); assert.equal(result.total, 114); assert.equal(result.truncated, true); assert.equal(result.nextOffset, 50);
});

test('native file adapter honors relative SDK offsets and partial reads and writes', async () => {
  const Module = require('node:module'); const originalLoad = Module._load;
  const contents = new Map(); const handles = new Map(); let serial = 0;
  const nativeFs = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4, READ_ONLY: 0 }, WhenceType: { SEEK_SET: 0 },
    async open(name, mode) { if (mode & 4) contents.set(name, new Uint8Array()); const file = { fd: ++serial, name, pointer: 0 }; handles.set(file.fd, file); return file; },
    async close(file) { handles.delete(file.fd); },
    async stat(fd) { return { size: contents.get(handles.get(fd).name).length }; },
    lseek(fd, offset) { handles.get(fd).pointer = offset; return offset; },
    async read(fd, buffer, options) {
      const file = handles.get(fd); file.pointer += options.offset || 0;
      const source = contents.get(file.name); const count = Math.min(buffer.byteLength, 7777, source.length - file.pointer);
      new Uint8Array(buffer).set(source.slice(file.pointer, file.pointer + count)); file.pointer += count; return count;
    },
    async write(fd, buffer, options) {
      const file = handles.get(fd); file.pointer += options.offset || 0;
      const bytes = new Uint8Array(buffer); const count = Math.min(bytes.length, 3333);
      let output = contents.get(file.name); if (output.length < file.pointer + count) { const next = new Uint8Array(file.pointer + count); next.set(output); output = next; }
      output.set(bytes.slice(0, count), file.pointer); file.pointer += count; contents.set(file.name, output); return count;
    }
  };
  Module._load = function (name, ...args) { if (name === '@kit.CoreFileKit') return { fileIo: nativeFs }; return originalLoad.call(this, name, ...args); };
  let NativeByteFile;
  try { ({ NativeByteFile } = require('../entry/src/main/ets/data/NativeByteFile.ets')); } finally { Module._load = originalLoad; }
  const file = new NativeByteFile('native-offset-fixture.zip', true);
  const payload = new Uint8Array(140000).map((_, index) => index % 253);
  await writeZip(file, [new ZipSource('manifest.json', new BufferFile(new TextEncoder().encode('{}'))), new ZipSource('media/a.jpg', new BufferFile(payload))]);
  const entries = await readZip(file);
  const destination = new BufferFile(); await copyZipEntry(file, entries[1], destination);
  assert.deepEqual(destination.bytes, payload);
  await file.close(); assert.equal(handles.size, 0);
});
