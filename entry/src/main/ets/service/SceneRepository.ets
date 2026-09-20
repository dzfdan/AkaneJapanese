import { Scene } from '../model/Scene';
import appLogger from '../utils/Logger';

/**
 * 场景索引条目（index.json 中的单条场景摘要）
 */
interface SceneIndexItem {
  id: string;
  titleJa: string;
  titleZh: string;
  level: string;
  category: string;
  dialogueCount: number;
  durationSec: number;
  file: string;
}

/**
 * 场景索引文件结构
 */
interface SceneIndex {
  version: string;
  scenes: SceneIndexItem[];
}

/**
 * 场景仓库
 * 负责从 rawfile 加载 JSON 并解析为 Scene 模型
 * 单例模式，需先调用 init(context) 初始化
 */
export class SceneRepository {
  private static instance: SceneRepository | null = null;
  private context: Context | null = null;
  private scenes: Scene[] = [];
  private loaded: boolean = false;

  private constructor() {
  }

  /**
   * 初始化单例（传入 Context 用于访问 resourceManager）
   * @param context 应用上下文
   */
  static init(context: Context): void {
    if (!SceneRepository.instance) {
      SceneRepository.instance = new SceneRepository();
    }
    SceneRepository.instance.context = context;
  }

  /**
   * 获取单例实例
   * @returns SceneRepository 实例
   */
  static getInstance(): SceneRepository {
    if (!SceneRepository.instance) {
      throw new Error('SceneRepository not initialized. Call SceneRepository.init(context) first.');
    }
    return SceneRepository.instance;
  }

  /**
   * 从 rawfile 加载所有场景数据
   * 先读 index.json 获取场景列表，再逐个加载场景 JSON 文件
   * @returns 加载完成的场景数组
   */
  async loadAll(): Promise<Scene[]> {
    if (this.loaded && this.scenes.length > 0) {
      appLogger.debug('SceneRepository: already loaded, return cached scenes');
      return this.scenes;
    }

    if (!this.context) {
      throw new Error('SceneRepository: context is null, call init first');
    }

    try {
      const resourceMgr = this.context.resourceManager;

      // 1. 读取 index.json
      appLogger.info('SceneRepository: loading index.json');
      const indexData = await resourceMgr.getRawFileContent('index.json');
      const indexStr = this.uint8ArrayToString(indexData as Uint8Array);
      const indexJson: SceneIndex = JSON.parse(indexStr);

      appLogger.info(`SceneRepository: index loaded, ${indexJson.scenes.length} scenes found`);

      // 2. 逐个加载场景文件
      const loadedScenes: Scene[] = [];
      for (const item of indexJson.scenes) {
        try {
          appLogger.debug(`SceneRepository: loading ${item.file}`);
          const sceneData = await resourceMgr.getRawFileContent(item.file);
          const sceneStr = this.uint8ArrayToString(sceneData as Uint8Array);
          const scene: Scene = JSON.parse(sceneStr);
          loadedScenes.push(scene);
          appLogger.debug(`SceneRepository: loaded scene ${scene.id} - ${scene.titleZh}`);
        } catch (sceneError) {
          appLogger.error(`SceneRepository: failed to load scene ${item.file}`, sceneError);
          // 解析失败，跳过该场景
        }
      }

      this.scenes = loadedScenes;
      this.loaded = true;
      appLogger.info(`SceneRepository: all scenes loaded, total ${loadedScenes.length}`);
      return loadedScenes;
    } catch (error) {
      appLogger.error('SceneRepository: loadAll failed', error);
      throw error;
    }
  }

  /**
   * 获取所有场景
   * @returns 场景数组
   */
  getAllScenes(): Scene[] {
    return this.scenes;
  }

  /**
   * 按 ID 获取场景
   * @param id 场景 ID
   * @returns 场景对象，未找到返回 undefined
   */
  getSceneById(id: string): Scene | undefined {
    return this.scenes.find((scene: Scene): boolean => scene.id === id);
  }

  /**
   * 按分类筛选场景
   * @param category 分类名称
   * @returns 匹配的场景数组
   */
  getScenesByCategory(category: string): Scene[] {
    return this.scenes.filter((scene: Scene): boolean => scene.category === category);
  }

  /**
   * 按难度筛选场景
   * @param level 难度等级（如 N5、N4）
   * @returns 匹配的场景数组
   */
  getScenesByLevel(level: string): Scene[] {
    return this.scenes.filter((scene: Scene): boolean => scene.level === level);
  }

  /**
   * 获取音频资源的 rawfile fd（用于 AVPlayer）
   * @param audioPath 音频文件名（如 scene-001-normal.m4a）
   * @returns fd 对象，包含 fd、offset、length
   */
  async getAudioFd(audioPath: string): Promise<{ fd: number; offset: number; length: number }> {
    if (!this.context) {
      throw new Error('SceneRepository: context is null, call init first');
    }

    const fullPath = `audio/${audioPath}`;
    appLogger.debug(`SceneRepository: getting audio fd for ${fullPath}`);

    try {
      const rawFd = await this.context.resourceManager.getRawFd(fullPath);
      return {
        fd: rawFd.fd,
        offset: rawFd.offset,
        length: rawFd.length
      };
    } catch (error) {
      appLogger.error(`SceneRepository: getAudioFd failed for ${fullPath}`, error);
      throw error;
    }
  }

  /**
   * 将 Uint8Array 转换为字符串
   * @param data 二进制数据
   * @returns 字符串
   */
  private uint8ArrayToString(data: Uint8Array): string {
    let result = '';
    const chunkSize = 8192;
    for (let i = 0; i < data.length; i += chunkSize) {
      const chunk = data.subarray(i, i + chunkSize);
      result += String.fromCharCode.apply(null, chunk as unknown as number[]);
    }
    return result;
  }
}
