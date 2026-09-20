/**
 * 用户设置数据模型
 */
export interface UserSettings {
  /** 默认播放模式：驾驶模式 / 停车模式 */
  defaultMode: 'driving' | 'parked';
  /** 默认播放速度倍率（如 1.0 为正常速，0.7 为慢速） */
  defaultSpeed: number;
  /** 是否显示罗马音 */
  showRomaji: boolean;
  /** 是否显示中文翻译 */
  showTranslation: boolean;
  /** 主题模式：深色 / 浅色 / 跟随系统 */
  theme: 'dark' | 'light' | 'system';
}
