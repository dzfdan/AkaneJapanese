/**
 * 应用全局常量
 */

export interface BreakpointConfig {
  sm: number;
  md: number;
  lg: number;
}

export interface StorageKeyConfig {
  progress: string;
  settings: string;
}

export interface AppConstantsType {
  APP_NAME: string;
  DEFAULT_SPEED: number;
  SPEED_OPTIONS: number[];
  DEFAULT_MODE: 'driving' | 'parked';
  BREAKPOINTS: BreakpointConfig;
  STORAGE_KEYS: StorageKeyConfig;
}

export const AppConstants: AppConstantsType = {
  APP_NAME: '朱音日语',
  DEFAULT_SPEED: 1.0,
  SPEED_OPTIONS: [0.75, 1.0, 1.25],
  DEFAULT_MODE: 'parked',
  BREAKPOINTS: {
    sm: 320,
    md: 600,
    lg: 840
  },
  STORAGE_KEYS: {
    progress: 'user_progress',
    settings: 'user_settings'
  }
};
