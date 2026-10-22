import { RelationInput } from '../domain/Models';

let nextRowId: number = 0;

// Keep one observed object per row. UI callbacks always read this live object;
// changing one field must never restore the other fields from an old snapshot.
@Observed
export class RelationEditorItem {
  readonly rowId: string;
  targetPersonId: string;
  relationId: string;
  strength: number | null;

  constructor(input: RelationInput) {
    this.rowId = 'relation-row-' + (++nextRowId).toString();
    this.targetPersonId = input.targetPersonId;
    this.relationId = input.relationId;
    this.strength = input.strength;
  }

  toInput(): RelationInput {
    const input = new RelationInput(); input.targetPersonId = this.targetPersonId;
    input.relationId = this.relationId; input.strength = this.strength; return input;
  }
}
