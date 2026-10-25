import { Palette } from '../domain/Models';

@Component
export struct ActionButton {
  @Prop label: string = '';
  @Prop palette: Palette = new Palette();
  @Prop isEnabled: boolean = true;
  onAction: () => void = () => {};
  build() {
    Button(this.label, { type: ButtonType.Normal }).height(48).width('100%').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.onPrimary).borderRadius(10)
      .backgroundColor(this.palette.primary).enabled(this.isEnabled).onClick(() => this.onAction())
  }
}
