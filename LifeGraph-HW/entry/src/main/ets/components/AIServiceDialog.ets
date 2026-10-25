import { Palette } from '../domain/Models';

@CustomDialog
export struct AIServiceDialog {
  controller?: CustomDialogController;
  initialUrl: string = '';
  initialModel: string = '';
  hasKey: boolean = false;
  initialError: string = '';
  palette: Palette = new Palette();
  onSave: (url: string, key: string, model: string, remember: boolean) => Promise<void> = async () => {};
  @State url: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State remember: boolean = true;
  @State saving: boolean = false;
  @State error: string = '';

  aboutToAppear(): void { this.url = this.initialUrl; this.model = this.initialModel; this.error = this.initialError; }
  aboutToDisappear(): void { this.apiKey = ''; }
  private async save(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true; this.error = '';
    try { await this.onSave(this.url, this.apiKey, this.model, this.remember); this.apiKey = ''; this.controller?.close(); }
    catch (error) { this.error = error.message || '配置未能保存，请重试'; }
    finally { this.saving = false; }
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('AI 服务设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
        Text('使用支持工具调用的 OpenAI 兼容模型。问题和必要的记录文字将直接发送给你填写的服务。')
          .fontSize(13).fontColor(this.palette.muted).width('100%')
        Text('接口 URL').fontSize(14).fontColor(this.palette.text).width('100%')
        TextInput({ text: this.url, placeholder: 'https://api.example.com/v1' }).maxLength(2048).id('ai-address').placeholderColor(this.palette.muted).caretColor(this.palette.primary)
          .fontColor(this.palette.text).backgroundColor(this.palette.card).onChange((value: string) => { this.url = value; })
        Text('可填根地址、/v1 地址或完整 /chat/completions 地址。').fontSize(12).fontColor(this.palette.muted).width('100%')
        Text('API Key').fontSize(14).fontColor(this.palette.text).width('100%')
        TextInput({ text: this.apiKey, placeholder: this.hasKey ? '已配置；地址不变时留空可保留' : '填写 API Key' }).type(InputType.Password).placeholderColor(this.palette.muted).caretColor(this.palette.primary)
          .enableAutoFill(false).maxLength(4096).id('ai-api-key').fontColor(this.palette.text).backgroundColor(this.palette.card)
          .onChange((value: string) => { this.apiKey = value; })
        Text('模型名称').fontSize(14).fontColor(this.palette.text).width('100%')
        TextInput({ text: this.model, placeholder: '填写服务提供方的模型 ID' }).maxLength(200).id('ai-model').placeholderColor(this.palette.muted).caretColor(this.palette.primary)
          .fontColor(this.palette.text).backgroundColor(this.palette.card).onChange((value: string) => { this.model = value; })
        Row({ space: 10 }) {
          Checkbox({ name: 'remember-ai-config' }).select(this.remember).selectedColor(this.palette.primary).id('ai-remember')
            .onChange((value: boolean) => { this.remember = value; })
          Text('在本机安全保存').fontSize(14).fontColor(this.palette.text).layoutWeight(1)
        }.width('100%')
        Text(this.remember ? '密钥单独保存在设备安全存储，不进入聊天、人物数据或导出备份。' : '本次配置只在当前运行期间使用，重开后需重新填写或使用此前保存的配置。')
          .fontSize(12).fontColor(this.palette.muted).width('100%')
        if (this.error.length > 0) { Text(this.error).fontSize(13).fontColor(this.palette.danger).width('100%') }
        Row({ space: 12 }) {
          Button('取消').layoutWeight(1).fontColor(this.palette.text).backgroundColor(this.palette.soft).onClick(() => { this.apiKey = ''; this.controller?.close(); })
          Button(this.saving ? '正在保存…' : '保存配置').layoutWeight(1).backgroundColor(this.palette.primary).fontColor(this.palette.onPrimary).id('ai-save-config').onClick(() => this.save())
        }.width('100%')
      }.padding(22).width('100%').enabled(!this.saving)
    }.constraintSize({ maxHeight: '85%' }).width('100%').backgroundColor(this.palette.paper).borderRadius(22)
  }
}
