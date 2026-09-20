/**
 * 单句对话数据模型
 */
export interface Sentence {
  /** 句子唯一标识 */
  id: string;
  /** 说话人名称（如 A、B、店員 等） */
  speaker: string;
  /** 说话人角色（日文） */
  speakerRoleJa: string;
  /** 说话人角色（中文） */
  speakerRoleZh: string;
  /** 日文原文 */
  japanese: string;
  /** 罗马音 */
  romaji: string;
  /** 中文翻译 */
  translation: string;
  /** 正常速音频开始时间（秒） */
  startTime: number;
  /** 正常速音频结束时间（秒） */
  endTime: number;
  /** 慢速音频开始时间（秒） */
  slowStartTime: number;
  /** 慢速音频结束时间（秒） */
  slowEndTime: number;
}
