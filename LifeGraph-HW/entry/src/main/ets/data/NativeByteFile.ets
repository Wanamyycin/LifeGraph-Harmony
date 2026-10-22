import { fileIo } from '@kit.CoreFileKit';
import { ByteFile } from './StoredZip';

export class NativeByteFile implements ByteFile {
  private path: string;
  private writable: boolean;
  private file: fileIo.File | null = null;
  constructor(path: string, writable: boolean = false) { this.path = path; this.writable = writable; }

  private async handle(): Promise<fileIo.File> {
    if (this.file === null) {
      this.file = await fileIo.open(this.path, this.writable ? fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC : fileIo.OpenMode.READ_ONLY);
    }
    return this.file;
  }
  async size(): Promise<number> { return (await fileIo.stat((await this.handle()).fd)).size; }
  async read(offset: number, length: number): Promise<Uint8Array> {
    const file = await this.handle();
    // SDK offsets are relative to the current file pointer, not absolute.
    fileIo.lseek(file.fd, offset, fileIo.WhenceType.SEEK_SET);
    const result = new Uint8Array(length); let total = 0;
    while (total < length) {
      const buffer = new ArrayBuffer(length - total);
      const count = await fileIo.read(file.fd, buffer, { length: length - total });
      if (count === 0) { break; }
      result.set(new Uint8Array(buffer, 0, count), total); total += count;
    }
    return result.slice(0, total);
  }
  async write(offset: number, bytes: Uint8Array): Promise<void> {
    if (!this.writable) { throw new Error('备份文件为只读'); }
    const file = await this.handle(); let written = 0;
    fileIo.lseek(file.fd, offset, fileIo.WhenceType.SEEK_SET);
    while (written < bytes.length) {
      const buffer = bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + bytes.byteLength);
      const count = await fileIo.write(file.fd, buffer, { length: bytes.length - written });
      if (count <= 0) { throw new Error('无法继续写入备份文件'); }
      written += count;
    }
  }
  async close(): Promise<void> { const file = this.file; this.file = null; if (file !== null) { await fileIo.close(file); } }
}

export class MemoryByteFile implements ByteFile {
  bytes: Uint8Array;
  constructor(bytes: Uint8Array) { this.bytes = bytes; }
  async size(): Promise<number> { return this.bytes.length; }
  async read(offset: number, length: number): Promise<Uint8Array> { return this.bytes.slice(offset, offset + length); }
  async write(offset: number, bytes: Uint8Array): Promise<void> {
    if (offset + bytes.length > this.bytes.length) { throw new Error('备份清单越界'); }
    this.bytes.set(bytes, offset);
  }
  async close(): Promise<void> {}
}
