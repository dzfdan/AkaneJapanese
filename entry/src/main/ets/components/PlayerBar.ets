/**
 * 底部播放条组件（完整模式）
 * 用于平板/车机宽屏场景的播放控制
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Segment } from '../model/Sentence';
import { FuriganaText } from '../components/FuriganaText';
import { formatDuration } from '../utils/TimeUtil';
import { SkipBackIcon, SkipNextIcon, PlayIcon, PauseIcon } from './PlayerIcons';

@Component
export struct PlayerBar {
  @Prop sceneTitle: string = '';
  @Prop sentenceJapanese: string = '';
  @Prop segments: Segment[] = [];
  @Prop isPlaying: boolean = false;
  @Prop currentTimeMs: number = 0;
  @Prop durationMs: number = 0;
  onPlayPause: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onBarClick?: () => void;
  @State showCompact: boolean = false;
  // 横屏（16:9）适配：紧凑内边距、控件居中
  @StorageProp('isLandscape') isLandscape: boolean = false;

  build() {
    Row() {
      // 控制按钮 + 进度（移除左侧场景标题区域）
      Row() {
        // 上一首按钮
        this.CircleButton('skipBack', 40, ThemeColors.bgCardElevated, ThemeColors.primary, () => {
          this.onPrev();
        });

        // 播放/暂停按钮（主按钮）
        Stack() {
          Circle()
            .width(52)
            .height(52)
            .fill(ThemeColors.primary);

          if (this.isPlaying) {
            PauseIcon({ color: '#FFFFFF', iconSize: 34 });
          } else {
            PlayIcon({ color: '#FFFFFF', iconSize: 34 });
          }
        }
        .width(52)
        .height(52)
        .margin({ left: 8, right: 8 })
        .onClick(() => {
          this.onPlayPause();
        });

        // 下一首按钮
        this.CircleButton('skipNext', 40, ThemeColors.bgCardElevated, ThemeColors.primary, () => {
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
      .alignItems(VerticalAlign.Center)
      .justifyContent(this.isLandscape ? FlexAlign.Center : FlexAlign.Start);
    }
    .width('100%')
    .padding(this.isLandscape ? 8 : 12)
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
    iconSize: number = 24
  ) {
    Stack() {
      Circle()
        .width(size)
        .height(size)
        .fill(bgColor);

      if (icon === 'skipBack') {
        SkipBackIcon({ color: iconColor, iconSize: iconSize });
      } else if (icon === 'skipNext') {
        SkipNextIcon({ color: iconColor, iconSize: iconSize });
      } else if (icon === 'pause') {
        PauseIcon({ color: iconColor, iconSize: iconSize });
      } else {
        PlayIcon({ color: iconColor, iconSize: iconSize });
      }
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
