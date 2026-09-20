import { preferences } from '@kit.ArkData';
import { UserSettings } from '../model/UserSettings';
import { AppConstants } from '../constants/AppConstants';
import { CallbackList } from '../utils/CallbackList';
import appLogger from '../utils/Logger';

type Preferences = preferences.Preferences;

/**
 * 默认用户设置
 */
const defaultSettings: UserSettings = {
  defaultMode: 'driving',
  defaultSpeed: 1.0,
  showRomaji: true,
  showTranslation: true,
  theme: 'dark'
};

/**
 * 深拷贝设置对象（ArkTS 不支持对象展开语法）
 */
function cloneSettings(source: UserSettings): UserSettings {
  return JSON.parse(JSON.stringify(source)) as UserSettings;
}

/**
 * 设置存储
 * 基于 Preferences 持久化用户设置数据
 * 单例模式，需先调用 init(context) 初始化
 */
export class SettingsStore {
  private static instance: SettingsStore | null = null;
  private prefs: Preferences | null = null;
  private settings: UserSettings = cloneSettings(defaultSettings);

  private settingsChangeListeners: CallbackList<(settings: UserSettings) => void> =
    new CallbackList<(settings: UserSettings) => void>();

  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns SettingsStore 实例
   */
  static getInstance(): SettingsStore {
    if (!SettingsStore.instance) {
      SettingsStore.instance = new SettingsStore();
    }
    return SettingsStore.instance;
  }

  /**
   * 初始化（传入 context）
   * @param context 应用上下文
   */
  async init(context: Context): Promise<void> {
    try {
      const prefsName = AppConstants.STORAGE_KEYS.settings;
      this.prefs = await preferences.getPreferences(context, prefsName);
      appLogger.info(`SettingsStore: initialized with prefs "${prefsName}"`);
      await this.load();
    } catch (error) {
      appLogger.error('SettingsStore: init failed', error);
      this.settings = cloneSettings(defaultSettings);
    }
  }

  /**
   * 获取当前设置
   * @returns 用户设置
   */
  getSettings(): UserSettings {
    return cloneSettings(this.settings);
  }

  addOnSettingsChange(callback: (settings: UserSettings) => void): void {
    this.settingsChangeListeners.add(callback);
  }

  removeOnSettingsChange(callback: (settings: UserSettings) => void): void {
    this.settingsChangeListeners.remove(callback);
  }

  /**
   * 设置默认播放模式
   * @param mode 模式：driving / parked
   */
  async setDefaultMode(mode: 'driving' | 'parked'): Promise<void> {
    try {
      if (this.settings.defaultMode === mode) {
        return;
      }
      this.settings.defaultMode = mode;
      appLogger.info(`SettingsStore: defaultMode -> ${mode}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: setDefaultMode failed', error);
    }
  }

  /**
   * 设置默认播放速度
   * @param speed 播放速度倍率
   */
  async setDefaultSpeed(speed: number): Promise<void> {
    try {
      if (this.settings.defaultSpeed === speed) {
        return;
      }
      this.settings.defaultSpeed = speed;
      appLogger.info(`SettingsStore: defaultSpeed -> ${speed}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: setDefaultSpeed failed', error);
    }
  }

  /**
   * 设置是否显示罗马音
   * @param value 是否显示
   */
  async setShowRomaji(value: boolean): Promise<void> {
    try {
      if (this.settings.showRomaji === value) {
        return;
      }
      this.settings.showRomaji = value;
      appLogger.info(`SettingsStore: showRomaji -> ${value}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: setShowRomaji failed', error);
    }
  }

  /**
   * 设置是否显示中文翻译
   * @param value 是否显示
   */
  async setShowTranslation(value: boolean): Promise<void> {
    try {
      if (this.settings.showTranslation === value) {
        return;
      }
      this.settings.showTranslation = value;
      appLogger.info(`SettingsStore: showTranslation -> ${value}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: setShowTranslation failed', error);
    }
  }

  /**
   * 设置主题模式
   * @param theme 主题：dark / light / system
   */
  async setTheme(theme: 'dark' | 'light' | 'system'): Promise<void> {
    try {
      if (this.settings.theme === theme) {
        return;
      }
      this.settings.theme = theme;
      appLogger.info(`SettingsStore: theme -> ${theme}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: setTheme failed', error);
    }
  }

  // ============== 私有方法 ==============

  /**
   * 保存设置到 Preferences
   */
  private async save(): Promise<void> {
    if (!this.prefs) {
      appLogger.warn('SettingsStore: save called but prefs is null');
      return;
    }

    try {
      const jsonStr = JSON.stringify(this.settings);
      await this.prefs.put('data', jsonStr);
      await this.prefs.flush();
      appLogger.debug('SettingsStore: saved');
    } catch (error) {
      appLogger.error('SettingsStore: save failed', error);
      throw error as Error;
    }
  }

  /**
   * 从 Preferences 加载设置
   */
  private async load(): Promise<void> {
    if (!this.prefs) {
      appLogger.warn('SettingsStore: load called but prefs is null');
      return;
    }

    try {
      const raw = await this.prefs.get('data', '');
      const jsonStr = raw as string;
      if (jsonStr && jsonStr.length > 0) {
        const loaded = JSON.parse(jsonStr) as UserSettings;
        // 合并默认值，确保新增字段有默认值
        const merged: UserSettings = {
          defaultMode: loaded.defaultMode ?? defaultSettings.defaultMode,
          defaultSpeed: loaded.defaultSpeed ?? defaultSettings.defaultSpeed,
          showRomaji: loaded.showRomaji ?? defaultSettings.showRomaji,
          showTranslation: loaded.showTranslation ?? defaultSettings.showTranslation,
          theme: loaded.theme ?? defaultSettings.theme
        };
        this.settings = merged;
        appLogger.info(`SettingsStore: loaded, theme=${this.settings.theme}`);
      } else {
        this.settings = cloneSettings(defaultSettings);
        appLogger.info('SettingsStore: no saved data, using defaults');
      }
      this.notifyChange();
    } catch (error) {
      appLogger.error('SettingsStore: load failed, using defaults', error);
      this.settings = cloneSettings(defaultSettings);
    }
  }

  /**
   * 通知设置变化
   */
  private notifyChange(): void {
    const snapshot: UserSettings = cloneSettings(this.settings);
    this.settingsChangeListeners.notify((callback: (settings: UserSettings) => void) => {
      callback(snapshot);
    });
  }
}
