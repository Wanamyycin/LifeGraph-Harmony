require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const { AppSnapshot, EventCard, RelationEdge, NamedItem } = require('../entry/src/main/ets/domain/Models.ets');
const { Person } = require('../entry/src/main/ets/domain/Person.ets');
const { DesktopCardConfig, normalizeCardConfig, projectDesktopCard, CardLaunch, cardLaunchBlocked } = require('../entry/src/main/ets/features/DesktopCard.ets');

function fixture() {
  const data = new AppSnapshot(); data.profile.defaultPersonId = 'me';
  data.persons = ['me', 'alice', 'bob', 'carol'].map((id, i) => Object.assign(new Person(), { id, name: ['我', '林晓敏', '张雨', '周阳'][i], description: 'PRIVATE_DESCRIPTION', avatarAssetId: 'PRIVATE_AVATAR' }));
  data.relations = [Object.assign(new NamedItem(), { id: 'friend', name: '朋友' })];
  const event = (id, people, time, title) => Object.assign(new EventCard(), {
    personIds: people, event: { id, occurredAt: time, createdAt: time, title, content: 'PRIVATE_BODY', locationText: 'PRIVATE_LOCATION' }
  });
  data.events = [event('old', ['me', 'alice'], 100, '旧的共同事件'), event('other', ['alice', 'bob'], 900, '他人的事件'),
    event('mention', ['me'], 1000, '提到了林晓敏'), event('new', ['me', 'alice'], 200, '最新共同事件')];
  const config = new DesktopCardConfig(); config.personIds = ['alice', 'bob', 'carol'];
  return { data, config };
}

test('safe default presentation excludes names, event titles, bodies, locations and avatars', () => {
  const { data, config } = fixture(); const card = projectDesktopCard(data, config);
  const text = JSON.stringify(card);
  for (const secret of ['林晓敏', '张雨', '周阳', '最新共同事件', 'PRIVATE_']) assert.ok(!text.includes(secret), secret);
  assert.equal(card.nodes[1].label, '人物 1');
  assert.equal(card.nodes[1].shortLabel, '1');
  assert.equal(card.nodes[1].count, 2); assert.equal(card.nodes[2].count, 0);
});
test('latest shared event requires both people and sorts by occurrence rather than input order', () => {
  const { data, config } = fixture(); config.showEventTitles = true; config.nameMode = 'name';
  const card = projectDesktopCard(data, config);
  assert.equal(card.nodes[1].label, '林晓敏'); assert.equal(card.nodes[1].recent, '最新共同事件');
  assert.equal(card.nodes[2].recent, '还没有共同记录');
  data.events = data.events.filter(e => e.event.id !== 'new');
  assert.equal(projectDesktopCard(data, config).nodes[1].recent, '旧的共同事件');
});
test('hidden/deleted pins vanish without moving surviving pins; snapshot order is irrelevant', () => {
  const { data, config } = fixture(); const before = projectDesktopCard(data, config);
  data.persons.find(p => p.id === 'alice').deletedAt = 99; data.persons.reverse();
  const after = projectDesktopCard(data, config);
  assert.ok(!after.nodes.some(p => p.id === 'alice'));
  assert.deepEqual(after.nodes.find(p => p.id === 'bob'), before.nodes.find(p => p.id === 'bob'));
});
test('initial privacy mode exposes only the first codepoint, including non-BMP names', () => {
  const { data, config } = fixture(); config.nameMode = 'initial'; data.persons[1].name = '𠮷野';
  assert.equal(projectDesktopCard(data, config).nodes[1].label, '𠮷·');
  assert.equal(projectDesktopCard(data, config).nodes[1].shortLabel, '𠮷');
});

test('compact card limits full-name labels to two codepoints while keeping detail labels', () => {
  const { data, config } = fixture(); config.nameMode = 'name';
  const card = projectDesktopCard(data, config);
  assert.equal(card.nodes[1].shortLabel, '林晓'); assert.equal(card.nodes[1].label, '林晓敏');
});
test('only real relations render; duplicate relations combine strength and strength is bounded', () => {
  const { data, config } = fixture(); assert.equal(projectDesktopCard(data, config).links.length, 0);
  data.edges = [Object.assign(new RelationEdge(), { personAId: 'me', personBId: 'alice', strength: 2 }),
    Object.assign(new RelationEdge(), { personAId: 'alice', personBId: 'me', strength: 99 }),
    Object.assign(new RelationEdge(), { personAId: 'bob', personBId: 'carol', strength: 3 }),
    Object.assign(new RelationEdge(), { personAId: 'missing', personBId: 'alice', strength: 5 })];
  const links = projectDesktopCard(data, config).links;
  assert.equal(links.length, 2); assert.equal(links[0].width, 3.25); assert.equal(links[1].width, 2.35);
});
test('config caps and deduplicates pins and fails closed on invalid privacy values', () => {
  const config = normalizeCardConfig({ personIds: ['a', 'a', '', 1, 'b', 'c', 'd', 'e', 'f', 'g'], nameMode: 'full', showEventTitles: 'true' });
  assert.deepEqual(config.personIds, ['a', 'b', 'c', 'd', 'e', 'f']);
  assert.equal(config.nameMode, 'hidden'); assert.equal(config.showEventTitles, false);
  assert.deepEqual(normalizeCardConfig(null), new DesktopCardConfig());
});
test('card launches wait through cold start and are consumed once; malformed routes are ignored', () => {
  CardLaunch.clear(); CardLaunch.request('record'); assert.equal(CardLaunch.take().action, 'record'); assert.equal(CardLaunch.take(), null);
  let wake = 0; CardLaunch.onRequest = () => wake++;
  CardLaunch.request('person', 'alice'); assert.equal(wake, 1); assert.equal(CardLaunch.take().personId, 'alice');
  CardLaunch.request('person', ''); CardLaunch.request('arbitrary'); assert.equal(CardLaunch.take(), null);
  CardLaunch.clear();
});

