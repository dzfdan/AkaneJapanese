import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { Scene } from '../model/Scene';
import { Dialogue } from '../model/Dialogue';
import { Sentence } from '../model/Sentence';
import { AVPlayerWrapper } from '../platform/AVPlayerWrapper';
import { AVSessionManager } from '../platform/AVSessionManager';
import { BackgroundTaskManager } from '../platform/BackgroundTaskManager';
import { AudioFocusHandler, AudioFocusEvent, InterruptHint } from './AudioFocusHandler';
import { SceneRepository } from './SceneRepository';
import { ProgressStore } from './ProgressStore';
import { CallbackList } from '../utils/CallbackList';
import { AppConstants } from '../constants/AppConstants';
import appLogger from '../utils/Logger';

/**
 * 播放器 UI 状态（供 UI 层订阅展示）
 */
export interface PlayerUiState {
  isPlaying: boolean;
  sceneId: string | null;
  sceneTitle: string;
  dialogueIndex: number;
  dialogueTitle: string;
  sentenceIndex: number;
  currentSentence: Sentence | null;
  currentTimeMs: number;
  durationMs: number;
  speed: number;
  isSlowMode: boolean;
}

/**
 * 播放控制器
 * 管理 AVPlayerWrapper 和播放状态，提供场景/对话/句子级别的播放控制
 * 单例模式
 */
type StateChangeCallback = (state: PlayerUiState) => void;
type TimeUpdateCallback = (currentTimeMs: number, durationMs: number) => void;
type SentenceChangeCallback = (sentence: Sentence) => void;
type SentenceEndCallback = (sentence: Sentence) => void;
type ErrorCallback = (message: string) => void;

export class PlayerController {
  private static instance: PlayerController | null = null;
  private player: AVPlayerWrapper;
  private currentScene: Scene | null = null;
  private currentDialogueIndex: number = 0;
  private currentSentenceIndex: number = 0;
  private isSlowMode: boolean = false;
  private playbackSpeed: number = AppConstants.DEFAULT_SPEED;
  private currentTimeMs: number = 0;
  private durationMs: number = 0;
  private isPlaying: boolean = false;

  private stateChangeListeners: CallbackList<StateChangeCallback> = new CallbackList<StateChangeCallback>();
  private timeUpdateListeners: CallbackList<TimeUpdateCallback> = new CallbackList<TimeUpdateCallback>();
  private sentenceChangeListeners: CallbackList<SentenceChangeCallback> = new CallbackList<SentenceChangeCallback>();
  private sentenceEndListeners: CallbackList<SentenceEndCallback> = new CallbackList<SentenceEndCallback>();
  private errorListeners: CallbackList<ErrorCallback> = new CallbackList<ErrorCallback>();
  // playSentenceAndNotify 模式标记：仅在此模式下检测句子结束并触发 onSentenceEnd
  private sentenceNotifyActive: boolean = false;

  private constructor() {
    this.player = new AVPlayerWrapper();
    this.bindPlayerCallbacks();
  }

  /**
   * 获取单例实例
   * @returns PlayerController 实例
   */
  static getInstance(): PlayerController {
    if (!PlayerController.instance) {
      PlayerController.instance = new PlayerController();
    }
    return PlayerController.instance;
  }

  addOnStateChange(callback: StateChangeCallback): void {
    this.stateChangeListeners.add(callback);
  }

  removeOnStateChange(callback: StateChangeCallback): void {
    this.stateChangeListeners.remove(callback);
  }

  addOnTimeUpdate(callback: TimeUpdateCallback): void {
    this.timeUpdateListeners.add(callback);
  }

  removeOnTimeUpdate(callback: TimeUpdateCallback): void {
    this.timeUpdateListeners.remove(callback);
  }

  addOnSentenceChange(callback: SentenceChangeCallback): void {
    this.sentenceChangeListeners.add(callback);
  }

  removeOnSentenceChange(callback: SentenceChangeCallback): void {
    this.sentenceChangeListeners.remove(callback);
  }

  addOnError(callback: ErrorCallback): void {
    this.errorListeners.add(callback);
  }

