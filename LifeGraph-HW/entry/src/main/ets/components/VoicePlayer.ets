import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { ApplicationRuntime } from '../runtime/ApplicationRuntime';
import { Palette } from '../domain/Models';

@Component
export struct VoicePlayer {
  @Prop filePath: string = '';
  @Prop palette: Palette = new Palette();
  @State playing: boolean = false;
  @State loading: boolean = false;
  @State progress: number = 0;
  @State duration: number = 0;
  @State error: string = '';
  private player: media.AVPlayer | null = null;
  private file: fileIo.File | null = null;
  private active: boolean = true;
  private timeoutId: number = -1;
  private generation: number = 0;
  private backgroundListener: number = -1;
  private rejectLoading: ((error: Error) => void) | null = null;

  aboutToAppear(): void {
    this.active = true;
    this.backgroundListener = ApplicationRuntime.addBackgroundListener(() => {
      this.generation++; this.release(); this.playing = false; this.loading = false;
    });
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++;
    ApplicationRuntime.removeBackgroundListener(this.backgroundListener); this.release();
  }

  private async toggle(): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Media.AVPlayer')) { this.error = '这台设备暂不支持音频播放'; return; }
    if (this.loading) { return; }
    const generation = ++this.generation;
    try {
      if (this.player !== null) {
        if (this.playing) { await this.player.pause(); if (generation === this.generation) { this.playing = false; } }
        else { if (this.player.state === 'completed') { this.player.seek(0); } await this.player.play(); if (generation === this.generation) { this.playing = true; } }
        return;
      }
      this.loading = true; this.error = '';
      const file = await fileIo.open(this.filePath, fileIo.OpenMode.READ_ONLY);
      if (!this.active || generation !== this.generation) { await fileIo.close(file); return; }
      this.file = file;
      const player = await media.createAVPlayer();
      if (!this.active || generation !== this.generation) { await player.release(); return; }
      this.player = player;
      await new Promise<void>((resolve, reject) => {
        this.rejectLoading = reject;
        this.timeoutId = setTimeout(() => reject(new Error('音频加载超时')), 10000);
        player.on('stateChange', (state: string) => {
          if (!this.active || generation !== this.generation) { return; }
          if (state === 'initialized') { player.prepare().catch(reject); }
          if (state === 'prepared') { clearTimeout(this.timeoutId); this.rejectLoading = null; this.duration = player.duration; resolve(); }
          if (state === 'completed') { this.playing = false; this.progress = this.duration; }
        });
        player.on('error', (error: Error) => {
          if (generation !== this.generation) { return; }
          clearTimeout(this.timeoutId); if (this.active) { this.error = '无法播放这段音频'; }
          reject(error); this.release(); this.playing = false;
        });
        player.on('timeUpdate', (time: number) => { if (this.active && generation === this.generation) { this.progress = time; } });
        player.fdSrc = { fd: file.fd, offset: 0, length: fileIo.statSync(file.fd).size };
      });
      if (this.active && generation === this.generation) { await player.play(); if (generation === this.generation) { this.playing = true; } }
    } catch (error) {
      if (generation === this.generation) { if (this.active) { this.error = '无法播放音频，请重试'; } await this.release(); }
    } finally { if (this.active && generation === this.generation) { this.loading = false; } }
  }

  private async release(): Promise<void> {
    clearTimeout(this.timeoutId);
    const reject = this.rejectLoading; this.rejectLoading = null;
    if (reject !== null) { reject(new Error('音频播放已结束')); }
    const player = this.player; const file = this.file; this.player = null; this.file = null;
    try { if (player !== null) { await player.release(); } } catch (_) {}
    finally { if (file !== null) { try { await fileIo.close(file); } catch (_) {} } }
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Button(this.loading ? '…' : (this.playing ? '暂停' : '播放')).fontSize(14).backgroundColor(this.palette.primary).enabled(!this.loading).onClick(() => this.toggle())
        Slider({ value: this.progress, min: 0, max: Math.max(1, this.duration) }).layoutWeight(1).selectedColor(this.palette.primary)
          .onChange((value: number, mode: SliderChangeMode) => { if (mode === SliderChangeMode.End && this.player !== null) { this.player.seek(value); } })
        Text(Math.floor(this.progress / 1000) + ' / ' + Math.floor(this.duration / 1000) + '秒').fontSize(12).fontColor(this.palette.muted)
      }.width('100%')
      if (this.error.length > 0) { Text(this.error).fontSize(12).fontColor(this.palette.danger) }
    }.padding(12).width('100%').backgroundColor(this.palette.soft).borderRadius(14)
  }
}
