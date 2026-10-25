import { Palette } from '../domain/Models';
import { MarkdownBlock, MarkdownPart, MarkdownRow, parseMarkdown } from '../features/Markdown';
import { MarkdownInline } from './MarkdownInline';

@Component
export struct MarkdownText {
  @Prop @Watch('changed') content: string = '';
  @Prop palette: Palette = new Palette();
  @State blocks: MarkdownBlock[] = [];
  onLink: (url: string) => void = () => {};
  aboutToAppear(): void { this.changed(); }
  private changed(): void { this.blocks = parseMarkdown(this.content); }

  build() {
    Column({ space: 5 }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        if (block.code) {
          Text(block.text).fontSize(14).fontFamily('monospace').fontColor(this.palette.text).lineHeight(22)
            .padding(12).backgroundColor(this.palette.soft).borderRadius(10).width('100%').copyOption(CopyOptions.LocalDevice)
        } else if (block.rows.length > 0) {
          Scroll() {
            Column() {
              ForEach(block.rows, (row: MarkdownRow, index: number) => {
                Row() {
                  ForEach(row.cells, (cell: MarkdownPart[]) => {
                    Column() {
                      MarkdownInline({ parts: cell, palette: this.palette, strong: index === 0, onLink: this.onLink })
                    }.width(160).padding(10).border({ width: 0.5, color: this.palette.border })
                  })
                }.backgroundColor(index === 0 ? this.palette.soft : this.palette.card)
              })
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
        } else if (block.rule) {
          Divider().color(this.palette.border).margin({ top: 8, bottom: 8 })
        } else if (block.text.length === 0) {
          Blank().height(5)
        } else {
          Column() {
            MarkdownInline({ parts: block.parts, palette: this.palette, heading: block.heading, onLink: this.onLink })
          }.width('100%').padding({ left: block.quote ? 12 : block.indent * 12, top: block.quote ? 5 : 0, bottom: block.quote ? 5 : 0 })
            .border({ width: { left: block.quote ? 3 : 0 }, color: this.palette.primary })
        }
      })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
