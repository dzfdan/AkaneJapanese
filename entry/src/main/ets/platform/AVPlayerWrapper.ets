import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import appLogger from '../utils/Logger';

/**
 * 播放器状态类型
 */
export type PlayerState = 'idle' | 'initialized' | 'prepared' | 'playing' | 'paused' | 'completed' | 'stopped' | 'released';

/**
 * 播放器事件回调接口
 */
export interface AVPlayerCallbacks {
  /** 状态变化回调 */
  onStateChange?: (state: PlayerState) => void;
  /** 播放进度更新回调（单位：毫秒） */
  onTimeUpdate?: (currentTimeMs: number) => void;
  /** 时长更新回调（单位：毫秒） */
  onDurationUpdate?: (durationMs: number) => void;
  /** 错误回调 */
  onError?: (error: Error) => void;
  /** 音频中断回调（透传系统 InterruptEvent 对象） */
  onAudioInterrupt?: (event: audio.InterruptEvent) => void;
}

/**
 * 状态等待器（用于 waitForState）
 */
interface StateWaiter {
  target: PlayerState;
  resolve: () => void;
  reject: (e: Error) => void;
}

/**
 * AVPlayer 封装类
 * 对鸿蒙系统 AVPlayer 进行封装，提供更易用的接口
 * 注意：AVPlayer 是状态机驱动，必须按状态顺序操作
 *
 * 状态流转：
 * idle -> initialized -> prepared -> playing <-> paused
 *                          |              |
 *                          v              v
 *                       stopped       completed
 *                          |              |
 *                          +----> idle <--+
 *                                   |
 *                                   v
 *                                released
 */
export class AVPlayerWrapper {
  private player: media.AVPlayer | null = null;
  private _state: PlayerState = 'idle';
  private _currentTimeMs: number = 0;
  private _durationMs: number = 0;
  private callbacks: AVPlayerCallbacks = {};
  private stateWaiters: StateWaiter[] = [];

  /**
   * 获取当前播放器状态
   */
  get state(): PlayerState {
    return this._state;
  }

  /**
   * 获取缓存的当前播放时间（毫秒）
   */
  getCurrentTime(): number {
    return this._currentTimeMs;
  }

  /**
   * 获取缓存的总时长（毫秒）
   */
  getDuration(): number {
    return this._durationMs;
  }

  /**
   * 设置事件回调
   * @param callbacks 回调对象
   */
  setCallbacks(callbacks: AVPlayerCallbacks): void {
    this.callbacks = callbacks;
  }

