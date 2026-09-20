import { AppConstants } from '../constants/AppConstants';
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

  /** 模式切换回调（UI 层订阅） */
  onModeChange?: (mode: AppMode) => void;

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
    if (this.onModeChange) {
      this.onModeChange(mode);
    }
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
