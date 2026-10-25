import { Palette } from '../domain/Models';

@Component
export struct MainTabButton {
  label: string = '';
  controlId: string = '';
  icon: Resource = $r('app.media.nav_graph');
  @Prop selected: boolean = false;
  @Prop disabled: boolean = false;
  @Prop palette: Palette = new Palette();
  onAction: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        Image(this.icon).width(22).height(22).fillColor(this.selected ? this.palette.primary : this.palette.muted)
        Text(this.label).fontSize(11).fontColor(this.selected ? this.palette.primary : this.palette.muted)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    }.width('100%').height(58).padding(0).backgroundColor(Color.Transparent).borderRadius(8)
      .id(this.controlId).accessibilityText(this.label).accessibilitySelected(this.selected)
      .enabled(!this.disabled).onClick(() => this.onAction())
  }
}
