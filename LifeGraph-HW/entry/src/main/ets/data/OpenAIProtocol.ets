import { ChatMessage, ChatReply } from '../features/AIAgent';
import { ToolArguments, ToolCall } from '../domain/Assistant';
import { AI_TOOLS_JSON } from './AiTools';

class FunctionDefinition {
  name: string = '';
  description: string = '';
  parameters: Object = JSON.parse('{}') as Object;
}
class FunctionCall {
  name: string = '';
  arguments: string = '';
}
class WireTool {
  type: string = 'function';
  function: FunctionDefinition = new FunctionDefinition();
}
class WireToolCall {
  id: string = '';
  type: string = 'function';
  function: FunctionCall = new FunctionCall();
}
class WireMessage {
  role: string = '';
  content: string | null = null;
  tool_calls?: WireToolCall[];
  tool_call_id?: string;
}
class ThinkingSettings { type: string = 'disabled'; }
export class OpenAIRequest {
  model: string = '';
  messages: WireMessage[] = [];
  tools: WireTool[] = [];
  tool_choice: string = 'auto';
  stream: boolean = false;
  thinking?: ThinkingSettings;
}
class ContentPart {
  type: string = '';
  text: string = '';
}
class ResponseMessage {
  content: string | ContentPart[] | null = null;
  tool_calls?: WireToolCall[];
  refusal?: string;
}
class Choice {
  message: ResponseMessage = new ResponseMessage();
  finish_reason: string = '';
}
class Completion {
  choices: Choice[] = [];
}

export function createOpenAIRequest(model: string, messages: ChatMessage[], endpoint: string = ''): OpenAIRequest {
  const request = new OpenAIRequest(); request.model = model;
  // DeepSeek defaults to thinking mode, whose tool protocol requires reasoning_content roundtrips.
  if (/^https:\/\/api\.deepseek\.com(?::443)?\//i.test(endpoint)) { request.thinking = new ThinkingSettings(); }
  request.messages = messages.map((message: ChatMessage): WireMessage => {
    const value = new WireMessage(); value.role = message.role; value.content = message.content;
    if (message.tool_call_id !== undefined) { value.tool_call_id = message.tool_call_id; }
    if (message.tool_calls !== undefined) {
      value.tool_calls = message.tool_calls.map((call: ToolCall): WireToolCall => {
        const item = new WireToolCall(); item.id = call.id; item.function.name = call.name; item.function.arguments = JSON.stringify(call.arguments); return item;
      });
    }
    return value;
  });
  request.tools = (JSON.parse(AI_TOOLS_JSON) as FunctionDefinition[]).map((definition: FunctionDefinition): WireTool => {
    const tool = new WireTool(); tool.function = definition; return tool;
  });
  return request;
}

export function parseOpenAIResponse(raw: string): ChatReply {
  let body: Completion;
  try { body = JSON.parse(raw) as Completion; } catch (_) { throw new Error('接口返回了非 JSON 内容，请检查 URL 是否为 Chat Completions 接口'); }
  if (body === null || !Array.isArray(body.choices) || body.choices.length === 0 || body.choices[0]?.message === null || typeof body.choices[0]?.message !== 'object') {
    throw new Error('接口返回内容不符合 OpenAI Chat Completions 格式');
  }
  const choice = body.choices[0]; const message = choice.message;
  if (choice.finish_reason === 'length') { throw new Error('模型回复达到长度限制，请缩小问题范围后重试'); }
  if (choice.finish_reason === 'content_filter' || (typeof message.refusal === 'string' && message.refusal.length > 0)) { throw new Error('模型未能回答本次问题，请调整问题后重试'); }
  const reply = new ChatReply();
  if (message.tool_calls !== undefined && message.tool_calls !== null && !Array.isArray(message.tool_calls)) { throw new Error('模型返回的工具调用格式不正确'); }
  if (message.tool_calls !== undefined && message.tool_calls !== null && message.tool_calls.length > 0) {
    if (!Array.isArray(message.tool_calls) || message.tool_calls.length > 12) { throw new Error('模型返回的工具调用格式不正确'); }
    reply.kind = 'tool_calls';
    reply.tool_calls = message.tool_calls.map((call: WireToolCall): ToolCall => {
      if (call === null || call.type !== 'function' || typeof call.id !== 'string' || call.id.length === 0 || call.function === null ||
        typeof call.function !== 'object' || typeof call.function.name !== 'string' || typeof call.function.arguments !== 'string' || call.function.arguments.length > 90000) {
        throw new Error('模型返回的工具调用格式不正确');
      }
      let args: ToolArguments;
      try { args = JSON.parse(call.function.arguments) as ToolArguments; } catch (_) { throw new Error('模型返回的工具参数不是有效 JSON，请重试'); }
      if (args === null || typeof args !== 'object' || Array.isArray(args)) { throw new Error('模型返回的工具参数必须为对象'); }
      const item = new ToolCall(); item.id = call.id; item.name = call.function.name; item.arguments = args; return item;
    });
    return reply;
  }
  reply.kind = 'text';
  if (typeof message.content === 'string') { reply.content = message.content; }
  else if (Array.isArray(message.content)) {
    reply.content = message.content.filter((part: ContentPart) => part !== null && part.type === 'text' && typeof part.text === 'string').map((part: ContentPart) => part.text).join('');
  }
  if (typeof reply.content !== 'string' || reply.content.trim().length === 0) { throw new Error('模型返回了空内容，请确认模型支持对话和工具调用'); }
  return reply;
}

export function providerError(status: number): Error {
  if (status === 401) { return new Error('API Key 无效或已过期，请在服务设置中更新'); }
  if (status === 403) { return new Error('该 API Key 无权访问此接口或模型'); }
  if (status === 404) { return new Error('接口或模型不存在，请检查 URL 和模型名称'); }
  if (status === 429) { return new Error('服务限流或额度不足，请稍后重试或检查账号额度'); }
  if (status >= 300 && status < 400) { return new Error('接口发生重定向，请填写最终的 Chat Completions URL'); }
  if (status === 400 || status === 422) { return new Error('服务不接受本次参数，请确认模型支持 Chat Completions 和工具调用'); }
  if (status >= 500) { return new Error('AI 服务暂时不可用，请稍后重试'); }
  return new Error('AI 请求失败（HTTP ' + status.toString() + '），请检查服务设置');
}
