/**
 * 和风朱音深色主题颜色常量
 * 与 resources/base/element/color.json 对应
 */

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
  textTertiary: '#8A7A66',

  // 分割线
  divider: '#3A2F24',

  // 语义色
  success: '#7CB342',
  warning: '#FFB74D',
  error: '#EF5350'
} as const;
