import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { MediaAsset } from '../domain/Models';

export class MediaFiles {
  private context: common.UIAbilityContext;
  private root: string;
  private thumbnails: Map<string, string> = new Map<string, string>();

  constructor(context: common.UIAbilityContext) { this.context = context; this.root = context.filesDir + '/media'; }
  directory(): string { return this.root; }

  async initialize(): Promise<void> {
    if (!await fileIo.access(this.root)) { await fileIo.mkdir(this.root, true); }
  }

  path(storagePath: string): string {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(storagePath) || storagePath.includes('..')) { throw new Error('附件路径无效'); }
    return this.root + '/' + storagePath;
  }

  uri(asset: MediaAsset): string { return fileUri.getUriFromPath(this.path(asset.storagePath)); }

  async chooseImages(max: number = 9): Promise<string[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = max;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    return result.photoUris;
  }

  async chooseAudio(): Promise<string[]> {
    const options = new picker.AudioSelectOptions(); options.maxSelectNumber = 1;
    return new picker.AudioViewPicker(this.context).select(options);
  }

  async import(uri: string, kind: string): Promise<MediaAsset> {
    await this.initialize();
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const asset = new MediaAsset(); asset.id = util.generateRandomUUID(); asset.mediaKind = kind;
    const match = uri.split('?')[0].match(/\.([a-zA-Z0-9]{1,8})$/);
    const extension = match !== null ? match[1].toLowerCase() : (kind === 'image' ? 'jpg' : 'm4a');
    asset.storagePath = asset.id + '.' + extension;
    asset.mimeType = kind === 'image' ? (extension === 'png' ? 'image/png' : 'image/jpeg') : (extension === 'mp3' ? 'audio/mpeg' : 'audio/mp4');
    asset.role = kind === 'audio' ? 'voice-note' : 'attachment';
    const destination = this.path(asset.storagePath);
    try {
      await fileIo.copyFile(source.fd, destination);
      if ((await fileIo.stat(destination)).size === 0) { throw new Error('所选文件没有内容'); }
      return asset;
    } catch (error) {
      try { await fileIo.unlink(destination); } catch (_) {}
      throw new Error('附件导入失败：' + String(error));
    } finally { await fileIo.close(source); }
  }

  async thumbnail(asset: MediaAsset): Promise<string> {
    const cached = this.thumbnails.get(asset.id);
    if (cached !== undefined) { return cached; }
    const source = image.createImageSource(this.path(asset.storagePath));
    const packer = image.createImagePacker();
    let pixels: image.PixelMap | null = null;
    try {
      pixels = await source.createPixelMap({ desiredSize: { width: 96, height: 96 } });
      const bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 72 });
      const uri = 'data:image/jpeg;base64,' + new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
      if (this.thumbnails.size >= 200) {
        const first = Array.from(this.thumbnails.keys())[0];
        if (first !== undefined) { this.thumbnails.delete(first); }
      }
      this.thumbnails.set(asset.id, uri); return uri;
    } finally {
      if (pixels !== null) { await pixels.release(); }
      await source.release(); await packer.release();
    }
  }

  async remove(asset: MediaAsset): Promise<void> {
    const path = this.path(asset.storagePath);
    if (await fileIo.access(path)) { await fileIo.unlink(path); }
    this.thumbnails.delete(asset.id);
  }

  async sweep(keep: string[]): Promise<void> {
    const retained = new Set<string>(keep);
    for (const name of await fileIo.listFile(this.root)) {
      if (retained.has(name)) { continue; }
      const path = this.path(name);
      if ((await fileIo.stat(path)).isFile()) { await fileIo.unlink(path); }
    }
  }

  async storageStats(): Promise<number[]> {
    // Include SQLite journal/WAL files, rather than measuring only the main db.
    return [await directoryBytes(this.context.databaseDir), await directoryBytes(this.root)];
  }
}

async function directoryBytes(root: string): Promise<number> {
  if (!await fileIo.access(root)) { return 0; }
  let bytes = 0;
  for (const name of await fileIo.listFile(root)) {
    const path = root + '/' + name;
    const stat = await fileIo.stat(path);
    if (stat.isFile()) { bytes += stat.size; }
    else if (stat.isDirectory()) { bytes += await directoryBytes(path); }
  }
  return bytes;
}
