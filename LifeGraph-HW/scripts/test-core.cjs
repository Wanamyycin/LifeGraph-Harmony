require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { SqlRow, SqlDatabase } = require('../entry/src/main/ets/data/SqlDatabase.ets');
const { LifeGraphService } = require('../entry/src/main/ets/features/LifeGraphService.ets');
const { PersonDraft, RelationInput, EventDraft, MediaAsset } = require('../entry/src/main/ets/domain/Models.ets');

// Real SQLite executes the same SQL as the RDB adapter. This verifies schema,
// transactions and business semantics, but not HarmonyOS native API behavior.
class HostSqlConnection {
  constructor(file = ':memory:') { this.sqlite = new DatabaseSync(file); }
  async query(sql, values = []) {
    return this.sqlite.prepare(sql).all(...values).map(source => {
      const row = new SqlRow();
      for (const [key, value] of Object.entries(source)) row.values.set(key, value);
      return row;
    });
  }
  async execute(sql, values = []) { this.sqlite.prepare(sql).run(...values); }
  async begin() { this.sqlite.exec('BEGIN IMMEDIATE'); }
  async commit() { this.sqlite.exec('COMMIT'); }
  async rollback() { this.sqlite.exec('ROLLBACK'); }
  async close() { this.sqlite.close(); }
  getVersion() { return this.sqlite.prepare('PRAGMA user_version').get().user_version; }
  setVersion(version) { assert.ok(Number.isInteger(version)); this.sqlite.exec(`PRAGMA user_version=${version}`); }
}

async function fixture(file) {
  const connection = new HostSqlConnection(file);
  const db = new SqlDatabase(connection);
  let tick = Date.UTC(2026, 9, 21);
  const service = new LifeGraphService(db, randomUUID, () => ++tick);
  await service.initialize();
  return { connection, db, service };
}
function person(name = '林晓') { const draft = new PersonDraft(); draft.name = name; return draft; }
function event(personId, title = '一起散步') { const draft = new EventDraft(); draft.title = title; draft.personIds = [personId]; return draft; }

test('fresh bootstrap creates all original business tables, presets and only the internal self', async () => {
  const { db, service, connection } = await fixture();
  const state = await service.snapshot();
  assert.equal(state.persons.length, 1);
  assert.equal(state.persons[0].id, state.profile.defaultPersonId);
  assert.equal(state.events.length, 0);
  assert.equal(state.branches.length, 5);
  assert.equal(state.relations.length, 4);
  assert.equal(state.emotions.length, 6);
  assert.equal((await connection.query("SELECT name FROM sqlite_master WHERE type='table'")).length, 12);
  await service.initialize();
  assert.equal((await service.snapshot()).persons.length, 1);
  await db.close();
});

test('person writes, canonical bidirectional relations and duplicate-name people', async () => {
  const { db, service } = await fixture();
  const a = await service.savePerson(person(' 林晓 '));
  const b = await service.savePerson(person('林晓'));
  let state = await service.snapshot();
  assert.equal(state.persons.filter(p => p.name === '林晓').length, 2);
  const edge = new RelationInput(); edge.targetPersonId = b; edge.relationId = state.relations[0].id; edge.strength = 4;
  await service.saveEdge(a, edge);
  edge.targetPersonId = a; edge.strength = 5;
  await service.saveEdge(b, edge);
  state = await service.snapshot();
  assert.equal(state.edges.length, 1);
  assert.ok(state.edges[0].personAId < state.edges[0].personBId);
  assert.equal(state.edges[0].strength, 5);
  edge.targetPersonId = b;
  await assert.rejects(service.saveEdge(b, edge), /自己/);
  edge.targetPersonId = a; edge.strength = 6;
  await assert.rejects(service.saveEdge(b, edge), /1～5/);
  await db.close();
});

test('an invalid relationship rolls back the entire person edit and preserves prior edges', async () => {
  const { db, service } = await fixture();
  const id = await service.savePerson(person());
  const state = await service.snapshot();
  const draft = person('不应留下这个名字'); draft.id = id;
  const edge = new RelationInput(); edge.targetPersonId = state.profile.defaultPersonId; edge.relationId = 'missing';
  draft.relations = [edge];
  await assert.rejects(service.savePerson(draft), /有效关系/);
  assert.equal((await service.snapshot()).persons.find(p => p.id === id).name, '林晓');
  await service.savePerson(person('队列仍可使用'));
  await db.close();
});

