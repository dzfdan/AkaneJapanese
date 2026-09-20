/**
 * 设置项 - 选择组件
 * 左侧标题，右侧当前值+箭头，点击弹出底部选择面板
 */

import { ThemeColors } from '../constants/ThemeConstants';

interface SelectOption {
  label: string;
  value: string;
}

@Component
export struct SettingItemSelect {
  @Prop title: string = '';
  @Prop options: SelectOption[] = [];
  @Link selectedValue: string;
  onChange?: (value: string) => void;

  @State showSheet: boolean = false;

  private getSelectedLabel(): string {
    const found = this.options.find((opt: SelectOption): boolean => opt.value === this.selectedValue);
    return found ? found.label : '';
  }

  private handleSelect(value: string): void {
    if (this.selectedValue !== value) {
      this.selectedValue = value;
      if (this.onChange) {
        this.onChange(value);
      }
    }
    this.showSheet = false;
  }

  build() {
    Row() {
      // 左侧：标题
      Text(this.title)
        .fontSize(14)
        .fontColor(ThemeColors.textPrimary)
        .fontWeight(500)
        .layoutWeight(1);

      // 右侧：当前值 + 箭头
      Row() {
        Text(this.getSelectedLabel())
          .fontSize(13)
          .fontColor(ThemeColors.textSecondary);

        Text('›')
          .fontSize(18)
          .fontColor(ThemeColors.textTertiary)
          .margin({ left: 4 });
      }
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.showSheet = true;
    })
    .bindSheet(this.showSheet, this.SheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: ThemeColors.bgCard,
      onDisappear: () => {
        this.showSheet = false;
      }
    });
  }

  @Builder
  SheetBuilder() {
    Column() {
      // 标题
      Text(this.title)
        .fontSize(16)
        .fontColor(ThemeColors.textPrimary)
        .fontWeight(600)
        .width('100%')
        .margin({ bottom: 12 });

      // 选项列表
      Column() {
        ForEach(this.options, (option: SelectOption, index: number) => {
          this.OptionItemBuilder(option, index);
        }, (option: SelectOption) => option.value);
      }
      .width('100%');

      // 取消按钮
      Text('取消')
        .fontSize(14)
        .fontColor(ThemeColors.textTertiary)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .backgroundColor(ThemeColors.bgCardElevated)
        .borderRadius(10)
        .margin({ top: 12 })
        .onClick(() => {
          this.showSheet = false;
        });
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeColors.bgCard);
  }

  @Builder
  OptionItemBuilder(option: SelectOption, index: number) {
    Row() {
      Text(option.label)
        .fontSize(14)
        .fontColor(this.selectedValue === option.value ? ThemeColors.primary : ThemeColors.textPrimary)
        .layoutWeight(1);

      if (this.selectedValue === option.value) {
        Text('✓')
          .fontSize(16)
          .fontColor(ThemeColors.primary)
          .fontWeight(700);
      }
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .border({
      width: { bottom: index < this.options.length - 1 ? 1 : 0 },
      color: ThemeColors.divider
    })
    .onClick(() => {
      this.handleSelect(option.value);
    });
  }
}
