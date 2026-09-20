/**
 * 测验题卡片组件
 * 用于展示单道测验题目及选项
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { QuizItem } from '../model/QuizItem';

@Component
export struct QuizCard {
  @Prop quiz: QuizItem;
  @Prop selectedIndex: number = -1;
  @Prop showResult: boolean = false;
  onSelect: (index: number) => void = () => {};

  build() {
    Column() {
      // 题目
      Text(this.quiz.questionZh)
        .fontSize(14)
        .fontColor(ThemeColors.textPrimary)
        .fontWeight(600)
        .width('100%');

      // 选项列表
      Column() {
        ForEach(this.quiz.options, (option: string, index: number) => {
          this.OptionBuilder(option, index);
        }, (option: string, index: number) => `${index}_${option}`);
      }
      .width('100%')
      .margin({ top: 12 });

      // 解析
      if (this.showResult) {
        Column() {
          Text('解析')
            .fontSize(12)
            .fontColor(ThemeColors.primary)
            .fontWeight(600)
            .width('100%');

          Text(this.quiz.explanationZh)
            .fontSize(12)
            .fontColor(ThemeColors.textSecondary)
            .width('100%')
            .margin({ top: 4 });
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeColors.bgCardElevated)
        .borderRadius(8)
        .margin({ top: 12 });
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12);
  }

  @Builder
  OptionBuilder(option: string, index: number) {
    Row() {
      // 单选按钮
      Stack() {
        Circle()
          .width(20)
          .height(20)
          .fill(this.getOptionBgColor(index))
          .stroke(this.getOptionBorderColor(index))
          .strokeWidth(2);

        if (this.selectedIndex === index) {
          Circle()
            .width(10)
            .height(10)
            .fill('#FFFFFF');
        }
      }
      .width(20)
      .height(20);

      // 选项文字
      Text(option)
        .fontSize(13)
        .fontColor(this.getOptionTextColor(index))
        .layoutWeight(1)
        .margin({ left: 10 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(2);
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getOptionBgColor(index))
    .borderRadius(10)
    .border({
      width: 1,
      color: this.getOptionBorderColor(index)
    })
    .margin({ bottom: index < this.quiz.options.length - 1 ? 8 : 0 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.showResult) {
        this.onSelect(index);
      }
    });
  }

  private getOptionBgColor(index: number): string {
    if (!this.showResult) {
      // 未显示结果时
      if (this.selectedIndex === index) {
        return ThemeColors.bgCardElevated;
      }
      return ThemeColors.bgCardElevated;
    }

    // 显示结果时
    if (index === this.quiz.correctIndex) {
      // 正确答案
      return this.hexToRgba(ThemeColors.success, 0.15);
    }
    if (this.selectedIndex === index && index !== this.quiz.correctIndex) {
      // 选中了错误答案
      return this.hexToRgba(ThemeColors.error, 0.15);
    }
    return ThemeColors.bgCardElevated;
  }

  private getOptionBorderColor(index: number): string {
    if (!this.showResult) {
      // 未显示结果时
      if (this.selectedIndex === index) {
        return ThemeColors.primary;
      }
      return ThemeColors.divider;
    }

    // 显示结果时
    if (index === this.quiz.correctIndex) {
      return ThemeColors.success;
    }
    if (this.selectedIndex === index && index !== this.quiz.correctIndex) {
      return ThemeColors.error;
    }
    return ThemeColors.divider;
  }

  private getOptionTextColor(index: number): string {
    if (!this.showResult) {
      return ThemeColors.textPrimary;
    }

    if (index === this.quiz.correctIndex) {
      return ThemeColors.success;
    }
    if (this.selectedIndex === index && index !== this.quiz.correctIndex) {
      return ThemeColors.error;
    }
    return ThemeColors.textPrimary;
  }

  /**
   * 将十六进制颜色转换为 RGBA 格式
   */
  private hexToRgba(hex: string, alpha: number): string {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }
}
