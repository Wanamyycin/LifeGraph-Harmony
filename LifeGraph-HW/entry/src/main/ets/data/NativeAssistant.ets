import { AssistantAnswer, AssistantTurn } from '../domain/Assistant';
import { AIAgent } from '../features/AIAgent';
import { AssistantRunner, ConversationStore } from '../features/AssistantController';
import { LifeGraphService } from '../features/LifeGraphService';
import { NativeChatTransport } from './NativeChatTransport';
import { OpenAIConfig } from '../domain/OpenAIConfig';

export class ServiceConversationStore implements ConversationStore {
  private service: LifeGraphService;
  constructor(service: LifeGraphService) { this.service = service; }
  async load(): Promise<AssistantTurn[]> { return this.service.loadAssistantConversation(); }
  async save(turns: AssistantTurn[]): Promise<void> { await this.service.saveAssistantConversation(turns); }
}
export class NativeAssistantRunner implements AssistantRunner {
  private service: LifeGraphService;
  private transport: NativeChatTransport;
  constructor(service: LifeGraphService, config: OpenAIConfig) { this.service = service; this.transport = new NativeChatTransport(config); }
  async ask(question: string, history: AssistantTurn[], progress: (text: string) => void): Promise<AssistantAnswer> {
    return new AIAgent(this.service, this.transport).askDetailed(question, history, progress);
  }
  cancel(): void { this.transport.cancel(); }
}
