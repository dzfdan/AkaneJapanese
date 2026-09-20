import { preferences } from '@kit.ArkData';
import { UserProgress } from '../model/UserProgress';
import { AppConstants } from '../constants/AppConstants';
import { getTodayStr, isSameDay, isConsecutiveDay } from '../utils/DateUtil';
import appLogger from '../utils/Logger';

type Preferences = preferences.Preferences;

/**
 * 默认学习进度
 */
const defaultProgress: UserProgress = {
  completedScenes: [],
  sceneProgress: {},
  totalStudyMinutes: 0,
  streakDays: 0,
  lastStudyDate: '',
  favoriteSentences: []
};

/**
 * 学习进度存储
 * 基于 Preferences 持久化用户学习进度数据
 * 单例模式，需先调用 init(context) 初始化
 */
export class ProgressStore {
  private static instance: ProgressStore | null = null;
  private prefs: Preferences | null = null;
  private context: Context | null = null;
  private progress: UserProgress = { ...defaultProgress };

  /** 进度变化回调（UI 层订阅） */
  onProgressChange?: (progress: UserProgress) => void;

  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns ProgressStore 实例
   */
  static getInstance(): ProgressStore {
    if (!ProgressStore.instance) {
      ProgressStore.instance = new ProgressStore();
    }
    return ProgressStore.instance;
  }

  /**
   * 初始化（传入 context）
   * @param context 应用上下文
   */
  async init(context: Context): Promise<void> {
    try {
      this.context = context;
      const prefsName = AppConstants.STORAGE_KEYS.progress;
      this.prefs = await preferences.getPreferences(context, prefsName);
      appLogger.info(`ProgressStore: initialized with prefs "${prefsName}"`);
      await this.load();
    } catch (error) {
      appLogger.error('ProgressStore: init failed', error);
      // 初始化失败时使用默认进度
      this.progress = { ...defaultProgress };
    }
  }

  /**
   * 获取当前进度
   * @returns 用户学习进度
   */
  getProgress(): UserProgress {
    return { ...this.progress };
  }

  /**
   * 记录学习时长（分钟）
   * @param minutes 学习分钟数
   */
  async addStudyMinutes(minutes: number): Promise<void> {
    if (minutes <= 0) {
      return;
    }
    try {
      this.progress.totalStudyMinutes += minutes;
      appLogger.debug(`ProgressStore: addStudyMinutes ${minutes}, total=${this.progress.totalStudyMinutes}`);
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('ProgressStore: addStudyMinutes failed', error);
    }
  }

  /**
   * 更新场景进度
   * @param sceneId 场景 ID
   * @param percent 进度百分比（0-100）
   */
  async updateSceneProgress(sceneId: string, percent: number): Promise<void> {
    try {
      const clampedPercent = Math.max(0, Math.min(100, percent));
      const oldPercent = this.progress.sceneProgress[sceneId] || 0;

      // 只更新比当前更高的进度（避免倒退）
      if (clampedPercent <= oldPercent) {
        return;
      }

      this.progress.sceneProgress[sceneId] = clampedPercent;
      appLogger.debug(`ProgressStore: updateSceneProgress ${sceneId} -> ${clampedPercent}%`);

      // 如果达到 100%，标记为已完成
      if (clampedPercent >= 100) {
        await this.markSceneCompleted(sceneId);
      } else {
        await this.save();
        this.notifyChange();
      }
    } catch (error) {
      appLogger.error('ProgressStore: updateSceneProgress failed', error);
    }
  }

  /**
   * 标记场景完成
   * @param sceneId 场景 ID
   */
  async markSceneCompleted(sceneId: string): Promise<void> {
    try {
      // 设置进度为 100%
      this.progress.sceneProgress[sceneId] = 100;

      // 添加到已完成列表（去重）
      if (!this.progress.completedScenes.includes(sceneId)) {
        this.progress.completedScenes.push(sceneId);
        appLogger.info(`ProgressStore: scene ${sceneId} completed`);
      }

      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('ProgressStore: markSceneCompleted failed', error);
    }
  }

