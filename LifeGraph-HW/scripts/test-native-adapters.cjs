require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const { randomUUID } = require('node:crypto');
const { writeZip, ZipSource } = require('../entry/src/main/ets/data/StoredZip.ets');

// Execute real adapter code with an injected SDK boundary. These tests check
// ownership/failure semantics; they do not claim native picker/media acceptance.
let state;
function reset() {
  state = { files: new Map(), dirs: new Set(['/cache', '/media', '/db']), handles: new Map(), serial: 0,
    destinations: [], failOpen: '', failClose: '', recorderFailure: '' };
}
function fileFor(fd) { const file = state.handles.get(typeof fd === 'number' ? fd : fd.fd); assert.ok(file, 'descriptor is open'); return file; }
const fileIo = {
  OpenMode: { READ_ONLY: 0, CREATE: 1, READ_WRITE: 2, TRUNC: 4 }, WhenceType: { SEEK_SET: 0 },
  async access(path) { return state.files.has(path) || state.dirs.has(path); },
  async mkdir(path) { state.dirs.add(path); },
  async open(path, mode) {
    if (path === state.failOpen) throw new Error('destination open failed');
    if (!(mode & 1) && !state.files.has(path)) throw new Error('file not found: ' + path);
    if (mode & 4 || !state.files.has(path)) state.files.set(path, new Uint8Array());
    const file = { fd: ++state.serial, path, pointer: 0 }; state.handles.set(file.fd, file); return file;
  },
  async close(file) { const opened = fileFor(file); state.handles.delete(opened.fd); if (opened.path === state.failClose) throw new Error('archive close failed'); },
  async unlink(path) { state.files.delete(path); },
  async stat(value) {
    const path = typeof value === 'number' ? fileFor(value).path : value;
    if (!state.files.has(path) && !state.dirs.has(path)) throw new Error('file not found');
    return { size: state.files.get(path)?.length ?? 0, isFile: () => state.files.has(path), isDirectory: () => state.dirs.has(path) };
  },
  async listFile(root) { return [...new Set([...state.files.keys(), ...state.dirs])].filter(path => path.startsWith(root + '/') && !path.slice(root.length + 1).includes('/')).map(path => path.slice(root.length + 1)); },
  lseek(fd, offset) { fileFor(fd).pointer = offset; },
  async read(fd, buffer) {
    const file = fileFor(fd), bytes = state.files.get(file.path);
    const count = Math.min(buffer.byteLength, bytes.length - file.pointer);
    new Uint8Array(buffer).set(bytes.slice(file.pointer, file.pointer + count)); file.pointer += count; return count;
  },
  async write(fd, buffer) {
    const file = fileFor(fd), bytes = new Uint8Array(buffer), prior = state.files.get(file.path);
    const next = new Uint8Array(Math.max(prior.length, file.pointer + bytes.length)); next.set(prior); next.set(bytes, file.pointer);
    state.files.set(file.path, next); file.pointer += bytes.length; return bytes.length;
  },
  async copyFile(source, destination) {
    state.files.set(typeof destination === 'number' ? fileFor(destination).path : destination, state.files.get(fileFor(source).path).slice());
  }
};
const context = { filesDir: '', cacheDir: '/cache', databaseDir: '/db' };
const originalLoad = Module._load;
Module._load = function(name, ...args) {
  if (name === '@kit.CoreFileKit') return { fileIo, fileUri: { getUriFromPath: path => 'file://' + path }, picker: {
    DocumentSaveOptions: class {}, DocumentSelectOptions: class {},
    DocumentViewPicker: class { async save() { return state.destinations; } async select() { return []; } }
  } };
  if (name === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID,
    TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
    TextDecoder: class { decodeToString(bytes) { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); } }
  } };
  if (name === '@kit.MediaLibraryKit') return { photoAccessHelper: {} };
  if (name === '@kit.ImageKit') return { image: {} };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
  if (name === '@kit.AbilityKit') return { abilityAccessCtrl: { createAtManager: () => ({ requestPermissionsFromUser: async () => ({ authResults: [0] }) }) } };
  if (name === '@kit.MediaKit') return { media: {
    AudioSourceType: { AUDIO_SOURCE_TYPE_MIC: 1 }, CodecMimeType: { AUDIO_AAC: 1 }, ContainerFormatType: { CFT_MPEG_4A: 1 },
    createAVRecorder: async () => ({ on() {}, async prepare() { if (state.recorderFailure === 'prepare') throw new Error('prepare failed'); },
      async start() {}, async stop() { if (state.recorderFailure === 'stop') throw new Error('stop failed'); }, async release() {} })
  } };
  return originalLoad.call(this, name, ...args);
};
let NativeBackup, MediaFiles, VoiceRecorder;
try {
  ({ NativeBackup } = require('../entry/src/main/ets/data/NativeBackup.ets'));
  ({ MediaFiles } = require('../entry/src/main/ets/data/MediaFiles.ets'));
  ({ VoiceRecorder } = require('../entry/src/main/ets/data/VoiceRecorder.ets'));
} finally { Module._load = originalLoad; }
global.canIUse = () => true;