  /**
   * 设置文件描述符源
   * @param fd 文件描述符
   * @param offset 偏移量（字节）
   * @param length 长度（字节）
   */
  async setFdSource(fd: number, offset?: number, length?: number): Promise<void> {
    try {
      if (!this.player) {
        this.player = await media.createAVPlayer();
        this.bindPlayerEvents();
      }

      if (this._state === 'released') {
        throw new Error('Player has been released');
      }

      // 重置到 idle 状态以设置新源
      if (this._state !== 'idle') {
        await this.reset();
        await this.waitForState('idle');
      }

      if (offset !== undefined && length !== undefined) {
        this.player.fdSrc = {
          fd: fd,
          offset: offset,
          length: length
        };
      } else {
        this.player.fdSrc = { fd: fd };
      }

      // 等待 AVPlayer 内部状态真正变为 initialized（异步事件驱动）
      await this.waitForState('initialized');
      appLogger.debug(`AVPlayerWrapper: setFdSource done, state=${this._state}`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: setFdSource failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 准备播放
   */
  async prepare(): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state !== 'initialized') {
        throw new Error(`Invalid state for prepare: ${this._state}`);
      }

      await this.player.prepare();
      // 等待 AVPlayer 内部状态真正变为 prepared
      await this.waitForState('prepared');
      appLogger.debug(`AVPlayerWrapper: prepare done, state=${this._state}`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: prepare failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 开始播放
   */
  async play(): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      // 容错：若仍在 initialized（prepare 事件未及时更新状态），补一次 prepare
      if (this._state === 'initialized') {
        appLogger.warn(`AVPlayerWrapper: play called in initialized state, doing prepare first`);
        await this.player.prepare();
        this._state = 'prepared';
      }
      if (this._state !== 'prepared' && this._state !== 'paused' && this._state !== 'completed') {
        throw new Error(`Invalid state for play: ${this._state}`);
      }

      await this.player.play();
      this._state = 'playing';
      this.notifyStateChange();
      appLogger.debug(`AVPlayerWrapper: play done, state=${this._state}`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: play failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 暂停播放
   */
  async pause(): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state !== 'playing') {
        appLogger.warn(`AVPlayerWrapper: pause called in state ${this._state}, ignored`);
        return;
      }

      await this.player.pause();
      this._state = 'paused';
      this.notifyStateChange();
      appLogger.debug(`AVPlayerWrapper: pause done, state=${this._state}`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: pause failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 停止播放
   */
  async stop(): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state === 'idle' || this._state === 'stopped' || this._state === 'released') {
        appLogger.warn(`AVPlayerWrapper: stop called in state ${this._state}, ignored`);
        return;
      }

      await this.player.stop();
      this._state = 'stopped';
      this.notifyStateChange();
      appLogger.debug(`AVPlayerWrapper: stop done, state=${this._state}`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: stop failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 重置播放器（回到 idle 状态）
   */
  async reset(): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state === 'released') {
        throw new Error('Player has been released');
      }

      await this.player.reset();
      this._currentTimeMs = 0;
      this._durationMs = 0;
      appLogger.debug(`AVPlayerWrapper: reset called, waiting for idle`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: reset failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 释放播放器资源
   */
  async release(): Promise<void> {
    try {
      if (!this.player) {
        appLogger.warn('AVPlayerWrapper: release called but player is null');
        return;
      }
      if (this._state === 'released') {
        return;
      }

      this.unbindPlayerEvents();
      await this.player.release();
      this.player = null;
      this._state = 'released';
      this._currentTimeMs = 0;
      this._durationMs = 0;
      this.notifyStateChange();
      appLogger.debug(`AVPlayerWrapper: released`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: release failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 跳转到指定时间
   * @param timeMs 目标时间（毫秒）
   */
  async seek(timeMs: number): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state !== 'prepared' && this._state !== 'playing'
        && this._state !== 'paused' && this._state !== 'completed') {
        throw new Error(`Invalid state for seek: ${this._state}`);
      }

      // 使用 seek 模式（鸿蒙 AVPlayer 的 seek 方法接收毫秒参数）
      await this.player.seek(timeMs, media.SeekMode.SEEK_NEXT_SYNC);
      appLogger.debug(`AVPlayerWrapper: seek to ${timeMs}ms`);
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: seek failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 设置播放速度
   * @param speed 播放速度（如 0.75, 1.0, 1.25）
   */
  async setSpeed(speed: number): Promise<void> {
    try {
      if (!this.player) {
        throw new Error('Player not created');
      }
      if (this._state !== 'playing' && this._state !== 'paused') {
        appLogger.warn(`AVPlayerWrapper: setSpeed called in state ${this._state}, will apply after play`);
      }

      // 将 speed 数值映射为 PlaybackSpeed 枚举
      const playbackSpeed = this.mapSpeedToEnum(speed);
      if (playbackSpeed !== undefined) {
        await this.player.setSpeed(playbackSpeed);
        appLogger.debug(`AVPlayerWrapper: setSpeed to ${speed}`);
      } else {
        appLogger.warn(`AVPlayerWrapper: unsupported speed ${speed}`);
      }
    } catch (error) {
      appLogger.error(`AVPlayerWrapper: setSpeed failed`, error);
      this.notifyError(error as Error);
      throw error as Error;
    }
  }

  /**
   * 将速度数值映射为鸿蒙 PlaybackSpeed 枚举
   */
  private mapSpeedToEnum(speed: number): media.PlaybackSpeed | undefined {
    switch (speed) {
      case 0.75:
        return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
      case 1.0:
        return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
      case 1.25:
        return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
      case 1.75:
        return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
      case 2.0:
        return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
      default:
        return undefined;
    }
  }

  /**
   * 绑定播放器事件
   */
  private bindPlayerEvents(): void {
    if (!this.player) {
      return;
    }

    // 状态变化事件
    this.player.on('stateChange', (state: string) => {
      const mappedState = this.mapState(state);
      if (mappedState) {
        this._state = mappedState;
        this.notifyStateChange();
        appLogger.debug(`AVPlayerWrapper: state changed to ${this._state}`);
      }
    });

    // 时间更新事件
    this.player.on('timeUpdate', (time: number) => {
      // timeUpdate 的回调参数单位为秒，转换为毫秒
      this._currentTimeMs = Math.floor(time * 1000);
      if (this.callbacks.onTimeUpdate) {
        this.callbacks.onTimeUpdate(this._currentTimeMs);
      }
    });

    // 时长更新事件
    this.player.on('durationUpdate', (duration: number) => {
      // durationUpdate 的回调参数单位为秒，转换为毫秒
      this._durationMs = Math.floor(duration * 1000);
      if (this.callbacks.onDurationUpdate) {
        this.callbacks.onDurationUpdate(this._durationMs);
      }
    });

    // 错误事件
    this.player.on('error', (err: Error) => {
      appLogger.error(`AVPlayerWrapper: error event`, err);
      this.notifyError(err);
    });

    // 音频中断事件（透传系统 InterruptEvent，由 PlayerController 用官方枚举解析）
    this.player.on('audioInterrupt', (interruptInfo: audio.InterruptEvent) => {
      appLogger.info(`AVPlayerWrapper: audioInterrupt, hintType=${interruptInfo.hintType}, forceType=${interruptInfo.forceType}`);
      if (this.callbacks.onAudioInterrupt) {
        this.callbacks.onAudioInterrupt(interruptInfo);
      }
    });
  }

  /**
   * 解绑播放器事件
   */
  private unbindPlayerEvents(): void {
    if (!this.player) {
      return;
    }
    try {
      this.player.off('stateChange');
      this.player.off('timeUpdate');
      this.player.off('durationUpdate');
      this.player.off('error');
      this.player.off('audioInterrupt');
    } catch (e) {
      appLogger.warn('AVPlayerWrapper: unbind events failed', e);
    }
  }

  /**
   * 将系统状态字符串映射为 PlayerState
   */
  private mapState(state: string): PlayerState | null {
    switch (state) {
      case 'idle':
        return 'idle';
      case 'initialized':
        return 'initialized';
      case 'prepared':
        return 'prepared';
      case 'playing':
        return 'playing';
      case 'paused':
        return 'paused';
      case 'completed':
        return 'completed';
      case 'stopped':
        return 'stopped';
      case 'released':
        return 'released';
      default:
        appLogger.warn(`AVPlayerWrapper: unknown state ${state}`);
        return null;
    }
  }

  /**
   * 通知状态变化
   */
  /**
   * 等待播放器状态变为指定状态
   * 依赖 stateChange 事件驱动，避免在异步状态转换未完成时执行下一步操作
   */
  private waitForState(target: PlayerState, timeoutMs: number = 5000): Promise<void> {
    if (this._state === target) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(`Timeout waiting for state ${target}, current=${this._state}`));
      }, timeoutMs);
      const waiter: StateWaiter = {
        target: target,
        resolve: (): void => {
          clearTimeout(timer);
          resolve();
        },
        reject: (e: Error): void => {
          clearTimeout(timer);
          reject(e);
        }
      };
      this.stateWaiters.push(waiter);
    });
  }

  private notifyStateChange(): void {
    // 唤醒所有等待该状态的 Promise
    const remaining: StateWaiter[] = [];
    for (const waiter of this.stateWaiters) {
      if (waiter.target === this._state) {
        waiter.resolve();
      } else {
        remaining.push(waiter);
      }
    }
    this.stateWaiters = remaining;

    if (this.callbacks.onStateChange) {
      this.callbacks.onStateChange(this._state);
    }
  }

  /**
   * 通知错误
   */
  private notifyError(error: Error): void {
    if (this.callbacks.onError) {
      this.callbacks.onError(error);
    }
  }
}
