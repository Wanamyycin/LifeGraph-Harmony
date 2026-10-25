import { Palette } from '../domain/Models';

@Component
export struct FilterTab {
  label: string = '';
  controlId: string = '';
  @Prop selected: boolean = false;
  @Prop disabled: boolean = false;
  @Prop palette: Palette = new Palette();
  onAction: () => void = () => {};

  build() {
    Button(this.label, { type: ButtonType.Normal }).fontSize(13).height(36).padding({ left: 3, right: 3 })
      .fontColor(this.selected ? this.palette.primary : this.palette.muted)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .backgroundColor(Color.Transparent).borderRadius(0)
      .border({ width: { bottom: 2 }, color: this.selected ? this.palette.primary : Color.Transparent })
      .accessibilitySelected(this.selected).accessibilityChecked(this.selected)
      .id(this.controlId).enabled(!this.disabled).onClick(() => this.onAction())
  }
}
