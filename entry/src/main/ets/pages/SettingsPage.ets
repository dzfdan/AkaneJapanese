/**
 * 设置页
 * 展示和管理用户偏好设置
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { UserSettings } from '../model/UserSettings';
import { SettingsStore } from '../service/SettingsStore';
import { SettingItemSwitch } from '../components/SettingItemSwitch';
import { SettingItemSelect } from '../components/SettingItemSelect';
import appLogger from '../utils/Logger';

interface OptionItem {
  label: string;
  value: string;
}

@Component
export struct SettingsPage {
  @State showRomaji: boolean = true;
  @State showTranslation: boolean = true;
  @State defaultSpeed: string = '1.0';
  @State theme: string = 'dark';
  @State isLoading: boolean = true;
  // 横屏（16:9）适配：左右双栏
  @StorageProp('isLandscape') isLandscape: boolean = false;

  aboutToAppear(): void {
    this.loadSettings();
  }

  private async loadSettings(): Promise<void> {
    this.isLoading = true;

    try {
      const settingsStore = SettingsStore.getInstance();
      const settings: UserSettings = settingsStore.getSettings();

      this.showRomaji = settings.showRomaji;
      this.showTranslation = settings.showTranslation;
      this.defaultSpeed = settings.defaultSpeed.toString();
      this.theme = settings.theme;
    } catch (error) {
      appLogger.error('SettingsPage: loadSettings failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  private async handleShowRomajiChange(value: boolean): Promise<void> {
    try {
      const settingsStore = SettingsStore.getInstance();
      await settingsStore.setShowRomaji(value);
    } catch (error) {
      appLogger.error('SettingsPage: setShowRomaji failed', error);
    }
  }

  private async handleShowTranslationChange(value: boolean): Promise<void> {
    try {
      const settingsStore = SettingsStore.getInstance();
      await settingsStore.setShowTranslation(value);
    } catch (error) {
      appLogger.error('SettingsPage: setShowTranslation failed', error);
    }
  }

  private async handleDefaultSpeedChange(value: string): Promise<void> {
    try {
      const speed = parseFloat(value);
      if (!isNaN(speed)) {
        const settingsStore = SettingsStore.getInstance();
        await settingsStore.setDefaultSpeed(speed);
      }
    } catch (error) {
      appLogger.error('SettingsPage: setDefaultSpeed failed', error);
    }
  }

  private async handleThemeChange(value: string): Promise<void> {
    try {
      const settingsStore = SettingsStore.getInstance();
      await settingsStore.setTheme(value as 'dark' | 'light' | 'system');
    } catch (error) {
      appLogger.error('SettingsPage: setTheme failed', error);
    }
  }

  private getSpeedOptions(): OptionItem[] {
    return AppConstants.SPEED_OPTIONS.map((speed: number): OptionItem => {
      return {
        label: `${speed}x`,
        value: speed.toString()
      };
    });
  }

  private getThemeOptions(): OptionItem[] {
    return [
      { label: '深色模式', value: 'dark' },
      { label: '浅色模式', value: 'light' },
      { label: '跟随系统', value: 'system' }
    ];
  }

  build() {
    Column() {
      // 顶部标题
      Text('设置')
        .fontSize(this.isLandscape ? 20 : 24)
        .fontWeight(700)
        .fontColor(ThemeColors.textPrimary)
        .width('100%')
        .margin({ bottom: this.isLandscape ? 12 : 20 });

      if (this.isLoading) {
        this.LoadingBuilder();
      } else {
        Scroll() {
          if (this.isLandscape) {
            // 横屏（16:9）：左列学习设置 + 外观，右列关于
            Row() {
              Column() {
                this.StudyPrefsBuilder();
              }
              .layoutWeight(1)
              .margin({ right: 16 })
              .alignItems(HorizontalAlign.Start);

              Column() {
                this.AboutSectionBuilder();
                this.FooterBuilder();
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start);
            }
            .width('100%')
            .alignItems(VerticalAlign.Top);
          } else {
            Column() {
              this.StudyPrefsBuilder();
              this.AboutSectionBuilder();
              this.FooterBuilder();
            }
            .width('100%');
          }
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .padding(this.isLandscape ? 12 : 16);
  }

  // ---- 学习设置 + 外观 ----
  @Builder
  StudyPrefsBuilder() {
    Column() {
      // 学习设置分组
      this.SectionHeaderBuilder('学习设置');

      SettingItemSwitch({
        title: '显示罗马音',
        description: '在日文下方显示罗马音标注',
        isOn: $showRomaji,
        onChange: (value: boolean) => this.handleShowRomajiChange(value)
      })
      .margin({ bottom: 8 });

      SettingItemSwitch({
        title: '显示中文翻译',
        description: '在日文下方显示中文翻译',
        isOn: $showTranslation,
        onChange: (value: boolean) => this.handleShowTranslationChange(value)
      })
      .margin({ bottom: 8 });

      SettingItemSelect({
        title: '默认倍速',
        options: this.getSpeedOptions(),
        selectedValue: $defaultSpeed,
        onChange: (value: string) => this.handleDefaultSpeedChange(value)
      })
      .margin({ bottom: 24 });

      // 外观分组
      this.SectionHeaderBuilder('外观');

      SettingItemSelect({
        title: '主题',
        options: this.getThemeOptions(),
        selectedValue: $theme,
        onChange: (value: string) => this.handleThemeChange(value)
      })
      .margin({ bottom: this.isLandscape ? 8 : 24 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  // ---- 关于分组 ----
  @Builder
  AboutSectionBuilder() {
    Column() {
      this.SectionHeaderBuilder('关于');

      this.AboutItemBuilder('版本号', '1.0.0');
      Column() {
        this.AboutItemBuilder('应用介绍', '和风朱音 - 车载日语学习');
      }
      .margin({ bottom: 24 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  // ---- 底部说明 ----
  @Builder
  FooterBuilder() {
    Text('© 2026 朱音日语. 保留所有权利.')
      .fontSize(11)
      .fontColor(ThemeColors.textTertiary)
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ bottom: 16 });
  }

  // ---- 分组标题 ----
  @Builder
  SectionHeaderBuilder(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(ThemeColors.textSecondary)
      .fontWeight(600)
      .width('100%')
      .margin({ bottom: 8, left: 4 });
  }

  // ---- 关于信息行 ----
  @Builder
  AboutItemBuilder(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor(ThemeColors.textPrimary)
        .layoutWeight(1);

      Text(value)
        .fontSize(13)
        .fontColor(ThemeColors.textTertiary);
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .margin({ bottom: 8 });
  }

  // ---- 加载状态 ----
  @Builder
  LoadingBuilder() {
    Column() {
      Text('加载中...')
        .fontSize(14)
        .fontColor(ThemeColors.textSecondary);
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }
}
