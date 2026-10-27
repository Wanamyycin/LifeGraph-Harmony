// Release-boundary checks: no networking capability, no native API client,
// all graph scripts bundled, and consistent application identity resources.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const json = rel => JSON.parse(read(rel).replace(/,\s*([}\]])/g, '$1'));
function files(dir) {
  return fs.readdirSync(dir, {withFileTypes:true}).flatMap(item => item.isDirectory() ? files(path.join(dir,item.name)) : [path.join(dir,item.name)]);
}
function resource(scope, type, reference) {
  assert.ok(reference.startsWith('$'+type+':'), reference);
  const name=reference.split(':')[1];
  if (type==='string') {
    const value=json(scope+'/resources/base/element/string.json').string.find(item=>item.name===name)?.value;
    assert.ok(value, reference); return value;
  }
  const media=path.join(root,scope,'resources/base/media');
  const matches=fs.readdirSync(media).filter(file=>path.parse(file).name===name);
  assert.equal(matches.length,1,reference); return path.join(media,matches[0]);
}

test('release manifest requests only microphone access at the recording scene', () => {
  const module=json('entry/src/main/module.json5').module;
  assert.deepEqual(module.requestPermissions.map(item=>item.name), ['ohos.permission.MICROPHONE']);
  assert.deepEqual(module.requestPermissions[0].usedScene,{abilities:['EntryAbility'],when:'inuse'});
  assert.ok(resource('entry/src/main','string',module.requestPermissions[0].reason));
});

test('app source has no native networking client or leftover API settings imports', () => {
  const source=files(path.join(root,'entry/src/main/ets')).filter(file=>file.endsWith('.ets'));
  for (const file of source) {
    const text=fs.readFileSync(file,'utf8');
    assert.doesNotMatch(text, /from\s+['"](?:@kit\.(?:NetworkKit|RemoteCommunicationKit)|@ohos\.net[^'"]*)['"]/,file);
    assert.doesNotMatch(text, /\b(?:fetch|XMLHttpRequest|WebSocket)\s*\(|\bhttp\.createHttp\s*\(/,file);
    assert.doesNotMatch(text, /from\s+['"][^'"]*(?:NativeChatTransport|AIConfigVault|NativeAssistant|AIServicePage|AIServiceDialog)['"]/,file);
  }
  for (const file of ['data/NativeChatTransport.ets','data/AIConfigVault.ets','data/NativeAssistant.ets','components/AIServicePage.ets','components/AIServiceDialog.ets']) {
    assert.equal(fs.existsSync(path.join(root,'entry/src/main/ets',file)),false,file);
  }
});

test('ArkWeb blocks network resources while every graph script resolves to a bundled file', () => {
  const web=read('entry/src/main/ets/components/NativeGraph.ets');
  assert.match(web,/\.blockNetwork\(true\)/); assert.match(web,/\.onlineImageAccess\(false\)/);
  assert.match(web,/\.mixedMode\(MixedMode\.None\)/);
  const graph=path.join(root,'entry/src/main/resources/rawfile/graph');
  const themes=fs.readdirSync(graph).filter(file=>file.endsWith('.html'));
  assert.equal(themes.length,8);
  for (const theme of themes) {
    const html=fs.readFileSync(path.join(graph,theme),'utf8');
    const scripts=[...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/g)].map(match=>match[1]);
    assert.deepEqual(scripts,['d3.min.js','graph-focus.js']);
    for (const script of scripts) assert.ok(fs.existsSync(path.join(graph,script)),theme+':'+script);
    assert.doesNotMatch(html, /(?:https?:)?\/\/[^\s"'<>]+/);
  }
});

test('launcher, ability and startup consistently use Life Graph and the original leaf asset', () => {
  const app=json('AppScope/app.json5').app;
  const module=json('entry/src/main/module.json5').module;
  assert.equal(resource('AppScope','string',app.label),'Life Graph');
  assert.equal(app.vendor,'LifeGraph');
  assert.doesNotMatch(resource('entry/src/main','string',module.description),/原型|prototype/i);
  const original=fs.readFileSync(path.join(root,'AppScope/resources/base/media/foreground.png'));
  assert.equal(crypto.createHash('sha256').update(original).digest('hex'),'1c7131cd3222ec935a5b1b4704c3155e859f40fc39ff0be27cec6777600db8a7');
  for (const [scope,reference] of [['AppScope',app.icon],['entry/src/main',module.abilities[0].icon]]) {
    const layers=JSON.parse(fs.readFileSync(resource(scope,'media',reference),'utf8'))['layered-image'];
    assert.deepEqual(fs.readFileSync(resource(scope,'media',layers.foreground)),original);
    assert.match(fs.readFileSync(resource(scope,'media',layers.background),'utf8'),/#5B8C5A/);
  }
  for (const ability of module.abilities) {
    assert.equal(resource('entry/src/main','string',ability.label),'Life Graph');
    assert.deepEqual(fs.readFileSync(resource('entry/src/main','media',ability.startWindowIcon)),original);
  }
});
