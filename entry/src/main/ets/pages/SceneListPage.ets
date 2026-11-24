/**
 * 场景列表页
 * 展示所有学习场景（App 默认驻车模式，不再提供模式切换）
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { SceneCard } from '../components/SceneCard';
import { Scene } from '../model/Scene';
import { UserProgress } from '../model/UserProgress';
import { SceneRepository } from '../service/SceneRepository';
import { ProgressStore } from '../service/ProgressStore';
import appLogger from '../utils/Logger';

@Component
export struct SceneListPage {
  onSceneClick: (sceneId: string) => void = () => {};

  @State scenes: Scene[] = [];
  @State completedMap: Record<string, boolean> = {};
  @State progressMap: Record<string, number> = {};
  @State selectedLevel: string = 'all';
  // 场景列表容器实际宽度（vp），用于响应式计算卡片宽度铺满可用空间
  @State containerWidth: number = 0;
  // 横屏（16:9）紧凑布局
  @StorageProp('isLandscape') isLandscape: boolean = false;

  private progressCallback: ((progress: UserProgress) => void) | null = null;

  aboutToAppear() {
    appLogger.info('SceneListPage aboutToAppear');

    // 从 SceneRepository 获取场景列表
    const allScenes = SceneRepository.getInstance().getAllScenes();
    if (allScenes.length > 0) {
      this.scenes = allScenes;
      appLogger.info(`SceneListPage: loaded ${allScenes.length} scenes from cache`);
    } else {
      // 如果还没加载，尝试加载
      SceneRepository.getInstance().loadAll().then((loadedScenes: Scene[]) => {
        this.scenes = loadedScenes;
        appLogger.info(`SceneListPage: loaded ${loadedScenes.length} scenes`);
      }).catch((err: Object) => {
        appLogger.error('SceneListPage: load scenes failed', err);
      });
    }

    // 从 ProgressStore 获取进度
    this.updateProgressFromStore();

    // 订阅进度变化
    this.progressCallback = (progress: UserProgress) => {
      this.updateProgressMap(progress);
    };
    ProgressStore.getInstance().addOnProgressChange(this.progressCallback);
  }

  aboutToDisappear() {
    appLogger.info('SceneListPage aboutToDisappear');
    // 取消订阅
    if (this.progressCallback) {
      ProgressStore.getInstance().removeOnProgressChange(this.progressCallback);
    }
    this.progressCallback = null;
  }

  private updateProgressFromStore(): void {
    const progress = ProgressStore.getInstance().getProgress();
    this.updateProgressMap(progress);
  }

  private updateProgressMap(progress: UserProgress): void {
    // 更新已完成映射
    const completed: Record<string, boolean> = {};
    for (const sceneId of progress.completedScenes) {
      completed[sceneId] = true;
    }
    this.completedMap = completed;

    // 更新进度映射
    const progressMap: Record<string, number> = {};
    for (const sceneId of Object.keys(progress.sceneProgress)) {
      progressMap[sceneId] = progress.sceneProgress[sceneId];
    }
    this.progressMap = progressMap;
  }

  private getFilteredScenes(): Scene[] {
    if (this.selectedLevel === 'all') {
      return this.scenes;
    }
    return this.scenes.filter((scene: Scene): boolean => scene.level === this.selectedLevel);
  }

  // 按数据中实际存在的难度等级生成筛选项，避免出现无内容的等级（如 N3）点击后页面空白
  private getAvailableLevels(): string[] {
    const levels: string[] = [];
    for (const scene of this.scenes) {
      if (scene.level && levels.indexOf(scene.level) < 0) {
        levels.push(scene.level);
      }
    }
    // 难度从高到低排序（N5 最简单排前面）
    return levels.sort((a: string, b: string): number => b.localeCompare(a));
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 左侧：Logo + 标题
        Row() {
          // 朱红色方块 + "朱"字
          Stack() {
            Rect()
              .width(32)
              .height(32)
              .fill(ThemeColors.primary)
              .borderRadius(8);

            Text('朱')
              .fontSize(18)
              .fontColor('#FFFFFF')
              .fontWeight(700);
          }
          .width(32)
          .height(32);

          Column() {
            Text('朱音日语')
              .fontSize(18)
              .fontColor(ThemeColors.textPrimary)
              .fontWeight(700);

            Text('车载情景对话学习')
              .fontSize(10)
              .fontColor(ThemeColors.textTertiary)
              .margin({ top: 2 });
          }
          .margin({ left: 10 })
          .alignItems(HorizontalAlign.Start);
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);

        // 右侧：难度筛选
        Row() {
          this.LevelFilterBuilder();
        }
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: this.isLandscape ? 6 : 12,
        bottom: this.isLandscape ? 6 : 12
      })
      .backgroundColor(ThemeColors.bgCard)
      .border({
        width: { bottom: 1 },
        color: ThemeColors.divider
      });

      // 场景列表区域
      Scroll() {
        Column() {
          if (this.getFilteredScenes().length === 0) {
            // 空状态：筛选无结果或数据未加载时给出提示，避免页面空白
            Column() {
              Text(this.scenes.length === 0 ? '场景加载中…' : '该难度暂无场景')
                .fontSize(14)
                .fontColor(ThemeColors.textTertiary);
            }
            .width('100%')
            .padding({ top: 80 })
            .alignItems(HorizontalAlign.Center);
          } else {
            // 场景网格 - 使用 Flex wrap
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.getFilteredScenes(), (scene: Scene) => {
                SceneCard({
                  scene: scene,
                  progressPercent: this.progressMap[scene.id] || 0,
                  isCompleted: !!this.completedMap[scene.id],
                  onCardClick: () => {
                    this.onSceneClick(scene.id);
                  }
                })
                .width(this.getCardWidth())
                .margin({ right: 12, bottom: 12 });
              }, (scene: Scene) => scene.id);
            }
            .width('100%')
            .padding(this.isLandscape ? 12 : 16);
          }
        }
        .width('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const w = Number(newArea.width);
          if (!isNaN(w) && w > 0 && w !== this.containerWidth) {
            this.containerWidth = w;
          }
        });
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp);
  }

  @Builder
  LevelFilterBuilder() {
    Row() {
      this.LevelChipBuilder('all', '全部');
      // 只展示数据中实际存在的难度等级
      ForEach(this.getAvailableLevels(), (level: string) => {
        this.LevelChipBuilder(level, level);
      }, (level: string) => level);
    }
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  LevelChipBuilder(key: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selectedLevel === key ? '#FFFFFF' : ThemeColors.textSecondary)
      .backgroundColor(this.selectedLevel === key ? ThemeColors.primary : ThemeColors.bgCardElevated)
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 6 })
      .onClick(() => {
        this.selectedLevel = key;
      });
  }

  // 响应式卡片宽度：按容器宽度自动分列（基准卡片 200 + 右间距 12），铺满可用宽度
  // 窄屏单列时卡片占满整行，宽屏自动排 2~3 列，避免右侧留大片空白
  private getCardWidth(): number {
    const unit = 212; // 基准卡片宽 200 + 右间距 12
    const padding = 32; // Flex 左右 padding 16*2
    const available = this.containerWidth - padding;
    if (available <= 0) {
      return 200; // 布局完成前的初始值
    }
    const cols = Math.max(1, Math.floor(available / unit));
    return Math.max(120, Math.floor(available / cols) - 12);
  }
}
