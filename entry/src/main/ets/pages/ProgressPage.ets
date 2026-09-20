/**
 * 学习进度页
 * 展示学习统计数据和最近学习场景
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Scene } from '../model/Scene';
import { UserProgress } from '../model/UserProgress';
import { ProgressStore } from '../service/ProgressStore';
import { SceneRepository } from '../service/SceneRepository';
import { SceneCard } from '../components/SceneCard';
import { formatTotalMinutes } from '../utils/TimeUtil';
import appLogger from '../utils/Logger';

interface RecentScene {
  scene: Scene;
  progress: number;
  isCompleted: boolean;
}

@Component
export struct ProgressPage {
  @State totalMinutes: number = 0;
  @State streakDays: number = 0;
  @State completedCount: number = 0;
  @State totalScenes: number = 0;
  @State lastStudyDate: string = '';
  @State todayMinutes: number = 0;
  @State recentScenes: RecentScene[] = [];
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    this.loadProgress();
  }

  private async loadProgress(): Promise<void> {
    this.isLoading = true;

    try {
      const progressStore = ProgressStore.getInstance();
      const progress: UserProgress = progressStore.getProgress();

      this.totalMinutes = progress.totalStudyMinutes;
      this.streakDays = progress.streakDays;
      this.completedCount = progress.completedScenes.length;
      this.lastStudyDate = progress.lastStudyDate;

      // 获取所有场景总数
      const repo = SceneRepository.getInstance();
      const allScenes = repo.getAllScenes();
      this.totalScenes = allScenes.length;

      // 计算今日学习时长（简化：从 totalMinutes 中估算，实际可根据日期记录）
      // MVP 版本直接展示累计学习的一个子项
      this.todayMinutes = this.getTodayMinutes(progress);

      // 加载最近学习场景
      this.loadRecentScenes(allScenes, progress);
    } catch (error) {
      appLogger.error('ProgressPage: loadProgress failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 获取今日学习分钟数
   * MVP 版本：如果今天有学习记录，估算一个值
   * 实际项目中应按日期存储每日学习时长
   */
  private getTodayMinutes(progress: UserProgress): number {
    const today = new Date().toISOString().split('T')[0];
    if (progress.lastStudyDate === today) {
      // 简化估算：取总时长的一小部分作为今日学习时长
      // 实际项目中应该有每日记录
      return Math.min(progress.totalStudyMinutes, 30);
    }
    return 0;
  }

  private loadRecentScenes(allScenes: Scene[], progress: UserProgress): void {
    const recent: RecentScene[] = [];

    // 优先展示已完成的场景
    for (const sceneId of progress.completedScenes) {
      const scene = allScenes.find((s: Scene): boolean => s.id === sceneId);
      if (scene) {
        recent.push({
          scene: scene,
          progress: 100,
          isCompleted: true
        });
      }
    }

    // 再展示进行中的场景
    for (const sceneId of Object.keys(progress.sceneProgress)) {
      if (!progress.completedScenes.includes(sceneId)) {
        const scene = allScenes.find((s: Scene): boolean => s.id === sceneId);
        if (scene) {
          recent.push({
            scene: scene,
            progress: progress.sceneProgress[sceneId] || 0,
            isCompleted: false
          });
        }
      }
    }

    // 如果没有学习记录，展示前几个场景作为推荐
    if (recent.length === 0 && allScenes.length > 0) {
      const count = Math.min(3, allScenes.length);
      for (let i = 0; i < count; i++) {
        recent.push({
          scene: allScenes[i],
          progress: 0,
          isCompleted: false
        });
      }
    }

    this.recentScenes = recent.slice(0, 6);
  }

  build() {
    Column() {
      // 顶部标题
      Text('学习进度')
        .fontSize(24)
        .fontWeight(700)
        .fontColor(ThemeColors.textPrimary)
        .width('100%')
        .margin({ bottom: 4 });

      // 上次学习
      if (this.lastStudyDate && this.lastStudyDate.length > 0) {
        Text(`上次学习：${this.lastStudyDate}`)
          .fontSize(12)
          .fontColor(ThemeColors.textTertiary)
          .width('100%')
          .margin({ bottom: 16 });
      }

      if (this.isLoading) {
        this.LoadingBuilder();
      } else {
        // 统计卡片（2列网格）
        Column() {
          this.StatsGridBuilder();
        }
        .margin({ bottom: 24 });

        // 最近学习场景列表
        Text('最近学习')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(ThemeColors.textPrimary)
          .width('100%')
          .margin({ bottom: 12 });

        if (this.recentScenes.length === 0) {
          this.EmptyStateBuilder();
        } else {
          List() {
            ForEach(this.recentScenes, (item: RecentScene, index: number) => {
              ListItem() {
                SceneCard({
                  scene: item.scene,
                  progressPercent: item.progress,
                  isCompleted: item.isCompleted
                });
              }
              .margin({ bottom: index < this.recentScenes.length - 1 ? 10 : 0 });
            }, (item: RecentScene) => item.scene.id);
          }
          .width('100%')
          .layoutWeight(1);
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .padding(16);
  }

  // ---- 统计卡片网格 ----
  @Builder
  StatsGridBuilder() {
    Column() {
      // 第一行
      Row() {
        Column() {
          this.StatCardBuilder(
            '连续打卡',
            `${this.streakDays} 天`,
            '🔥',
            ThemeColors.warning
          );
        }
        .layoutWeight(1)
        .margin({ right: 10 });

        Column() {
          this.StatCardBuilder(
            '累计学习',
            formatTotalMinutes(this.totalMinutes),
            '📚',
            ThemeColors.primary
          );
        }
        .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 10 });

      // 第二行
      Row() {
        Column() {
          this.StatCardBuilder(
            '已完成场景',
            `${this.completedCount} / ${this.totalScenes}`,
            '✓',
            ThemeColors.success
          );
        }
        .layoutWeight(1)
        .margin({ right: 10 });

        Column() {
          this.StatCardBuilder(
            '今日学习',
            `${this.todayMinutes} 分钟`,
            '⏱',
            ThemeColors.primaryLight
          );
        }
        .layoutWeight(1);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  StatCardBuilder(title: string, value: string, icon: string, accentColor: string) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(20);

        Blank();

        Text(value)
          .fontSize(18)
          .fontColor(accentColor)
          .fontWeight(700);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Text(title)
        .fontSize(12)
        .fontColor(ThemeColors.textSecondary)
        .width('100%')
        .margin({ top: 8 });
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12)
    .border({
      width: { top: 2 },
      color: accentColor
    });
  }

  // ---- 加载状态 ----
  @Builder
  LoadingBuilder() {
    Column() {
      Text('加载中...')
        .fontSize(14)
        .fontColor(ThemeColors.textSecondary);
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  // ---- 空状态 ----
  @Builder
  EmptyStateBuilder() {
    Column() {
      Text('📖')
        .fontSize(48);

      Text('还没有学习记录')
        .fontSize(14)
        .fontColor(ThemeColors.textTertiary)
        .margin({ top: 12 });

      Text('开始你的日语学习之旅吧')
        .fontSize(12)
        .fontColor(ThemeColors.textTertiary)
        .margin({ top: 4 });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }
}
