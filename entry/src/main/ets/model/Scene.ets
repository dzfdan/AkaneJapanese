import { Dialogue } from './Dialogue';

/**
 * 场景数据模型
 * 每个场景对应一个主题下的多组对话与测验
 */
export interface Scene {
  /** 场景唯一标识，如 scene-001 */
  id: string;
  /** 场景标题（日文） */
  titleJa: string;
  /** 场景标题（中文） */
  titleZh: string;
  /** 难度等级，如 N5、N4、N3 等 */
  level: string;
  /** 场景分类，如 日常生活、旅行、商务 等 */
  category: string;
  /** 场景描述（中文） */
  descriptionZh: string;
  /** 正常速音频文件名（相对 rawfile/audio/ 路径） */
  audioNormal: string;
  /** 慢速音频文件名（相对 rawfile/audio/ 路径） */
  audioSlow: string;
  /** 对话列表 */
  dialogues: Dialogue[];
}
