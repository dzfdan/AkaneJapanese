/**
 * 底部 TAB 导航组件
 * 用于手机窄屏场景的底部导航
 */

import { ThemeColors } from '../constants/ThemeConstants';

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
    { key: 'scenes', icon: '🎧', label: '会话' },
    { key: 'progress', icon: '📊', label: '进度' },
    { key: 'favorites', icon: '⭐', label: '收藏' },
    { key: 'settings', icon: '⚙️', label: '设置' }
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
      Text(item.icon)
        .fontSize(18);

      Text(item.label)
        .fontSize(10)
        .fontColor(this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textTertiary)
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
