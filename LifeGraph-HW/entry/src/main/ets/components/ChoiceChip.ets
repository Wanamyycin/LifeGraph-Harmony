import { Palette } from '../domain/Models';

// Props are evaluated in the parent's observed render scope, including inside
// keyed ForEach rows. A value parameter captured by @Builder cannot do this.
@Component
export struct ChoiceChip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop palette: Palette = new Palette();
  @Prop disabled: boolean = false;
  @Prop controlId: string = '';
  onAction: () => void = () => {};

  build() {
    Button(this.selected ? '✓ ' + this.label : this.label).fontSize(13)
      .fontColor(this.selected ? Color.White : this.palette.text)
      .backgroundColor(this.selected ? this.palette.primary : this.palette.soft).height(36)
      .accessibilitySelected(this.selected).accessibilityChecked(this.selected)
      .id(this.controlId || 'choice-' + this.label).enabled(!this.disabled)
      .onClick(() => this.onAction())
  }
}
