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
  private lastPayload: string = '';
  private loadTimer: number = -1;
  private recoveryAttempts: number = 0;
  @State webVisible: boolean = true;
  @State error: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.bridge.callback = (message: string): void => {
      if (!this.active || message.length > 2048) { return; }
      try {
        const parsed = JSON.parse(message) as GraphMessage;
        if (parsed.type === 'ready') { this.pageReady(); }
        else if (typeof parsed.id === 'string' && parsed.id.length <= 160) {
          if (parsed.type === 'person') { this.onPerson(parsed.id); }
          if (parsed.type === 'event') { this.onEvent(parsed.id); }
          if (parsed.type === 'branch') { this.onBranch(parsed.id.replace(/^branch:/, '')); }
        }
      } catch (_) { /* Ignore messages outside the graph protocol. */ }
    };
  }

  aboutToDisappear(): void {
    this.active = false; this.loaded = false; this.bridge.callback = null;
    clearTimeout(this.loadTimer);
  }

  private pageReady(): void {
    if (!this.active) { return; }
    clearTimeout(this.loadTimer);
    this.loaded = true;
    this.error = '';
    this.dataChanged();
  }

  private visibilityChanged(visible: boolean): void {
    if (!this.active) { return; }
    if (!visible) {
      try { this.controller.onInactive(); } catch (_) {}
      return;
    }
    try { this.controller.onActive(); } catch (_) {}
    // A healthy retained page only needs reactivation. Refreshing here clears
    // its first frame and restarts D3, producing a flash and losing the viewport.
    // Actual renderer exits and loading failures retain their recovery paths.
    this.dataChanged();
  }

  private reloadGraph(automatic: boolean = false): void {
    if (!this.active || !this.webVisible) { return; }
    clearTimeout(this.loadTimer);
    this.loaded = false;
    this.lastPayload = '';
    if (automatic && this.recoveryAttempts >= 1) {
      this.error = '图谱加载失败，请重新加载';
      return;
    }
    this.recoveryAttempts = automatic ? this.recoveryAttempts + 1 : 0;
    this.error = '';
    // A crashed renderer needs a new Web/controller, rather than refresh on the dead instance.
    this.webVisible = false;
    this.loadTimer = setTimeout(() => {
      if (!this.active) { return; }
      this.controller = new webview.WebviewController();
      this.webVisible = true;
    }, 100);
  }

  private dataChanged(): void {
    if (!this.loaded || this.payload.length === 0 || this.payload === this.lastPayload) { return; }
    this.lastPayload = this.payload;
    this.send(this.payload, true);
  }

  private themeChanged(): void {
    if (!this.active) { return; }
    this.reloadGraph();
  }

  private send(message: string, graphData: boolean = false): void {
    if (!this.active || !this.loaded) { return; }
    // The bundled renderer starts a force simulation per payload; stop the previous animation first.
    const script = (graphData ? 'if(window.simulation){window.simulation.stop();}' : '') +
      'document.dispatchEvent(new MessageEvent("message",{data:' + JSON.stringify(message) + '}));';
    try {
      this.controller.runJavaScript(script).catch((error: Error) => {
        if (this.active) { this.lastPayload = ''; this.error = '图谱数据未能送达，请重试'; }
      });
    } catch (_) { this.lastPayload = ''; this.error = '图谱尚未就绪，请重试'; }
  }

  private graphSource(): Resource {
    switch (this.theme) {
      case 'forest-dark': return $rawfile('graph/forest-dark.html');
      case 'ocean-light': return $rawfile('graph/ocean-light.html');
      case 'ocean-dark': return $rawfile('graph/ocean-dark.html');
      case 'sunset-light': return $rawfile('graph/sunset-light.html');
      case 'sunset-dark': return $rawfile('graph/sunset-dark.html');
      case 'minimal-light': return $rawfile('graph/minimal-light.html');
      case 'minimal-dark': return $rawfile('graph/minimal-dark.html');
      default: return $rawfile('graph/forest-light.html');
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.webVisible) {
        // Compose the graph with ArkUI instead of an independent surface. The
        // emulator can retain a black surface while the SVG/DOM remains alive.
        Web({ src: this.graphSource(), controller: this.controller, renderMode: RenderMode.SYNC_RENDER })
          .width('100%').height('100%')
          .javaScriptAccess(true).domStorageAccess(false).fileAccess(false)
          .blockNetwork(true).onlineImageAccess(false).mixedMode(MixedMode.None)
          .backgroundColor(this.paperColor)
          .javaScriptProxy({ object: this.bridge, name: 'nativeBridge', methodList: ['postMessage'], controller: this.controller })
          .onPageBegin(() => {
            this.loaded = false; this.lastPayload = ''; this.error = '';
            clearTimeout(this.loadTimer);
            this.loadTimer = setTimeout(() => { this.reloadGraph(true); }, 6000);
          })
          .onPageEnd(() => {
            this.controller.runJavaScript('typeof render === "function" && typeof d3 !== "undefined"')
              .then((result: string) => { if (result === 'true') { this.pageReady(); } })
              .catch(() => { if (this.active) { this.reloadGraph(true); } });
          })
          .onErrorReceive(() => { this.error = '图谱加载失败，请重试'; })
          .onRenderExited(() => { this.reloadGraph(true); })
      }
      Column({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          Stack({ alignContent: Alignment.Center }) {
            Rect().width(16).height(2).radius(1).fill(this.palette.text)
            Rect().width(2).height(16).radius(1).fill(this.palette.text)
          }.width(22).height(22)
        }.width(42).height(42).padding(0).backgroundColor(this.palette.card)
          .id('graph-zoom-in').accessibilityText('放大图谱').onClick(() => this.send('{"type":"zoomIn"}'))
        Button({ type: ButtonType.Circle }) {
          Stack({ alignContent: Alignment.Center }) {
            Rect().width(16).height(2).radius(1).fill(this.palette.text)
          }.width(22).height(22)
        }.width(42).height(42).padding(0).backgroundColor(this.palette.card)
          .id('graph-zoom-out').accessibilityText('缩小图谱').onClick(() => this.send('{"type":"zoomOut"}'))
      }.padding(12)
      if (this.error.length > 0) {
        Column({ space: 12 }) {
          Text(this.error).fontSize(14).fontColor(this.palette.danger)
          Button('重新加载图谱').onClick(() => this.reloadGraph())
        }.padding(20).backgroundColor(this.palette.card).borderRadius(16).align(Alignment.Center)
      }
    }.width('100%').height('100%').onVisibleAreaChange([0], (visible: boolean) => this.visibilityChanged(visible))
  }
}

