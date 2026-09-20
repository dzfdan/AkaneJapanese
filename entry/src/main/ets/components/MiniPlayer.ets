/**
 * 迷你播放条组件
 * 用于手机窄屏场景的简易播放控制
 */

import { ThemeColors } from '../constants/ThemeConstants';

@Component
export struct MiniPlayer {
  @Prop sentenceJapanese: string = '';
  @Prop isPlaying: boolean = false;
  onPlayPause: () => void = () => {};
  onBarClick?: () => void;

  build() {
    Row() {
      // 左侧：句子日文
      Text(this.sentenceJapanese)
        .fontSize(12)
        .fontColor(ThemeColors.textPrimary)
        .layoutWeight(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(1)
        .margin({ right: 8 })
        .onClick(() => {
          if (this.onBarClick) {
            this.onBarClick();
          }
        });

      // 右侧：播放/暂停按钮
      Stack() {
        Circle()
          .width(36)
          .height(36)
          .fill(ThemeColors.primary);

        Text(this.isPlaying ? '⏸' : '▶')
          .fontSize(16)
          .fontColor('#FFFFFF');
      }
      .width(36)
      .height(36)
      .onClick(() => {
        this.onPlayPause();
      });
    }
    .width('100%')
    .padding(10)
    .backgroundColor(ThemeColors.bgCard)
    .alignItems(VerticalAlign.Center)
    .border({
      width: { top: 1 },
      color: ThemeColors.divider
    });
  }
}
