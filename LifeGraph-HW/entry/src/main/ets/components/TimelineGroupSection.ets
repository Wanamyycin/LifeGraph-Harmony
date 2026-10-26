import { EventCard, NamedItem, Palette } from '../domain/Models';
import { Person } from '../domain/Person';
import { TimelineEventGroup } from '../features/EventQuery';
import { TimelineEventCard } from './TimelineEventCard';

@Component
export struct TimelineGroupSection {
  @Prop group: TimelineEventGroup = new TimelineEventGroup();
  @Prop palette: Palette = new Palette();
  @Prop people: Person[] = [];
  @Prop branches: NamedItem[] = [];
  @Prop emotions: NamedItem[] = [];
  @Prop expanded: boolean = true;
  @Prop expandedEventIds: string[] = [];
  @Prop disabled: boolean = false;
  onToggleGroup: (key: string) => void = () => {};
  onToggleEvent: (id: string) => void = () => {};
  onOpenEvent: (id: string) => void = () => {};

  private peopleLabel(card: EventCard): string {
    return card.personIds.map((id: string) => {
      const person = this.people.find((candidate: Person) => candidate.id === id);
      return person === undefined ? '已删除的人物' : person.name + (person.deletedAt !== null ? '（已隐藏）' : '');
    }).join('、');
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Row() {}.width(25).height(1).backgroundColor(this.palette.border)
          Row() {}.width(15).height(15).borderRadius(8).backgroundColor(this.palette.primary)
            .border({ width: 3, color: this.palette.paper }).margin({ left: 15 })
        }.width(34).height(38)
        Button({ type: ButtonType.Normal }) {
          Row({ space: 7 }) {
            Text(this.group.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.primary).layoutWeight(1)
            Text(this.group.events.length.toString() + ' 件').fontSize(10).fontColor(this.palette.muted)
            Text(this.expanded ? '⌃' : '⌄').fontSize(17).fontColor(this.palette.muted).width(18).textAlign(TextAlign.Center)
          }.width('100%')
        }.layoutWeight(1).height(38).padding({ left: 4, right: 5 }).borderRadius(0)
          .backgroundColor(Color.Transparent).enabled(!this.disabled)
          .accessibilityText(this.group.label + '，' + this.group.events.length + '件，' + (this.expanded ? '已展开' : '已折叠'))
          .id('timeline-group-' + this.group.key).onClick(() => this.onToggleGroup(this.group.key))
      }.width('100%')
      if (this.expanded) {
        Column({ space: 2 }) {
          ForEach(this.group.events, (card: EventCard) => {
            TimelineEventCard({ card: card, palette: this.palette, peopleLabel: this.peopleLabel(card), branches: this.branches,
              emotions: this.emotions, expanded: this.expandedEventIds.includes(card.event.id), disabled: this.disabled,
              onToggle: (id: string) => this.onToggleEvent(id), onOpen: (id: string) => this.onOpenEvent(id) })
          }, (card: EventCard) => card.event.id + ':' + card.event.updatedAt)
        }.width('100%')
      }
    }.width('100%').padding({ bottom: 4 }).border({ width: { left: 8 }, color: this.expanded ? this.palette.primary : this.palette.soft })
  }
}
