/**
 * 场景卡片组件
 * 用于场景列表中展示单个学习场景
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Scene } from '../model/Scene';

@Component
export struct SceneCard {
  @Prop scene: Scene;
  @Prop progressPercent: number = 0;
  @Prop isCompleted: boolean = false;
  onClick?: () => void;

  build() {
    Column() {
      // 日文标题
      Text(this.scene.titleJa)
        .fontSize(16)
        .fontColor(ThemeColors.textPrimary)
        .fontWeight(700)
        .width('100%')
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(1);

      // 中文副标题
      Text(this.scene.titleZh)
        .fontSize(12)
        .fontColor(ThemeColors.textSecondary)
        .width('100%')
        .margin({ top: 4 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(1);

      // 底部：难度标签 + 状态
      Row() {
        // 难度标签
        Text(this.scene.level)
          .fontSize(10)
          .fontColor(ThemeColors.textTertiary)
          .backgroundColor(ThemeColors.bgCardElevated)
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 });

        Blank();

        // 状态区域
        if (this.isCompleted) {
          // 已完成
          Row() {
            Text('✓')
              .fontSize(12)
              .fontColor(ThemeColors.success)
              .fontWeight(700);

            Text('完成')
              .fontSize(10)
              .fontColor(ThemeColors.success)
              .margin({ left: 2 });
          }
        } else if (this.progressPercent > 0) {
          // 进行中 - 进度条
          Row() {
            Stack({ alignContent: Alignment.Start }) {
              // 背景
              Rect()
                .width(60)
                .height(4)
                .fill(ThemeColors.bgCardElevated)
                .borderRadius(2);

              // 前景进度
              Rect()
                .width(this.getProgressWidth())
                .height(4)
                .fill(ThemeColors.primary)
                .borderRadius(2);
            }
          }
        } else {
          // 未开始
          Text('未开始')
            .fontSize(10)
            .fontColor(ThemeColors.textTertiary);
        }
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(16)
    .border({
      width: { left: 4 },
      color: this.getBorderColor()
    })
    .onClick(() => {
      if (this.onClick) {
        this.onClick();
      }
    });
  }

  private getBorderColor(): string {
    if (this.isCompleted) {
      return ThemeColors.success;
    }
    if (this.progressPercent > 0) {
      return ThemeColors.primary;
    }
    return ThemeColors.divider;
  }

  private getProgressWidth(): number {
    const percent = Math.max(0, Math.min(100, this.progressPercent));
    return 60 * (percent / 100);
  }
}
