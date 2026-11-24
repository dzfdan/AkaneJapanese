/**
 * 迷你播放条组件
 * 用于手机窄屏场景的简易播放控制
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Segment } from '../model/Sentence';
import { FuriganaText } from '../components/FuriganaText';
import { PlayIcon, PauseIcon } from './PlayerIcons';

@Component
export struct MiniPlayer {
  @Prop sentenceJapanese: string = '';
  @Prop segments: Segment[] = [];
  @Prop isPlaying: boolean = false;
  onPlayPause: () => void = () => {};
  onBarClick?: () => void;

  build() {
    Row() {
      // 左侧：句子日文（含振假名注音）
      FuriganaText({
        segments: this.segments,
        japanese: this.sentenceJapanese,
        fontSize: 12,
        fontColor: ThemeColors.textPrimary,
        containerWidth: '100%',
        compact: true
      })
        .layoutWeight(1)
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

        if (this.isPlaying) {
          PauseIcon({ color: '#FFFFFF', iconSize: 22 });
        } else {
          PlayIcon({ color: '#FFFFFF', iconSize: 22 });
        }
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
