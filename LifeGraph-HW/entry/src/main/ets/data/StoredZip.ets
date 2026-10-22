// Streaming ZIP32 (stored entries). JPEG/AAC media is already compressed;
// avoiding a JS compression library keeps memory bounded and works offline.
export interface ByteFile {
  size(): Promise<number>;
  read(offset: number, length: number): Promise<Uint8Array>;
  write(offset: number, bytes: Uint8Array): Promise<void>;
  close(): Promise<void>;
}

export class ZipSource {
  name: string;
  file: ByteFile;
  constructor(name: string, file: ByteFile) { this.name = name; this.file = file; }
}

export class ZipEntry {
  name: string = '';
  size: number = 0;
  crc: number = 0;
  offset: number = 0;
  dataOffset: number = 0;
}

const BLOCK = 65536;
const CRC_TABLE: Uint32Array = new Uint32Array(256);
for (let i = 0; i < 256; i++) {
  let value = i;
  for (let bit = 0; bit < 8; bit++) { value = (value & 1) !== 0 ? 0xEDB88320 ^ (value >>> 1) : value >>> 1; }
  CRC_TABLE[i] = value >>> 0;
}

export async function writeZip(output: ByteFile, sources: ZipSource[]): Promise<void> {
  if (sources.length === 0 || sources.length > 20000) { throw new Error('备份文件数量超出范围'); }
  let offset = 0;
  const entries: ZipEntry[] = [];
  const seen = new Set<string>();
  for (const source of sources) {
    checkName(source.name);
    if (seen.has(source.name)) { throw new Error('备份存在重复文件'); }
    seen.add(source.name);
    const entry = new ZipEntry(); entry.name = source.name; entry.size = await source.file.size(); entry.offset = offset;
    if (entry.size > 536870912 || entry.size < 0) { throw new Error('单个附件超过 512MB 备份限制'); }
    const name = ascii(source.name);
    const header = new Uint8Array(30 + name.length); const view = new DataView(header.buffer);
    view.setUint32(0, 0x04034B50, true); view.setUint16(4, 20, true); view.setUint16(6, 0x808, true);
    view.setUint16(12, 33, true); view.setUint16(26, name.length, true); header.set(name, 30);
    await output.write(offset, header); offset += header.length;
    let crc = 0xFFFFFFFF;
    for (let position = 0; position < entry.size; position += BLOCK) {
      const bytes = await source.file.read(position, Math.min(BLOCK, entry.size - position));
      if (bytes.length !== Math.min(BLOCK, entry.size - position)) { throw new Error('读取附件不完整'); }
      crc = crcBlock(crc, bytes); await output.write(offset, bytes); offset += bytes.length;
    }
    await source.file.close();
    entry.crc = (crc ^ 0xFFFFFFFF) >>> 0;
    const descriptor = new Uint8Array(16); const d = new DataView(descriptor.buffer);
    d.setUint32(0, 0x08074B50, true); d.setUint32(4, entry.crc, true); d.setUint32(8, entry.size, true); d.setUint32(12, entry.size, true);
    await output.write(offset, descriptor); offset += descriptor.length; entries.push(entry);
    if (offset > 1073741824) { throw new Error('当前版本支持总大小不超过 1GB 的备份'); }
  }
  const centralOffset = offset;
  for (const entry of entries) {
    const name = ascii(entry.name); const record = new Uint8Array(46 + name.length); const view = new DataView(record.buffer);
    view.setUint32(0, 0x02014B50, true); view.setUint16(4, 20, true); view.setUint16(6, 20, true); view.setUint16(8, 0x808, true);
    view.setUint16(14, 33, true); view.setUint32(16, entry.crc, true); view.setUint32(20, entry.size, true); view.setUint32(24, entry.size, true);
    view.setUint16(28, name.length, true); view.setUint32(42, entry.offset, true); record.set(name, 46);
    await output.write(offset, record); offset += record.length;
  }
  const footer = new Uint8Array(22); const view = new DataView(footer.buffer);
  view.setUint32(0, 0x06054B50, true); view.setUint16(8, entries.length, true); view.setUint16(10, entries.length, true);
  view.setUint32(12, offset - centralOffset, true); view.setUint32(16, centralOffset, true);
  await output.write(offset, footer);
}

