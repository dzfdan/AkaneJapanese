/**
 * 振假名注音文本组件
 * 在汉字上方显示假名读音（furigana），segments 为空时回退到 japanese 纯文本
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Segment } from '../model/Sentence';

@Component
export struct FuriganaText {
  /** 文本段数组（含注音），为空时回退到 japanese 纯文本 */
  @Prop segments: Segment[] = [];
  /** 纯文本回退（segments 为空时显示） */
  @Prop japanese: string = '';
  /** 主字号 */
  @Prop fontSize: number = 16;
  /** 主字体颜色 */
  @Prop fontColor: string = ThemeColors.textPrimary;
  /** 主字重 */
  @Prop fontWeight: number = 400;
  /** 文本对齐 */
  @Prop textAlign: TextAlign = TextAlign.Start;
  /** 容器宽度（避免与 CustomComponent.width 冲突） */
  @Prop containerWidth: string = '100%';
  /** 紧凑模式（播放条等单行场景）：单行 + clip，振假名仍垂直叠加 */
  @Prop compact: boolean = false;

  build() {
    if (this.segments.length === 0) {
      // 无注音数据，回退纯文本
      if (this.compact) {
        Text(this.japanese || '—')
          .fontSize(this.fontSize)
          .fontColor(this.fontColor)
          .fontWeight(this.fontWeight)
          .textAlign(this.textAlign)
          .width(this.containerWidth)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      } else {
        Text(this.japanese || '—')
          .fontSize(this.fontSize)
          .fontColor(this.fontColor)
          .fontWeight(this.fontWeight)
          .textAlign(this.textAlign)
          .width(this.containerWidth);
      }
    } else {
      if (this.compact) {
        // 紧凑模式：单行 Row + clip
        Row() {
          ForEach(this.segments, (seg: Segment) => {
            if (seg.kana) {
              Column() {
                Text(seg.kana)
                  .fontSize(this.fontSize * 0.5)
                  .fontColor(this.fontColor)
                  .lineHeight(this.fontSize * 0.6)
                  .height(this.fontSize * 0.6);
                Text(seg.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.fontColor)
                  .fontWeight(this.fontWeight)
                  .lineHeight(this.fontSize * 1.2);
              }
              .alignItems(HorizontalAlign.Center)
              .margin({ right: 1 });
            } else {
              Column() {
                Text(' ')
                  .fontSize(this.fontSize * 0.5)
                  .lineHeight(this.fontSize * 0.6)
                  .height(this.fontSize * 0.6);
                Text(seg.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.fontColor)
                  .fontWeight(this.fontWeight)
                  .lineHeight(this.fontSize * 1.2);
              }
              .alignItems(HorizontalAlign.Center);
            }
          });
        }
        .width(this.containerWidth)
        .clip(true);
      } else {
        // 完整模式：Flex 自动换行
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.segments, (seg: Segment) => {
            if (seg.kana) {
              Column() {
                Text(seg.kana)
                  .fontSize(this.fontSize * 0.5)
                  .fontColor(this.fontColor)
                  .lineHeight(this.fontSize * 0.6);
                Text(seg.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.fontColor)
                  .fontWeight(this.fontWeight)
                  .lineHeight(this.fontSize * 1.2);
              }
              .alignItems(HorizontalAlign.Center)
              .margin({ right: 1 });
            } else {
              Column() {
                Text(' ')
                  .fontSize(this.fontSize * 0.5)
                  .lineHeight(this.fontSize * 0.6);
                Text(seg.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.fontColor)
                  .fontWeight(this.fontWeight)
                  .lineHeight(this.fontSize * 1.2);
              }
              .alignItems(HorizontalAlign.Center);
            }
          });
        }
        .width(this.containerWidth);
      }
    }
  }
}
