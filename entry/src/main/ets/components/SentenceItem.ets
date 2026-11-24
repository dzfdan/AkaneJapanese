/**
 * 句子条目组件
 * 用于学习详情页展示单句对话
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Sentence } from '../model/Sentence';
import { FuriganaText } from '../components/FuriganaText';
import { PlayIcon, PauseIcon } from './PlayerIcons';

@Component
export struct SentenceItem {
  @Prop sentence: Sentence;
  @Prop showRomaji: boolean = true;
  @Prop showTranslation: boolean = true;
  @Prop isFavorite: boolean = false;
  @Prop isPlaying: boolean = false;
  onPlay: () => void = () => {};
  onToggleFavorite: () => void = () => {};

  build() {
    Column() {
      // 说话人
      Text(this.sentence.speakerRoleZh)
        .fontSize(9)
        .fontColor(ThemeColors.primary)
        .fontWeight(600)
        .width('100%');

      // 日文原文（含振假名注音）
      FuriganaText({
        segments: this.sentence.segments || [],
        japanese: this.sentence.japanese,
        fontSize: 15,
        fontColor: ThemeColors.textPrimary,
        containerWidth: '100%'
      })
        .margin({ top: 4 });

      // 罗马音
      if (this.showRomaji) {
        Text(this.sentence.romaji)
          .fontSize(11)
          .fontColor(ThemeColors.textSecondary)
          .width('100%')
          .margin({ top: 2 });
      }

      // 中文翻译
      if (this.showTranslation) {
        Text(this.sentence.translation)
          .fontSize(11)
          .fontColor(ThemeColors.textTertiary)
          .width('100%')
          .margin({ top: 2 });
      }

      // 底部操作区
      Row() {
        // 播放按钮
        Row() {
          if (this.isPlaying) {
            PauseIcon({ color: ThemeColors.primary, iconSize: 18 });
          } else {
            PlayIcon({ color: ThemeColors.primary, iconSize: 18 });
          }
        }
        .padding(8)
        .backgroundColor(ThemeColors.bgCardElevated)
        .borderRadius(8)
        .onClick(() => {
          this.onPlay();
        });

        Blank();

      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .border({
      width: { left: this.isPlaying ? 3 : 0 },
      color: ThemeColors.primary
    });
  }
}
