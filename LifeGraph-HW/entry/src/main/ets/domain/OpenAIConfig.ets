export class OpenAIConfig {
  url: string = '';
  apiKey: string = '';
  model: string = '';
}

export function completionUrl(raw: string): string {
  const value = raw.trim();
  if (value.length > 2048 || /[\s<>"'\\#]/.test(value)) { throw new Error('请填写有效的 http(s) 接口 URL，不要包含空格或片段'); }
  const match = value.match(/^(https?):\/\/(\[[0-9a-f:]+\]|[a-z0-9._-]+)(?::([0-9]{1,5}))?((?:\/|\?).*)?$/i);
  if (match === null || (match[3] !== undefined && (Number(match[3]) < 1 || Number(match[3]) > 65535))) { throw new Error('请填写有效的 http(s) 接口 URL'); }
  const origin = match[1].toLowerCase() + '://' + match[2].toLowerCase() + (match[3] === undefined ? '' : ':' + match[3]);
  const tail = match[4] ?? ''; const split = tail.indexOf('?');
  const path = (split < 0 ? tail : tail.slice(0, split)).replace(/\/+$/, '');
  const query = split < 0 ? '' : tail.slice(split);
  if (/\/chat\/completions$/i.test(path)) { return origin + path + query; }
  return origin + (path.length === 0 ? '/v1' : path) + '/chat/completions' + query;
}

export function prepareOpenAIConfig(url: string, key: string, model: string, previous: OpenAIConfig | null = null): OpenAIConfig {
  const endpoint = completionUrl(url);
  const name = model.trim(); let secret = key.trim().replace(/^Bearer\s+/i, '');
  if (name.length === 0 || name.length > 200 || /[\r\n\x00-\x1f]/.test(name)) { throw new Error('请填写服务提供方的模型名称，最多200字'); }
  if (secret.length === 0 && previous !== null) {
    if (completionUrl(previous.url) !== endpoint) { throw new Error('接口 URL 已更改，请重新填写 API Key'); }
    secret = previous.apiKey;
  }
  if (secret.length === 0 || secret.length > 4096 || /[^\x21-\x7e]/.test(secret)) { throw new Error('请填写有效的 API Key，不要包含空格或换行'); }
  const config = new OpenAIConfig(); config.url = endpoint; config.apiKey = secret; config.model = name; return config;
}