test('events atomically persist participants, branches and emotions and roll back failed edits', async () => {
  const { db, service } = await fixture();
  const id = await service.savePerson(person());
  let state = await service.snapshot();
  const draft = event(id); draft.branchIds = [state.branches[0].id]; draft.emotionIds = [state.emotions[0].id];
  const eventId = await service.saveEvent(draft);
  state = await service.snapshot();
  assert.equal(state.events[0].personIds[0], id);
  assert.equal(state.events[0].branchIds.length, 1);
  assert.equal(state.events[0].emotionIds.length, 1);
  draft.id = eventId; draft.title = '应该回滚'; draft.branchIds = ['missing'];
  await assert.rejects(service.saveEvent(draft), /分类已不存在/);
  state = await service.snapshot();
  assert.equal(state.events[0].event.title, '一起散步');
  assert.equal(state.events[0].branchIds.length, 1);
  await assert.rejects(service.saveEvent(new EventDraft()), /标题/);
  await db.close();
});

test('ghost deletion preserves history; deleting its last event cleans the ghost', async () => {
  const { db, service } = await fixture();
  const id = await service.savePerson(person());
  const eventId = await service.saveEvent(event(id));
  await service.deletePerson(id, 'ghost');
  let state = await service.snapshot();
  assert.ok(state.persons.find(p => p.id === id).deletedAt > 0);
  assert.equal(state.events[0].personIds[0], id);
  await service.deleteEvent(eventId);
  state = await service.snapshot();
  assert.equal(state.persons.some(p => p.id === id), false);
  await assert.rejects(service.deletePerson(state.profile.defaultPersonId, 'clean'), /不能删除/);
  await db.close();
});

test('clean deletion removes orphan events but retains shared events and other people', async () => {
  const { db, service } = await fixture();
  const first = await service.savePerson(person());
  const second = await service.savePerson(person('周远'));
  await service.saveEvent(event(first, '独自事件'));
  const shared = event(first, '共同事件'); shared.personIds.push(second);
  await service.saveEvent(shared);
  await service.deletePerson(first, 'clean');
  const state = await service.snapshot();
  assert.equal(state.events.length, 1);
  assert.equal(state.events[0].event.title, '共同事件');
  assert.deepEqual(state.events[0].personIds, [second]);
  await db.close();
});

test('label uniqueness, soft deletion and re-creation keep links consistent', async () => {
  const { db, service } = await fixture();
  await assert.rejects(service.saveNamed('relations', '', '朋友'), /已经存在/);
  const state = await service.snapshot();
  const id = state.branches[0].id;
  await service.deleteNamed('branches', id);
  await service.saveNamed('branches', '', state.branches[0].name);
  assert.equal((await service.snapshot()).branches.length, 5);
  await assert.rejects(service.saveNamed('untrusted_table', '', '非法'), /未知分类/);
  await db.close();
});

test('concurrent jobs serialize and actual disk data survive a closed and reopened connection', async () => {
  const testRoot = path.resolve(__dirname, '../.test'); fs.mkdirSync(testRoot, { recursive: true });
  const file = path.join(testRoot, `core-${randomUUID()}.sqlite`);
  let runtime = await fixture(file);
  await Promise.all(Array.from({ length: 15 }, (_, i) => runtime.service.savePerson(person(`人物 ${i}`))));
  let state = await runtime.service.snapshot();
  state.profile.themeKey = 'ocean'; state.profile.displayName = '我的名字';
  await runtime.service.saveProfile(state.profile, '个人简介', null);
  const originalSelf = state.profile.defaultPersonId;
  await runtime.db.close();
  runtime = await fixture(file);
  state = await runtime.service.snapshot();
  assert.equal(state.persons.length, 16);
  assert.equal(state.profile.defaultPersonId, originalSelf);
  assert.equal(state.profile.themeKey, 'ocean');
  assert.equal(state.persons.find(p => p.id === originalSelf).description, '个人简介');
  await runtime.db.close();
  assert.equal(path.dirname(file), testRoot); fs.unlinkSync(file);
});

