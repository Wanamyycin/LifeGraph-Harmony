import { Palette } from '../domain/Models';
import { OpenAIConfig, prepareOpenAIConfig } from '../domain/OpenAIConfig';
import { NativeChatTransport } from '../data/NativeChatTransport';
import { ChatMessage } from '../features/AIAgent';
import { PageScroll } from './PageScroll';

@Component
export struct AIServicePage {
  previous: OpenAIConfig | null = null;
  initialError: string = '';
  @Prop palette: Palette = new Palette();
  onSave: (url: string, key: string, model: string, remember: boolean) => Promise<void> = async () => {};
  onSaved: () => void = () => {};
  @State url: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State remember: boolean = true;
  @State saving: boolean = false;
  @State testing: boolean = false;
  @State helpExpanded: boolean = false;
  @State error: string = '';
  @State connected: boolean = false;
  private transport: NativeChatTransport | null = null;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true; this.url = this.previous?.url ?? ''; this.model = this.previous?.model ?? ''; this.error = this.initialError;
    this.helpExpanded = this.initialError.length > 0;
  }
  aboutToDisappear(): void { this.active = false; this.apiKey = ''; this.transport?.cancel(); }
  private changed(): void { this.connected = false; this.error = ''; }
  private async test(): Promise<void> {
    this.testing = true; this.error = ''; this.connected = false;
    try {
      const config = prepareOpenAIConfig(this.url, this.apiKey, this.model, this.previous);
      this.transport = new NativeChatTransport(config);
      await this.transport.chat([new ChatMessage('user', '这是连接测试，请勿调用工具，只回复“连接成功”。')]);
      if (this.active) { this.connected = true; }
    } catch (error) { if (this.active) { this.error = error.message || '连接未成功，请检查配置'; } }
    finally { this.transport = null; if (this.active) { this.testing = false; } }
  }
  private async save(): Promise<void> {
    this.saving = true; this.error = '';
    try { await this.onSave(this.url, this.apiKey, this.model, this.remember); if (this.active) { this.apiKey = ''; this.onSaved(); } }
    catch (error) { if (this.active) { this.error = error.message || '配置未能保存，请重试'; } }
    finally { if (this.active) { this.saving = false; } }
  }

  build() {
    Column({ space: 16 }) {
      PageScroll({ tint: this.palette.muted }) {
        Column({ space: 16 }) {
          Text('连接你信任的 AI 服务').fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
          Text(this.connected ? '连接成功' : this.previous === null ? '未连接' : '已配置').fontSize(13)
            .fontColor(this.connected ? this.palette.primary : this.palette.muted).width('100%')
          Column({ space: 8 }) {
            Text('服务地址').fontSize(14).fontColor(this.palette.text).width('100%')
            TextInput({ text: this.url, placeholder: 'https://api.example.com/v1' }).maxLength(2048).height(48).borderRadius(10)
              .id('ai-address').placeholderColor(this.palette.muted).caretColor(this.palette.primary).fontColor(this.palette.text).backgroundColor(this.palette.card)
              .onChange((value: string) => { this.url = value; this.changed(); })
          }.width('100%')
          Column({ space: 8 }) {
            Text('API Key').fontSize(14).fontColor(this.palette.text).width('100%')
            TextInput({ text: this.apiKey, placeholder: this.previous !== null ? '已配置，地址不变时留空保留' : '填写 API Key' }).type(InputType.Password)
              .enableAutoFill(false).maxLength(4096).height(48).borderRadius(10).id('ai-api-key').fontColor(this.palette.text)
              .placeholderColor(this.palette.muted).caretColor(this.palette.primary).backgroundColor(this.palette.card)
              .onChange((value: string) => { this.apiKey = value; this.changed(); })
          }.width('100%')
          Column({ space: 8 }) {
            Text('模型名称').fontSize(14).fontColor(this.palette.text).width('100%')
            TextInput({ text: this.model, placeholder: '填写服务商提供的模型 ID' }).maxLength(200).height(48).borderRadius(10)
              .id('ai-model').placeholderColor(this.palette.muted).caretColor(this.palette.primary).fontColor(this.palette.text).backgroundColor(this.palette.card)
              .onChange((value: string) => { this.model = value; this.changed(); })
          }.width('100%')
          Button('如何获取配置信息？', { type: ButtonType.Normal }).fontSize(13).height(44).padding(0).backgroundColor(Color.Transparent)
            .fontColor(this.palette.primary).alignSelf(ItemAlign.Start).onClick(() => { this.helpExpanded = !this.helpExpanded; })
          if (this.helpExpanded) {
            Text('在服务商控制台获取 API Key 和模型 ID，选择支持工具调用的 OpenAI 兼容模型。服务地址可填根地址、/v1 或完整的 /chat/completions 地址。')
              .fontSize(13).lineHeight(21).fontColor(this.palette.muted).width('100%')
            Row({ space: 8 }) {
              Checkbox({ name: 'remember-ai-config' }).select(this.remember).selectedColor(this.palette.primary).id('ai-remember')
                .onChange((value: boolean) => { this.remember = value; })
              Text('在本机安全保存').fontSize(14).fontColor(this.palette.text).layoutWeight(1)
            }.width('100%')
            Text('取消后仅本次运行使用，重开应用时不会保留本次改动。').fontSize(12).fontColor(this.palette.muted).width('100%')
          }
          if (this.error.length > 0) { Text(this.error).fontSize(13).fontColor(this.palette.danger).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 16 })
      }
      Column({ space: 5 }) {
        Text(this.remember ? '密钥保存在本机' : '密钥仅在本次运行中使用').fontSize(13).fontColor(this.palette.text).width('100%')
        Text('提问和相关记录会发送至该服务。').fontSize(12).fontColor(this.palette.muted).width('100%')
      }.width('100%')
      Row({ space: 12 }) {
        Button(this.testing ? '正在连接…' : '测试连接', { type: ButtonType.Normal }).layoutWeight(1).height(46).borderRadius(10)
          .backgroundColor(Color.Transparent).fontColor(this.palette.primary).border({ width: 1, color: this.palette.primary })
          .id('ai-test-connection').onClick(() => this.test())
        Button(this.saving ? '正在保存…' : '保存', { type: ButtonType.Normal }).layoutWeight(1).height(46).borderRadius(10)
          .backgroundColor(this.palette.primary).fontColor(this.palette.onPrimary).id('ai-save-config').onClick(() => this.save())
      }.width('100%')
    }.width('100%').layoutWeight(1).enabled(!this.saving && !this.testing)
  }
}
