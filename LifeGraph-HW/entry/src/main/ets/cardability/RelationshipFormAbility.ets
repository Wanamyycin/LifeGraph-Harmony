import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesktopCardStore } from '../data/DesktopCardStore';
import { DesktopCardData } from '../features/DesktopCard';

export default class RelationshipFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // Return an initial binding synchronously. Publishing an async update before
    // the host has registered a new form can lose the first update.
    try { return formBindingData.createFormBindingData(DesktopCardStore.cachedSync(this.context)); }
    catch (_) { return formBindingData.createFormBindingData(new DesktopCardData()); }
  }
  onUpdateForm(formId: string): void { this.refresh(formId); }
  onFormEvent(formId: string, message: string): void { this.refresh(formId); }
  private refresh(id: string): void {
    DesktopCardStore.update(this.context, id).catch(() => {
      hilog.warn(0x0000, 'LifeGraphCard', 'Desktop card refresh failed');
    });
  }
}
