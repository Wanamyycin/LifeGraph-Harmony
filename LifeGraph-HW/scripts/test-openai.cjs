require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const { OpenAIConfig, completionUrl, prepareOpenAIConfig } = require('../entry/src/main/ets/domain/OpenAIConfig.ets');
const { createOpenAIRequest, parseOpenAIResponse, providerError } = require('../entry/src/main/ets/data/OpenAIProtocol.ets');
const { ChatMessage, AIAgent } = require('../entry/src/main/ets/features/AIAgent.ets');
const { ToolCall } = require('../entry/src/main/ets/domain/Assistant.ets');
const { AppSnapshot, EventCard } = require('../entry/src/main/ets/domain/Models.ets');

let responses = [], requests = [], destroyed = 0, stored = null, failSave = false, available = true;
const Tags = { ALIAS: 1, SECRET: 2, RETURN_TYPE: 3, ACCESSIBILITY: 4, SYNC_TYPE: 5, IS_PERSISTENT: 6, CONFLICT_RESOLUTION: 7 };
const mockAsset = { Tag: Tags, ReturnType: { ALL: 0 }, Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, SyncType: { NEVER: 0 },
  ConflictResolution: { OVERWRITE: 0 }, ErrorCode: { NOT_FOUND: 24000002 },
  async query() { if (stored === null) throw Object.assign(new Error('not found'), { code: 24000002 }); return [new Map(stored)]; },
  async add(attributes) { if (failSave) throw new Error('secret backend error'); stored = new Map(attributes); }
};
const original = Module._load;
Module._load = function(name, ...args) {
  if (name === '@kit.NetworkKit') return { http: { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'STRING' }, createHttp() {
    return { async request(url, options) { requests.push({ url, options }); const response = responses.shift(); if (typeof response === 'function') return response(); if (response instanceof Error) throw response; return response; }, destroy() { destroyed++; } };
  } } };
  if (name === '@kit.AssetStoreKit') return { asset: mockAsset };
  if (name === '@kit.ArkTS') return { util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } }, TextDecoder: class { decodeToString(bytes) { return new TextDecoder().decode(bytes); } } } };
  return original.call(this, name, ...args);
};
let NativeChatTransport, AIConfigVault;
try { ({ NativeChatTransport } = require('../entry/src/main/ets/data/NativeChatTransport.ets')); ({ AIConfigVault } = require('../entry/src/main/ets/data/AIConfigVault.ets')); }
finally { Module._load = original; }
global.canIUse = () => available;
function reset() { responses = []; requests = []; destroyed = 0; stored = null; failSave = false; available = true; }
function config() { return prepareOpenAIConfig('https://api.example.com/v1', 'test-key-only', 'test-model'); }
function response(message, finish_reason = 'stop') { return { responseCode: 200, result: JSON.stringify({ choices: [{ message, finish_reason }] }) }; }

