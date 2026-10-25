import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { OpenAIConfig, prepareOpenAIConfig } from '../domain/OpenAIConfig';

class AssetError extends Error { code: number = 0; }

// Credentials live outside RDB, chat history, media and exported ZIP files.
export class AIConfigVault {
  async load(): Promise<OpenAIConfig | null> {
    this.available();
    const query = this.alias(); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const values = await asset.query(query);
      if (values.length === 0) { return null; }
      const bytes = values[0].get(asset.Tag.SECRET);
      if (!(bytes instanceof Uint8Array)) { throw new Error('invalid credential'); }
      const config = JSON.parse(new util.TextDecoder('utf-8').decodeToString(bytes)) as OpenAIConfig;
      if (config === null || typeof config.url !== 'string' || typeof config.apiKey !== 'string' || typeof config.model !== 'string') { throw new Error('invalid credential'); }
      return prepareOpenAIConfig(config.url, config.apiKey, config.model);
    } catch (error) {
      if ((error as AssetError).code === asset.ErrorCode.NOT_FOUND) { return null; }
      throw new Error('无法读取本机 AI 安全配置，请解锁设备后重试，或在服务设置中重新保存');
    }
  }

  async save(config: OpenAIConfig): Promise<void> {
    this.available();
    const valid = prepareOpenAIConfig(config.url, config.apiKey, config.model);
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(valid));
    if (bytes.length > 1024) { throw new Error('配置超过安全存储的1024字节上限，可取消“在本机安全保存”仅本次使用'); }
    const attributes = this.alias();
    attributes.set(asset.Tag.SECRET, bytes);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    // Omit IS_PERSISTENT: the default removes data on uninstall without requesting persistent-data permission.
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try { await asset.add(attributes); }
    catch (_) { throw new Error('AI 配置未能安全保存，请解锁设备后重试，或取消“在本机安全保存”仅本次使用'); }
  }

  private alias(): asset.AssetMap {
    const value: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    value.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('lifegraph-openai-config-v1')); return value;
  }
  private available(): void {
    if (!canIUse('SystemCapability.Security.Asset')) { throw new Error('此设备的安全存储不可用，暂时无法保存 API Key'); }
  }
}
