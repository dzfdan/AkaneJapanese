/**
 * 场景列表页
 * 展示所有学习场景，支持驾驶/驻车两种模式展示
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { SceneCard } from '../components/SceneCard';
import { ModeSwitcher } from '../components/ModeSwitcher';
import { Scene } from '../model/Scene';
import { UserProgress } from '../model/UserProgress';
import { SceneRepository } from '../service/SceneRepository';
import { ProgressStore } from '../service/ProgressStore';
import { ModeManager, AppMode } from '../service/ModeManager';
import appLogger from '../utils/Logger';

@Component
export struct SceneListPage {
  @Link currentMode: 'driving' | 'parked';
  onSceneClick: (sceneId: string) => void = () => {};

  @State scenes: Scene[] = [];
  @State completedMap: Record<string, boolean> = {};
  @State progressMap: Record<string, number> = {};
  @State selectedLevel: string = 'all';

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

  private handleModeChange(mode: 'driving' | 'parked'): void {
    ModeManager.getInstance().setMode(mode);
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

        // 右侧：模式切换 + 难度筛选
        Row() {
          // 难度筛选（驻车模式显示）
          if (this.currentMode === 'parked') {
            this.LevelFilterBuilder();
          }

          // 模式切换器
          ModeSwitcher({
            currentMode: $currentMode,
            onModeChange: (mode: 'driving' | 'parked') => {
              this.handleModeChange(mode);
            }
          })
          .margin({ left: 12 });
        }
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(ThemeColors.bgCard)
      .border({
        width: { bottom: 1 },
        color: ThemeColors.divider
      });

      // 场景列表区域
      Scroll() {
        Column() {
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
          .padding(16);
        }
        .width('100%');
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
      this.LevelChipBuilder('N5', 'N5');
      this.LevelChipBuilder('N4', 'N4');
      this.LevelChipBuilder('N3', 'N3');
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

  private getCardWidth(): number {
    // 驾驶模式卡片更大更易点击，驻车模式信息更丰富但卡片稍小
    if (this.currentMode === 'driving') {
      return 220;
    } else {
      return 200;
    }
  }
}
