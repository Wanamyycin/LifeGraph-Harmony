import { http } from '@kit.NetworkKit';
import { ChatMessage, ChatReply, ChatTransport } from '../features/AIAgent';
import { OpenAIConfig, prepareOpenAIConfig } from '../domain/OpenAIConfig';
import { createOpenAIRequest, parseOpenAIResponse, providerError } from './OpenAIProtocol';

class NetworkError extends Error { code: number = 0; }

export class NativeChatTransport implements ChatTransport {
  private config: OpenAIConfig;
  private current: http.HttpRequest | null = null;
  private canceled: boolean = false;
  constructor(config: OpenAIConfig) { this.config = prepareOpenAIConfig(config.url, config.apiKey, config.model); }

  async chat(messages: ChatMessage[]): Promise<ChatReply> {
    if (this.canceled) { throw new Error('对话请求已取消'); }
    const request = http.createHttp(); this.current = request;
    try {
      let response: http.HttpResponse;
      try {
        response = await request.request(this.config.url, {
          method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + this.config.apiKey },
          extraData: JSON.stringify(createOpenAIRequest(this.config.model, messages, this.config.url)),
          connectTimeout: 10000, readTimeout: 60000, expectDataType: http.HttpDataType.STRING, usingCache: false, maxRedirects: 0
        });
      } catch (error) {
        if (this.canceled) { throw new Error('对话请求已取消'); }
        if ((error as NetworkError).code === 2300047) { throw providerError(302); }
        if ((error as NetworkError).code === 2300028) { throw new Error('AI 请求超时，请稍后重试或缩小问题范围'); }
        throw new Error('AI 网络请求失败，请检查网络、接口 URL 和证书');
      }
      if (this.canceled) { throw new Error('对话请求已取消'); }
      if (response.responseCode < 200 || response.responseCode >= 300) { throw providerError(response.responseCode); }
      if (typeof response.result !== 'string' || response.result.length > 2000000) { throw new Error('AI 响应格式或大小不正确'); }
      return parseOpenAIResponse(response.result);
    } finally {
      if (this.current === request) { this.current = null; try { request.destroy(); } catch (_) {} }
    }
  }

  cancel(): void { this.canceled = true; const request = this.current; this.current = null; if (request !== null) { try { request.destroy(); } catch (_) {} } }
  isCanceled(): boolean { return this.canceled; }
}