test('a future schema version is rejected without downgrading or deleting data', async () => {
  const connection = new HostSqlConnection(); connection.setVersion(9);
  const db = new SqlDatabase(connection);
  const service = new LifeGraphService(db, randomUUID, Date.now);
  await assert.rejects(service.initialize(), /较新版本/);
  assert.equal(connection.getVersion(), 9);
  await db.close();
});

test('historical participants remain editable without turning a ghost back into an active person', async () => {
  const { db, service } = await fixture();
  const personId = await service.savePerson(person());
  const draft = event(personId); draft.id = await service.saveEvent(draft);
  await service.deletePerson(personId, 'ghost');
  draft.title = '修改后的历史';
  await service.saveEvent(draft);
  const state = await service.snapshot();
  assert.equal(state.events[0].event.title, draft.title);
  assert.ok(state.persons.find(p => p.id === personId).deletedAt > 0);
  await db.close();
});

test('backup restore roundtrips real SQL tables, links, profile and media metadata', async () => {
  const { db, service } = await fixture();
  const personId = await service.savePerson(person());
  const asset = new MediaAsset(); asset.id = randomUUID(); asset.storagePath = `${asset.id}.jpg`;
  asset.mediaKind = 'image'; asset.mimeType = 'image/jpeg'; asset.role = 'cover';
  await service.registerMedia(asset);
  const draft = event(personId); draft.assets = [asset]; await service.saveEvent(draft);
  const original = await service.exportBackup();
  await service.deletePerson(personId, 'clean');
  assert.equal((await service.snapshot()).events.length, 0);
  await service.restoreBackup(original);
  const restored = await service.snapshot();
  assert.equal(restored.events.length, 1);
  assert.equal(restored.events[0].assets[0].id, asset.id);
  assert.equal(restored.events[0].personIds[0], personId);
  assert.equal(restored.profile.defaultPersonId, restored.persons.find(p => p.name === '我').id);
  await db.close();
});

test('damaged backup references roll back replacement and keep current data', async () => {
  const { db, service } = await fixture();
  const personId = await service.savePerson(person('需要保留的人'));
  await service.saveEvent(event(personId));
  const backup = await service.exportBackup();
  const links = backup.tables.find(table => table.name === 'event_persons');
  links.rows[0][links.columns.indexOf('person_id')] = 'missing-person';
  await assert.rejects(service.restoreBackup(backup), /FOREIGN KEY|关联/);
  const state = await service.snapshot();
  assert.equal(state.events.length, 1);
  assert.equal(state.persons.find(p => p.id === personId).name, '需要保留的人');
  await db.close();
});

test('backup rejects unknown columns and corrupted profile without clearing current data', async () => {
  const { db, service } = await fixture();
  await service.savePerson(person('当前数据'));
  const backup = await service.exportBackup();
  const people = backup.tables.find(table => table.name === 'persons');
  people.columns[0] = 'id); DROP TABLE persons; --';
  await assert.rejects(service.restoreBackup(backup), /字段/);
  const invalid = await service.exportBackup();
  const config = invalid.tables.find(table => table.name === 'app_config');
  const column = config.columns.indexOf('value');
  const profile = JSON.parse(config.rows[0][column]); profile.themeKey = '../../invalid';
  config.rows[0][column] = JSON.stringify(profile);
  await assert.rejects(service.restoreBackup(invalid), /外观配置/);
  assert.equal((await service.snapshot()).persons.length, 2);
  await db.close();
});

test('abandoned media cleanup never removes assets still referenced by events', async () => {
  const { db, service } = await fixture();
  const personId = await service.savePerson(person());
  const assets = [new MediaAsset(), new MediaAsset()];
  for (const asset of assets) { asset.id = randomUUID(); asset.storagePath = `${asset.id}.jpg`; asset.mediaKind = 'image'; asset.mimeType = 'image/jpeg'; await service.registerMedia(asset); }
  const draft = event(personId); draft.assets = [assets[0]]; await service.saveEvent(draft);
  const discarded = await service.discardUnreferencedMedia(assets.map(a => a.id));
  assert.deepEqual(discarded.map(a => a.id), [assets[1].id]);
  assert.equal((await service.snapshot()).events[0].assets[0].id, assets[0].id);
  await db.close();
});