  removeOnError(callback: ErrorCallback): void {
    this.errorListeners.remove(callback);
  }

  addOnSentenceEnd(callback: SentenceEndCallback): void {
    this.sentenceEndListeners.add(callback);
  }

  removeOnSentenceEnd(callback: SentenceEndCallback): void {
    this.sentenceEndListeners.remove(callback);
  }

  /**
   * 初始化播放器控制器
   * 初始化 AVSession、BackgroundTaskManager 和 AudioFocusHandler
   * @param context UIAbility 的 Context
   */
  static async init(context: Context): Promise<void> {
    try {
      await AVSessionManager.getInstance().init(context);
      BackgroundTaskManager.getInstance().init(context);

      const controller = PlayerController.getInstance();
      controller.bindAVSessionCallbacks();
      controller.bindAudioFocusCallbacks();
      appLogger.info('PlayerController: init completed');
    } catch (error) {
      appLogger.error('PlayerController: init failed', error);
      throw error as Error;
    }
  }

  /**
   * 播放指定场景的指定对话
   * @param scene 场景对象
   * @param dialogueIndex 对话索引，默认 0
   */
  async playScene(scene: Scene, dialogueIndex: number = 0): Promise<void> {
    try {
      appLogger.info(`PlayerController: playScene ${scene.id}, dialogue=${dialogueIndex}, slowMode=${this.isSlowMode}`);

      this.currentScene = scene;
      this.currentDialogueIndex = this.clampDialogueIndex(dialogueIndex);
      this.currentSentenceIndex = 0;

      // 获取音频 fd
      const audioFile = this.isSlowMode ? scene.audioSlow : scene.audioNormal;
      const fdInfo = await SceneRepository.getInstance().getAudioFd(audioFile);

      // 设置播放器源
      await this.player.setFdSource(fdInfo.fd, fdInfo.offset, fdInfo.length);
      await this.player.prepare();

      // 设置速度
      await this.player.setSpeed(this.playbackSpeed);

      // 获取对话起始时间并 seek
      const startTimeMs = this.getDialogueStartTimeMs(this.currentDialogueIndex);
      await this.player.seek(startTimeMs);

      // 开始播放
      await this.player.play();
      this.isPlaying = true;
      await this.startPlaybackSession();

      // 通知 UI 状态变化
      this.notifyStateChange();
    } catch (error) {
      appLogger.error('PlayerController: playScene failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 开始播放
   */
  async play(): Promise<void> {
    try {
      await this.player.play();
      this.isPlaying = true;
      await this.startPlaybackSession();
      this.notifyStateChange();
    } catch (error) {
      appLogger.error('PlayerController: play failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 暂停播放
   */
  async pause(): Promise<void> {
    this.sentenceNotifyActive = false;
    try {
      await this.player.pause();
      this.isPlaying = false;
      await this.stopPlaybackSession();
      if (this.durationMs > 0) {
        this.recordSceneProgress(Math.floor((this.currentTimeMs / this.durationMs) * 100));
      }
      this.notifyStateChange();
    } catch (error) {
      appLogger.error('PlayerController: pause failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 切换播放/暂停
   */
  async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  /**
   * 跳到下一句
   */
  async nextSentence(): Promise<void> {
    if (!this.currentScene) {
      return;
    }

    const dialogue = this.getCurrentDialogue();
    if (!dialogue) {
      return;
    }

    if (this.currentSentenceIndex < dialogue.sentences.length - 1) {
      // 同一对话内下一句
      this.currentSentenceIndex++;
    } else if (this.currentDialogueIndex < this.currentScene.dialogues.length - 1) {
      // 跳到下一对话的第一句
      this.currentDialogueIndex++;
      this.currentSentenceIndex = 0;
    } else {
      // 已经是最后一句，不做处理
      appLogger.debug('PlayerController: nextSentence reached end');
      return;
    }

    const sentence = this.getCurrentSentence();
    if (sentence) {
      const startTimeMs = this.getSentenceStartTimeMs(sentence);
      await this.player.seek(startTimeMs);
      this.notifySentenceChange(sentence);
      this.notifyStateChange();
    }
  }

  /**
   * 跳到上一句
   */
  async prevSentence(): Promise<void> {
    if (!this.currentScene) {
      return;
    }

    if (this.currentSentenceIndex > 0) {
      // 同一对话内上一句
      this.currentSentenceIndex--;
    } else if (this.currentDialogueIndex > 0) {
      // 跳到上一对话的最后一句
      this.currentDialogueIndex--;
      const prevDialogue = this.getCurrentDialogue();
      if (prevDialogue) {
        this.currentSentenceIndex = prevDialogue.sentences.length - 1;
      }
    } else {
      // 已经是第一句，seek 到开头
      const sentence = this.getCurrentSentence();
      if (sentence) {
        const startTimeMs = this.getSentenceStartTimeMs(sentence);
        await this.player.seek(startTimeMs);
      }
      return;
    }

    const sentence = this.getCurrentSentence();
    if (sentence) {
      const startTimeMs = this.getSentenceStartTimeMs(sentence);
      await this.player.seek(startTimeMs);
      this.notifySentenceChange(sentence);
      this.notifyStateChange();
    }
  }

  /**
   * 跳到下一组对话
   */
  async nextDialogue(): Promise<void> {
    if (!this.currentScene) {
      return;
    }

    if (this.currentDialogueIndex < this.currentScene.dialogues.length - 1) {
      this.currentDialogueIndex++;
      this.currentSentenceIndex = 0;
      const sentence = this.getCurrentSentence();
      if (sentence) {
        const startTimeMs = this.getSentenceStartTimeMs(sentence);
        await this.player.seek(startTimeMs);
        this.notifySentenceChange(sentence);
        this.notifyStateChange();
      }
    }
  }

  /**
   * 跳到上一组对话
   */
  async prevDialogue(): Promise<void> {
    if (!this.currentScene) {
      return;
    }

    if (this.currentDialogueIndex > 0) {
      this.currentDialogueIndex--;
      this.currentSentenceIndex = 0;
      const sentence = this.getCurrentSentence();
      if (sentence) {
        const startTimeMs = this.getSentenceStartTimeMs(sentence);
        await this.player.seek(startTimeMs);
        this.notifySentenceChange(sentence);
        this.notifyStateChange();
      }
    }
  }

  /**
   * 跳转到指定时间
   * @param timeMs 目标时间（毫秒）
   */
  async seekTo(timeMs: number): Promise<void> {
    try {
      await this.player.seek(timeMs);
      // seek 后更新当前句子
      this.updateCurrentSentence(timeMs);
      // 更新 AVSession 播放状态
      const avState: 'playing' | 'paused' | 'stopped' = this.isPlaying ? 'playing' : 'paused';
      AVSessionManager.getInstance().updatePlaybackState(avState, timeMs, this.playbackSpeed).catch((err: Object) => {
        appLogger.error('PlayerController: update AVSession state after seek failed', err);
      });
    } catch (error) {
      appLogger.error('PlayerController: seekTo failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 设置播放速度
   * @param speed 播放速度（0.75 / 1.0 / 1.25）
   */
  async setSpeed(speed: number): Promise<void> {
    try {
      this.playbackSpeed = speed;
      await this.player.setSpeed(speed);
      // 更新 AVSession 播放状态
      const avState: 'playing' | 'paused' | 'stopped' = this.isPlaying ? 'playing' : 'paused';
      AVSessionManager.getInstance().updatePlaybackState(avState, this.currentTimeMs, speed).catch((err: Object) => {
        appLogger.error('PlayerController: update AVSession state after setSpeed failed', err);
      });
      this.notifyStateChange();
    } catch (error) {
      appLogger.error('PlayerController: setSpeed failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 切换慢速模式
   * 切换时保存当前进度，切换音频文件后 seek 到对应位置
   */
  async toggleSlowMode(): Promise<void> {
    if (!this.currentScene) {
      appLogger.warn('PlayerController: toggleSlowMode called without scene');
      return;
    }

    try {
      const wasPlaying = this.isPlaying;

      // 先暂停
      if (wasPlaying) {
        await this.player.pause();
        this.isPlaying = false;
      }

      // 计算当前时间在句子中的相对位置
      const currentSentence = this.getCurrentSentence();
      const currentTimeSec = this.currentTimeMs / 1000;
      let targetTimeMs: number = 0;

      if (currentSentence) {
        let sentenceStart: number;
        let sentenceEnd: number;
        let targetSentenceStart: number;
        let targetSentenceEnd: number;

        if (this.isSlowMode) {
          // 当前是慢速，切换到正常速
          sentenceStart = currentSentence.slowStartTime;
          sentenceEnd = currentSentence.slowEndTime;
          targetSentenceStart = currentSentence.startTime;
          targetSentenceEnd = currentSentence.endTime;
        } else {
          // 当前是正常速，切换到慢速
          sentenceStart = currentSentence.startTime;
          sentenceEnd = currentSentence.endTime;
          targetSentenceStart = currentSentence.slowStartTime;
          targetSentenceEnd = currentSentence.slowEndTime;
        }

        const sentenceDuration = sentenceEnd - sentenceStart;
        const targetSentenceDuration = targetSentenceEnd - targetSentenceStart;

        if (sentenceDuration > 0) {
          // 计算在句子中的相对进度（0-1）
          const progress = (currentTimeSec - sentenceStart) / sentenceDuration;
          const clampedProgress = Math.max(0, Math.min(1, progress));
          targetTimeMs = Math.floor((targetSentenceStart + clampedProgress * targetSentenceDuration) * 1000);
        } else {
          targetTimeMs = Math.floor(targetSentenceStart * 1000);
        }
      } else {
        // 没有当前句子，直接按比例换算
        const ratio = this.durationMs > 0 ? this.currentTimeMs / this.durationMs : 0;
        targetTimeMs = Math.floor(ratio * this.durationMs);
      }

      // 切换慢速模式标记
      this.isSlowMode = !this.isSlowMode;

      // 切换音频源
      const audioFile = this.isSlowMode ? this.currentScene.audioSlow : this.currentScene.audioNormal;
      const fdInfo = await SceneRepository.getInstance().getAudioFd(audioFile);

      await this.player.setFdSource(fdInfo.fd, fdInfo.offset, fdInfo.length);
      await this.player.prepare();
      await this.player.setSpeed(this.playbackSpeed);
      await this.player.seek(targetTimeMs);

      // 如果之前在播放，恢复播放
      if (wasPlaying) {
        await this.player.play();
        this.isPlaying = true;
      }

      appLogger.info(`PlayerController: toggleSlowMode -> slowMode=${this.isSlowMode}, targetTime=${targetTimeMs}ms`);
      this.notifyStateChange();
    } catch (error) {
      appLogger.error('PlayerController: toggleSlowMode failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 播放指定场景的指定对话中的指定句子
   * @param scene 场景对象
   * @param dialogueIndex 对话索引
   * @param sentenceIndex 句子索引
   */
  async playSentence(scene: Scene, dialogueIndex: number, sentenceIndex: number): Promise<void> {
    try {
      // 如果场景不同，先加载场景
      if (!this.currentScene || this.currentScene.id !== scene.id) {
        this.currentScene = scene;
        const audioFile = this.isSlowMode ? scene.audioSlow : scene.audioNormal;
        const fdInfo = await SceneRepository.getInstance().getAudioFd(audioFile);
        await this.player.setFdSource(fdInfo.fd, fdInfo.offset, fdInfo.length);
        await this.player.prepare();
        await this.player.setSpeed(this.playbackSpeed);
      }

      this.currentDialogueIndex = this.clampDialogueIndex(dialogueIndex);

      const dialogue = this.getCurrentDialogue();
      if (!dialogue) {
        throw new Error(`Dialogue at index ${dialogueIndex} not found`);
      }

      this.currentSentenceIndex = Math.max(0, Math.min(sentenceIndex, dialogue.sentences.length - 1));

      const sentence = this.getCurrentSentence();
      if (sentence) {
        const startTimeMs = this.getSentenceStartTimeMs(sentence);
        await this.player.seek(startTimeMs);
        await this.player.play();
        this.isPlaying = true;
        this.notifySentenceChange(sentence);
        this.notifyStateChange();
      }
    } catch (error) {
      appLogger.error('PlayerController: playSentence failed', error);
      this.notifyError((error as Error).message);
      throw error as Error;
    }
  }

  /**
   * 播放单句并在播放完成时通过 onSentenceEnd 通知监听者。
   * 播放完成由 onStateChange 的 completed 分支触发 sentenceEndListeners。
   * @param scene 场景对象
   * @param dialogueIndex 对话索引
   * @param sentenceIndex 句子索引
   */
  async playSentenceAndNotify(scene: Scene, dialogueIndex: number, sentenceIndex: number): Promise<void> {
    this.sentenceNotifyActive = true;
    await this.playSentence(scene, dialogueIndex, sentenceIndex);
  }

  private notifySentenceEnd(sentence: Sentence): void {
    this.sentenceEndListeners.notify((cb: SentenceEndCallback) => cb(sentence));
  }

  /**
   * 获取当前 UI 状态
   * @returns PlayerUiState 对象
   */
  getUiState(): PlayerUiState {
    const dialogue = this.getCurrentDialogue();
    const sentence = this.getCurrentSentence();

    return {
      isPlaying: this.isPlaying,
      sceneId: this.currentScene ? this.currentScene.id : null,
      sceneTitle: this.currentScene ? this.currentScene.titleZh : '',
      dialogueIndex: this.currentDialogueIndex,
      dialogueTitle: dialogue ? dialogue.titleZh : '',
      sentenceIndex: this.currentSentenceIndex,
      currentSentence: sentence,
      currentTimeMs: this.currentTimeMs,
      durationMs: this.durationMs,
      speed: this.playbackSpeed,
      isSlowMode: this.isSlowMode
    };
  }

  /**
   * 释放播放器资源
   */
  async release(): Promise<void> {
    try {
      this.isPlaying = false;
      // 先停止后台任务
      try {
        await BackgroundTaskManager.getInstance().stopAudioPlayback();
      } catch (err) {
        appLogger.error('PlayerController: stop background task failed during release', err);
      }
      // 释放 AVSession
      try {
        await AVSessionManager.getInstance().release();
      } catch (err) {
        appLogger.error('PlayerController: release AVSession failed', err);
      }
      this.currentScene = null;
      this.currentDialogueIndex = 0;
      this.currentSentenceIndex = 0;
      this.currentTimeMs = 0;
      this.durationMs = 0;
      await this.player.release();
      this.notifyStateChange();
      appLogger.info('PlayerController: released');
    } catch (error) {
      appLogger.error('PlayerController: release failed', error);
    }
  }

  // ============== 私有方法 ==============

  /**
   * 绑定播放器事件回调
   */
  private bindPlayerCallbacks(): void {
    this.player.setCallbacks({
      onStateChange: (state: string): void => {
        appLogger.debug(`PlayerController: player state = ${state}`);
        if (state === 'playing') {
          this.isPlaying = true;
        } else if (state === 'paused' || state === 'completed' || state === 'stopped') {
          this.isPlaying = false;
        }
        if (state === 'completed') {
          this.recordSceneProgress(100);
          // 仅在 playSentenceAndNotify 模式下触发 onSentenceEnd，避免普通播放误触发
          if (this.sentenceNotifyActive) {
            this.sentenceNotifyActive = false;
            const sentence = this.getCurrentSentence();
            if (sentence) {
              this.notifySentenceEnd(sentence);
            }
          }
        }
        this.notifyStateChange();
      },
      onTimeUpdate: (currentTimeMs: number): void => {
        this.currentTimeMs = currentTimeMs;
        // 根据时间更新当前句子
        this.updateCurrentSentence(currentTimeMs);
        // playSentenceAndNotify 模式：检测当前句子播放完毕（到达 endTime）
        if (this.sentenceNotifyActive) {
          const sentence = this.getCurrentSentence();
          if (sentence) {
            const endTimeSec = this.isSlowMode ? sentence.slowEndTime : sentence.endTime;
            if (currentTimeMs >= endTimeSec * 1000) {
              this.sentenceNotifyActive = false;
              this.player.pause().catch(() => {});
              this.notifySentenceEnd(sentence);
            }
          }
        }
        const currentTime = currentTimeMs;
        const duration = this.durationMs;
        this.timeUpdateListeners.notify((callback: TimeUpdateCallback) => {
          callback(currentTime, duration);
        });
      },
      onDurationUpdate: (durationMs: number): void => {
        this.durationMs = durationMs;
        this.notifyStateChange();
      },
      onError: (error: Error): void => {
        appLogger.error('PlayerController: player error', error);
        this.isPlaying = false;
        this.notifyError(error.message);
        this.notifyStateChange();
      },
      onAudioInterrupt: (event: audio.InterruptEvent): void => {
        appLogger.info(`PlayerController: audioInterrupt hintType=${event.hintType}, forceType=${event.forceType}`);
        const focusEvent = this.convertAudioInterruptEvent(event);
        AudioFocusHandler.getInstance().handleInterrupt(focusEvent);
      }
    });
  }

  /**
   * 绑定 AVSession 控制命令回调
   * 将系统播控中心的控制命令映射到 PlayerController 的对应方法
   */
  private bindAVSessionCallbacks(): void {
    const avSession = AVSessionManager.getInstance();

    avSession.onPlay = () => {
      this.play().catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onPlay failed', err);
      });
    };

    avSession.onPause = () => {
      this.pause().catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onPause failed', err);
      });
    };

    avSession.onStop = () => {
      this.pause().catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onStop failed', err);
      });
    };

    avSession.onSkipToNext = () => {
      this.nextDialogue().catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onSkipToNext failed', err);
      });
    };

    avSession.onSkipToPrevious = () => {
      this.prevDialogue().catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onSkipToPrevious failed', err);
      });
    };

    avSession.onSeek = (timeMs: number) => {
      this.seekTo(timeMs).catch((err: Object) => {
        appLogger.error('PlayerController: AVSession onSeek failed', err);
      });
    };

    appLogger.info('PlayerController: AVSession callbacks bound');
  }

  /**
   * 绑定 AudioFocusHandler 回调
   * 处理音频焦点变化的业务逻辑
   */
  private bindAudioFocusCallbacks(): void {
    const handler = AudioFocusHandler.getInstance();

    handler.onPause = () => {
      appLogger.info('PlayerController: audio focus pause, pausing playback');
      this.pause().catch((err: Object) => {
        appLogger.error('PlayerController: audio focus pause failed', err);
      });
    };

    handler.onResume = () => {
      appLogger.info('PlayerController: audio focus resume, resuming playback');
      this.play().catch((err: Object) => {
        appLogger.error('PlayerController: audio focus resume failed', err);
      });
    };

    handler.onStop = () => {
      appLogger.info('PlayerController: audio focus stop, stopping playback');
      this.pause().catch((err: Object) => {
        appLogger.error('PlayerController: audio focus stop failed', err);
      });
    };

    handler.onDuck = () => {
      appLogger.info('PlayerController: audio focus duck, updating UI');
      // DUCK 由系统自动处理音量，此处仅通知 UI 状态变化
      this.notifyStateChange();
    };

    handler.onUnduck = () => {
      appLogger.info('PlayerController: audio focus unduck, updating UI');
      // UNDUCK 由系统自动处理音量，此处仅通知 UI 状态变化
      this.notifyStateChange();
    };

    appLogger.info('PlayerController: AudioFocus callbacks bound');
  }

  /**
   * 启动播放会话
   * 统一处理：启动后台长时任务 + 更新 AVSession 播放状态 + 更新元数据
   */
  private async startPlaybackSession(): Promise<void> {
    ProgressStore.getInstance().checkInIfNeeded().catch((err: Object) => {
      appLogger.error('PlayerController: check-in failed', err);
    });

    // 启动后台长时任务
    try {
      await BackgroundTaskManager.getInstance().startAudioPlayback();
    } catch (error) {
      appLogger.error('PlayerController: startAudioPlayback failed', error);
      // 后台任务启动失败不影响播放，仅记录错误
    }

    // 更新 AVSession 播放状态
    try {
      await AVSessionManager.getInstance().updatePlaybackState(
        'playing',
        this.currentTimeMs,
        this.playbackSpeed
      );
    } catch (error) {
      appLogger.error('PlayerController: update AVSession playback state failed', error);
    }

    // 更新 AVSession 媒体元数据
    if (this.currentScene) {
      try {
        await AVSessionManager.getInstance().updateMetadata(
          this.currentScene.titleZh,
          '',
          '',
          this.durationMs
        );
      } catch (error) {
        appLogger.error('PlayerController: update AVSession metadata failed', error);
      }
    }
  }

  /**
   * 停止播放会话
   * 统一处理：更新 AVSession 播放状态为暂停 + 停止后台长时任务
   * 注意：必须先暂停播放器再调用此方法
   */
  private async stopPlaybackSession(): Promise<void> {
    // 更新 AVSession 播放状态为暂停
    try {
      await AVSessionManager.getInstance().updatePlaybackState(
        'paused',
        this.currentTimeMs,
        this.playbackSpeed
      );
    } catch (error) {
      appLogger.error('PlayerController: update AVSession paused state failed', error);
    }

    // 停止后台长时任务
    try {
      await BackgroundTaskManager.getInstance().stopAudioPlayback();
    } catch (error) {
      appLogger.error('PlayerController: stopAudioPlayback failed', error);
    }
  }

  /**
   * 将 AVPlayer 的 audioInterrupt 原始事件转换为 AudioFocusEvent
   * @param event 系统音频中断事件
   * @returns 转换后的 AudioFocusEvent
   */
  private convertAudioInterruptEvent(event: audio.InterruptEvent): AudioFocusEvent {
    // InterruptForceType: INTERRUPT_FORCE=系统已强制处理, INTERRUPT_SHARE=应用需自主处理
    const force = event.forceType === audio.InterruptForceType.INTERRUPT_FORCE;
    let hint: InterruptHint = 'pause';
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      hint = 'resume';
    } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      hint = 'pause';
    } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      hint = 'stop';
    } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      hint = 'duck';
    } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
      hint = 'unduck';
    }
    return { hint, force };
  }

  /**
   * 根据当前播放时间更新当前句子索引
   * @param timeMs 当前播放时间（毫秒）
   */
  private updateCurrentSentence(timeMs: number): void {
    if (!this.currentScene || this.currentScene.dialogues.length === 0) {
      return;
    }

    const timeSec = timeMs / 1000;
    let foundDialogueIndex = -1;
    let foundSentenceIndex = -1;

    // 精确匹配：遍历所有对话的所有句子
    for (let d = 0; d < this.currentScene.dialogues.length; d++) {
      const dialogue = this.currentScene.dialogues[d];
      for (let i = 0; i < dialogue.sentences.length; i++) {
        const sentence = dialogue.sentences[i];
        const startTime = this.isSlowMode ? sentence.slowStartTime : sentence.startTime;
        const endTime = this.isSlowMode ? sentence.slowEndTime : sentence.endTime;
        if (timeSec >= startTime && timeSec < endTime) {
          foundDialogueIndex = d;
          foundSentenceIndex = i;
          break;
        }
      }
      if (foundDialogueIndex !== -1) break;
    }

    // 容差匹配（200ms）
    if (foundSentenceIndex === -1) {
      for (let d = 0; d < this.currentScene.dialogues.length; d++) {
        const dialogue = this.currentScene.dialogues[d];
        for (let i = 0; i < dialogue.sentences.length; i++) {
          const sentence = dialogue.sentences[i];
          const startTime = this.isSlowMode ? sentence.slowStartTime : sentence.startTime;
          const endTime = this.isSlowMode ? sentence.slowEndTime : sentence.endTime;
          if (timeSec >= startTime - 0.2 && timeSec <= endTime + 0.2) {
            foundDialogueIndex = d;
            foundSentenceIndex = i;
            break;
          }
        }
        if (foundDialogueIndex !== -1) break;
      }
    }

    if (foundSentenceIndex === -1) {
      // gap 期间不更新
      return;
    }

    // 跨对话切换
    if (foundDialogueIndex !== this.currentDialogueIndex) {
      appLogger.info(`PlayerController: auto switch dialogue ${this.currentDialogueIndex} -> ${foundDialogueIndex} at ${timeSec}s`);
      this.currentDialogueIndex = foundDialogueIndex;
      this.currentSentenceIndex = foundSentenceIndex;
      const sentence = this.getCurrentSentence();
      if (sentence) {
        this.notifySentenceChange(sentence);
      }
      this.notifyStateChange();
      return;
    }

    // 同对话内切换句子
    if (foundSentenceIndex !== this.currentSentenceIndex) {
      this.currentSentenceIndex = foundSentenceIndex;
      const sentence = this.getCurrentSentence();
      if (sentence) {
        this.notifySentenceChange(sentence);
      }
      this.notifyStateChange();
    }
  }

  /**
   * 获取当前对话
   */
  private getCurrentDialogue(): Dialogue | null {
    if (!this.currentScene) {
      return null;
    }
    if (this.currentDialogueIndex < 0 || this.currentDialogueIndex >= this.currentScene.dialogues.length) {
      return null;
    }
    return this.currentScene.dialogues[this.currentDialogueIndex];
  }

  /**
   * 获取当前句子
   */
  private getCurrentSentence(): Sentence | null {
    const dialogue = this.getCurrentDialogue();
    if (!dialogue) {
      return null;
    }
    if (this.currentSentenceIndex < 0 || this.currentSentenceIndex >= dialogue.sentences.length) {
      return null;
    }
    return dialogue.sentences[this.currentSentenceIndex];
  }

  /**
   * 获取指定对话的起始时间（毫秒）
   */
  private getDialogueStartTimeMs(dialogueIndex: number): number {
    if (!this.currentScene) {
      return 0;
    }
    const dialogue = this.currentScene.dialogues[dialogueIndex];
    if (!dialogue || dialogue.sentences.length === 0) {
      return 0;
    }
    const firstSentence = dialogue.sentences[0];
    return this.getSentenceStartTimeMs(firstSentence);
  }

  /**
   * 获取句子的起始时间（毫秒），根据是否慢速模式选择对应时间戳
   */
  private getSentenceStartTimeMs(sentence: Sentence): number {
    const startTimeSec = this.isSlowMode ? sentence.slowStartTime : sentence.startTime;
    return Math.floor(startTimeSec * 1000);
  }

  /**
   * 限制对话索引在有效范围内
   */
  private clampDialogueIndex(index: number): number {
    if (!this.currentScene) {
      return 0;
    }
    return Math.max(0, Math.min(index, this.currentScene.dialogues.length - 1));
  }

  /**
   * 通知 UI 状态变化
   */
  private notifyStateChange(): void {
    const state = this.getUiState();
    this.stateChangeListeners.notify((callback: StateChangeCallback) => {
      callback(state);
    });
  }

  /**
   * 通知句子变化
   */
  private notifySentenceChange(sentence: Sentence): void {
    this.sentenceChangeListeners.notify((callback: SentenceChangeCallback) => {
      callback(sentence);
    });
  }

  /**
   * 通知错误
   */
  private notifyError(message: string): void {
    this.errorListeners.notify((callback: ErrorCallback) => {
      callback(message);
    });
  }

  /**
   * 记录场景学习进度（0-100），达到 100 自动标记完成
   */
  private recordSceneProgress(percent: number): void {
    const sceneId = this.currentScene ? this.currentScene.id : '';
    if (!sceneId) {
      return;
    }
    ProgressStore.getInstance().updateSceneProgress(sceneId, percent).catch((err: Object) => {
      appLogger.error('PlayerController: record scene progress failed', err);
    });
  }
}
