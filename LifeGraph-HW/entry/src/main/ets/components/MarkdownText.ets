import { Palette } from '../domain/Models';
import { MarkdownBlock, MarkdownPart, parseMarkdown } from '../features/Markdown';

@Component
export struct MarkdownText {
  @Prop @Watch('changed') content: string = '';
  @Prop palette: Palette = new Palette();
  @State blocks: MarkdownBlock[] = [];
  aboutToAppear(): void { this.changed(); }
  private changed(): void { this.blocks = parseMarkdown(this.content); }

  build() {
    Column({ space: 5 }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        if (block.code) {
          Text(block.text).fontSize(14).fontFamily('monospace').fontColor(this.palette.text).lineHeight(22)
            .padding(12).backgroundColor(this.palette.soft).borderRadius(10).width('100%').copyOption(CopyOptions.LocalDevice)
        } else {
          Text() {
            ForEach(block.parts, (part: MarkdownPart) => {
              Span(part.text).fontWeight(part.bold || block.heading > 0 ? FontWeight.Bold : FontWeight.Normal)
                .fontFamily(part.code ? 'monospace' : 'sans-serif').fontColor(part.code ? this.palette.primary : this.palette.text)
            })
          }.fontSize(block.heading > 0 ? Math.max(17, 25 - block.heading * 2) : 16).lineHeight(26)
            .width('100%').copyOption(CopyOptions.LocalDevice)
        }
      })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
