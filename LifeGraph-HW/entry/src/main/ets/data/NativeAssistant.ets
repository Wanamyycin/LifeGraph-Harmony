import { AssistantAnswer, AssistantTurn, ToolArguments } from '../domain/Assistant';
import { AIAgent } from '../features/AIAgent';
import { AssistantRunner } from '../features/AssistantController';
import { LifeGraphService } from '../features/LifeGraphService';
import { NativeChatTransport } from './NativeChatTransport';
import { OpenAIConfig } from '../domain/OpenAIConfig';

export { ServiceConversationStore } from './AssistantConversationStore';
export class NativeAssistantRunner implements AssistantRunner {
  private service: LifeGraphService;
  private transport: NativeChatTransport;
  constructor(service: LifeGraphService, config: OpenAIConfig) { this.service = service; this.transport = new NativeChatTransport(config); }
  async ask(question: string, history: AssistantTurn[], progress: (text: string) => void, scope?: ToolArguments): Promise<AssistantAnswer> {
    return new AIAgent(this.service, this.transport).askDetailed(question, history, progress, scope);
  }
  cancel(): void { this.transport.cancel(); }
}
