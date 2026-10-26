import { AssistantTurn } from '../domain/Assistant';
import { AssistantHistory } from '../domain/AssistantHistory';
import { ConversationStore } from '../features/AssistantController';
import { LifeGraphService } from '../features/LifeGraphService';

// Each controller keeps its own ID, so a late save cannot target another chat.
export class ServiceConversationStore implements ConversationStore {
  private service: LifeGraphService;
  private id: string = '';
  private onLoaded: (history: AssistantHistory) => void;
  private onSaved: (history: AssistantHistory) => void;

  constructor(service: LifeGraphService, onLoaded: (history: AssistantHistory) => void = () => {},
    onSaved: (history: AssistantHistory) => void = () => {}) {
    this.service = service; this.onLoaded = onLoaded; this.onSaved = onSaved;
  }
  conversationId(): string { return this.id; }
  async load(): Promise<AssistantTurn[]> {
    const history = await this.service.loadAssistantHistory();
    this.id = history.activeId; this.onLoaded(history);
    return this.service.loadAssistantChat(this.id);
  }
  async save(turns: AssistantTurn[]): Promise<void> {
    if (turns.length === 0) {
      const history = await this.service.deleteAssistantChat(this.id);
      this.id = ''; this.onSaved(history); return;
    }
    const saved = await this.service.saveAssistantChat(this.id, turns);
    this.id = saved.id; this.onSaved(saved.history);
  }
}