function envelope(rows = []) { return { format: 'lifegraph-harmony', schemaVersion: 1, createdAt: Date.now(), tables: [
  { name: 'media_assets', columns: ['storage_path', 'deleted_at'], rows }
] }; }
function backup(service = {}) { return new NativeBackup(context, { exportBackup: async () => envelope(), ...service }, new MediaFiles(context)); }
class BufferFile {
  constructor(bytes = new Uint8Array()) { this.bytes = bytes; }
  async size() { return this.bytes.length; }
  async read(offset, length) { return this.bytes.slice(offset, offset + length); }
  async write(offset, bytes) { const next = new Uint8Array(Math.max(this.bytes.length, offset + bytes.length)); next.set(this.bytes); next.set(bytes, offset); this.bytes = next; }
  async close() {}
}
async function installArchive() {
  const output = new BufferFile();
  await writeZip(output, [new ZipSource('manifest.json', new BufferFile(new TextEncoder().encode(JSON.stringify(envelope([['photo.jpg', null]]))))),
    new ZipSource('media/photo.jpg', new BufferFile(new Uint8Array([1, 2, 3])))]);
  state.files.set('/backup.zip', output.bytes);
}

test('cancelled backup export closes every descriptor and removes only its scratch archive', async () => {
  reset(); state.files.set('/keep.zip', new Uint8Array([7]));
  assert.equal(await backup().export(), false);
  assert.equal(state.handles.size, 0); assert.deepEqual([...state.files.keys()], ['/keep.zip']);
});
test('destination-open failure during backup export closes the source and clears scratch files', async () => {
  reset(); state.destinations = ['/broken.zip']; state.failOpen = '/broken.zip';
  await assert.rejects(backup().export(), /destination open failed/);
  assert.equal(state.handles.size, 0); assert.equal(state.files.size, 0);
});
test('archive close errors after committed restore do not report the database operation as failed', async () => {
  reset(); await installArchive(); state.failClose = '/backup.zip'; let committed = false;
  await backup({ restoreBackup: async () => { committed = true; } }).restore('/backup.zip');
  assert.equal(committed, true); assert.equal(state.handles.size, 0);
  assert.equal([...state.files.keys()].filter(path => path.startsWith('/media/restore-')).length, 1);
});
test('restore failure preserves its primary error and removes copied attachments even when archive close fails', async () => {
  reset(); await installArchive(); state.failClose = '/backup.zip';
  await assert.rejects(backup({ restoreBackup: async () => { throw new Error('database rollback'); } }).restore('/backup.zip'), /database rollback/);
  assert.equal(state.handles.size, 0); assert.deepEqual([...state.files.keys()], ['/backup.zip']);
});
test('space statistics include nested databases, journal files and media but exclude cache', async () => {
  reset(); state.dirs.add('/db/rdb');
  for (const [path, size] of [['/db/rdb/lifegraph.db', 100], ['/db/rdb/lifegraph.db-wal', 20], ['/media/photo.jpg', 30], ['/cache/export.zip', 1000]]) state.files.set(path, new Uint8Array(size));
  assert.deepEqual(await new MediaFiles(context).storageStats(), [120, 30]);
});
for (const failure of ['prepare', 'stop', 'empty']) {
  test('recording ' + failure + ' failure closes resources and discards the unusable capture', async () => {
    reset(); state.recorderFailure = failure; const recorder = new VoiceRecorder();
    if (failure === 'prepare') await assert.rejects(recorder.start(context), /prepare failed/);
    else { await recorder.start(context); await assert.rejects(recorder.stop()); }
    assert.equal(state.handles.size, 0); assert.equal(state.files.size, 0);
  });
}

test('a completed capture remains available for import until explicitly discarded', async () => {
  reset(); const recorder = new VoiceRecorder(); await recorder.start(context);
  const path = [...state.files.keys()][0]; state.files.set(path, new Uint8Array([1, 2, 3]));
  assert.equal(await recorder.stop(), path);
  assert.equal(state.handles.size, 0); assert.deepEqual([...state.files.get(path)], [1, 2, 3]);
  await recorder.removeCapture(path); assert.equal(state.files.size, 0);
});

test('disposing an active recorder discards its unfinished capture', async () => {
  reset(); const recorder = new VoiceRecorder(); await recorder.start(context);
  await recorder.release(); assert.equal(state.handles.size, 0); assert.equal(state.files.size, 0);
});
