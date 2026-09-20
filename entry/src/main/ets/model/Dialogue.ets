import { Sentence } from './Sentence';
import { QuizItem } from './QuizItem';

/**
 * 对话（场景内的一组对话）数据模型
 */
export interface Dialogue {
  /** 对话唯一标识 */
  id: string;
  /** 对话标题（日文） */
  titleJa: string;
  /** 对话标题（中文） */
  titleZh: string;
  /** 句子列表 */
  sentences: Sentence[];
  /** 测验题目列表 */
  quiz: QuizItem[];
}