  /**
   * 打卡（如果今天还没打卡）
   * 更新连续学习天数和最后学习日期
   */
  async checkInIfNeeded(): Promise<void> {
    try {
      const today = getTodayStr();

      // 如果今天已经打卡，不做处理
      if (isSameDay(this.progress.lastStudyDate, today)) {
        appLogger.debug('ProgressStore: already checked in today');
        return;
      }

      // 如果上次学习是昨天，连续天数 +1
      if (isConsecutiveDay(this.progress.lastStudyDate, today)) {
        this.progress.streakDays += 1;
        appLogger.info(`ProgressStore: streak continues, day ${this.progress.streakDays}`);
      } else if (this.progress.lastStudyDate === '') {
        // 第一次学习
        this.progress.streakDays = 1;
        appLogger.info('ProgressStore: first check-in, streak = 1');
      } else {
        // 间隔超过一天，重置为 1
        this.progress.streakDays = 1;
        appLogger.info('ProgressStore: streak reset to 1');
      }

      this.progress.lastStudyDate = today;
      await this.save();
      this.notifyChange();
    } catch (error) {
      appLogger.error('ProgressStore: checkInIfNeeded failed', error);
    }
  }

  /**
   * 收藏/取消收藏句子
   * @param sentenceKey 句子标识，格式：sceneId:dialogueIndex:sentenceIndex
   * @returns 收藏状态（true 表示已收藏，false 表示已取消）
   */
  async toggleFavorite(sentenceKey: string): Promise<boolean> {
    try {
      const index = this.progress.favoriteSentences.indexOf(sentenceKey);
      let isFav: boolean;

      if (index === -1) {
        // 添加收藏
        this.progress.favoriteSentences.push(sentenceKey);
        isFav = true;
        appLogger.debug(`ProgressStore: added favorite ${sentenceKey}`);
      } else {
        // 取消收藏
        this.progress.favoriteSentences.splice(index, 1);
        isFav = false;
        appLogger.debug(`ProgressStore: removed favorite ${sentenceKey}`);
      }

      await this.save();
      this.notifyChange();
      return isFav;
    } catch (error) {
      appLogger.error('ProgressStore: toggleFavorite failed', error);
      return false;
    }
  }

  /**
   * 判断句子是否已收藏
   * @param sentenceKey 句子标识
   * @returns true 表示已收藏
   */
  isFavorite(sentenceKey: string): boolean {
    return this.progress.favoriteSentences.includes(sentenceKey);
  }

  /**
   * 获取收藏句子数量
   * @returns 收藏数量
   */
  getFavoriteCount(): number {
    return this.progress.favoriteSentences.length;
  }

  // ============== 私有方法 ==============

  /**
   * 保存进度到 Preferences
   */
  private async save(): Promise<void> {
    if (!this.prefs) {
      appLogger.warn('ProgressStore: save called but prefs is null');
      return;
    }

    try {
      const jsonStr = JSON.stringify(this.progress);
      await this.prefs.putString('data', jsonStr);
      await this.prefs.flush();
      appLogger.debug('ProgressStore: saved');
    } catch (error) {
      appLogger.error('ProgressStore: save failed', error);
      throw error;
    }
  }

  /**
   * 从 Preferences 加载进度
   */
  private async load(): Promise<void> {
    if (!this.prefs) {
      appLogger.warn('ProgressStore: load called but prefs is null');
      return;
    }

    try {
      const jsonStr = await this.prefs.getString('data', '');
      if (jsonStr && jsonStr.length > 0) {
        const loaded = JSON.parse(jsonStr) as UserProgress;
        // 合并默认值，确保新增字段有默认值
        this.progress = {
          ...defaultProgress,
          ...loaded,
          sceneProgress: loaded.sceneProgress || {},
          favoriteSentences: loaded.favoriteSentences || []
        };
        appLogger.info(`ProgressStore: loaded, completedScenes=${this.progress.completedScenes.length}`);
      } else {
        this.progress = { ...defaultProgress };
        appLogger.info('ProgressStore: no saved data, using defaults');
      }
      this.notifyChange();
    } catch (error) {
      appLogger.error('ProgressStore: load failed, using defaults', error);
      this.progress = { ...defaultProgress };
    }
  }

  /**
   * 通知进度变化
   */
  private notifyChange(): void {
    if (this.onProgressChange) {
      this.onProgressChange({ ...this.progress });
    }
  }
}
