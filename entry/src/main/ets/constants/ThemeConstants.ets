/**
 * 和风朱音主题颜色常量
 * 深色主题与 resources/base/element/color.json 对应
 */

export type ThemeMode = 'dark' | 'light';

export interface ThemeColorsType {
  /** 主色 - 朱红色 */
  primary: string;
  /** 主色 - 亮色 */
  primaryLight: string;
  /** 主色 - 暗色 */
  primaryDark: string;
  /** 应用背景色 */
  bgApp: string;
  /** 卡片背景色 */
  bgCard: string;
  /** 悬浮卡片背景色 */
  bgCardElevated: string;
  /** 主要文字颜色 */
  textPrimary: string;
  /** 次要文字颜色 */
  textSecondary: string;
  /** 三级文字颜色 */
  textTertiary: string;
  /** 分割线颜色 */
  divider: string;
  /** 成功色 */
  success: string;
  /** 警告色 */
  warning: string;
  /** 错误色 */
  error: string;
}

/**
 * 深色主题（默认）—— 墨黑底 + 米白暖色系文字
 */
export const ThemeColors: ThemeColorsType = {
  // 朱红色系（和风主题主色 - 温暖的朱红 #D4553A）
  primary: '#D4553A',
  primaryLight: '#E87A5F',
  primaryDark: '#B8442C',

  // 背景色（墨黑底 - 日式深色氛围）
  bgApp: '#0E0B08',
  bgCard: '#1A1510',
  bgCardElevated: '#2A231C',

  // 文字色（米白暖色系）
  textPrimary: '#F5E6D8',
  textSecondary: '#A89880',
  textTertiary: '#A0907C',

  // 分割线
  divider: '#3A2F24',

  // 语义色
  success: '#7CB342',
  warning: '#FFB74D',
  error: '#EF5350'
};

/**
 * 浅色主题 —— 米白底 + 深棕文字，保持和风配色语言
 * 对比度全部 ≥ WCAG AA 4.5:1（textPrimary/textSecondary/textTertiary vs bgCard）
 */
export const LightThemeColors: ThemeColorsType = {
  // 主色（浅色模式下需要更深，保证白底对比度 ≥4.5）
  primary: '#C23F2A',
  primaryLight: '#D4553A',
  primaryDark: '#9C2A1C',

  // 背景色（和风米色）
  bgApp: '#FAF7F4',
  bgCard: '#FFFFFF',
  bgCardElevated: '#F0EBE3',

  // 文字色（深棕暖色系）
  textPrimary: '#1A1510',
  textSecondary: '#5C5040',
  textTertiary: '#6E5E4A',

  // 分割线
  divider: '#E5DCD2',

  // 语义色（浅色模式下需加深以保证对比度）
  success: '#2E7D32',
  warning: '#B26A00',
  error: '#C62828'
};

/**
 * 根据 ThemeMode 返回对应的主题色板
 */
export function getThemeColorsByMode(mode: ThemeMode): ThemeColorsType {
  return mode === 'light' ? LightThemeColors : ThemeColors;
}

/**
 * 基于色板构建 ArkUI ThemeControl 所需的 CustomTheme
 * 未显式设置 fontColor 的 Text/Span/Button 会使用这套默认 token
 */
export function buildCustomTheme(colors: ThemeColorsType): import('@kit.ArkUI').CustomTheme {
  return {
    colors: {
      brand: colors.primary,
      fontPrimary: colors.textPrimary,
      fontSecondary: colors.textSecondary,
      fontTertiary: colors.textTertiary,
      fontFourth: colors.textTertiary,
      fontEmphasize: colors.primary,
      fontOnPrimary: '#FFFFFF',
      backgroundPrimary: colors.bgApp,
      backgroundSecondary: colors.bgCard,
      backgroundTertiary: colors.bgCardElevated,
      backgroundFourth: colors.bgCardElevated,
      compBackgroundPrimary: colors.bgCard,
      compBackgroundSecondary: colors.bgCard,
      compBackgroundTertiary: colors.bgCardElevated,
      compDivider: colors.divider,
      iconPrimary: colors.textPrimary,
      iconSecondary: colors.textSecondary,
      iconTertiary: colors.textTertiary
    }
  };
}
