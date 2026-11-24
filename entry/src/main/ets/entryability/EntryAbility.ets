import { UIAbility, Want, AbilityConstant, ConfigurationConstant, Configuration } from '@kit.AbilityKit';
import { window, ThemeControl } from '@kit.ArkUI';
import { ThemeColors, LightThemeColors, getThemeColorsByMode, buildCustomTheme, ThemeMode } from '../constants/ThemeConstants';
import { SettingsStore } from '../service/SettingsStore';
import { UserSettings } from '../model/UserSettings';
import { SceneRepository } from '../service/SceneRepository';
import { ProgressStore } from '../service/ProgressStore';
import { PlayerController } from '../service/PlayerController';
import { ModeManager } from '../service/ModeManager';
import appLogger from '../utils/Logger';

export default class EntryAbility extends UIAbility {
  private settingsChangeListener: ((s: UserSettings) => void) | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    appLogger.info('EntryAbility onCreate');
    const ctx = this.context;

    SceneRepository.init(ctx);
    ModeManager.getInstance();

    Promise.all([
      ProgressStore.getInstance().init(ctx),
      SettingsStore.getInstance().init(ctx)
    ]).then(() => {
      appLogger.info('All stores initialized');
      this.applyThemeFromSettings();
      this.settingsChangeListener = (s: UserSettings) => {
        this.applyThemeMode(s.theme);
      };
      SettingsStore.getInstance().addOnSettingsChange(this.settingsChangeListener);
      return PlayerController.init(ctx);
    }).then(() => {
      appLogger.info('PlayerController initialized');
      return SceneRepository.getInstance().loadAll();
    }).then(() => {
      appLogger.info('Scenes loaded');
    }).catch((err: Object) => {
      appLogger.error('Init failed: ' + JSON.stringify(err));
    });
  }

  private applyThemeFromSettings(): void {
    const settings = SettingsStore.getInstance().getSettings();
    appLogger.info(`EntryAbility: applyThemeFromSettings theme=${settings.theme}`);
    this.applyThemeMode(settings.theme);
  }

  /**
   * 根据主题设置（'dark' | 'light' | 'system'）应用：
   * 1) setColorMode —— 告诉系统应用要强制什么色彩模式
   * 2) ThemeControl.setDefaultTheme —— 覆盖 ArkUI 默认 token
   */
  private applyThemeMode(themeSetting: string): void {
    let effectiveMode: ThemeMode;
    let colorMode: number;

    if (themeSetting === 'dark') {
      effectiveMode = 'dark';
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (themeSetting === 'light') {
      effectiveMode = 'light';
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else {
      // 'system'：跟随系统色彩模式
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      effectiveMode = this.isConfigurationDark() ? 'dark' : 'light';
    }

    this.context.getApplicationContext().setColorMode(colorMode);

    const colors = getThemeColorsByMode(effectiveMode);
    ThemeControl.setDefaultTheme(buildCustomTheme(colors));
    appLogger.info(`EntryAbility: applied theme=${themeSetting} effective=${effectiveMode}`);
  }

  /**
   * 通过当前 ability 的 configuration 判断是否为深色模式
   * UIAbility 自带的 configuration 有 colorMode 字段
   */
  private isConfigurationDark(): boolean {
    try {
      const cfg = this.context.config as Configuration;
      if (cfg && typeof cfg.colorMode === 'number') {
        return cfg.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
    } catch (e) {
      appLogger.warn(`EntryAbility: isConfigurationDark failed: ${e}`);
    }
    return true; // fallback：默认深色
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    appLogger.info(`EntryAbility: onConfigurationUpdate colorMode=${newConfig.colorMode}`);
    const settings = SettingsStore.getInstance().getSettings();
    if (settings.theme === 'system') {
      this.applyThemeMode('system');
    }
  }

  onDestroy(): void {
    appLogger.info('EntryAbility onDestroy');
    if (this.settingsChangeListener) {
      SettingsStore.getInstance().removeOnSettingsChange(this.settingsChangeListener);
      this.settingsChangeListener = null;
    }
    PlayerController.getInstance().release().catch((err: Object) => {
      appLogger.error('Release player failed: ' + JSON.stringify(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    appLogger.info('EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        appLogger.error('Failed to load content: ' + JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    appLogger.info('EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    appLogger.info('EntryAbility onForeground');
    this.applyThemeFromSettings();
  }

  onBackground(): void {
    appLogger.info('EntryAbility onBackground');
  }
}

export { ThemeColors, LightThemeColors };
