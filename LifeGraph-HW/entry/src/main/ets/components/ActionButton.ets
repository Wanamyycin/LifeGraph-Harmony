import { Palette } from '../domain/Models';

@Component
export struct ActionButton {
  @Prop label: string = '';
  @Prop palette: Palette = new Palette();
  @Prop isEnabled: boolean = true;
  onAction: () => void = () => {};
  build() {
    Button(this.label).height(50).width('100%').fontSize(16).fontColor(Color.White)
      .backgroundColor(this.palette.primary).enabled(this.isEnabled).onClick(() => this.onAction())
  }
}
