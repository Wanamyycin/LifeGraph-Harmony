import { Palette } from '../domain/Models';

@Component
export struct PageHeading {
  @Prop title: string = '';
  @Prop palette: Palette = new Palette();
  @Prop showBack: boolean = false;
  @Prop showAdd: boolean = false;
  @Prop showSearch: boolean = false;
  @Prop showProfile: boolean = false;
  @Prop avatarUri: string = '';
  @Prop disabled: boolean = false;
  onBackAction: () => void = () => {};
  onAddAction: () => void = () => {};
  onSearchAction: () => void = () => {};
  onProfileAction: () => void = () => {};
  build() {
    Row({ space: 12 }) {
      if (this.showBack) {
        Button('‹').fontSize(30).width(40).height(42).padding(0).backgroundColor(Color.Transparent).fontColor(this.palette.text)
          .accessibilityText('返回').id('nav-back').onClick(() => this.onBackAction())
      }
      Text(this.title).fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1).id('page-title')
      if (this.showSearch) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.nav_search')).width(20).height(20).fillColor(this.palette.muted)
        }.width(40).height(44).padding(10).backgroundColor(Color.Transparent)
          .id('nav-search').accessibilityText('搜索').onClick(() => this.onSearchAction())
      }
      if (this.showAdd) {
        Button('＋', { type: ButtonType.Normal }).fontSize(25).fontColor(this.palette.onPrimary).backgroundColor(this.palette.primary).width(42).height(42).padding(0).borderRadius(10)
          .accessibilityText('新建').id('nav-add').onClick(() => this.onAddAction())
      }
      if (this.showProfile) {
        Button({ type: ButtonType.Circle }) {
          if (this.avatarUri.length > 0) { Image(this.avatarUri).width(48).height(48).objectFit(ImageFit.Cover) }
          else { Text('我').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.palette.primary) }
        }.width(48).height(48).padding(0).backgroundColor(this.palette.soft).clip(true)
          .id('nav-profile').accessibilityText('我的资料与设置').onClick(() => this.onProfileAction())
      }
    }.width('100%').enabled(!this.disabled)
  }
}
