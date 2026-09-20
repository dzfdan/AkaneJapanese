/**
 * 用户学习进度数据模型
 */
export interface UserProgress {
  /** 已完成的场景 id 列表 */
  completedScenes: string[];
  /** 各场景的学习进度百分比（0-100），key 为场景 id */
  sceneProgress: Record<string, number>;
  /** 累计学习分钟数 */
  totalStudyMinutes: number;
  /** 连续学习天数 */
  streakDays: number;
  /** 最近一次学习日期（ISO 日期字符串，如 2026-09-17） */
  lastStudyDate: string;
  /** 收藏的句子 id 列表 */
  favoriteSentences: string[];
}
