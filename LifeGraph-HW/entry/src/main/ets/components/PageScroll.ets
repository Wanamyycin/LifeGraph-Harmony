import { ColorMetrics } from '@kit.ArkUI';

// Page content keeps its existing width; only the scrollbar moves into the outer gutter.
const SCROLLBAR_WIDTH: number = 3;
const SCROLLBAR_OUTSET: number = 10;
const SCROLLBAR_OPACITY: number = 0.2;

@Component
struct PageScrollBar {
  scroller: Scroller = new Scroller();
  @Prop tint: string = '#69776F';

  private sliderColor(): ColorMetrics {
    try {
      const color = ColorMetrics.resourceColor(this.tint);
      return ColorMetrics.rgba(color.red, color.green, color.blue, SCROLLBAR_OPACITY);
    } catch (_) {
      return ColorMetrics.rgba(105, 119, 111, SCROLLBAR_OPACITY);
    }
  }

  build() {
    ScrollBar({ scroller: this.scroller, direction: ScrollBarDirection.Vertical, state: BarState.Auto })
      .width(SCROLLBAR_WIDTH)
      .height('100%')
      .scrollBarColor(this.sliderColor())
  }
}

@Component
export struct PageScroll {
  @Prop tint: string = '#69776F';
  @Prop barOutset: number = SCROLLBAR_OUTSET;
  @BuilderParam content: () => void = this.emptyContent;
  private scroller: Scroller = new Scroller();

  @Builder
  emptyContent() {}

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        this.content()
      }.width('100%').height('100%').scrollBar(BarState.Off)
      PageScrollBar({ scroller: this.scroller, tint: this.tint })
        .position({ right: -this.barOutset, top: 0 })
    }.width('100%').height('100%').layoutWeight(1).clip(false)
  }
}

@Component
export struct PageList {
  scroller: Scroller = new Scroller();
  @Prop tint: string = '#69776F';
  @Prop space: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop barOutset: number = SCROLLBAR_OUTSET;
  @Prop divider: ListDividerOptions | null = null;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: this.space, scroller: this.scroller }) {
        this.content()
      }.width('100%').height('100%').scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring).divider(this.divider)
      PageScrollBar({ scroller: this.scroller, tint: this.tint })
        .position({ right: -this.barOutset, top: 0 })
    }.width('100%').height(this.viewportHeight > 0 ? this.viewportHeight : '100%')
      .layoutWeight(this.viewportHeight > 0 ? 0 : 1).clip(false)
  }
}
