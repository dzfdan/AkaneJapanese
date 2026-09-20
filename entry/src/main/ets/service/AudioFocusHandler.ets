import appLogger from '../utils/Logger';

/**
 * 音频焦点变化提示类型
 */
export type InterruptHint = 'pause' | 'resume' | 'stop' | 'duck' | 'unduck';

/**
 * 音频焦点事件
 * 由 PlayerController 将 AVPlayer 的 audioInterrupt 原始事件转换后传入
 */
export interface AudioFocusEvent {
  /** 焦点变化提示 */
  hint: InterruptHint;
  /** 是否系统强制处理（系统已自动暂停/恢复，上层只需同步状态） */
  force: boolean;
}

/**
 * 音频焦点处理器
 * 封装音频焦点的业务逻辑，统一处理来自系统的音频中断事件
 * 单例模式
 *
 * 职责：
 * - 接收 PlayerController 转换后的 AudioFocusEvent
 * - 根据 hint 类型分发到对应的回调
 * - 管理 duck（压低音量）状态
 * - 区分系统强制处理和自主处理，避免重复操作
 *
 * 使用方式：
 * 1. PlayerController 收到 AVPlayer 的 audioInterrupt 事件
 * 2. PlayerController 将 InterruptEvent 转换为 AudioFocusEvent
 * 3. 调用 AudioFocusHandler.handleInterrupt(event)
 * 4. AudioFocusHandler 通过回调通知上层（PlayerController）执行对应操作
 */
export class AudioFocusHandler {
  private static instance: AudioFocusHandler | null = null;
  private isDucked: boolean = false;

  // ======== 焦点变化回调（通知上层处理） ========

  /** 暂停播放回调 */
  onPause?: () => void;
  /** 恢复播放回调 */
  onResume?: () => void;
  /** 停止播放回调 */
  onStop?: () => void;
  /**
   * 压低音量回调（可选）
   * 系统通常会自动处理音量压低，此回调主要用于 UI 状态更新
   */
  onDuck?: () => void;
  /**
   * 恢复音量回调
   * 对应 duck 的恢复，系统通常自动处理
   */
  onUnduck?: () => void;

  /**
   * 获取单例实例
   */
  static getInstance(): AudioFocusHandler {
    if (!AudioFocusHandler.instance) {
      AudioFocusHandler.instance = new AudioFocusHandler();
    }
    return AudioFocusHandler.instance;
  }

  private constructor() {}

  /**
   * 处理音频焦点事件
   * 由 PlayerController 在收到 AVPlayer 的 audioInterrupt 事件后调用
   *
   * @param event 转换后的音频焦点事件
   */
  handleInterrupt(event: AudioFocusEvent): void {
    appLogger.info(`AudioFocusHandler: hint=${event.hint}, force=${event.force}`);

    switch (event.hint) {
      case 'duck':
        this.isDucked = true;
        this.onDuck?.();
        break;

      case 'unduck':
        this.isDucked = false;
        this.onUnduck?.();
        break;

      case 'pause':
        // 系统强制暂停时，系统已自动暂停音频，上层只需同步 UI 状态
        // 非强制暂停时，需要上层主动调用 pause
        if (!event.force) {
          this.onPause?.();
        }
        break;

      case 'resume':
        // 恢复播放通常由应用自主决定
        // 即使是系统触发的 resume，也交给上层处理
        this.onResume?.();
        break;

      case 'stop':
        // 停止播放，通常是失去音频焦点且不会恢复
        this.onStop?.();
        break;

      default:
        appLogger.warn(`AudioFocusHandler: unknown hint ${event.hint}`);
        break;
    }
  }

  /**
   * 查询当前是否处于压低音量（duck）状态
   */
  isVolumeDucked(): boolean {
    return this.isDucked;
  }
}
