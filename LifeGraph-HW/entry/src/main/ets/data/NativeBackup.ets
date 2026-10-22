import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupEnvelope, BackupTable } from '../domain/Backup';
import { LifeGraphService } from '../features/LifeGraphService';
import { MediaFiles } from './MediaFiles';
import { MemoryByteFile, NativeByteFile } from './NativeByteFile';
import { ByteFile, copyZipEntry, readZip, writeZip, ZipEntry, ZipSource } from './StoredZip';

export class BackupPreview {
  date: string = '';
  people: number = 0;
  events: number = 0;
}

export class NativeBackup {
  private context: common.UIAbilityContext;
  private service: LifeGraphService;
  private files: MediaFiles;
  constructor(context: common.UIAbilityContext, service: LifeGraphService, files: MediaFiles) {
    this.context = context; this.service = service; this.files = files;
  }

  async export(): Promise<boolean> {
    const envelope = await this.service.exportBackup();
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(envelope));
    if (bytes.length > 16777216) { throw new Error('备份清单超过当前 16MB 上限，请减少记录后重试'); }
    const sources: ZipSource[] = [new ZipSource('manifest.json', new MemoryByteFile(bytes))];
    for (const path of mediaPaths(envelope)) { sources.push(new ZipSource('media/' + path, new NativeByteFile(this.files.path(path)))); }
    const cache = this.context.cacheDir + '/export-' + util.generateRandomUUID() + '.zip';
    const output = new NativeByteFile(cache, true);
    try {
      await writeZip(output, sources); await output.close();
      const options = new picker.DocumentSaveOptions(); options.newFileNames = ['LifeGraph-' + Date.now().toString() + '.zip'];
      options.fileSuffixChoices = ['Life Graph 备份|.zip'];
      const destinations = await new picker.DocumentViewPicker(this.context).save(options);
      if (destinations.length === 0) { return false; }
      const source = await fileIo.open(cache, fileIo.OpenMode.READ_ONLY);
      try {
        const destination = await fileIo.open(destinations[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try { await fileIo.copyFile(source.fd, destination.fd); }
        finally { await fileIo.close(destination); }
      } finally {
        try { await fileIo.close(source); } catch (error) { cleanupWarning(error); }
      }
      return true;
    } finally {
      await closeAfterUse(output);
      for (const source of sources) { await closeAfterUse(source.file); }
      await removeAfterUse(cache);
    }
  }

  async choose(): Promise<string | null> {
    const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1; options.fileSuffixFilters = ['.zip'];
    const files = await new picker.DocumentViewPicker(this.context).select(options);
    return files.length > 0 ? files[0] : null;
  }

  async preview(uri: string): Promise<BackupPreview> {
    const archive = new NativeByteFile(uri);
    try {
      const entries = await readZip(archive); const envelope = await readManifest(archive, entries);
      const result = new BackupPreview(); result.date = new Date(envelope.createdAt).toLocaleString();
      result.people = envelope.tables.find((table: BackupTable) => table.name === 'persons')?.rows.length ?? 0;
      result.events = envelope.tables.find((table: BackupTable) => table.name === 'events')?.rows.length ?? 0;
      return result;
    } finally { await closeAfterUse(archive); }
  }

  async restore(uri: string): Promise<void> {
    const archive = new NativeByteFile(uri);
    const createdPaths: string[] = [];
    let committed = false;
    try {
      const entries = await readZip(archive); const envelope = await readManifest(archive, entries);
      const paths = mediaPaths(envelope);
      if (entries.length !== paths.length + 1) { throw new Error('备份清单与附件数量不一致'); }
      const replacements = new Map<string, string>();
      for (const path of paths) {
        const entry = entries.find((item: ZipEntry) => item.name === 'media/' + path);
        if (entry === undefined) { throw new Error('备份缺少附件：' + path); }
        const replacement = 'restore-' + util.generateRandomUUID() + '-' + path;
        const fullPath = this.files.path(replacement); createdPaths.push(fullPath);
        const destination = new NativeByteFile(fullPath, true);
        try { await copyZipEntry(archive, entry, destination); } finally { await destination.close(); }
        replacements.set(path, replacement);
      }
      const media = envelope.tables.find((table: BackupTable) => table.name === 'media_assets');
      if (media !== undefined) {
        const column = media.columns.indexOf('storage_path');
        for (const row of media.rows) {
          const path = row[column];
          if (typeof path === 'string' && replacements.has(path)) { row[column] = replacements.get(path) ?? path; }
        }
      }
      await this.service.restoreBackup(envelope); committed = true;
    } finally {
      await closeAfterUse(archive);
      if (!committed) {
        for (const path of createdPaths) { await removeAfterUse(path); }
      }
    }
  }
}

// Cleanup must not turn a committed restore into an apparent failure, or hide a
// validation/transaction failure and prevent the remaining files from being removed.
async function closeAfterUse(file: ByteFile): Promise<void> {
  try { await file.close(); } catch (error) { cleanupWarning(error); }
}

async function removeAfterUse(path: string): Promise<void> {
  try { if (await fileIo.access(path)) { await fileIo.unlink(path); } } catch (error) { cleanupWarning(error); }
}

function cleanupWarning(error: Error): void {
  hilog.warn(0x0000, 'LifeGraph', 'Backup cleanup deferred: %{public}s', String(error));
}

async function readManifest(archive: NativeByteFile, entries: ZipEntry[]): Promise<BackupEnvelope> {
  const manifest = entries.find((entry: ZipEntry) => entry.name === 'manifest.json');
  if (manifest === undefined || manifest.size === 0 || manifest.size > 16777216) { throw new Error('备份清单不存在或超过 16MB'); }
  const memory = new MemoryByteFile(new Uint8Array(manifest.size)); await copyZipEntry(archive, manifest, memory);
  const envelope = JSON.parse(new util.TextDecoder('utf-8', { fatal: true }).decodeToString(memory.bytes)) as BackupEnvelope;
  if (envelope.format !== 'lifegraph-harmony' || envelope.schemaVersion !== 1 || !Array.isArray(envelope.tables) || !Number.isFinite(envelope.createdAt)) { throw new Error('请选择本应用导出的鸿蒙版备份'); }
  return envelope;
}

function mediaPaths(envelope: BackupEnvelope): string[] {
  const media = envelope.tables.find((table: BackupTable) => table.name === 'media_assets');
  if (media === undefined || !Array.isArray(media.columns) || !Array.isArray(media.rows)) { throw new Error('备份缺少附件清单'); }
  const pathColumn = media.columns.indexOf('storage_path'); const deletedColumn = media.columns.indexOf('deleted_at');
  if (pathColumn < 0 || deletedColumn < 0) { throw new Error('附件清单格式不正确'); }
  const paths = new Set<string>();
  for (const row of media.rows) {
    if (row[deletedColumn] !== null) { continue; }
    const path = row[pathColumn];
    if (typeof path !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(path) || path.includes('..')) { throw new Error('备份附件路径不正确'); }
    paths.add(path);
  }
  return Array.from(paths);
}
