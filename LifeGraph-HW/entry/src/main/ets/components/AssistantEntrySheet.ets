import { Person } from '../domain/Person';
import { Palette } from '../domain/Models';
import { AssistantEntryRequest, assistantDate, assistantEntryRequest, assistantRangeEnd, assistantRangeStart } from '../features/AssistantEntry';
import { ChoiceChip } from './ChoiceChip';

@Component
export struct AssistantEntrySheet {
  kind: string = 'together';
  people: Person[] = [];
  selfId: string = '';
  @Prop palette: Palette = new Palette();
  onClose: () => void = () => {};
  onStart: (request: AssistantEntryRequest) => void = () => {};
  @State personId: string = '';
  @State personSearch: string = '';
  @State clue: string = '';
  @State period: string = 'all';
  @State choosingPerson: boolean = false;
  @State choosingTime: boolean = false;
  @State from: number = assistantRangeStart(30);
  @State to: number = assistantRangeEnd();

  aboutToAppear(): void { this.period = this.kind === 'recent' ? '30' : 'all'; }
  private candidates(): Person[] {
    const query = this.personSearch.trim().toLocaleLowerCase();
    return this.people.filter((person: Person) => person.deletedAt === null && person.id !== this.selfId &&
      (person.name.toLocaleLowerCase().includes(query) || (person.description ?? '').toLocaleLowerCase().includes(query)));
  }
  private selectedName(): string { return this.people.find((person: Person) => person.id === this.personId)?.name ?? ''; }
  private title(): string {
    if (this.choosingPerson) { return '选择人物'; }
    return this.kind === 'together' ? '和谁一起回顾？' : this.kind === 'memory' ? '记得哪些片段？' : '想回顾多久？';
  }
  private periodLabel(): string {
    if (this.period === 'custom') { return assistantDate(this.from) + ' 至 ' + assistantDate(this.to); }
    return this.period === 'all' ? '不限' : this.period === 'year' ? '近一年' : '近' + this.period + '天';
  }
  private canStart(): boolean {
    return !this.choosingPerson && (this.kind !== 'together' || this.personId.length > 0) &&
      (this.kind !== 'memory' || this.clue.trim().length > 0) && (this.period !== 'custom' || this.from <= this.to);
  }
  private chooseDate(start: boolean): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(start ? this.from : this.to),
      onDateAccept: (date: Date) => {
        if (start) { date.setHours(0, 0, 0, 0); this.from = date.getTime(); }
        else { this.to = assistantRangeEnd(date.getTime()); }
      } });
  }
  private start(): void {
    let from: number | undefined = undefined; let to: number | undefined = undefined;
    if (this.period === 'custom') { from = this.from; to = this.to; }
    else if (this.period !== 'all') {
      to = assistantRangeEnd();
      if (this.period === 'year') { const date = new Date(); date.setFullYear(date.getFullYear() - 1); date.setHours(0, 0, 0, 0); from = date.getTime(); }
      else { from = assistantRangeStart(Number(this.period)); }
    }
    const request = assistantEntryRequest(this.kind, this.personId, this.selectedName(), this.clue, from, to);
    if (this.kind === 'together') { request.scope.withPersonId = this.selfId; }
    this.onStart(request);
  }

  @Builder
  personPicker() {
    Column({ space: 10 }) {
      TextInput({ text: this.personSearch, placeholder: '搜索人物' }).height(44).borderRadius(10)
        .fontColor(this.palette.text).placeholderColor(this.palette.muted).caretColor(this.palette.primary).backgroundColor(this.palette.card)
        .id('ai-entry-person-search').onChange((value: string) => { this.personSearch = value; })
      if (this.kind === 'memory') {
        Button('不限人物', { type: ButtonType.Normal }).width('100%').height(44).fontColor(this.palette.primary).backgroundColor(this.palette.soft)
          .onClick(() => { this.personId = ''; this.choosingPerson = false; this.personSearch = ''; })
      }
      if (this.candidates().length === 0) {
        Text(this.personSearch.trim().length > 0 ? '没有找到匹配的人物' : '还没有可选择的人物，可先到人物页添加。').fontSize(14).fontColor(this.palette.muted).padding({ top: 12, bottom: 12 })
      } else {
        List() {
          ForEach(this.candidates(), (person: Person) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(person.name.slice(0, 1)).fontSize(17).fontColor(this.palette.primary).width(38).height(38)
                  .textAlign(TextAlign.Center).backgroundColor(this.palette.soft).borderRadius(19)
                Column({ space: 3 }) {
                  Text(person.name).fontSize(16).fontColor(this.palette.text).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if ((person.description ?? '').length > 0) {
                    Text(person.description ?? '').fontSize(12).fontColor(this.palette.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }
                }.layoutWeight(1)
                Radio({ value: person.id, group: 'assistant-entry-person' }).checked(this.personId === person.id)
                  .radioStyle({ checkedBackgroundColor: this.palette.primary, uncheckedBorderColor: this.palette.muted, indicatorColor: this.palette.onPrimary })
                  .width(22).height(22).onChange((checked: boolean) => { if (checked) { this.personId = person.id; if (this.kind === 'memory') { this.choosingPerson = false; } } })
              }.height(58).width('100%').id('ai-entry-person-' + person.id).accessibilityText(person.name + (person.description ?? ''))
                .onClick(() => { this.personId = person.id; if (this.kind === 'memory') { this.choosingPerson = false; } })
            }
          }, (person: Person) => person.id)
        }.width('100%').height(Math.min(this.candidates().length, 3) * 58).divider({ strokeWidth: 1, color: this.palette.border })
      }
    }.width('100%')
  }

  @Builder
  timePicker() {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.kind !== 'recent') {
          Row() { ChoiceChip({ label: this.kind === 'together' ? '全部时间' : '不限时间', selected: this.period === 'all', palette: this.palette,
            onAction: () => { this.period = 'all'; } }) }.margin({ right: 8, bottom: 8 })
        }
        if (this.kind === 'together') {
          Row() { ChoiceChip({ label: '近一年', selected: this.period === 'year', palette: this.palette,
            onAction: () => { this.period = 'year'; } }) }.margin({ right: 8, bottom: 8 })
        } else {
          Row() { ChoiceChip({ label: '近30天', selected: this.period === '30', palette: this.palette,
            onAction: () => { this.period = '30'; } }) }.margin({ right: 8, bottom: 8 })
          Row() { ChoiceChip({ label: '近90天', selected: this.period === '90', palette: this.palette,
            onAction: () => { this.period = '90'; } }) }.margin({ right: 8, bottom: 8 })
        }
        Row() { ChoiceChip({ label: '自定义', selected: this.period === 'custom', palette: this.palette,
          onAction: () => { this.period = 'custom'; } }) }.margin({ bottom: 8 })
      }.width('100%')
      if (this.period === 'custom') {
        Row({ space: 10 }) {
          Button(assistantDate(this.from), { type: ButtonType.Normal }).layoutWeight(1).height(44).borderRadius(8)
            .fontSize(14).fontColor(this.palette.text).backgroundColor(this.palette.card).accessibilityText('开始日期').onClick(() => this.chooseDate(true))
          Text('至').fontSize(13).fontColor(this.palette.muted)
          Button(assistantDate(this.to), { type: ButtonType.Normal }).layoutWeight(1).height(44).borderRadius(8)
            .fontSize(14).fontColor(this.palette.text).backgroundColor(this.palette.card).accessibilityText('结束日期').onClick(() => this.chooseDate(false))
        }.width('100%')
        if (this.from > this.to) { Text('结束日期不能早于开始日期').fontSize(12).fontColor(this.palette.danger).width('100%') }
      }
    }.width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        if (this.choosingPerson) {
          Button('‹').fontSize(26).fontColor(this.palette.text).backgroundColor(Color.Transparent).width(36).height(44).padding(0)
            .accessibilityText('返回查找条件').onClick(() => { this.choosingPerson = false; })
        }
        Text(this.title()).fontSize(21).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1)
        Button('×').fontSize(27).fontColor(this.palette.muted).backgroundColor(Color.Transparent).width(44).height(44).padding(0)
          .accessibilityText('关闭').id('ai-entry-close').onClick(() => this.onClose())
      }.width('100%')
      if (this.kind === 'together' || this.choosingPerson) { this.personPicker() }
      if (!this.choosingPerson) {
        if (this.kind === 'memory') {
          TextArea({ text: this.clue, placeholder: '例如：杭州、聚餐，或记得的一句话' }).height(96).borderRadius(12).maxLength(1000)
            .fontSize(16).fontColor(this.palette.text).placeholderColor(this.palette.muted).caretColor(this.palette.primary).backgroundColor(this.palette.card)
            .id('ai-entry-clue').onChange((value: string) => { this.clue = value; })
          Flex({ wrap: FlexWrap.Wrap }) {
            Button('人物：' + (this.selectedName() || '不限'), { type: ButtonType.Normal }).height(40).borderRadius(20).fontSize(13)
              .fontColor(this.palette.text).backgroundColor(this.palette.soft).margin({ right: 8, bottom: 8 }).id('ai-entry-person-filter')
              .onClick(() => { this.choosingPerson = true; this.personSearch = ''; })
            Button('时间：' + this.periodLabel(), { type: ButtonType.Normal }).height(40).borderRadius(20).fontSize(13)
              .fontColor(this.palette.text).backgroundColor(this.palette.soft).id('ai-entry-time-filter')
              .onClick(() => { this.choosingTime = !this.choosingTime; })
          }.width('100%')
          if (this.choosingTime) { this.timePicker() }
          Text('不记得具体时间，也可以找。').fontSize(13).fontColor(this.palette.muted).width('100%')
        } else {
          if (this.kind === 'together') { Text('时间范围').fontSize(13).fontColor(this.palette.muted).width('100%') }
          this.timePicker()
          if (this.kind === 'recent') { Text('整理这段时间的人物与经历。').fontSize(14).fontColor(this.palette.muted).width('100%') }
        }
        Button(this.kind === 'together' ? '开始回顾' : this.kind === 'memory' ? '查找记录' : '生成回顾', { type: ButtonType.Normal })
          .height(48).width('100%').borderRadius(12).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.canStart() ? this.palette.onPrimary : this.palette.muted).backgroundColor(this.canStart() ? this.palette.primary : this.palette.soft)
          .enabled(this.canStart()).id('ai-entry-start').onClick(() => this.start())
      }
    }.padding({ left: 24, right: 24, top: 4, bottom: 24 }).width('100%').backgroundColor(this.palette.paper)
  }
}
