/**
 * 底部播放条组件（完整模式）
 * 用于平板/车机宽屏场景的播放控制
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { formatDuration } from '../utils/TimeUtil';

@Component
export struct PlayerBar {
  @Prop sceneTitle: string = '';
  @Prop sentenceJapanese: string = '';
  @Prop isPlaying: boolean = false;
  @Prop currentTimeMs: number = 0;
  @Prop durationMs: number = 0;
  onPlayPause: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onBarClick?: () => void;
  @State showCompact: boolean = false;

  build() {
    Row() {
      // 左侧：当前播放信息
      Column() {
        Text(this.sceneTitle)
          .fontSize(10)
          .fontColor(ThemeColors.textSecondary)
          .width('100%')
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1);

        Text(this.sentenceJapanese)
          .fontSize(14)
          .fontColor(ThemeColors.textPrimary)
          .fontWeight(600)
          .width('100%')
          .margin({ top: 2 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (this.onBarClick) {
          this.onBarClick();
        }
      });

      // 右侧：控制按钮 + 进度
      Row() {
        // 上一首按钮
        this.CircleButton('⏮', 40, ThemeColors.bgCardElevated, ThemeColors.textPrimary, () => {
          this.onPrev();
        });

        // 播放/暂停按钮（主按钮）
        Column() {
          this.CircleButton(
            this.isPlaying ? '⏸' : '▶',
            52,
            ThemeColors.primary,
            '#FFFFFF',
            () => {
              this.onPlayPause();
            },
            22
          );
        }
        .margin({ left: 8, right: 8 });

        // 下一首按钮
        this.CircleButton('⏭', 40, ThemeColors.bgCardElevated, ThemeColors.textPrimary, () => {
          this.onNext();
        });

        // 时间显示 + 进度条
        if (!this.showCompact) {
          Column() {
            // 时间显示
            Row() {
              Text(formatDuration(this.currentTimeMs / 1000))
                .fontSize(10)
                .fontColor(ThemeColors.textTertiary);

              Text('/')
                .fontSize(10)
                .fontColor(ThemeColors.textTertiary)
                .margin({ left: 2, right: 2 });

              Text(formatDuration(this.durationMs / 1000))
                .fontSize(10)
                .fontColor(ThemeColors.textTertiary);
            }
            .width(120)
            .justifyContent(FlexAlign.End);

            // 进度条
            Stack({ alignContent: Alignment.Start }) {
              Rect()
                .width(120)
                .height(4)
                .fill(ThemeColors.bgCardElevated)
                .borderRadius(2);

              Rect()
                .width(this.getProgressWidth())
                .height(4)
                .fill(ThemeColors.primary)
                .borderRadius(2);
            }
            .margin({ top: 4 });
          }
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.End);
        }
      }
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12)
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  CircleButton(
    icon: string,
    size: number,
    bgColor: string,
    iconColor: string,
    onClick: () => void,
    iconSize: number = 18
  ) {
    Stack() {
      Circle()
        .width(size)
        .height(size)
        .fill(bgColor);

      Text(icon)
        .fontSize(iconSize)
        .fontColor(iconColor);
    }
    .width(size)
    .height(size)
    .onClick(() => {
      onClick();
    });
  }

  private getProgressWidth(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    const percent = Math.max(0, Math.min(1, this.currentTimeMs / this.durationMs));
    return 120 * percent;
  }
}
