import { AssistantChat, assistantChatGroup } from '../domain/AssistantHistory';
import { Palette } from '../domain/Models';

@Component
export struct AssistantHistoryPage {
  @Prop chats: AssistantChat[] = [];
  @Prop activeId: string = '';
  @Prop disabled: boolean = false;
  @Prop palette: Palette = new Palette();
  onBack: () => void = () => {};
  onNew: () => void = () => {};
  onSelect: (id: string) => void = () => {};
  onSearch: (query: string) => Promise<string[]> = async () => [];
  @State query: string = '';
  @State matches: string[] = [];
  @State searching: boolean = false;
  @State error: string = '';
  private timer: number = -1;
  private generation: number = 0;

  aboutToDisappear(): void { this.generation++; clearTimeout(this.timer); }
  private changeQuery(value: string): void {
    this.query = value; this.error = ''; this.matches = []; clearTimeout(this.timer);
    const generation = ++this.generation;
    if (value.trim().length === 0) { this.searching = false; this.matches = []; return; }
    this.searching = true;
    this.timer = setTimeout(async () => {
      try {
        const matches = await this.onSearch(value);
        if (generation === this.generation) { this.matches = matches; }
      } catch (_) { if (generation === this.generation) { this.error = '暂时无法搜索聊天，请重试'; } }
      finally { if (generation === this.generation) { this.searching = false; } }
    }, 180);
  }
  private visibleChats(): AssistantChat[] {
    return this.query.trim().length === 0 ? this.chats : this.chats.filter((chat: AssistantChat) => this.matches.includes(chat.id));
  }
  private groupChats(group: string): AssistantChat[] { return this.visibleChats().filter((chat: AssistantChat) => assistantChatGroup(chat.updatedAt) === group); }
  private timeLabel(chat: AssistantChat): string {
    const date = new Date(chat.updatedAt);
    if (assistantChatGroup(chat.updatedAt) !== '更早') {
      return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
    }
    return (date.getFullYear() === new Date().getFullYear() ? '' : date.getFullYear().toString() + '年') +
      (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日';
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Button('‹').fontSize(30).width(40).height(44).padding(0).backgroundColor(Color.Transparent).fontColor(this.palette.text)
          .id('nav-back').accessibilityText('返回当前聊天').onClick(() => this.onBack())
        Text('历史聊天').fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1)
        Button('＋ 新聊天', { type: ButtonType.Normal }).fontSize(14).height(44).padding({ left: 8, right: 0 })
          .fontColor(this.palette.primary).backgroundColor(Color.Transparent).id('ai-history-new').onClick(() => this.onNew())
      }.width('100%')
      Search({ value: this.query, placeholder: '搜索历史聊天' }).height(48).fontColor(this.palette.text).placeholderColor(this.palette.muted)
        .searchIcon({ color: this.palette.muted }).backgroundColor(this.palette.card).id('ai-history-search')
        .onChange((value: string) => this.changeQuery(value))
      if (this.error.length > 0) { Text(this.error).fontSize(13).fontColor(this.palette.danger).width('100%') }
      if (this.chats.length === 0) {
        Column({ space: 10 }) {
          Text('还没有历史聊天').fontSize(20).fontColor(this.palette.text)
          Text('发送第一条消息后，会自动保存在这里。').fontSize(14).fontColor(this.palette.muted)
        }.width('100%').padding({ top: 48 })
        Blank()
      } else if (!this.searching && this.visibleChats().length === 0 && this.error.length === 0) {
        Text('没有找到匹配的聊天').fontSize(16).fontColor(this.palette.muted).padding({ top: 40 })
        Blank()
      } else {
        List({ space: 8 }) {
          if (this.searching) { ListItem() { Text('正在搜索…').fontSize(12).fontColor(this.palette.muted) } }
          ForEach(['今天', '昨天', '更早'], (group: string) => {
            if (this.groupChats(group).length > 0) {
              ListItem() { Text(group).fontSize(13).fontColor(this.palette.muted).padding({ top: 12, bottom: 4 }) }
              ForEach(this.groupChats(group), (chat: AssistantChat) => {
                ListItem() {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: 12 }) {
                      Column({ space: 7 }) {
                        Row({ space: 12 }) {
                          Text(chat.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1)
                            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
                          Text(this.timeLabel(chat)).fontSize(12).fontColor(this.palette.muted)
                        }.width('100%')
                        Text(chat.preview).fontSize(13).fontColor(this.palette.muted).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
                      }.layoutWeight(1)
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.palette.muted])
                    }.width('100%')
                  }.width('100%').height(82).padding({ left: 12, right: 12 }).borderRadius(10)
                    .backgroundColor(chat.id === this.activeId ? this.palette.soft : Color.Transparent)
                    .id('ai-history-chat-' + chat.id).accessibilityText(chat.title).onClick(() => this.onSelect(chat.id))
                }
              }, (chat: AssistantChat) => chat.id)
            }
          }, (group: string) => group)
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').layoutWeight(1).enabled(!this.disabled)
  }
}
