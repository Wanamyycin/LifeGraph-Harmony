import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSnapshot } from '../domain/Models';
import { DesktopCardConfig, DesktopCardData, normalizeCardConfig, projectDesktopCard } from '../features/DesktopCard';

const STORE = 'lifegraph_desktop_card_v1';

export class DesktopCardStore {
  private static tail: Promise<void> = Promise.resolve();

  private static async open(context: common.Context): Promise<preferences.Preferences> {
    // Extension and UIAbility can live in separate processes. Do not reuse a
    // preferences memory cache after the other process has flushed new content.
    await preferences.removePreferencesFromCache(context, STORE);
    return preferences.getPreferences(context, { name: STORE });
  }

  static async config(context: common.Context): Promise<DesktopCardConfig> {
    await DesktopCardStore.tail;
    const store = await DesktopCardStore.open(context);
    const text = await store.get('config', '');
    if (typeof text !== 'string' || text.length === 0) { return new DesktopCardConfig(); }
    try { return normalizeCardConfig(JSON.parse(text) as DesktopCardConfig); }
    catch (_) { return new DesktopCardConfig(); }
  }

  static async cached(context: common.Context): Promise<DesktopCardData> {
    await DesktopCardStore.tail;
    const store = await DesktopCardStore.open(context);
    const text = await store.get('presentation', '');
    if (typeof text !== 'string' || text.length === 0) { return new DesktopCardData(); }
    return JSON.parse(text) as DesktopCardData;
  }

  static cachedSync(context: common.Context): DesktopCardData {
    preferences.removePreferencesFromCacheSync(context, STORE);
    const store = preferences.getPreferencesSync(context, { name: STORE });
    const text = store.getSync('presentation', '');
    return typeof text === 'string' && text.length > 0 ? JSON.parse(text) as DesktopCardData : new DesktopCardData();
  }

  static publish(context: common.Context, snapshot: AppSnapshot, config?: DesktopCardConfig): Promise<boolean> {
    const job = DesktopCardStore.tail.then(async (): Promise<boolean> => {
      const store = await DesktopCardStore.open(context);
      let selected = config;
      if (selected === undefined) {
        const text = await store.get('config', '');
        try { selected = typeof text === 'string' && text.length > 0 ? normalizeCardConfig(JSON.parse(text) as DesktopCardConfig) : new DesktopCardConfig(); }
        catch (_) { selected = new DesktopCardConfig(); }
      }
      selected = normalizeCardConfig(selected);
      const data = projectDesktopCard(snapshot, selected);
      await store.put('config', JSON.stringify(selected));
      await store.put('presentation', JSON.stringify(data));
      await store.flush();
      // Published form IDs are owned by the OS; no stale ID registry to restore.
      const forms = await formProvider.getPublishedRunningFormInfos().catch((error: BusinessError): formInfo.RunningFormInfo[] => {
        if (error.code === 16500100) { return []; }
        throw new Error('卡片设置已保存，暂时无法读取桌面卡片，请稍后重试');
      });
      let failed = false;
      for (const form of forms) {
        if (form.formName !== 'RelationshipCard') { continue; }
        try { await formProvider.updateForm(form.formId, formBindingData.createFormBindingData(data)); }
        catch (_) { failed = true; }
      }
      if (failed) { throw new Error('卡片设置已保存，部分桌面卡片刷新失败，请重新打开应用后重试'); }
      return forms.some((form: formInfo.RunningFormInfo) => form.formName === 'RelationshipCard');
    });
    DesktopCardStore.tail = job.then(() => {}, () => {});
    return job;
  }

  static async update(context: common.Context, formId: string): Promise<void> {
    const data = await DesktopCardStore.cached(context);
    await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
  }
}
