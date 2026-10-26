import { AssistantReference, AssistantTurn, referenceUrl } from '../domain/Assistant';
import { Palette } from '../domain/Models';
import { MarkdownText } from './MarkdownText';

@Component
export struct AssistantBubble {
  @Prop turn: AssistantTurn = new AssistantTurn();
  @Prop palette: Palette = new Palette();
  @State expanded: boolean = false;
  @State sourcesExpanded: boolean = false;
  onCopy: (text: string) => void = () => {};
  onRetry: (text: string) => void = () => {};
  onLink: (url: string, refs: AssistantReference[]) => void = () => {};

  private visibleContextNote(): string {
    return this.turn.contextNote.replace('；分页列表可能尚未读完，完整数量以统计结果为准。', '。')
      .replace('分页列表可能尚未读完，完整数量以统计结果为准。', '').trim();
  }

  build() {
    Column({ space: 6 }) {
      Column({ space: 10 }) {
        Row() {
          Text(this.turn.user ? '我' : '助手').fontSize(12).fontColor(this.palette.primary).layoutWeight(1)
          Button('复制').fontSize(12).height(28).padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent).fontColor(this.palette.muted)
            .id('ai-copy-' + this.turn.id).onClick(() => this.onCopy(this.turn.text))
        }.width('100%')
        if (this.turn.user) {
          Text(this.turn.text).fontSize(16).fontColor(this.palette.text).lineHeight(25).width('100%').copyOption(CopyOptions.LocalDevice)
          if (this.turn.status === 'failed' || this.turn.status === 'canceled') {
            Row() {
              Text(this.turn.status === 'canceled' ? '已停止' : '本次未完成').fontSize(12).fontColor(this.palette.muted).layoutWeight(1)
              Button('重新填写').fontSize(12).height(30).fontColor(this.palette.primary).backgroundColor(this.palette.card).onClick(() => this.onRetry(this.turn.text))
            }.width('100%')
          }
        } else {
          MarkdownText({ content: !this.expanded && this.turn.text.length > 1800 ? this.turn.text.slice(0, 1800) + '\n\n…' : this.turn.text,
            palette: this.palette, onLink: (url: string) => this.onLink(url, this.turn.references) })
          if (this.turn.text.length > 1800) {
            Button(this.expanded ? '收起回复' : '展开完整回复').fontSize(13).fontColor(this.palette.primary).backgroundColor(Color.Transparent)
              .onClick(() => { this.expanded = !this.expanded; })
          }
          if (this.turn.references.length > 0) {
            Divider().color(this.palette.border)
            Text('本次查询记录').fontSize(12).fontColor(this.palette.muted).width('100%')
            ForEach(this.sourcesExpanded ? this.turn.references : this.turn.references.slice(0, 5), (reference: AssistantReference) => {
              Row({ space: 8 }) {
                Text(reference.kind === 'event' ? '事件' : reference.kind === 'person' ? '人物' : '说明').fontSize(11).fontColor(this.palette.primary)
                Text((reference.kind === 'event' ? new Date(reference.occurredAt).toLocaleDateString() + ' · ' : '') + reference.title)
                  .fontSize(13).fontColor(this.palette.text).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('›').fontSize(18).fontColor(this.palette.muted)
              }.width('100%').padding({ top: 6, bottom: 6 }).onClick(() => this.onLink(referenceUrl(reference), this.turn.references))
            }, (reference: AssistantReference) => referenceUrl(reference))
            if (this.turn.references.length > 5) {
              Button(this.sourcesExpanded ? '收起来源' : '查看全部来源（' + this.turn.references.length.toString() + '）').fontSize(12).backgroundColor(Color.Transparent)
                .fontColor(this.palette.primary).onClick(() => { this.sourcesExpanded = !this.sourcesExpanded; })
            }
          }
          if (this.turn.readAt > 0) { Text('记录查询于 ' + new Date(this.turn.readAt).toLocaleString()).fontSize(11).fontColor(this.palette.muted).width('100%') }
          if (this.visibleContextNote().length > 0) { Text(this.visibleContextNote()).fontSize(11).fontColor(this.palette.muted).width('100%') }
        }
      }.alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 12, bottom: 16 })
        .width(this.turn.user ? '88%' : '100%').backgroundColor(this.turn.user ? this.palette.soft : this.palette.card).borderRadius(14)
      if (!this.turn.user) {
        Text('回答以记录为依据，关系建议仅供参考').fontSize(11).fontColor(this.palette.muted).maxLines(1).width('100%')
      }
    }.width('100%').alignItems(this.turn.user ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}
