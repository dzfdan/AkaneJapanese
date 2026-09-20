import { AppConstants } from '../constants/AppConstants';
import { CallbackList } from '../utils/CallbackList';
import appLogger from '../utils/Logger';

/**
 * 应用模式类型
 * - driving: 驾驶模式，大字体、语音优先、操作简化
 * - parked: 驻车模式，正常界面，支持交互学习
 */
export type AppMode = 'driving' | 'parked';

/**
 * 双模式管理器
 * 管理驾驶模式与驻车模式的切换
 * MVP 阶段不持久化偏好，设置页时再加
 */
export class ModeManager {
  private static instance: ModeManager | null = null;
  private currentMode: AppMode = AppConstants.DEFAULT_MODE;

  private modeChangeListeners: CallbackList<(mode: AppMode) => void> =
    new CallbackList<(mode: AppMode) => void>();

  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns ModeManager 实例
   */
  static getInstance(): ModeManager {
    if (!ModeManager.instance) {
      ModeManager.instance = new ModeManager();
    }
    return ModeManager.instance;
  }

  /**
   * 订阅模式变化（支持多个订阅者，需与 removeOnModeChange 成对使用）
   * @param callback 模式变化回调
   */
  addOnModeChange(callback: (mode: AppMode) => void): void {
    this.modeChangeListeners.add(callback);
  }

  /**
   * 取消订阅模式变化
   * @param callback 已注册的回调
   */
  removeOnModeChange(callback: (mode: AppMode) => void): void {
    this.modeChangeListeners.remove(callback);
  }

  /**
   * 获取当前模式
   * @returns 当前应用模式
   */
  getMode(): AppMode {
    return this.currentMode;
  }

  /**
   * 设置模式
   * 驻车模式切换的确认逻辑由 UI 层处理，此处只管切换
   * @param mode 目标模式
   */
  setMode(mode: AppMode): void {
    if (this.currentMode === mode) {
      return;
    }
    this.currentMode = mode;
    appLogger.info(`ModeManager: mode changed to ${mode}`);
    this.modeChangeListeners.notify((callback: (mode: AppMode) => void) => {
      callback(mode);
    });
  }

  /**
   * 切换模式（驾驶 <-> 驻车）
   */
  toggleMode(): void {
    const newMode: AppMode = this.currentMode === 'driving' ? 'parked' : 'driving';
    this.setMode(newMode);
  }

  /**
   * 是否为驾驶模式
   * @returns true 表示驾驶模式
   */
  isDrivingMode(): boolean {
    return this.currentMode === 'driving';
  }
}
