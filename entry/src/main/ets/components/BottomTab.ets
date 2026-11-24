/**
 * 底部 TAB 导航组件
 * 用于手机窄屏场景的底部导航
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { ScenesIcon, ProgressIcon, SettingsIcon } from './PlayerIcons';

interface TabItem {
  key: string;
  icon: string;
  label: string;
}

@Component
export struct BottomTab {
  @Link currentTab: string;
  onTabChange: (tab: string) => void = () => {};

  private tabItems: TabItem[] = [
    { key: 'scenes', icon: '◆', label: '会话' },
    { key: 'progress', icon: '▩', label: '进度' },
    { key: 'settings', icon: '☰', label: '设置' }
  ];

  build() {
    Row() {
      ForEach(this.tabItems, (item: TabItem) => {
        this.TabItemBuilder(item);
      }, (item: TabItem) => item.key);
    }
    .width('100%')
    .height(56)
    .backgroundColor(ThemeColors.bgCard)
    .justifyContent(FlexAlign.SpaceAround)
    .alignItems(VerticalAlign.Center)
    .border({
      width: { top: 1 },
      color: ThemeColors.divider
    });
  }

  @Builder
  TabItemBuilder(item: TabItem) {
    Column() {
            if (item.key === 'scenes') {
        ScenesIcon({ color: this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textSecondary, iconSize: 22 });
      } else if (item.key === 'progress') {
        ProgressIcon({ color: this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textSecondary, iconSize: 22 });
      } else {
        SettingsIcon({ color: this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textSecondary, iconSize: 22 });
      }

      Text(item.label)
        .fontSize(10)
        .fontColor(this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textSecondary)
        .margin({ top: 2 });
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTabChange(item.key);
    });
  }
}
