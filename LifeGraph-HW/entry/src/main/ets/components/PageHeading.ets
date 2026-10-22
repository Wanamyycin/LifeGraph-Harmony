import { Palette } from '../domain/Models';

@Component
export struct PageHeading {
  @Prop title: string = '';
  @Prop palette: Palette = new Palette();
  @Prop showBack: boolean = false;
  @Prop showAdd: boolean = false;
  @Prop showSearch: boolean = false;
  @Prop disabled: boolean = false;
  onBackAction: () => void = () => {};
  onAddAction: () => void = () => {};
  onSearchAction: () => void = () => {};
  build() {
    Row({ space: 12 }) {
      if (this.showBack) {
        Button('‹').fontSize(30).width(40).height(42).padding(0).backgroundColor(Color.Transparent).fontColor(this.palette.text)
          .accessibilityText('返回').id('nav-back').onClick(() => this.onBackAction())
      }
      Text(this.title).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.palette.text).layoutWeight(1).id('page-title')
      if (this.showSearch) {
        Button('搜索').fontSize(14).fontColor(this.palette.primary).backgroundColor(this.palette.soft)
          .id('nav-search').onClick(() => this.onSearchAction())
      }
      if (this.showAdd) {
        Button('＋').fontSize(25).fontColor(this.palette.primary).backgroundColor(this.palette.soft).width(42).height(42).padding(0)
          .accessibilityText('新建').id('nav-add').onClick(() => this.onAddAction())
      }
    }.width('100%').enabled(!this.disabled)
  }
}
