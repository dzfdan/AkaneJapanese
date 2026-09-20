/**
 * 侧边栏导航组件
 * 用于平板/车机宽屏场景的主导航
 */

import { ThemeColors } from '../constants/ThemeConstants';

interface NavItem {
  key: string;
  icon: string;
  label: string;
}

@Component
export struct SideNav {
  @Link currentTab: string;
  onTabChange: (tab: string) => void = () => {};
  @State isCompact: boolean = false;

  private navItems: NavItem[] = [
    { key: 'scenes', icon: '🎧', label: '会话' },
    { key: 'progress', icon: '📊', label: '进度' },
    { key: 'favorites', icon: '⭐', label: '收藏' },
    { key: 'settings', icon: '⚙️', label: '设置' }
  ];

  build() {
    Column() {
      // 顶部 Logo
      Column() {
        // 朱红色方块 + "朱"字
        Stack() {
          Rect()
            .width(this.isCompact ? 36 : 44)
            .height(this.isCompact ? 36 : 44)
            .fill(ThemeColors.primary)
            .borderRadius(8);

          Text('朱')
            .fontSize(this.isCompact ? 20 : 24)
            .fontColor('#FFFFFF')
            .fontWeight(700);
        }
        .width('100%')
        .height(this.isCompact ? 56 : 72)
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .padding({ top: this.isCompact ? 12 : 16, bottom: this.isCompact ? 8 : 12 });

      // 中间导航项
      Column() {
        ForEach(this.navItems, (item: NavItem) => {
          this.NavItemBuilder(item);
        }, (item: NavItem) => item.key);
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8 });

      // 底部模式切换占位（ModeSwitcher 组件由外部传入）
      Column() {
        Text('')
          .fontSize(12)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .padding({ bottom: this.isCompact ? 12 : 16 });
    }
    .width(this.isCompact ? 56 : 140)
    .height('100%')
    .backgroundColor(ThemeColors.bgCard);
  }

  @Builder
  NavItemBuilder(item: NavItem) {
    Row() {
      // 激活时左侧竖条
      if (this.currentTab === item.key) {
        Rect()
          .width(4)
          .height(24)
          .fill(ThemeColors.primary)
          .borderRadius(2)
          .margin({ right: this.isCompact ? 0 : 10 });
      } else if (!this.isCompact) {
        // 未激活时占位对齐
        Blank()
          .width(14);
      }

      // 图标
      Text(item.icon)
        .fontSize(this.isCompact ? 20 : 20)
        .opacity(this.currentTab === item.key ? 1 : 0.7);

      // 文字（非紧凑模式显示）
      if (!this.isCompact) {
        Text(item.label)
          .fontSize(14)
          .fontColor(this.currentTab === item.key ? ThemeColors.primary : ThemeColors.textSecondary)
          .fontWeight(this.currentTab === item.key ? 600 : 400)
          .margin({ left: 10 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1);
      }
    }
    .width('100%')
    .height(this.isCompact ? 52 : 48)
    .justifyContent(this.isCompact ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.isCompact ? 0 : 0, right: this.isCompact ? 0 : 12 })
    .onClick(() => {
      this.onTabChange(item.key);
    });
  }
}
