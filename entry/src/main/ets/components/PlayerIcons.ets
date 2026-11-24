/**
 * 播放控制矢量图标组件
 * 使用 Path 矢量绘制，避免 Unicode 字符在不同设备上的渲染差异（emoji 化、粗细不一）。
 * 注意：Path commands 坐标单位为 px（物理像素），必须用 vp2px() 把 iconSize(vp) 换算成 px，
 * 否则在高密度屏幕上图形只渲染约 1/density 大小且锚定左上角。
 * 保证上一句/下一句/播放/暂停四个图标风格完全统一
 * 图形按 24 单位网格设计：跳转/暂停图标占 2~22 格（83%），
 * 播放三角形占 0.5~23.5 格（96% 高度），并做光学居中——
 * 质心偏左 1.45 格与边界偏右 1.45 格互相抵消，视觉上精确居中
 */

@Component
export struct SkipBackIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${2 * s} ${2 * s} L${5.5 * s} ${2 * s} L${5.5 * s} ${22 * s} L${2 * s} ${22 * s} Z M${21.5 * s} ${2 * s} L${21.5 * s} ${22 * s} L${10.5 * s} ${12 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct SkipNextIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${18.5 * s} ${2 * s} L${22 * s} ${2 * s} L${22 * s} ${22 * s} L${18.5 * s} ${22 * s} Z M${2.5 * s} ${2 * s} L${2.5 * s} ${22 * s} L${13.5 * s} ${12 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct PlayIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${4.7 * s} ${0.5 * s} L${4.7 * s} ${23.5 * s} L${22.2 * s} ${12 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct PauseIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${4 * s} ${2 * s} L${10 * s} ${2 * s} L${10 * s} ${22 * s} L${4 * s} ${22 * s} Z M${14 * s} ${2 * s} L${20 * s} ${2 * s} L${20 * s} ${22 * s} L${14 * s} ${22 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct SlowIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${3 * s} ${16 * s} C${3 * s} ${10.97 * s} ${7.03 * s} ${7 * s} ${12 * s} ${7 * s} C${16.97 * s} ${7 * s} ${21 * s} ${10.97 * s} ${21 * s} ${16 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct RecordIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${12 * s} ${2 * s} C${17.52 * s} ${2 * s} ${22 * s} ${6.48 * s} ${22 * s} ${12 * s} C${22 * s} ${17.52 * s} ${17.52 * s} ${22 * s} ${12 * s} ${22 * s} C${6.48 * s} ${22 * s} ${2 * s} ${17.52 * s} ${2 * s} ${12 * s} C${2 * s} ${6.48 * s} ${6.48 * s} ${2 * s} ${12 * s} ${2 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct ScenesIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${12 * s} ${2 * s} L${21.5 * s} ${12 * s} L${12 * s} ${22 * s} L${2.5 * s} ${12 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct ProgressIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${3 * s} ${14 * s} L${7 * s} ${14 * s} L${7 * s} ${21 * s} L${3 * s} ${21 * s} Z M${10 * s} ${9 * s} L${14 * s} ${9 * s} L${14 * s} ${21 * s} L${10 * s} ${21 * s} Z M${17 * s} ${4 * s} L${21 * s} ${4 * s} L${21 * s} ${21 * s} L${17 * s} ${21 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}

@Component
export struct SettingsIcon {
  color: ResourceColor = '#E5484D';
  iconSize: number = 24;

  private cmds(): string {
    const s = vp2px(this.iconSize) / 24;
    return `M${3 * s} ${4.2 * s} L${21 * s} ${4.2 * s} L${21 * s} ${6.8 * s} L${3 * s} ${6.8 * s} Z M${3 * s} ${10.7 * s} L${21 * s} ${10.7 * s} L${21 * s} ${13.3 * s} L${3 * s} ${13.3 * s} Z M${3 * s} ${17.2 * s} L${21 * s} ${17.2 * s} L${21 * s} ${19.8 * s} L${3 * s} ${19.8 * s} Z`;
  }

  build() {
    Path({ width: this.iconSize, height: this.iconSize })
      .commands(this.cmds())
      .fill(this.color);
  }
}