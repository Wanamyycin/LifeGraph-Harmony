import { Person } from '../domain/Person';
import { NamedItem, Palette } from '../domain/Models';
import { RelationEditorItem } from './RelationEditorItem';

@Component
export struct RelationEditorRow {
  @ObjectLink item: RelationEditorItem;
  @Prop people: Person[] = [];
  @Prop relations: NamedItem[] = [];
  @Prop palette: Palette = new Palette();
  @Prop disabled: boolean = false;
  onRemove: (rowId: string) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Select(this.people.map((person: Person): SelectOption => ({ value: person.name + (person.deletedAt !== null ? '（已隐藏）' : '') })))
          .selected(this.people.findIndex((person: Person) => person.id === this.item.targetPersonId))
          .value(this.targetLabel())
          .layoutWeight(1).id(this.item.rowId + '-target')
          .onSelect((selected: number) => {
            if (this.people[selected] !== undefined) { this.item.targetPersonId = this.people[selected].id; }
          })
        Select(this.relations.map((relation: NamedItem): SelectOption => ({ value: relation.name })))
          .selected(this.relations.findIndex((relation: NamedItem) => relation.id === this.item.relationId))
          .value(this.relations.find((relation: NamedItem) => relation.id === this.item.relationId)?.name ?? '请选择类型')
          .id(this.item.rowId + '-kind')
          .onSelect((selected: number) => {
            if (this.relations[selected] !== undefined) { this.item.relationId = this.relations[selected].id; }
          })
        Button('移除').fontSize(12).fontColor(this.palette.danger).backgroundColor(Color.Transparent)
          .id(this.item.rowId + '-remove').onClick(() => this.onRemove(this.item.rowId))
      }.width('100%')
      Row({ space: 12 }) {
        Text('关系强度 ' + (this.item.strength ?? 3)).fontSize(13).fontColor(this.palette.muted)
          .id(this.item.rowId + '-value')
        Slider({ value: this.item.strength ?? 3, min: 1, max: 5, step: 1 }).layoutWeight(1).selectedColor(this.palette.primary)
          .id(this.item.rowId + '-strength').onChange((value: number) => { this.item.strength = Math.round(value); })
      }
    }.padding(12).width('100%').backgroundColor(this.palette.card).borderRadius(14).enabled(!this.disabled)
  }

  private targetLabel(): string {
    const person = this.people.find((candidate: Person) => candidate.id === this.item.targetPersonId);
    return person === undefined ? '请选择人物' : person.name + (person.deletedAt !== null ? '（已隐藏）' : '');
  }
}
