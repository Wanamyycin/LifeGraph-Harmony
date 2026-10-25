import { Palette } from '../domain/Models';
import { MarkdownPart } from '../features/Markdown';

@Component
export struct MarkdownInline {
  @Prop parts: MarkdownPart[] = [];
  @Prop palette: Palette = new Palette();
  @Prop heading: number = 0;
  @Prop strong: boolean = false;
  onLink: (url: string) => void = () => {};
  build() {
    Text() {
      ForEach(this.parts, (part: MarkdownPart) => {
        Span(part.text).fontWeight(part.bold || this.heading > 0 || this.strong ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(part.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(part.code ? 'monospace' : 'sans-serif')
          .fontColor(part.code || part.href.length > 0 ? this.palette.primary : this.palette.text)
          .decoration({ type: part.href.length > 0 ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => { if (part.href.length > 0) { this.onLink(part.href); } })
      })
    }.fontSize(this.heading > 0 ? Math.max(17, 25 - this.heading * 2) : 16).lineHeight(26)
      .width('100%').copyOption(CopyOptions.LocalDevice)
  }
}
