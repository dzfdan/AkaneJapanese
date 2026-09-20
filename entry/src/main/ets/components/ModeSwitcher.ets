/**
 * 模式切换器组件
 * 用于驾驶模式与驻车模式之间的切换
 */

import { ThemeColors } from '../constants/ThemeConstants';

@Component
export struct ModeSwitcher {
  @Link currentMode: 'driving' | 'parked';
  onModeChange: (mode: 'driving' | 'parked') => void = () => {};
  @State showConfirm: boolean = false;

  build() {
    Button() {
      Text(this.currentMode === 'driving' ? '切换驻车模式' : '切换驾驶模式')
        .fontSize(13)
        .fontColor(this.currentMode === 'driving' ? '#FFFFFF' : ThemeColors.textPrimary);
    }
    .type(ButtonType.Normal)
    .backgroundColor(this.currentMode === 'driving' ? ThemeColors.primary : ThemeColors.bgCardElevated)
    .borderRadius(20)
    .height(36)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      if (this.currentMode === 'driving') {
        // 切到驻车模式，需要确认
        this.showConfirm = true;
      } else {
        // 切到驾驶模式，直接切换（更安全）
        this.onModeChange('driving');
      }
    })
    .bindSheet($$this.showConfirm, this.ConfirmSheetBuilder(), {
      height: 240,
      dragBar: true,
      backgroundColor: ThemeColors.bgCard,
      onDisappear: () => {
        this.showConfirm = false;
      }
    });
  }

  @Builder
  ConfirmSheetBuilder() {
    Column() {
      Text('安全提示')
        .fontSize(16)
        .fontColor(ThemeColors.textPrimary)
        .fontWeight(600)
        .margin({ top: 24 });

      Text('请勿在行驶中操作，确认切换到驻车学习模式？')
        .fontSize(14)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: 16, left: 24, right: 24 });

      Row() {
        // 取消按钮
        Button('取消')
          .type(ButtonType.Normal)
          .backgroundColor(ThemeColors.bgCardElevated)
          .fontColor(ThemeColors.textPrimary)
          .fontSize(14)
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => {
            this.showConfirm = false;
          });

        // 确认按钮
        Button('确认切换')
          .type(ButtonType.Normal)
          .backgroundColor(ThemeColors.primary)
          .fontColor('#FFFFFF')
          .fontSize(14)
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.showConfirm = false;
            this.onModeChange('parked');
          });
      }
      .width('100%')
      .margin({ top: 24, left: 24, right: 24, bottom: 24 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center);
  }
}
