/**
 * 时间工具函数
 */

/**
 * 将秒数格式化为 "mm:ss" 格式
 * @param seconds 秒数
 * @returns 格式化后的时间字符串，如 "03:45"
 */
export function formatDuration(seconds: number): string {
  if (seconds < 0 || !Number.isFinite(seconds)) {
    return '00:00';
  }
  const totalSeconds = Math.floor(seconds);
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

/**
 * 将总分钟数格式化为 "X小时Y分" 或 "Y分钟"
 * @param minutes 总分钟数
 * @returns 格式化后的时长字符串
 */
export function formatTotalMinutes(minutes: number): string {
  if (minutes < 0 || !Number.isFinite(minutes)) {
    return '0分钟';
  }
  const totalMinutes = Math.floor(minutes);
  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;
  if (hours > 0) {
    return `${hours}小时${mins}分`;
  }
  return `${mins}分钟`;
}

/**
 * 将数值限制在指定范围内
 * @param value 输入值
 * @param min 最小值
 * @param max 最大值
 * @returns 限制后的值
 */
export function clamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
