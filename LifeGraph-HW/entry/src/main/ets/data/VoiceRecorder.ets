import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class VoiceRecorder {
  private recorder: media.AVRecorder | null = null;
  private file: fileIo.File | null = null;
  private path: string = '';
  private failure: string = '';

  async start(context: common.UIAbilityContext): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Media.AVRecorder')) { throw new Error('这台设备暂不支持录音，可以导入已有音频'); }
    if (this.recorder !== null) { throw new Error('录音已经开始'); }
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
    if (permission.authResults.length === 0 || permission.authResults[0] !== 0) { throw new Error('需要麦克风权限才能录音，也可以选择导入音频'); }
    this.path = context.cacheDir + '/voice-' + util.generateRandomUUID() + '.m4a';
    this.failure = '';
    this.file = await fileIo.open(this.path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      this.recorder = await media.createAVRecorder();
      this.recorder.on('error', () => { this.failure = '录音被中断，请重新录制或导入已有音频'; });
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: { audioBitrate: 64000, audioChannels: 1, audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 44100, fileFormat: media.ContainerFormatType.CFT_MPEG_4A },
        url: 'fd://' + this.file.fd
      };
      await this.recorder.prepare(config); await this.recorder.start();
      if (this.failure.length > 0) { throw new Error(this.failure); }
    } catch (error) { await this.release(); throw new Error('无法开始录音：' + String(error)); }
  }

  async stop(): Promise<string> {
    if (this.recorder === null) { throw new Error('录音尚未开始'); }
    const path = this.path;
    let stopped = false;
    try {
      if (this.failure.length > 0) { throw new Error(this.failure); }
      await this.recorder.stop();
      stopped = true;
    } finally { await this.release(!stopped); }
    try {
      if ((await fileIo.stat(path)).size === 0) { throw new Error('录音没有内容，请重试'); }
    } catch (error) { await this.removeCapture(path); throw new Error(String(error)); }
    return path;
  }

  async release(discard: boolean = true): Promise<void> {
    const recorder = this.recorder; const file = this.file;
    this.recorder = null; this.file = null;
    try { if (recorder !== null) { await recorder.release(); } }
    catch (error) { hilog.warn(0x0000, 'LifeGraph', 'Recorder release: %{public}s', String(error)); }
    try { if (file !== null) { await fileIo.close(file); } }
    catch (error) { hilog.warn(0x0000, 'LifeGraph', 'Capture close: %{public}s', String(error)); }
    if (discard) { await this.removeCapture(this.path); }
  }

  async removeCapture(path: string): Promise<void> {
    if (path !== this.path || this.recorder !== null) { return; }
    try { await fileIo.unlink(path); } catch (_) {}
  }
}
