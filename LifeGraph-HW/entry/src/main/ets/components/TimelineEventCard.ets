import { EventCard, NamedItem, Palette } from '../domain/Models';
import { eventDayLabel, eventWeekdayLabel } from '../features/EventQuery';

@Component
export struct TimelineEventCard {
  card: EventCard = new EventCard();
  @Prop palette: Palette = new Palette();
  @Prop peopleLabel: string = '';
  @Prop branches: NamedItem[] = [];
  @Prop emotions: NamedItem[] = [];
  @Prop expanded: boolean = false;
  @Prop disabled: boolean = false;
  onToggle: (id: string) => void = () => {};
  onOpen: (id: string) => void = () => {};

  private namedLabel(items: NamedItem[], ids: string[]): string {
    return items.filter((item: NamedItem) => ids.includes(item.id)).map((item: NamedItem) => item.name).join(' · ');
  }

  build() {
    Row({ space: 6 }) {
      Column({ space: 2 }) {
        Text(eventDayLabel(this.card.event.occurredAt)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette.primary)
        Text(eventWeekdayLabel(this.card.event.occurredAt)).fontSize(10).fontColor(this.palette.muted)
      }.width(30).alignItems(HorizontalAlign.Start).padding({ top: 9 })
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {}.width(22).height(1).backgroundColor(this.palette.border).margin({ top: 20 })
        Row() {}.width(9).height(9).borderRadius(5).backgroundColor(this.palette.primary)
          .border({ width: 2, color: this.palette.paper }).margin({ left: 17, top: 16 })
      }.width(26).height(40)
      Column({ space: 7 }) {
        Row({ space: 7 }) {
          Column({ space: 5 }) {
            Text(this.card.event.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
              .width('100%').maxLines(this.expanded ? 4 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 5 }) {
              Text('人物').fontSize(10).fontColor(this.palette.primary)
              Text(this.peopleLabel || '我').fontSize(11).fontColor(this.palette.muted).layoutWeight(1)
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text(this.expanded ? '⌃' : '⌄').fontSize(17).fontColor(this.palette.muted).width(18).textAlign(TextAlign.Center)
        }.width('100%').alignItems(VerticalAlign.Top).onClick(() => this.onToggle(this.card.event.id))
          .accessibilityText(this.card.event.title + '，' + this.peopleLabel + (this.expanded ? '，已展开' : '，已折叠'))
        if (this.expanded) {
          if (this.card.event.content.length > 0) {
            Text(this.card.event.content).fontSize(13).lineHeight(20).fontColor(this.palette.muted).width('100%')
          }
          if (this.card.event.locationText.length > 0) {
            Text('地点 · ' + this.card.event.locationText).fontSize(11).fontColor(this.palette.muted).width('100%')
          }
          Row({ space: 7 }) {
            if (this.namedLabel(this.branches, this.card.branchIds).length > 0) {
              Text(this.namedLabel(this.branches, this.card.branchIds)).fontSize(10).fontColor(this.palette.primary)
                .padding({ left: 7, right: 7, top: 4, bottom: 4 }).backgroundColor(this.palette.soft).borderRadius(7)
            }
            if (this.namedLabel(this.emotions, this.card.emotionIds).length > 0) {
              Text(this.namedLabel(this.emotions, this.card.emotionIds)).fontSize(10).fontColor(this.palette.primary)
                .padding({ left: 7, right: 7, top: 4, bottom: 4 }).backgroundColor(this.palette.soft).borderRadius(7)
            }
            if (this.card.assets.length > 0) {
              Text('附件 ' + this.card.assets.length).fontSize(10).fontColor(this.palette.muted)
                .padding({ left: 7, right: 7, top: 4, bottom: 4 }).backgroundColor(this.palette.paper).borderRadius(7)
            }
          }.width('100%')
          Button('查看完整记录  ›', { type: ButtonType.Normal }).fontSize(11).fontColor(this.palette.primary)
            .backgroundColor(Color.Transparent).padding(0).alignSelf(ItemAlign.End).enabled(!this.disabled)
            .onClick(() => this.onOpen(this.card.event.id))
        }
      }.layoutWeight(1).padding({ left: 11, right: 9, top: 9, bottom: 9 }).borderRadius(10)
        .backgroundColor(this.palette.card).alignItems(HorizontalAlign.Start).enabled(!this.disabled)
    }.width('100%')
      .padding({ left: 8 })
      .alignItems(VerticalAlign.Top)
  }
}