test('desktop launch protects nested unsaved editors, settings and active recording', () => {
  for (const page of ['personEditor', 'eventEditor', 'profileEditor', 'aiSettings', 'desktopCard', 'tags', 'appearance']) {
    assert.equal(cardLaunchBlocked([page, 'image'], false, false), true, page);
  }
  assert.equal(cardLaunchBlocked(['person'], true, false), true);
  assert.equal(cardLaunchBlocked([], false, true), true);
  assert.equal(cardLaunchBlocked(['person', 'event'], false, false), false);
});

test('empty setup never invents people or relationships', () => {
  const { data } = fixture(); const card = projectDesktopCard(data, new DesktopCardConfig());
  assert.deepEqual(card.nodes.map(n => n.id), ['me']); assert.deepEqual(card.links, []);
});

// Execute real store/extension code while mocking only the OS APIs. This tests
// serialized writes, persisted privacy, lifecycle and failure semantics, not a
// launcher installation or rendering on a HarmonyOS device.
const disk = new Map(); let updates = []; let failId = ''; let flushes = 0;
const pref = { async get(k, fallback) { return disk.get(k) ?? fallback; }, getSync(k, fallback) { return disk.get(k) ?? fallback; },
  async put(k, v) { disk.set(k, v); }, async flush() { flushes++; } };
const originalLoad = Module._load;
Module._load = function(name, ...args) {
  if (name === '@kit.ArkData') return { preferences: { async removePreferencesFromCache() {}, removePreferencesFromCacheSync() {}, async getPreferences() { return pref; }, getPreferencesSync() { return pref; } } };
  if (name === '@kit.FormKit') return { FormExtensionAbility: class {}, formBindingData: { createFormBindingData: data => ({ data }) },
    formProvider: { async getPublishedRunningFormInfos() { return [{ formId: 'one', formName: 'RelationshipCard' }, { formId: 'two', formName: 'RelationshipCard' }, { formId: 'other', formName: 'OtherCard' }]; },
      async updateForm(id, binding) { if (id === failId) throw Error('launcher unavailable'); updates.push({ id, binding }); } } };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
  return originalLoad.call(this, name, ...args);
};
let DesktopCardStore, FormAbility;
try {
  ({ DesktopCardStore } = require('../entry/src/main/ets/data/DesktopCardStore.ets'));
  FormAbility = require('../entry/src/main/ets/cardability/RelationshipFormAbility.ets').default;
} finally { Module._load = originalLoad; }

test('card settings persist, refresh all own instances, and survive a subsequent ordinary refresh', async () => {
  const { data, config } = fixture(); config.nameMode = 'initial'; disk.clear(); updates = [];
  await Promise.all([DesktopCardStore.publish({}, data, config), DesktopCardStore.publish({}, data)]);
  assert.equal(flushes, 2); assert.equal(updates.length, 4); assert.ok(updates.every(u => u.id !== 'other'));
  assert.deepEqual((await DesktopCardStore.config({})).personIds, config.personIds);
  assert.equal((await DesktopCardStore.cached({})).nodes[1].label, '林·');
});
test('one failed launcher instance does not block other instances or lose saved privacy settings', async () => {
  const { data, config } = fixture(); failId = 'one'; updates = []; config.nameMode = 'hidden';
  await assert.rejects(DesktopCardStore.publish({}, data, config), /卡片设置已保存/);
  assert.equal(updates.length, 1); assert.equal(updates[0].id, 'two');
  assert.equal((await DesktopCardStore.config({})).nameMode, 'hidden');
  failId = ''; await DesktopCardStore.publish({}, data); // rejected job must not poison later updates
});
test('onAddForm returns real cached data synchronously; corrupt cache returns a safe empty binding', () => {
  const ability = new FormAbility(); ability.context = {};
  assert.ok(ability.onAddForm({}).data.nodes.length > 1);
  disk.set('presentation', 'broken'); assert.deepEqual(ability.onAddForm({}).data.nodes, []);
});
