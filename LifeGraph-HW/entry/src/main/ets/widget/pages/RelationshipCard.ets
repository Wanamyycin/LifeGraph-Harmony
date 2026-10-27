import { DesktopCardNode, DesktopCardLink } from '../../features/DesktopCard';

const storage = new LocalStorage();

@Entry(storage)
@Component
struct RelationshipCard {
  @LocalStorageProp('nodes') nodes: DesktopCardNode[] = [];
  @LocalStorageProp('links') @Watch('drawLinks') links: DesktopCardLink[] = [];
  @LocalStorageProp('appearance') appearance: string = 'system';
  @LocalStorageProp('empty') empty: string = '在设置中选几位重要的人';
  private drawing: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private drawingReady: boolean = false;

  private drawLinks(): void {
    if (!this.drawingReady) { return; }
    const width = this.drawing.width; const height = this.drawing.height;
    this.drawing.clearRect(0, 0, width, height);
    this.drawing.globalAlpha = 0.65;
    for (const link of this.links) {
      this.drawing.beginPath(); this.drawing.strokeStyle = link.color; this.drawing.lineWidth = link.width * 0.7;
      this.drawing.moveTo(width * link.x1 / 100, height * link.y1 / 100);
      this.drawing.lineTo(width * link.x2 / 100, height * link.y2 / 100); this.drawing.stroke();
    }
  }

  private paper(): ResourceColor {
    return this.appearance === 'dark' ? '#222D27' : (this.appearance === 'light' ? '#FCFDFB' : $r('app.color.card_paper'));
  }
  private ink(): ResourceColor {
    return this.appearance === 'dark' ? '#E6ECE2' : (this.appearance === 'light' ? '#243B32' : $r('app.color.card_ink'));
  }
  private muted(): ResourceColor {
    return this.appearance === 'dark' ? '#A4B1A5' : (this.appearance === 'light' ? '#69776F' : $r('app.color.card_muted'));
  }
  private route(action: string, id: string = ''): void {
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { cardAction: action, cardPersonId: id } });
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('关系微图').fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1)
        Text('⋯').fontSize(20).fontColor(this.muted()).width(24).height(22).textAlign(TextAlign.Center)
          .accessibilityText('设置卡片人物').onClick(() => this.route('settings'))
      }.width('100%').height(22)
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.drawing).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
          .onReady(() => { this.drawingReady = true; this.drawLinks(); })
        ForEach(this.nodes, (node: DesktopCardNode) => {
          Stack() {
            Stack() {}.backgroundColor(node.color).width(node.x === 50 && node.y === 50 ? 24 : 20)
              .height(node.x === 50 && node.y === 50 ? 24 : 20).borderRadius(12)
            Text(node.shortLabel || node.label.slice(0, 1)).fontSize(8).fontWeight(FontWeight.Medium).fontColor('#15261C')
              .maxLines(1).textAlign(TextAlign.Center)
          }.width(28).height(28).position({ x: node.x.toString() + '%', y: node.y.toString() + '%' })
            .translate({ x: -14, y: -14 }).accessibilityText(node.label)
            .onClick(() => this.route(node.x === 50 && node.y === 50 ? 'settings' : 'person', node.id))
        }, (node: DesktopCardNode) => JSON.stringify(node))
        if (this.nodes.length <= 1) {
          Text('点右上角选择人物').fontSize(9).fontColor(this.muted()).width('100%').textAlign(TextAlign.Center)
            .position({ x: 0, y: '78%' })
        }
      }.width('100%').layoutWeight(1).margin({ top: 2, bottom: 4 })
      Button('+ 记一件事').fontSize(10).width('100%').height(26).borderRadius(8)
        .backgroundColor(this.ink()).fontColor(this.paper()).onClick(() => this.route('record'))
    }.width('100%').height('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.paper())
  }
}