export async function readZip(file: ByteFile): Promise<ZipEntry[]> {
  const size = await file.size();
  if (size < 22 || size > 1078000000) { throw new Error('备份大小不正确，当前上限为 1GB'); }
  const tailOffset = Math.max(0, size - 65557);
  const tail = await exact(file, tailOffset, size - tailOffset); const tailView = new DataView(tail.buffer);
  let end = -1;
  for (let i = tail.length - 22; i >= 0; i--) {
    if (tailView.getUint32(i, true) === 0x06054B50 && i + 22 + tailView.getUint16(i + 20, true) === tail.length) { end = i; break; }
  }
  if (end < 0) { throw new Error('不是完整的 ZIP 备份'); }
  const count = tailView.getUint16(end + 10, true); const length = tailView.getUint32(end + 12, true); const start = tailView.getUint32(end + 16, true);
  if (count === 0 || count > 20000 || length > 4000000 || tailView.getUint16(end + 4, true) !== 0 || tailView.getUint16(end + 6, true) !== 0 ||
    tailView.getUint16(end + 8, true) !== count || start + length !== tailOffset + end) { throw new Error('不支持这个备份结构'); }
  const central = await exact(file, start, length); const view = new DataView(central.buffer);
  const entries: ZipEntry[] = []; const seen = new Set<string>(); let position = 0; let totalSize = 0;
  for (let index = 0; index < count; index++) {
    if (position + 46 > central.length || view.getUint32(position, true) !== 0x02014B50) { throw new Error('备份索引损坏'); }
    const flags = view.getUint16(position + 8, true); const method = view.getUint16(position + 10, true);
    const nameLength = view.getUint16(position + 28, true); const extraLength = view.getUint16(position + 30, true); const commentLength = view.getUint16(position + 32, true);
    if ((flags & 1) !== 0 || method !== 0 || position + 46 + nameLength + extraLength + commentLength > central.length) { throw new Error('请选择本应用导出的鸿蒙版备份'); }
    const entry = new ZipEntry(); entry.name = decodeAscii(central.slice(position + 46, position + 46 + nameLength)); checkName(entry.name);
    if (seen.has(entry.name)) { throw new Error('备份含重复文件'); } seen.add(entry.name);
    entry.crc = view.getUint32(position + 16, true); entry.size = view.getUint32(position + 24, true); entry.offset = view.getUint32(position + 42, true);
    if (entry.size !== view.getUint32(position + 20, true) || entry.size > 536870912 || entry.offset + 30 > start) { throw new Error('备份附件大小不正确'); }
    const local = await exact(file, entry.offset, 30); const localView = new DataView(local.buffer);
    if (localView.getUint32(0, true) !== 0x04034B50 || localView.getUint16(8, true) !== 0 || localView.getUint16(6, true) !== flags) { throw new Error('备份文件头不一致'); }
    const localNameLength = localView.getUint16(26, true); const localExtraLength = localView.getUint16(28, true);
    const localName = decodeAscii(await exact(file, entry.offset + 30, localNameLength));
    if (localName !== entry.name) { throw new Error('备份文件名不一致'); }
    entry.dataOffset = entry.offset + 30 + localNameLength + localExtraLength;
    if (entry.dataOffset + entry.size > start) { throw new Error('备份附件越界'); }
    totalSize += entry.size;
    if (totalSize > 1073741824) { throw new Error('备份展开后超过 1GB'); }
    entries.push(entry); position += 46 + nameLength + extraLength + commentLength;
  }
  if (position !== central.length || !seen.has('manifest.json')) { throw new Error('备份缺少清单或索引不正确'); }
  const sorted = entries.slice().sort((a: ZipEntry, b: ZipEntry) => a.offset - b.offset);
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].offset < sorted[i - 1].dataOffset + sorted[i - 1].size) { throw new Error('备份文件区间重叠'); }
  }
  return entries;
}

export async function copyZipEntry(archive: ByteFile, entry: ZipEntry, destination: ByteFile): Promise<void> {
  let crc = 0xFFFFFFFF;
  for (let offset = 0; offset < entry.size; offset += BLOCK) {
    const bytes = await exact(archive, entry.dataOffset + offset, Math.min(BLOCK, entry.size - offset));
    crc = crcBlock(crc, bytes); await destination.write(offset, bytes);
  }
  if (((crc ^ 0xFFFFFFFF) >>> 0) !== entry.crc) { throw new Error('备份文件校验失败，当前数据未替换'); }
}

function checkName(name: string): void {
  if (name !== 'manifest.json' && (!/^media\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(name) || name.includes('..'))) { throw new Error('备份包含不安全或不支持的路径'); }
}
function ascii(text: string): Uint8Array { const bytes = new Uint8Array(text.length); for (let i = 0; i < text.length; i++) { bytes[i] = text.charCodeAt(i); } return bytes; }
function decodeAscii(bytes: Uint8Array): string {
  let text = ''; for (const value of bytes) { if (value < 32 || value > 126) { throw new Error('备份路径编码不正确'); } text += String.fromCharCode(value); } return text;
}
function crcBlock(crc: number, bytes: Uint8Array): number {
  let current = crc; for (const value of bytes) { current = CRC_TABLE[(current ^ value) & 0xFF] ^ (current >>> 8); } return current >>> 0;
}
async function exact(file: ByteFile, offset: number, length: number): Promise<Uint8Array> {
  const bytes = await file.read(offset, length); if (bytes.length !== length) { throw new Error('备份文件截断'); } return bytes;
}
