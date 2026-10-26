import { Palette } from '../domain/Models';

@Component
export struct PageHeading {
  @Prop title: string = '';
  @Prop palette: Palette = new Palette();
  @Prop showBack: boolean = false;
  @Prop showAdd: boolean = false;
  @Prop showSearch: boolean = false;
  @Prop showProfile: boolean = false;
  @Prop disabled: boolean = false;
  onBackAction: () => void = () => {};
  onAddAction: () => void = () => {};
  onSearchAction: () => void = () => {};
  onProfileAction: () => void = () => {};
  build() {
    Row({ space: 4 }) {
      if (this.showBack) {
        Button('‹').fontSize(26).width(40).height(40).padding(0).backgroundColor(Color.Transparent).fontColor(this.palette.text)
          .accessibilityText('返回').id('nav-back').onClick(() => this.onBackAction())
      }
      Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1).id('page-title')
      if (this.showSearch) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.nav_search')).width(18).height(18).fillColor(this.palette.muted)
        }.width(40).height(40).padding(11).backgroundColor(Color.Transparent)
          .id('nav-search').accessibilityText('搜索').onClick(() => this.onSearchAction())
      }
      if (this.showAdd) {
        Button('＋', { type: ButtonType.Normal }).fontSize(22).fontColor(this.palette.primary).backgroundColor(Color.Transparent).width(40).height(40).padding(0)
          .accessibilityText('新建').id('nav-add').onClick(() => this.onAddAction())
      }
      if (this.showProfile) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Circle().width(3).height(3).fill(this.palette.text)
            Circle().width(3).height(3).fill(this.palette.text)
            Circle().width(3).height(3).fill(this.palette.text)
          }
        }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
          .id('nav-profile').accessibilityText('更多：我的资料与设置').onClick(() => this.onProfileAction())
      }
    }.width('100%').height(40).enabled(!this.disabled)
  }
}
