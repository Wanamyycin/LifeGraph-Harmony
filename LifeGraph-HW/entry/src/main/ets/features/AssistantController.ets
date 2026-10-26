import { AssistantAnswer, AssistantReference, AssistantTurn, ToolArguments } from '../domain/Assistant';
import { ASSISTANT_HELP, HelpEntry, localHelpText } from './AssistantHelp';

export interface ConversationStore {
  load(): Promise<AssistantTurn[]>;
  save(turns: AssistantTurn[]): Promise<void>;
}
export interface AssistantRunner {
  ask(question: string, history: AssistantTurn[], progress: (text: string) => void, scope?: ToolArguments): Promise<AssistantAnswer>;
  cancel(): void;
}
export class AssistantState {
  turns: AssistantTurn[] = [];
  ready: boolean = false;
  busy: boolean = false;
  error: string = '';
  progress: string = '';
}

export class AssistantController {
  private state: AssistantState = new AssistantState();
  private store: ConversationStore;
  private runnerFactory: () => AssistantRunner;
  private onChange: (state: AssistantState) => void;
  private onProgress: (text: string) => void;
  private runner: AssistantRunner | null = null;
  private generation: number = 0;
  private active: boolean = true;
  private writes: Promise<void> = Promise.resolve();

  constructor(store: ConversationStore, factory: () => AssistantRunner, onChange: (state: AssistantState) => void, onProgress: (text: string) => void = () => {}) {
    this.store = store; this.runnerFactory = factory; this.onChange = onChange; this.onProgress = onProgress;
  }
  snapshot(): AssistantState { return JSON.parse(JSON.stringify(this.state)) as AssistantState; }
  async load(): Promise<void> {
    if (!this.active) { return; }
    const generation = ++this.generation;
    try {
      const turns = await this.store.load();
      if (!this.current(generation)) { return; }
      this.state.turns = turns; this.state.ready = true; this.state.error = '';
    } catch (_) {
      if (this.current(generation)) { this.state.error = '这段聊天暂时无法读取，可从历史聊天重新选择，或删除此聊天后重试；人物和事件不受影响。'; }
    }
    if (this.current(generation)) { this.publish(); }
  }
  async send(question: string, scope?: ToolArguments): Promise<void> {
    if (!this.active || this.state.busy || !this.state.ready || question.trim().length === 0) { return; }
    if (question.length > 6000) { this.state.error = '问题最多6000字，请缩短后再发送'; this.publish(); return; }
    const generation = ++this.generation;
    const history = this.snapshot().turns;
    const user = makeTurn(question.trim(), true); user.status = 'pending'; user.scope = scope;
    this.state.turns = [...this.state.turns, user]; this.state.busy = true; this.state.error = ''; this.state.progress = '正在准备查询…'; this.publish();
    try {
      await this.persist();
      if (!this.current(generation)) { return; }
      const runner = this.runnerFactory(); this.runner = runner;
      const answer = await runner.ask(question.trim(), history, (text: string) => {
        if (this.current(generation)) { this.state.progress = text; this.onProgress(text); }
      }, scope);
      if (!this.current(generation)) { return; }
      this.finishUser(user.id, 'complete');
      const response = makeTurn(answer.text, false); response.references = answer.references;
      response.readAt = answer.readAt; response.contextNote = answer.contextNote;
      this.state.turns = [...this.state.turns, response]; this.state.busy = false; this.state.progress = ''; this.runner = null; this.publish();
      try { await this.persist(); } catch (_) {
        if (this.current(generation)) { this.state.error = '回复已生成，但聊天保存未完成；请复制需要的内容，勿重复发送同一问题。'; this.publish(); }
      }
    } catch (error) {
      if (!this.current(generation)) { return; }
      this.finishUser(user.id, 'failed'); this.state.busy = false; this.state.progress = ''; this.runner = null;
      this.state.error = String(error).replace(/^Error:\s*/, ''); this.publish();
      try { await this.persist(); } catch (_) { /* The visible error remains the primary error. */ }
    }
  }
  async cancel(): Promise<void> {
    if (!this.active) { await this.writes; return; }
    if (!this.state.busy) { await this.writes; return; }
    const generation = ++this.generation; this.runner?.cancel(); this.runner = null;
    this.state.turns = this.state.turns.map((turn: AssistantTurn): AssistantTurn => {
      const copy = JSON.parse(JSON.stringify(turn)) as AssistantTurn; if (copy.status === 'pending') { copy.status = 'canceled'; } return copy;
    });
    this.state.busy = false; this.state.progress = ''; this.state.error = ''; this.publish();
    try { await this.persist(); } catch (_) {
      if (this.current(generation)) { this.state.error = '查询已停止，但聊天状态保存未完成'; this.publish(); }
    }
  }
  async clear(): Promise<void> {
    if (!this.active) { return; }
    const generation = ++this.generation; this.runner?.cancel(); this.runner = null;
    for (const turn of this.state.turns) { if (turn.status === 'pending') { turn.status = 'canceled'; } }
    this.state.busy = false; this.state.ready = false; this.state.progress = ''; this.state.error = ''; this.publish();
    try {
      await this.persist([]);
      if (this.current(generation)) { this.state.turns = []; this.state.ready = true; this.publish(); }
    } catch (_) {
      if (this.current(generation)) { this.state.ready = true; this.state.error = '聊天删除未完成，原聊天仍保留，请重试'; this.publish(); }
    }
  }
  async showHelp(): Promise<void> {
    if (!this.active || !this.state.ready || this.state.busy) { return; }
    const generation = ++this.generation;
    const answer = makeTurn(localHelpText(), false);
    answer.references = ASSISTANT_HELP.map((entry: HelpEntry): AssistantReference => {
      const ref = new AssistantReference(); ref.kind = 'help'; ref.id = entry.id; ref.title = entry.title; return ref;
    });
    answer.contextNote = '本机内置使用说明，未向 AI 服务发送请求。';
    this.state.turns = [...this.state.turns, makeTurn('软件怎么用？', true), answer]; this.state.error = ''; this.publish();
    try { await this.persist(); } catch (_) {
      if (this.current(generation)) { this.state.error = '使用说明已打开，聊天保存未完成'; this.publish(); }
    }
  }
  dispose(): void {
    this.generation++; this.active = false; this.runner?.cancel(); this.runner = null;
  }
  private finishUser(id: string, status: string): void {
    this.state.turns = this.state.turns.map((turn: AssistantTurn): AssistantTurn => {
      const copy = JSON.parse(JSON.stringify(turn)) as AssistantTurn; if (copy.id === id) { copy.status = status; } return copy;
    });
  }
  private persist(turns: AssistantTurn[] = this.state.turns): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(turns)) as AssistantTurn[];
    const result = this.writes.then(() => this.store.save(snapshot));
    this.writes = result.then(() => {}, () => {}); return result;
  }
  private current(generation: number): boolean { return this.active && this.generation === generation; }
  private publish(): void { if (this.active) { this.onChange(this.snapshot()); } }
}
function makeTurn(text: string, user: boolean): AssistantTurn {
  const turn = new AssistantTurn(); turn.id = Date.now().toString() + '-' + Math.random().toString(36).slice(2);
  turn.text = text; turn.user = user; turn.createdAt = Date.now(); return turn;
}
