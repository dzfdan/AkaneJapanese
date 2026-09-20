import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, common } from '@kit.AbilityKit';
import appLogger from '../utils/Logger';

/**
 * 后台长时任务管理器
 * 封装 BackgroundTasksKit，申请 AUDIO_PLAYBACK 长时任务以支持锁屏续播
 * 单例模式
 *
 * 功能：
 * - 开始 audioPlayback 后台长时任务（开始播放时调用）
 * - 停止后台长时任务（暂停/停止播放时调用）
 *
 * 注意事项：
 * - 停止长时任务时必须同步暂停/停止音频，否则应用会被系统强制终止
 * - 通知点击会通过 WantAgent 跳转回应用
 */
export class BackgroundTaskManager {
  private static instance: BackgroundTaskManager | null = null;
  private context: Context | null = null;
  private isRunning: boolean = false;

  /**
   * 获取单例实例
   */
  static getInstance(): BackgroundTaskManager {
    if (!BackgroundTaskManager.instance) {
      BackgroundTaskManager.instance = new BackgroundTaskManager();
    }
    return BackgroundTaskManager.instance;
  }

  private constructor() {}

  /**
   * 初始化（保存 context 引用）
   * @param context UIAbility 的 Context
   */
  init(context: Context): void {
    this.context = context;
  }

  /**
   * 开始后台长时任务（开始播放时调用）
   * 申请 audioPlayback 模式的长时任务，使应用在锁屏后可以继续播放音频
   */
  async startAudioPlayback(): Promise<void> {
    if (!this.context) {
      appLogger.error('BackgroundTaskManager: context not initialized, call init() first');
      throw new Error('BackgroundTaskManager not initialized');
    }

    if (this.isRunning) {
      appLogger.warn('BackgroundTaskManager: audioPlayback task already running');
      return;
    }

    try {
      // 1. 创建 WantAgent（点击通知时跳转回应用）
      const abilityContext = this.context as common.UIAbilityContext;
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: abilityContext.abilityInfo.bundleName,
            abilityName: abilityContext.abilityInfo.name
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      appLogger.debug('BackgroundTaskManager: WantAgent created');

      // 2. 调用 startBackgroundRunning 申请长时任务
      // NOTE: API 26 中 startBackgroundRunning 第三参数为 WantAgent 实例
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        ['audioPlayback'],
        agent
      );

      this.isRunning = true;
      appLogger.info('BackgroundTaskManager: audioPlayback background task started');
    } catch (error) {
      appLogger.error('BackgroundTaskManager: startAudioPlayback failed', error);
      throw error as Error;
    }
  }

  /**
   * 停止后台长时任务（暂停/停止播放时调用）
   *
   * 重要：调用此方法前必须确保音频已经暂停或停止，
   * 否则系统可能会强制终止应用。
   */
  async stopAudioPlayback(): Promise<void> {
    if (!this.context) {
      appLogger.warn('BackgroundTaskManager: context not initialized');
      return;
    }

    if (!this.isRunning) {
      appLogger.debug('BackgroundTaskManager: audioPlayback task not running, skip stop');
      return;
    }

    try {
      // 停止后台长时任务
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.isRunning = false;
      appLogger.info('BackgroundTaskManager: audioPlayback background task stopped');
    } catch (error) {
      appLogger.error('BackgroundTaskManager: stopAudioPlayback failed', error);
      // 即使失败也重置状态，避免状态不一致
      this.isRunning = false;
    }
  }

  /**
   * 查询当前后台长时任务是否在运行
   */
  isTaskRunning(): boolean {
    return this.isRunning;
  }
}
