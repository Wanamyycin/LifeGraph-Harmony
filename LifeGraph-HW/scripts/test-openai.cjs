// Legacy serialization coverage only. The offline app has no native API transport or key vault.
require('./ets-loader.cjs');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { completionUrl, prepareOpenAIConfig } = require('../entry/src/main/ets/domain/OpenAIConfig.ets');
const { createOpenAIRequest, parseOpenAIResponse } = require('../entry/src/main/ets/data/OpenAIProtocol.ets');
const { ChatMessage } = require('../entry/src/main/ets/features/AIAgent.ets');
const { ToolCall } = require('../entry/src/main/ets/domain/Assistant.ets');
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
