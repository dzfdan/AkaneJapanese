/**
 * 句子条目组件
 * 用于学习详情页展示单句对话
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Sentence } from '../model/Sentence';

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

      // 日文原文
      Text(this.sentence.japanese)
        .fontSize(15)
        .fontColor(ThemeColors.textPrimary)
        .width('100%')
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
          Text(this.isPlaying ? '⏸' : '▶')
            .fontSize(12)
            .fontColor(ThemeColors.textPrimary);
        }
        .padding(8)
        .backgroundColor(ThemeColors.bgCardElevated)
        .borderRadius(8)
        .onClick(() => {
          this.onPlay();
        });

        Blank();

        // 收藏按钮
        Text(this.isFavorite ? '♥' : '♡')
          .fontSize(16)
          .fontColor(this.isFavorite ? ThemeColors.primary : ThemeColors.textTertiary)
          .padding(8)
          .onClick(() => {
            this.onToggleFavorite();
          });
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
