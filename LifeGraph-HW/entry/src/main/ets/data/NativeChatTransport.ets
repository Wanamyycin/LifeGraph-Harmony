import { http } from '@kit.NetworkKit';
import { ChatMessage, ChatReply, ChatTransport } from '../features/AIAgent';
import { AI_TOOLS_JSON } from './AiTools';

class ApiEnvelope {
  code: number = -1;
  message: string = '';
  data: ChatReply = new ChatReply();
}

class ChatRequest {
  messages: ChatMessage[];
  tools: Object[];
  constructor(messages: ChatMessage[]) { this.messages = messages; this.tools = JSON.parse(AI_TOOLS_JSON) as Object[]; }
}

export class NativeChatTransport implements ChatTransport {
  private baseUrl: string;
  private current: http.HttpRequest | null = null;
  private canceled: boolean = false;
  constructor(baseUrl: string) { this.baseUrl = baseUrl.trim().replace(/\/+$/, ''); }

  async chat(messages: ChatMessage[]): Promise<ChatReply> {
    if (this.canceled) { throw new Error('对话请求已取消'); }
    if (!/^https?:\/\//.test(this.baseUrl)) { throw new Error('请先配置可访问的 AI 服务地址'); }
    const request = http.createHttp(); this.current = request;
    try {
      const response = await request.request(this.baseUrl + '/api/v1/ai/chat', {
        method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(new ChatRequest(messages)),
        connectTimeout: 10000, readTimeout: 45000, expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode < 200 || response.responseCode >= 300) { throw new Error('AI 服务暂时不可用，请稍后重试'); }
      if (typeof response.result !== 'string' || response.result.length > 2000000) { throw new Error('AI 响应格式或大小不正确'); }
      const body = JSON.parse(response.result) as ApiEnvelope;
      if (body.code !== 0 || body.data === null || typeof body.data !== 'object') { throw new Error(body.message || 'AI 服务请求失败'); }
      return body.data;
    } finally { if (this.current === request) { this.current = null; } request.destroy(); }
  }

  cancel(): void { this.canceled = true; const request = this.current; this.current = null; if (request !== null) { request.destroy(); } }
}
