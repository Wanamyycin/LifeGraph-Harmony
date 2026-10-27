import { AppSnapshot, Palette } from '../domain/Models';
import { Person } from '../domain/Person';
import { DesktopCardConfig, normalizeCardConfig } from '../features/DesktopCard';
import { ChoiceChip } from './ChoiceChip';

@Component
export struct DesktopCardSettings {
  data: AppSnapshot = new AppSnapshot();
  initial: DesktopCardConfig = new DesktopCardConfig();
  palette: Palette = new Palette();
  onSave: (config: DesktopCardConfig) => Promise<void> = async () => {};
  @State ids: string[] = [];
  @State nameMode: string = 'hidden';
  @State saving: boolean = false;
  @State error: string = '';
  @State message: string = '';

  aboutToAppear(): void {
    const config = normalizeCardConfig(this.initial);
    this.ids = config.personIds.filter((id: string) => this.data.persons.some((p: Person) => p.id === id && p.deletedAt === null && p.id !== this.data.profile.defaultPersonId));
    this.nameMode = config.nameMode;
  }
  private toggle(id: string): void {
    this.message = ''; this.error = '';
    if (this.ids.includes(id)) { this.ids = this.ids.filter((item: string) => item !== id); }
    else if (this.ids.length < 6) { this.ids = [...this.ids, id]; }
    else { this.error = '最多选择 6 位人物'; }
  }
  private async save(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true; this.error = ''; this.message = '';
    const config = new DesktopCardConfig(); config.personIds = this.ids; config.nameMode = this.nameMode;
    try { await this.onSave(config); this.message = '已保存，桌面卡片已更新'; }
    catch (error) { this.error = String(error).replace(/^Error: /, ''); }
    finally { this.saving = false; }
  }
  build() {
    Scroll() {
      Column({ space: 18 }) {
        Text('把重要的人留在桌面').fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
        Text('长按桌面应用图标 → 卡片，添加 2×2 关系微图。小球显示序号或简称，点击人物进入应用查看共同经历。所有卡片共用以下设置。').fontSize(14).fontColor(this.palette.muted).width('100%')
        Text('桌面人物 · ' + this.ids.length.toString() + '/6').fontSize(16).fontColor(this.palette.text).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.data.persons.filter((p: Person) => p.deletedAt === null && p.id !== this.data.profile.defaultPersonId), (p: Person) => {
            Row() { ChoiceChip({ label: p.name, selected: this.ids.includes(p.id), palette: this.palette, disabled: this.saving, onAction: () => this.toggle(p.id) }) }.margin({ right: 8, bottom: 8 })
          }, (p: Person) => p.id)
        }.width('100%')
        Text('姓名显示').fontSize(16).fontColor(this.palette.text).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(['hidden', 'initial', 'name'], (mode: string) => {
            Row() { ChoiceChip({ label: mode === 'hidden' ? '隐藏姓名' : (mode === 'initial' ? '名字首字' : '记录中的称呼'), selected: this.nameMode === mode,
              palette: this.palette, disabled: this.saving, onAction: () => { this.nameMode = mode; this.message = ''; } }) }.margin({ right: 8, bottom: 8 })
          })
        }.width('100%')
        Text('桌面对旁人可见。默认用序号隐藏姓名，仍会显示人物数量和连线。紧凑卡片不展示事件标题、正文、照片、录音和 AI 对话。').fontSize(13).fontColor(this.palette.muted).width('100%')
        if (this.error.length > 0) { Text(this.error).fontSize(14).fontColor(this.palette.danger).width('100%') }
        if (this.message.length > 0) { Text(this.message).fontSize(14).fontColor(this.palette.primary).width('100%') }
        Button(this.saving ? '正在保存' : '保存卡片设置').width('100%').height(46).backgroundColor(this.palette.primary).fontColor(this.palette.onPrimary)
          .enabled(!this.saving).onClick(() => this.save())
      }.width('100%').padding({ bottom: 24 })
    }.width('100%').layoutWeight(1)
  }
}
