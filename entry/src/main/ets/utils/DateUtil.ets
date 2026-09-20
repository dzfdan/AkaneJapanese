/**
 * 日期工具函数
 */

/**
 * 获取今天的日期字符串 "YYYY-MM-DD"
 * @returns 今天的日期字符串
 */
export function getTodayStr(): string {
  const date = new Date();
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * 判断两个日期字符串是否为同一天
 * @param date1 日期字符串 "YYYY-MM-DD"
 * @param date2 日期字符串 "YYYY-MM-DD"
 * @returns 是否为同一天
 */
export function isSameDay(date1: string, date2: string): boolean {
  return date1 === date2;
}

/**
 * 判断今天是否是昨天的下一天（连续打卡用）
 * @param prevDate 前一天的日期字符串 "YYYY-MM-DD"
 * @param today 今天的日期字符串 "YYYY-MM-DD"
 * @returns 是否为连续的一天
 */
export function isConsecutiveDay(prevDate: string, today: string): boolean {
  const diff = daysBetween(prevDate, today);
  return diff === 1;
}

/**
 * 计算两个日期之间的天数差（date2 - date1）
 * @param date1 日期字符串 "YYYY-MM-DD"
 * @param date2 日期字符串 "YYYY-MM-DD"
 * @returns 天数差，正数表示 date2 在 date1 之后
 */
export function daysBetween(date1: string, date2: string): number {
  const d1 = new Date(date1);
  const d2 = new Date(date2);
  if (isNaN(d1.getTime()) || isNaN(d2.getTime())) {
    return 0;
  }
  const msPerDay = 24 * 60 * 60 * 1000;
  // 使用 UTC 计算避免夏令时影响
  const utc1 = Date.UTC(d1.getFullYear(), d1.getMonth(), d1.getDate());
  const utc2 = Date.UTC(d2.getFullYear(), d2.getMonth(), d2.getDate());
  return Math.floor((utc2 - utc1) / msPerDay);
}
