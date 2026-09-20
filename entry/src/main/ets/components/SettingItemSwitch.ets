/**
 * 设置项 - 开关组件
 * 左侧标题+描述，右侧 Switch 开关
 */

import { ThemeColors } from '../constants/ThemeConstants';

@Component
export struct SettingItemSwitch {
  @Prop title: string = '';
  @Prop description: string = '';
  @Link @Watch('onIsOnChange') isOn: boolean;
  onChange?: (value: boolean) => void;

  private onIsOnChange(): void {
    if (this.onChange) {
      this.onChange(this.isOn);
    }
  }

  build() {
    Row() {
      // 左侧：标题 + 描述
      Column() {
        Text(this.title)
          .fontSize(14)
          .fontColor(ThemeColors.textPrimary)
          .fontWeight(500)
          .width('100%');

        if (this.description && this.description.length > 0) {
          Text(this.description)
            .fontSize(11)
            .fontColor(ThemeColors.textTertiary)
            .width('100%')
            .margin({ top: 2 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      // 右侧：Switch 开关
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(ThemeColors.primary)
        .switchPointColor('#FFFFFF')
        .onChange((isOn: boolean) => {
          this.isOn = isOn;
        });
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .alignItems(VerticalAlign.Center);
  }
}
