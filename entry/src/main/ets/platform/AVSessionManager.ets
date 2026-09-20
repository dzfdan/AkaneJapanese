import { avSession } from '@kit.AVSessionKit';
import appLogger from '../utils/Logger';

/**
 * 媒体会话管理器
 * 封装 AVSessionKit，让应用支持后台播放和系统播控中心控制
 * 单例模式
 *
 * 功能：
 * - 创建 audio 类型的 AVSession
 * - 更新播放状态（播放/暂停/停止 + 进度 + 速度）
 * - 更新媒体元数据（标题/艺术家/专辑/时长）
 * - 监听系统播控中心的控制命令并回调给上层
 */
export class AVSessionManager {
  private static instance: AVSessionManager | null = null;
  private session: avSession.AVSession | null = null;
  private context: Context | null = null;
  private isInitialized: boolean = false;

  // ======== 播放控制回调（系统播控中心的操作会回调到这里） ========

  /** 播放命令回调 */
  onPlay?: () => void;
  /** 暂停命令回调 */
  onPause?: () => void;
  /** 停止命令回调 */
  onStop?: () => void;
  /** 下一曲命令回调 */
  onSkipToNext?: () => void;
  /** 上一曲命令回调 */
  onSkipToPrevious?: () => void;
  /** 跳转进度命令回调（timeMs 为目标时间毫秒） */
  onSeek?: (timeMs: number) => void;

  /**
   * 获取单例实例
   */
  static getInstance(): AVSessionManager {
    if (!AVSessionManager.instance) {
      AVSessionManager.instance = new AVSessionManager();
    }
    return AVSessionManager.instance;
  }

  private constructor() {}

  /**
   * 初始化 AVSession
   * @param context UIAbility 的 Context
   */
  async init(context: Context): Promise<void> {
    if (this.isInitialized) {
      appLogger.warn('AVSessionManager: already initialized, skip');
      return;
    }

    try {
      this.context = context;

      // 1. 创建 audio 类型的会话
      this.session = await avSession.createAVSession(context, 'audio');
      appLogger.info('AVSessionManager: AVSession created');

      // 2. 设置初始元数据
      await this.session.setAVMetadata({
        title: '',
        artist: '',
        album: '',
        duration: 0
      });

      // 3. 设置初始播放状态
      await this.session.setPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_STOPPED,
        position: 0,
        speed: 1.0
      });

      // 4. 注册控制命令回调
      this.registerControlCallbacks();

      // 5. 激活会话
      await this.session.activate();
      this.isInitialized = true;
      appLogger.info('AVSessionManager: AVSession activated');
    } catch (error) {
      appLogger.error('AVSessionManager: init failed', error);
      this.session = null;
      throw error;
    }
  }

  /**
   * 更新播放状态
   * @param state 播放状态：playing / paused / stopped
   * @param positionMs 当前播放位置（毫秒）
   * @param speed 播放速度（如 1.0, 0.75, 1.25）
   */
  async updatePlaybackState(
    state: 'playing' | 'paused' | 'stopped',
    positionMs: number,
    speed: number
  ): Promise<void> {
    if (!this.session || !this.isInitialized) {
      return;
    }

    try {
      let playbackState: avSession.PlaybackState;
      switch (state) {
        case 'playing':
          playbackState = avSession.PlaybackState.PLAYBACK_STATE_PLAYING;
          break;
        case 'paused':
          playbackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSED;
          break;
        case 'stopped':
        default:
          playbackState = avSession.PlaybackState.PLAYBACK_STATE_STOPPED;
          break;
      }

      await this.session.setPlaybackState({
        state: playbackState,
        position: positionMs,
        speed: speed
      });

      appLogger.debug(
        `AVSessionManager: updatePlaybackState state=${state}, position=${positionMs}ms, speed=${speed}`
      );
    } catch (error) {
      appLogger.error('AVSessionManager: updatePlaybackState failed', error);
    }
  }

  /**
   * 更新媒体元数据（在系统播控中心显示）
   * @param title 标题
   * @param artist 艺术家
   * @param album 专辑
   * @param durationMs 总时长（毫秒）
   */
  async updateMetadata(
    title: string,
    artist: string,
    album: string,
    durationMs: number
  ): Promise<void> {
    if (!this.session || !this.isInitialized) {
      return;
    }

    try {
      await this.session.setAVMetadata({
        title: title,
        artist: artist,
        album: album,
        duration: durationMs
      });

      appLogger.debug(
        `AVSessionManager: updateMetadata title="${title}", artist="${artist}", duration=${durationMs}ms`
      );
    } catch (error) {
      appLogger.error('AVSessionManager: updateMetadata failed', error);
    }
  }

  /**
   * 释放会话资源
   * 取消激活并销毁 AVSession
   */
  async release(): Promise<void> {
    if (!this.session) {
      return;
    }

    try {
      // 取消激活
      if (this.isInitialized) {
        await this.session.deactivate();
        this.isInitialized = false;
        appLogger.info('AVSessionManager: AVSession deactivated');
      }

      // 销毁会话
      await this.session.destroy();
      this.session = null;
      this.context = null;
      appLogger.info('AVSessionManager: AVSession destroyed');
    } catch (error) {
      appLogger.error('AVSessionManager: release failed', error);
    }
  }

  // ============== 私有方法 ==============

  /**
   * 注册系统播控中心的控制命令回调
   * 注意：HarmonyOS AVSession 的控制命令事件名
   * - play / pause / stop
   * - skipToNext / skipToPrevious
   * - seekTo（回调参数为毫秒时间戳）
   */
  private registerControlCallbacks(): void {
    if (!this.session) {
      return;
    }

    // 播放
    this.session.on('play', () => {
      appLogger.info('AVSessionManager: received play command from system');
      this.onPlay?.();
    });

    // 暂停
    this.session.on('pause', () => {
      appLogger.info('AVSessionManager: received pause command from system');
      this.onPause?.();
    });

    // 停止
    this.session.on('stop', () => {
      appLogger.info('AVSessionManager: received stop command from system');
      this.onStop?.();
    });

    // 下一曲
    this.session.on('skipToNext', () => {
      appLogger.info('AVSessionManager: received skipToNext command from system');
      this.onSkipToNext?.();
    });

    // 上一曲
    this.session.on('skipToPrevious', () => {
      appLogger.info('AVSessionManager: received skipToPrevious command from system');
      this.onSkipToPrevious?.();
    });

    // 跳转进度
    // NOTE: seekTo 回调参数为毫秒时间戳（HarmonyOS API 26）
    this.session.on('seekTo', (timeMs: number) => {
      appLogger.info(`AVSessionManager: received seekTo command from system, time=${timeMs}ms`);
      this.onSeek?.(timeMs);
    });
  }
}
