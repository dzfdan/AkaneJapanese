/**
 * 测验题目数据模型
 */
export interface QuizItem {
  /** 题目唯一标识 */
  id: string;
  /** 题目类型：听力 / 阅读 / 释义 */
  type: 'listening' | 'reading' | 'meaning';
  /** 题目（中文） */
  questionZh: string;
  /** 选项列表 */
  options: string[];
  /** 正确选项索引（从 0 开始） */
  correctIndex: number;
  /** 答案解析（中文） */
  explanationZh: string;
}
