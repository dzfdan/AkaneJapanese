/**
 * 应用全局常量
 */

export const AppConstants = {
  APP_NAME: '朱音日语',

  DEFAULT_SPEED: 1.0,

  SPEED_OPTIONS: [0.75, 1.0, 1.25],

  DEFAULT_MODE: 'driving' as const,

  BREAKPOINTS: {
    sm: 320,
    md: 600,
    lg: 840
  },

  STORAGE_KEYS: {
    progress: 'user_progress',
    settings: 'user_settings'
  },

  SCENE_INDEX_FILE: 'scenes/index.json'
} as const;

export type AppMode = typeof AppConstants.DEFAULT_MODE;
export type BreakpointKey = keyof typeof AppConstants.BREAKPOINTS;
export type StorageKey = keyof typeof AppConstants.STORAGE_KEYS;