test('editing an active person preserves existing relations to hidden people without permitting new hidden targets', async () => {
  const { db, service } = await fixture();
  const first = await service.savePerson(person('仍在列表'));
  const hidden = await service.savePerson(person('保留历史'));
  const state = await service.snapshot();
  const edge = new RelationInput(); edge.targetPersonId = hidden; edge.relationId = state.relations[0].id;
  await service.saveEdge(first, edge);
  await service.deletePerson(hidden, 'ghost');
  const draft = person('修改后的名字'); draft.id = first; draft.relations = [edge];
  await service.savePerson(draft);
  const updated = await service.snapshot();
  assert.equal(updated.edges.length, 1);
  assert.ok(updated.persons.find(p => p.id === hidden).deletedAt !== null);
  const another = person('不能新关联隐藏人物'); another.relations = [edge];
  await assert.rejects(service.savePerson(another), /人物已不存在/);
  await db.close();
});

test('avatar replacement validates image assets and retires only the superseded unreferenced avatar', async () => {
  const { db, service } = await fixture();
  const images = [new MediaAsset(), new MediaAsset()];
  for (const asset of images) {
    asset.id = randomUUID(); asset.storagePath = asset.id + '.jpg'; asset.mediaKind = 'image'; asset.mimeType = 'image/jpeg';
    await service.registerMedia(asset);
  }
  const draft = person('头像测试'); draft.avatarAssetId = images[0].id;
  draft.id = await service.savePerson(draft);
  const shared = event(draft.id); shared.assets = [images[0]]; const sharedId = await service.saveEvent(shared);
  // Saving the event retires unreferenced media, so import the replacement afterwards.
  const replacement = new MediaAsset(); replacement.id = randomUUID(); replacement.storagePath = replacement.id + '.jpg';
  replacement.mediaKind = 'image'; replacement.mimeType = 'image/jpeg'; await service.registerMedia(replacement);
  draft.avatarAssetId = replacement.id; await service.savePerson(draft);
  assert.equal((await service.unusedMedia(false)).some(a => a.id === images[0].id), false);
  await service.deleteEvent(sharedId);
  assert.ok((await service.unusedMedia(false)).some(a => a.id === images[0].id));
  draft.avatarAssetId = 'missing-avatar';
  await assert.rejects(service.savePerson(draft), /头像/);
  assert.equal((await service.snapshot()).persons.find(p => p.id === draft.id).avatarAssetId, replacement.id);
  const config = (await service.snapshot()).profile;
  await assert.rejects(service.saveProfile(config, '', 'missing-avatar'), /头像/);
  await service.saveProfile(config, '', replacement.id);
  await service.saveProfile(config, '', null);
  assert.equal((await service.unusedMedia(false)).some(a => a.id === replacement.id), false);
  draft.avatarAssetId = null; await service.savePerson(draft);
  assert.ok((await service.unusedMedia(false)).some(a => a.id === replacement.id));
  await db.close();
});

test('restoring a dangling avatar rejects the replacement and preserves the existing database', async () => {
  const { db, service } = await fixture();
  const id = await service.savePerson(person('必须保留'));
  const backup = await service.exportBackup();
  const people = backup.tables.find(table => table.name === 'persons');
  const row = people.rows.find(values => values[people.columns.indexOf('id')] === id);
  row[people.columns.indexOf('avatar_asset_id')] = 'absent-image';
  await assert.rejects(service.restoreBackup(backup), /头像/);
  assert.equal((await service.snapshot()).persons.find(p => p.id === id).avatarAssetId, null);
  await db.close();
});

test('profile edits validate original name/bio limits and calendar birthdays before changing saved data', async () => {
  const { db, service } = await fixture();
  const original = (await service.snapshot()).profile;
  await assert.rejects(service.saveProfile({ ...original, displayName: '名'.repeat(25) }, '', null), /24/);
  await assert.rejects(service.saveProfile(original, '简'.repeat(201), null), /200/);
  for (const birthday of ['2023-02-29', '1899-12-31', '9999-01-01', 'bad-date']) {
    await assert.rejects(service.saveProfile({ ...original, birthday }, '', null), /生日/);
  }
  assert.equal((await service.snapshot()).profile.birthday, '');
  assert.equal((await service.snapshot()).profile.displayName, '我');
  await service.saveProfile({ ...original, birthday: '2000-02-29' }, '有效简介', null);
  assert.equal((await service.snapshot()).profile.birthday, '2000-02-29');
  await db.close();
});
