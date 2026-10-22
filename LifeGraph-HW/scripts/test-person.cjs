// Runs the actual UI-independent .ets service with the SDK's bundled TS parser.
// This is a host logic test; it does not simulate ArkUI or HarmonyOS RDB.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const studio = process.env.DEVECO_STUDIO_HOME || 'F:/DevEco Studio';
const ts = require(path.join(studio,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
require.extensions['.ets'] = (module, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  });
  module._compile(result.outputText, filename);
};
const { PersonService } = require('../entry/src/main/ets/features/PersonService.ets');
const { ApplicationRuntime } = require('../entry/src/main/ets/runtime/ApplicationRuntime.ets');
const { PeoplePageController } = require('../entry/src/main/ets/components/PeoplePageController.ets');
const copy = (value) => structuredClone(value);

function fixture() {
  const rows = new Map();
  let clock = 1000;
  let serial = 0;
  const repository = {
    async listActive() { return [...rows.values()].filter(p => p.deletedAt === null).map(copy); },
    async findActive(id) { const p = rows.get(id); return p && p.deletedAt === null ? copy(p) : null; },
    async insert(person) { rows.set(person.id, copy(person)); },
    async update(person) { rows.set(person.id, copy(person)); },
    async archive(id, timestamp) { rows.get(id).deletedAt = timestamp; rows.get(id).updatedAt = timestamp; }
  };
  return { rows, repository, service: new PersonService(repository, () => `person-${++serial}`, () => ++clock) };
}

test('a new app starts empty; whitespace names never write data', async () => {
  const { service, rows } = fixture();
  assert.deepEqual(await service.list(), []);
  await assert.rejects(service.save('', ' \n ', 'description'), /请填写人物姓名/);
  assert.equal(rows.size, 0);
});

test('creation normalizes whitespace, nullable descriptions and timestamps', async () => {
  const { service, rows } = fixture();
  await service.save('', '  林晓  ', '   ');
  const person = rows.get('person-1');
  assert.equal(person.name, '林晓');
  assert.equal(person.description, null);
  assert.equal(person.createdAt, person.updatedAt);
  assert.equal(person.deletedAt, null);
});

test('editing preserves identity, creation time and reserved avatar field', async () => {
  const { service, rows } = fixture();
  await service.save('', '林晓', '朋友');
  const createdAt = rows.get('person-1').createdAt;
  rows.get('person-1').avatarAssetId = 'reserved-avatar';
  await service.save('person-1', '  林晓同学 ', ' 大学朋友 ');
  const updated = rows.get('person-1');
  assert.equal(rows.size, 1);
  assert.equal(updated.name, '林晓同学');
  assert.equal(updated.description, '大学朋友');
  assert.equal(updated.createdAt, createdAt);
  assert.ok(updated.updatedAt > createdAt);
  assert.equal(updated.avatarAssetId, 'reserved-avatar');
});

test('search supports Chinese descriptions, case-insensitive names and clearing', async () => {
  const { service } = fixture();
  await service.save('', 'Alice', '大学朋友');
  await service.save('', '周远', '同事');
  const people = await service.list();
  assert.equal(service.filter(people, ' ALICE ')[0].name, 'Alice');
  assert.equal(service.filter(people, '大学')[0].name, 'Alice');
  assert.equal(service.filter(people, '不存在').length, 0);
  assert.equal(service.filter(people, '  ').length, 2);
});

test('soft deletion hides a person without physically deleting the row', async () => {
  const { service, rows } = fixture();
  await service.save('', '林晓', '朋友');
  await service.archive('person-1');
  assert.equal(rows.size, 1);
  assert.equal((await service.list()).length, 0);
  assert.ok(rows.get('person-1').deletedAt > 0);
  await assert.rejects(service.save('person-1', '林晓', '不能恢复'), /不存在/);
  await assert.rejects(service.archive('person-1'), /不存在/);
});

test('a failed repository write rejects instead of reporting success', async () => {
  const { service, repository, rows } = fixture();
  repository.insert = async () => { throw new Error('disk full'); };
  await assert.rejects(service.save('', '林晓', ''), /disk full/);
  assert.equal(rows.size, 0);
});

test('both page preview and component preview are read-only until the real ability starts', () => {
  ApplicationRuntime.stop();
  assert.equal(ApplicationRuntime.useVisualPreview(false), true);
  assert.equal(ApplicationRuntime.useVisualPreview(true), true);
  ApplicationRuntime.start();
  assert.equal(ApplicationRuntime.useVisualPreview(false), false);
  assert.equal(ApplicationRuntime.useVisualPreview(true), true);
  ApplicationRuntime.stop();
  assert.equal(ApplicationRuntime.useVisualPreview(false), true);
});

test('a resolved database insert without a readable row is not confirmed as saved', async () => {
  // Exercise the actual .ets RDB adapter with the same failure shape seen in
  // Previewer logs: insert resolves, but the next query returns no new row.
  const Module = require('node:module');
  const originalLoad = Module._load;
  const noRows = () => ({ goToNextRow: () => false, goToFirstRow: () => false, close() {} });
  Module._load = function (name, ...args) {
    if (name === '@kit.ArkData') {
      return { relationalStore: {
        SecurityLevel: { S1: 1 },
        getRdbStore: async () => ({
          executeSql: async () => {}, insert: async () => 1, querySql: async () => noRows()
        })
      } };
    }
    return originalLoad.call(this, name, ...args);
  };
  let PersonRdbRepository;
  try {
    ({ PersonRdbRepository } = require('../entry/src/main/ets/data/PersonRdbRepository.ets'));
  } finally {
    Module._load = originalLoad;
  }
  const repository = new PersonRdbRepository();
  await repository.initialize({});
  const service = new PersonService(repository, () => 'preview-mock-person', () => 1000);
  const expected = await service.save('', '林晓', '朋友');
  assert.equal(service.confirmsSave(await service.list(), expected), false);
});

test('write confirmation rejects stale fields and accepts matching readback', async () => {
  const { service } = fixture();
  const expected = await service.save('', '林晓', '朋友');
  const people = await service.list();
  assert.equal(service.confirmsSave(people, expected), true);
  people[0].description = '旧描述';
  assert.equal(service.confirmsSave(people, expected), false);
});

test('the entry controller forwards back actions and drops a disposed page handler', () => {
  const controller = new PeoplePageController();
  assert.equal(controller.onBackPress(), false);
  controller.bind(() => true);
  assert.equal(controller.onBackPress(), true);
  controller.clear();
  assert.equal(controller.onBackPress(), false);
});

test('foreground state tracks ability lifetime for delayed microphone startup', () => {
  ApplicationRuntime.stop(); assert.equal(ApplicationRuntime.isForeground(), false);
  ApplicationRuntime.start(); assert.equal(ApplicationRuntime.isForeground(), false);
  ApplicationRuntime.enterForeground(); assert.equal(ApplicationRuntime.isForeground(), true);
  ApplicationRuntime.enterBackground(); assert.equal(ApplicationRuntime.isForeground(), false);
  ApplicationRuntime.enterForeground(); assert.equal(ApplicationRuntime.isForeground(), true);
  ApplicationRuntime.stop(); assert.equal(ApplicationRuntime.isForeground(), false);
});
