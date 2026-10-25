import { webview } from '@kit.ArkWeb';
import { Palette } from '../domain/Models';

class GraphMessage {
  type: string = '';
  id: string = '';
}

class GraphBridge {
  callback: ((message: string) => void) | null = null;
  postMessage(message: string): void { if (this.callback !== null) { this.callback(message); } }
}

@Component
export struct NativeGraph {
  @Prop @Watch('dataChanged') payload: string = '';
  @Prop @Watch('themeChanged') theme: string = 'forest-light';
  @Prop paperColor: string = '#FCFDFB';
  @Prop palette: Palette = new Palette();
  onPerson: (id: string) => void = () => {};
  onEvent: (id: string) => void = () => {};
  onBranch: (id: string) => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: GraphBridge = new GraphBridge();
  private loaded: boolean = false;
  private active: boolean = false;
  @State error: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.bridge.callback = (message: string): void => {
      if (!this.active || message.length > 2048) { return; }
      try {
        const parsed = JSON.parse(message) as GraphMessage;
        if (parsed.type === 'ready') { this.loaded = true; this.dataChanged(); }
        else if (typeof parsed.id === 'string' && parsed.id.length <= 160) {
          if (parsed.type === 'person') { this.onPerson(parsed.id); }
          if (parsed.type === 'event') { this.onEvent(parsed.id); }
          if (parsed.type === 'branch') { this.onBranch(parsed.id.replace(/^branch:/, '')); }
        }
      } catch (_) { /* Ignore messages outside the graph protocol. */ }
    };
  }

  aboutToDisappear(): void { this.active = false; this.loaded = false; this.bridge.callback = null; }

  private dataChanged(): void {
    if (this.payload.length > 0) { this.send(this.payload); }
  }

  private themeChanged(): void {
    if (!this.active) { return; }
    this.loaded = false;
    try { this.controller.loadUrl($rawfile('graph/' + this.theme + '.html')); }
    catch (_) { this.error = '主题切换未完成，请重新加载图谱'; }
  }

  private send(message: string): void {
    if (!this.active || !this.loaded) { return; }
    const script = 'document.dispatchEvent(new MessageEvent("message",{data:' + JSON.stringify(message) + '}));';
    try {
      this.controller.runJavaScript(script).catch((error: Error) => { if (this.active) { this.error = '图谱数据未能送达，请重试'; } });
    } catch (_) { this.error = '图谱尚未就绪，请重试'; }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Web({ src: $rawfile('graph/' + this.theme + '.html'), controller: this.controller })
        .javaScriptAccess(true).domStorageAccess(false).fileAccess(false)
        .backgroundColor(this.paperColor)
        .javaScriptProxy({ object: this.bridge, name: 'nativeBridge', methodList: ['postMessage'], controller: this.controller })
        .onPageBegin(() => { this.loaded = false; this.error = ''; })
        .onPageEnd(() => { this.loaded = true; this.dataChanged(); })
        .onErrorReceive(() => { this.error = '图谱加载失败，请重试'; })
        .onRenderExited(() => { this.loaded = false; this.error = '图谱已暂停，请重新加载'; })
      Column({ space: 8 }) {
        Button('＋').width(42).height(42).padding(0).fontSize(23).backgroundColor(this.palette.card).fontColor(this.palette.text)
          .id('graph-zoom-in').accessibilityText('放大图谱').onClick(() => this.send('{"type":"zoomIn"}'))
        Button('－').width(42).height(42).padding(0).fontSize(23).backgroundColor(this.palette.card).fontColor(this.palette.text)
          .id('graph-zoom-out').accessibilityText('缩小图谱').onClick(() => this.send('{"type":"zoomOut"}'))
      }.padding(12)
      if (this.error.length > 0) {
        Column({ space: 12 }) {
          Text(this.error).fontSize(14).fontColor(this.palette.danger)
          Button('重新加载图谱').onClick(() => { this.error = ''; this.controller.refresh(); })
        }.padding(20).backgroundColor(this.palette.card).borderRadius(16).align(Alignment.Center)
      }
    }.width('100%').height('100%')
  }
}