test('URL normalization handles roots, version bases, nested bases, full endpoints and local addresses', () => {
  for (const url of ['https://api.example.com', 'https://api.example.com/', 'https://api.example.com/v1/', 'https://api.example.com/v1/chat/completions']) assert.equal(completionUrl(url), 'https://api.example.com/v1/chat/completions');
  assert.equal(completionUrl('http://127.0.0.1:1234/v1'), 'http://127.0.0.1:1234/v1/chat/completions');
  assert.equal(completionUrl('http://[::1]:8080'), 'http://[::1]:8080/v1/chat/completions');
  assert.equal(completionUrl('https://host.example/custom/openai'), 'https://host.example/custom/openai/chat/completions');
  assert.equal(completionUrl('https://host.example/chat/completions?api-version=x'), 'https://host.example/chat/completions?api-version=x');
  assert.equal(completionUrl('https://host.example/v1/?scope=a/'), 'https://host.example/v1/chat/completions?scope=a/');
});
test('URL and configuration validation reject malformed endpoints and missing key/model', () => {
  for (const url of ['file:///tmp', 'https://user:pass@host.example', 'https://host.example/#part', 'https://host.example/a b', 'https://host.example:99999', 'https://']) assert.throws(() => completionUrl(url), /URL/);
  assert.throws(() => prepareOpenAIConfig('https://host.example', '', 'm'), /Key/);
  assert.throws(() => prepareOpenAIConfig('https://host.example', 'key', ''), /模型/);
  assert.throws(() => prepareOpenAIConfig('https://host.example', 'key\nheader', 'm'), /Key/);
});
test('blank key retains the existing key only for the same normalized endpoint', () => {
  const previous = config(); const updated = prepareOpenAIConfig('https://api.example.com', '', 'another-model', previous);
  assert.equal(updated.apiKey, previous.apiKey); assert.equal(updated.model, 'another-model');
  assert.throws(() => prepareOpenAIConfig('https://another.example/v1', '', 'm', previous), /重新填写/);
  assert.equal(prepareOpenAIConfig('https://another.example/v1', 'new-key', 'm', previous).apiKey, 'new-key');
  assert.equal(prepareOpenAIConfig('https://api.example.com', 'Bearer test-key', 'm').apiKey, 'test-key');
});
test('request serializes OpenAI function tools and string arguments with matching tool_call_id', () => {
  const assistant = new ChatMessage('assistant', null), call = new ToolCall(); call.id = 'call1'; call.name = 'searchEvents'; call.arguments = { query: '聚餐' }; assistant.tool_calls = [call];
  const result = new ChatMessage('tool', '{"total":1}'); result.tool_call_id = 'call1';
  const request = createOpenAIRequest('my-model', [new ChatMessage('user', '查聚餐'), assistant, result]);
  assert.equal(request.model, 'my-model'); assert.equal(request.stream, false); assert.equal(request.tools.length, 13);
  assert.equal(request.tools[0].type, 'function'); assert.equal(request.tools[0].function.name, 'searchPersons');
  assert.equal(request.messages[1].tool_calls[0].function.arguments, '{"query":"聚餐"}'); assert.equal(request.messages[2].tool_call_id, 'call1');
  assert.ok(!('temperature' in request)); assert.ok(!('apiKey' in request));
});
test('responses decode text, text arrays and function calls while excluding reasoning content', () => {
  assert.equal(parseOpenAIResponse(response({ content: '答案', reasoning_content: 'hidden' }).result).content, '答案');
  assert.equal(parseOpenAIResponse(response({ content: [{ type: 'text', text: 'A' }, { type: 'image', text: 'skip' }, { type: 'text', text: 'B' }] }).result).content, 'AB');
  const result = parseOpenAIResponse(response({ content: null, tool_calls: [{ id: 'c', type: 'function', function: { name: 'countEvents', arguments: '{}' } }] }, 'tool_calls').result);
  assert.equal(result.kind, 'tool_calls'); assert.deepEqual(result.tool_calls[0].arguments, {});
});
test('malformed, legacy, empty, refused or truncated responses are not treated as successful answers', () => {
  for (const raw of ['not json', 'null', '{"code":0,"data":{"kind":"text","content":"old"}}', '{"choices":[]}', response({ content: '' }).result,
    response({ content: 'partial' }, 'length').result, response({ content: null, refusal: 'no' }).result, response({ content: 'invalid tools', tool_calls: {} }).result,
    response({ content: null, tool_calls: [{ id: 'c', type: 'function', function: { name: 'countEvents', arguments: '[1]' } }] }).result]) assert.throws(() => parseOpenAIResponse(raw));
});
test('native transport sends Bearer authorization directly and prevents redirects and cache use', async () => {
  reset(); responses.push(response({ content: 'hello' })); const transport = new NativeChatTransport(config());
  assert.equal((await transport.chat([new ChatMessage('user', 'hello')])).content, 'hello');
  assert.equal(requests[0].url, 'https://api.example.com/v1/chat/completions');
  assert.equal(requests[0].options.header.Authorization, 'Bearer test-key-only');
  assert.equal(requests[0].options.maxRedirects, 0); assert.equal(requests[0].options.usingCache, false); assert.equal(destroyed, 1);
});
test('DeepSeek official API uses non-thinking mode so tool roundtrips do not require discarded reasoning content', async () => {
  reset(); responses.push(response({ content: 'ok' }));
  await new NativeChatTransport(prepareOpenAIConfig('https://api.deepseek.com', 'test-key-only', 'deepseek-flash')).chat([]);
  assert.deepEqual(JSON.parse(requests[0].options.extraData).thinking, { type: 'disabled' });
  reset(); responses.push(response({ content: 'ok' }));
  await new NativeChatTransport(config()).chat([]);
  assert.ok(!('thinking' in JSON.parse(requests[0].options.extraData)));
});
test('a full native transport tool roundtrip returns local results using the OpenAI wire protocol', async () => {
  reset(); responses.push(response({ content: null, tool_calls: [{ id: 'call-count', type: 'function', function: { name: 'countEvents', arguments: '{}' } }] }, 'tool_calls'), response({ content: '记录了1件事。' }));
  const data = new AppSnapshot(); data.events.push(new EventCard());
  const result = await new AIAgent({ snapshot: async () => data }, new NativeChatTransport(config())).ask('有多少事件？');
  assert.equal(result, '记录了1件事。'); assert.equal(requests.length, 2);
  const second = JSON.parse(requests[1].options.extraData);
  assert.equal(second.messages.find(x => x.role === 'tool').tool_call_id, 'call-count');
  assert.equal(second.messages.find(x => x.role === 'tool').content, '{"count":1}');
  assert.equal(second.messages.find(x => x.tool_calls).tool_calls[0].function.arguments, '{}');
});
test('provider and network errors are useful and never echo the API key or response body', async () => {
  for (const status of [400, 401, 403, 404, 429, 500]) {
    reset(); responses.push({ responseCode: status, result: 'test-key-only private body' });
    await assert.rejects(new NativeChatTransport(config()).chat([]), error => !error.message.includes('test-key-only') && !error.message.includes('private body'));
    assert.equal(destroyed, 1);
  }
  reset(); responses.push(new Error('request leaked Bearer test-key-only'));
  await assert.rejects(new NativeChatTransport(config()).chat([]), error => error.message.includes('网络') && !error.message.includes('test-key-only'));
  assert.ok(providerError(401).message.includes('Key')); assert.ok(providerError(404).message.includes('模型')); assert.ok(providerError(429).message.includes('额度'));
});
test('cancel prevents a late HTTP reply and destroys the active request only once', async () => {
  reset(); let finish; responses.push(() => new Promise(resolve => { finish = resolve; }));
  const transport = new NativeChatTransport(config()); const pending = transport.chat([]); transport.cancel(); finish(response({ content: 'late' }));
  await assert.rejects(pending, /取消/); assert.equal(destroyed, 1); await assert.rejects(transport.chat([]), /取消/); assert.equal(requests.length, 1);
});
test('security vault stores the complete config atomically with local-only policy', async () => {
  reset(); const vault = new AIConfigVault(); assert.equal(await vault.load(), null);
  await vault.save(config()); assert.deepEqual(await vault.load(), config());
  assert.equal(stored.get(Tags.SYNC_TYPE), 0); assert.equal(stored.has(Tags.IS_PERSISTENT), false); assert.equal(stored.get(Tags.CONFLICT_RESOLUTION), 0);
  assert.ok(stored.get(Tags.SECRET) instanceof Uint8Array);
});
test('vault failures preserve previous credentials and surface redacted messages; unavailable storage fails closed', async () => {
  reset(); const vault = new AIConfigVault(); await vault.save(config()); failSave = true;
  await assert.rejects(vault.save(prepareOpenAIConfig('https://new.example', 'new-key', 'm')), /安全保存/);
  assert.equal((await vault.load()).apiKey, 'test-key-only');
  failSave = false;
  await assert.rejects(vault.save(prepareOpenAIConfig('https://new.example', 'k'.repeat(1024), 'm')), /1024字节/);
  assert.equal((await vault.load()).apiKey, 'test-key-only');
  available = false; await assert.rejects(vault.load(), /安全存储/); await assert.rejects(vault.save(config()), /安全存储/);
});
