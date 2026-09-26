/**
 * 文本段（用于振假名注音）
 * kana 存在时表示该段为汉字，需在上方显示假名读音
 */
export interface Segment {
  /** 文本内容 */
  text: string;
  /** 假名读音（仅汉字段有） */
  kana?: string;
}

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
  /** 振假名分段注音（可选，为空时 UI 回退到 japanese 纯文本） */
  segments?: Segment[];
  /** 正常速音频开始时间（秒） */
  startTime: number;
  /** 正常速音频结束时间（秒） */
  endTime: number;
  /** 慢速音频开始时间（秒） */
  slowStartTime: number;
  /** 慢速音频结束时间（秒） */
  slowEndTime: number;
}
