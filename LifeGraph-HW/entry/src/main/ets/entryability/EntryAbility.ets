import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ApplicationRuntime } from '../runtime/ApplicationRuntime';
import { AppServices } from '../application/AppServices';
import { ColorModeController } from '../runtime/ColorModeController';
import { Palette, ProfileConfig, paletteFor } from '../domain/Models';
import { CardLaunch } from '../features/DesktopCard';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private colorMode: ColorModeController = new ColorModeController((appearance: string): void => {
    const mode = appearance === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (appearance === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    this.context.getApplicationContext().setColorMode(mode);
  });
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ApplicationRuntime.start();
    this.acceptCardWant(want);
    AppStorage.setOrCreate('nativeSystemDark', this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    CardLaunch.clear();
    ApplicationRuntime.stop();
    ApplicationRuntime.onColors = null;
    AppServices.close().catch((error: Error) => { hilog.error(DOMAIN, 'LifeGraph', '%{public}s', error.message); });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void { this.acceptCardWant(want); }

  private acceptCardWant(want: Want): void {
    const action = want.parameters?.['cardAction'];
    const personId = want.parameters?.['cardPersonId'];
    if (typeof action === 'string') { CardLaunch.request(action, typeof personId === 'string' ? personId : ''); }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    ApplicationRuntime.onAppearance = (appearance: string): void => {
      try { this.colorMode.setAppearance(appearance); }
      catch (_) { hilog.warn(DOMAIN, 'LifeGraph', 'Native appearance update failed'); }
    };
    ApplicationRuntime.onAppearance('system');
    ApplicationRuntime.onColors = (background: string, text: string): void => {
      try {
        const mainWindow = windowStage.getMainWindowSync();
        mainWindow.setWindowBackgroundColor(background);
        mainWindow.setWindowSystemBarProperties({ statusBarColor: background, navigationBarColor: background,
          statusBarContentColor: text, navigationBarContentColor: text }).catch(() => {});
      } catch (_) {}
    };
    const initialColors: Palette = paletteFor(new ProfileConfig(), this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    ApplicationRuntime.onColors(initialColors.paper, initialColors.text);
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

  }

  onWindowStageDestroy(): void {
    ApplicationRuntime.onColors = null; ApplicationRuntime.onAppearance = null;
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    ApplicationRuntime.enterForeground();
    AppStorage.setOrCreate('nativeSystemDark', this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onConfigurationUpdate(config: Configuration): void {
    AppStorage.setOrCreate('nativeSystemDark', config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onBackground(): void {
    ApplicationRuntime.enterBackground();
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
